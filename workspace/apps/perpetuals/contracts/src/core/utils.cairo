use core::num::traits::Zero;
use core::panic_with_felt252;
use core::panics::panic_with_byte_array;
use perpetuals::core::components::positions::Positions::FEE_POSITION;
use perpetuals::core::errors::{
    CANT_TRADE_WITH_FEE_POSITION, DIFFERENT_BASE_ASSET_IDS, INVALID_QUOTE_FEE_AMOUNT,
    INVALID_ZERO_AMOUNT,
};
use starknet::eth_address::EthAddress;
use starknet::eth_signature::is_eth_signature_valid;
use starknet::secp256_trait::Signature as Secp256Signature;
use starkware_utils::hash::message_hash::OffchainMessageHash;
use starkware_utils::math::abs::Abs;
use starkware_utils::math::utils::have_same_sign;
use starkware_utils::signature::stark::{HashType, PublicKey, Signature, validate_stark_signature};
use starkware_utils::time::time::Time;
use super::components::assets::errors::{SYNTHETIC_NOT_ACTIVE, SYNTHETIC_NOT_EXISTS};
use super::eip712::eip712_request_digest;
use super::errors::{
    ASSET_ID_NOT_COLLATERAL, INVALID_ACTUAL_BASE_SIGN, INVALID_ACTUAL_QUOTE_SIGN,
    INVALID_AMOUNT_SIGN, INVALID_QUOTE_AMOUNT_SIGN, INVALID_SAME_POSITIONS,
    INVALID_SECP256K1_SIGNATURE, order_expired_err,
};
use super::types::asset::synthetic::AssetConfig;
use super::types::asset::{AssetId, AssetStatus};
use super::types::order::ValidateableOrderTrait;

/// Validates `signature` over `message` for the position key `public_key`, and returns the SNIP-12
/// message hash.
///
/// The returned hash is the same value on both curves and is what every caller stores: approval
/// records, fulfillment entries and emitted `*_hash` fields are all unchanged by a position moving
/// to secp256k1. Only the input to the signature check itself differs.
///
/// The curve is chosen from the magnitude of `public_key`, which is already loaded — see
/// `types::key_type::derive_key_type`. Dispatching on the stored key rather than on the length of
/// the caller-supplied signature matters twice over: the decision rests on trusted state, and a
/// secp-shaped signature aimed at a STARK position is rejected by the cheap path instead of paying
/// for an elliptic-curve recovery that was never going to succeed.
pub fn validate_signature<T, +Drop<T>, +Copy<T>, +OffchainMessageHash<T>>(
    public_key: PublicKey, message: T, signature: Signature,
) -> HashType {
    let msg_hash = message.get_message_hash(:public_key);
    let as_address: Option<EthAddress> = public_key.try_into();
    match as_address {
        Option::Some(eth_address) => validate_secp256k1_signature(
            :eth_address, :msg_hash, :signature,
        ),
        Option::None => validate_stark_signature(:public_key, :msg_hash, :signature),
    }
    msg_hash
}

/// Verifies an Ethereum-wallet signature over the EIP-712 wrapping of `msg_hash`.
///
/// `signature` is the serialization of `starknet::secp256_trait::Signature`: five felts, being
/// `[r.low, r.high, s.low, s.high, y_parity]`.
///
/// Malleability note: `(r, n - s, !y_parity)` also verifies here, because the underlying check
/// range-checks `r` and `s` but does not require a low `s`. That is safe only because nothing in
/// this protocol is keyed by a signature — replay is prevented by `msg_hash`, which the approvals
/// map and the fulfillment tracker both index. Anything added later that keys off signature bytes
/// must impose `s <= n/2` first.
pub fn validate_secp256k1_signature(
    eth_address: EthAddress, msg_hash: HashType, signature: Signature,
) {
    let mut serialized = signature;
    let parsed: Secp256Signature = Serde::deserialize(ref serialized)
        .expect(INVALID_SECP256K1_SIGNATURE);
    // Reject trailing junk: a caller must not be able to pad a signature with unread felts.
    assert(serialized.is_empty(), INVALID_SECP256K1_SIGNATURE);
    is_eth_signature_valid(
        msg_hash: eip712_request_digest(request_hash: msg_hash), signature: parsed, :eth_address,
    )
        .expect(INVALID_SECP256K1_SIGNATURE);
}

pub fn validate_trade<T, impl TValidateableOrder: ValidateableOrderTrait<T>, +Drop<T>, +Copy<T>>(
    order_a: T,
    order_b: T,
    actual_amount_base_a: i64,
    actual_amount_quote_a: i64,
    actual_fee_a: u64,
    actual_fee_b: u64,
    asset: Option<AssetConfig>,
    collateral_id: AssetId,
) {
    // Base asset check.
    assert(order_a.base_asset_id() == order_b.base_asset_id(), DIFFERENT_BASE_ASSET_IDS);

    match asset {
        None => panic_with_felt252(SYNTHETIC_NOT_EXISTS),
        Some(synthetic_asset) => assert(
            synthetic_asset.status == AssetStatus::ACTIVE, SYNTHETIC_NOT_ACTIVE,
        ),
    }

    assert(order_a.position_id() != order_b.position_id(), INVALID_SAME_POSITIONS);

    validate_order(order: order_a, collateral_id: collateral_id);
    validate_order(order: order_b, collateral_id: collateral_id);

    // Non-zero actual amount check.
    assert(actual_amount_base_a.is_non_zero(), INVALID_ZERO_AMOUNT);
    assert(actual_amount_quote_a.is_non_zero(), INVALID_ZERO_AMOUNT);

    // Sign Validation for amounts.
    assert(
        !have_same_sign(order_a.quote_amount(), order_b.quote_amount()), INVALID_QUOTE_AMOUNT_SIGN,
    );
    assert(have_same_sign(order_a.base_amount(), actual_amount_base_a), INVALID_ACTUAL_BASE_SIGN);
    assert(
        have_same_sign(order_a.quote_amount(), actual_amount_quote_a), INVALID_ACTUAL_QUOTE_SIGN,
    );

    order_a
        .validate_against_actual_amounts(
            actual_amount_base: actual_amount_base_a,
            actual_amount_quote: actual_amount_quote_a,
            actual_fee: actual_fee_a,
        );
    order_b
        .validate_against_actual_amounts(
            // Passing the negative of actual amounts to order_b as it is linked to order_a.
            actual_amount_base: -actual_amount_base_a,
            actual_amount_quote: -actual_amount_quote_a,
            actual_fee: actual_fee_b,
        );
}

pub fn validate_order<T, impl TValidateableOrder: ValidateableOrderTrait<T>, +Drop<T>, +Copy<T>>(
    order: T, collateral_id: AssetId,
) {
    // Verify that position is not fee position.
    assert(order.position_id() != FEE_POSITION, CANT_TRADE_WITH_FEE_POSITION);
    // This is to make sure that the fee is relative to the quote amount.
    assert(order.quote_amount().abs() > order.fee_amount(), INVALID_QUOTE_FEE_AMOUNT);
    // Non-zero amount check.
    assert(order.base_amount().is_non_zero(), INVALID_ZERO_AMOUNT);
    assert(order.quote_amount().is_non_zero(), INVALID_ZERO_AMOUNT);

    // Expiration check.
    let now = Time::now();
    if (now > order.expiration()) {
        let err = order_expired_err(order.position_id());
        panic_with_byte_array(err: @err);
    }

    // Sign Validation for amounts.
    assert(!have_same_sign(order.quote_amount(), order.base_amount()), INVALID_AMOUNT_SIGN);

    // Validate asset ids.
    assert(order.quote_asset_id() == collateral_id, ASSET_ID_NOT_COLLATERAL);
    assert(order.fee_asset_id() == collateral_id, ASSET_ID_NOT_COLLATERAL);
}
