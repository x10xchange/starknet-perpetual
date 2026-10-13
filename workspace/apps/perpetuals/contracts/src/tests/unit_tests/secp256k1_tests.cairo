//! End-to-end coverage for positions owned by a secp256k1 key.
//!
//! `set_owner_account_request` stands in for the whole signed-request family: it is the shortest
//! path that exercises the full chain — SNIP-12 hash, EIP-712 wrap, curve dispatch, approval
//! storage — using the position's own key. Every other signed entrypoint reaches
//! `validate_signature` identically, and their own tests already cover both curves for free,
//! because they sign through `User::sign_message` rather than through a STARK key pair directly.

use core::num::traits::Zero;
use perpetuals::core::components::operator_nonce::interface::IOperatorNonce;
use perpetuals::core::components::positions::Positions::InternalTrait as PositionsInternal;
use perpetuals::core::components::positions::interface::IPositions;
use perpetuals::core::core::Core;
use perpetuals::core::types::key_type;
use perpetuals::core::types::position::{PositionId, PositionMutableTrait};
use perpetuals::core::types::set_owner_account::SetOwnerAccountArgs;
use perpetuals::core::types::set_public_key::SetPublicKeyArgs;
use perpetuals::tests::constants::*;
use perpetuals::tests::signers::{
    Signer, SignerTrait, flip_signature_malleability, secp256k1_signer, stark_signer,
};
use perpetuals::tests::test_utils::{
    PerpetualsInitConfig, User, UserTrait, init_position, init_position_with_owner,
    setup_state_with_active_synthetic,
};
use snforge_std::signature::secp256k1_curve::{Secp256k1CurveKeyPairImpl, Secp256k1CurveSignerImpl};
use snforge_std::signature::{KeyPairTrait, SignerTrait as SnforgeSignerTrait};
use snforge_std::test_address;
use starknet::eth_signature::{is_eth_signature_valid, public_key_point_to_eth_address};
use starknet::secp256_trait::{Secp256Trait, Signature as Secp256Signature};
use starknet::secp256k1::Secp256k1Point;
use starkware_utils::components::request_approvals::interface::{IRequestApprovals, RequestStatus};
use starkware_utils::hash::message_hash::OffchainMessageHash;
use starkware_utils::signature::stark::Signature;
use starkware_utils::time::time::{Time, Timestamp};
use starkware_utils_testing::test_utils::{Deployable, cheat_caller_address_once};
use crate::core::components::snip::SNIP12MetadataImpl;

const SECP_SECRET_KEY: u256 = 0x9a8b7c6d5e4f30211122334455667788990011223344556677889900aabbccdd;
const OTHER_SECP_SECRET_KEY: u256 =
    0x1122334455667788990011223344556677889900aabbccddeeff001122334455;

/// A position owned by `signer`, with no owner account yet, ready for a set-owner request.
fn setup_position(signer: Signer) -> (Core::ContractState, User) {
    let cfg: PerpetualsInitConfig = Default::default();
    let token_state = cfg.collateral_cfg.token_cfg.deploy();
    let mut state = setup_state_with_active_synthetic(cfg: @cfg, token_state: @token_state);
    let user = UserTrait::new_with_signer(
        position_id: POSITION_ID_100, key_pair: KEY_PAIR_1(), :signer,
    );
    init_position(cfg: @cfg, ref :state, :user);
    (state, user)
}

fn set_owner_args(user: @User, expiration: Timestamp) -> SetOwnerAccountArgs {
    SetOwnerAccountArgs {
        position_id: *user.position_id,
        public_key: user.get_public_key(),
        new_owner_account: *user.address,
        expiration,
    }
}

fn submit_set_owner_request(
    ref state: Core::ContractState, user: @User, args: @SetOwnerAccountArgs, signature: Signature,
) {
    cheat_caller_address_once(contract_address: test_address(), caller_address: *user.address);
    state
        .set_owner_account_request(
            :signature,
            position_id: *args.position_id,
            new_owner_account: *args.new_owner_account,
            expiration: *args.expiration,
        );
}

fn day_ahead() -> Timestamp {
    Time::now().add(delta: Time::days(1))
}

// ---------------------------------------------------------------- position setup

#[test]
fn test_new_position_stores_secp_key_and_type() {
    let (mut state, user) = setup_position(secp256k1_signer(SECP_SECRET_KEY));

    let position = state.positions.get_position_mut(position_id: user.position_id);
    assert_eq!(position.get_owner_public_key(), user.get_public_key());
    assert_eq!(position.get_owner_key_type(), key_type::SECP256K1);
    // The stored key really is an Ethereum address, not a STARK key.
    assert_eq!(key_type::derive_key_type(user.get_public_key()), key_type::SECP256K1);
}

#[test]
#[should_panic(expected: 'KEY_TYPE_MISMATCH')]
fn test_new_position_rejects_secp_key_declared_stark() {
    let cfg: PerpetualsInitConfig = Default::default();
    let token_state = cfg.collateral_cfg.token_cfg.deploy();
    let mut state = setup_state_with_active_synthetic(cfg: @cfg, token_state: @token_state);
    let user = UserTrait::new_with_signer(
        position_id: POSITION_ID_100,
        key_pair: KEY_PAIR_1(),
        signer: secp256k1_signer(SECP_SECRET_KEY),
    );

    cheat_caller_address_once(contract_address: test_address(), caller_address: cfg.operator);
    state
        .new_position(
            operator_nonce: state.get_operator_nonce(),
            position_id: user.position_id,
            owner_public_key: user.get_public_key(),
            owner_key_type: key_type::STARK,
            owner_account: Zero::zero(),
            owner_protection_enabled: false,
        );
}

// ---------------------------------------------------------------- happy path

#[test]
fn test_secp_signature_accepted() {
    let (mut state, user) = setup_position(secp256k1_signer(SECP_SECRET_KEY));
    let args = set_owner_args(user: @user, expiration: day_ahead());
    let msg_hash = args.get_message_hash(public_key: user.get_public_key());
    let signature = user.sign_message(message: msg_hash);

    // Five felts: [r.low, r.high, s.low, s.high, y_parity].
    assert_eq!(signature.len(), 5);

    submit_set_owner_request(ref :state, user: @user, args: @args, :signature);
    assert_eq!(
        state.request_approvals.get_request_status(request_hash: msg_hash), RequestStatus::PENDING,
    );
}

#[test]
fn test_approval_is_keyed_by_the_snip12_hash() {
    // The approval is stored under the SNIP-12 Poseidon hash, not the EIP-712 digest the wallet
    // actually signed. That is the property which lets every downstream map stay untouched.
    let (mut state, user) = setup_position(secp256k1_signer(SECP_SECRET_KEY));
    let args = set_owner_args(user: @user, expiration: day_ahead());
    let msg_hash = args.get_message_hash(public_key: user.get_public_key());
    submit_set_owner_request(
        ref :state, user: @user, args: @args, signature: user.sign_message(message: msg_hash),
    );

    let recomputed = args.get_message_hash(public_key: user.get_public_key());
    assert_eq!(recomputed, msg_hash);
    assert_eq!(
        state.request_approvals.get_request_status(request_hash: recomputed),
        RequestStatus::PENDING,
    );
}

// ---------------------------------------------------------------- rejection paths

#[test]
#[should_panic(expected: 'INVALID_SECP256K1_SIGNATURE')]
fn test_secp_rejects_signature_from_another_key() {
    let (mut state, user) = setup_position(secp256k1_signer(SECP_SECRET_KEY));
    let args = set_owner_args(user: @user, expiration: day_ahead());
    let msg_hash = args.get_message_hash(public_key: user.get_public_key());

    let impostor = UserTrait::new_with_signer(
        position_id: user.position_id,
        key_pair: KEY_PAIR_1(),
        signer: secp256k1_signer(OTHER_SECP_SECRET_KEY),
    );
    submit_set_owner_request(
        ref :state, user: @user, args: @args, signature: impostor.sign_message(message: msg_hash),
    );
}

#[test]
#[should_panic(expected: 'INVALID_SECP256K1_SIGNATURE')]
fn test_secp_rejects_signature_over_a_different_request() {
    let (mut state, user) = setup_position(secp256k1_signer(SECP_SECRET_KEY));
    let args = set_owner_args(user: @user, expiration: day_ahead());
    submit_set_owner_request(
        ref :state,
        user: @user,
        args: @args,
        signature: user.sign_message(message: 'SOME_OTHER_REQUEST'),
    );
}

#[test]
#[should_panic(expected: 'INVALID_SECP256K1_SIGNATURE')]
fn test_secp_rejects_stark_shaped_signature() {
    // A two-felt STARK signature aimed at a secp position: deserializing a secp signature needs
    // five felts, so this fails before any curve work.
    let (mut state, user) = setup_position(secp256k1_signer(SECP_SECRET_KEY));
    let args = set_owner_args(user: @user, expiration: day_ahead());
    submit_set_owner_request(
        ref :state, user: @user, args: @args, signature: array![0x1, 0x2].span(),
    );
}

#[test]
#[should_panic(expected: 'INVALID_SECP256K1_SIGNATURE')]
fn test_secp_rejects_trailing_junk_after_signature() {
    // Padding a valid signature with unread felts must not be accepted, or signature encodings
    // stop being unique.
    let (mut state, user) = setup_position(secp256k1_signer(SECP_SECRET_KEY));
    let args = set_owner_args(user: @user, expiration: day_ahead());
    let msg_hash = args.get_message_hash(public_key: user.get_public_key());

    let mut padded = array![];
    for felt in user.sign_message(message: msg_hash) {
        padded.append(*felt);
    }
    padded.append(0xdeadbeef);
    submit_set_owner_request(ref :state, user: @user, args: @args, signature: padded.span());
}

#[test]
#[should_panic(expected: 'INVALID_STARK_KEY_SIGNATURE')]
fn test_stark_position_rejects_secp_shaped_signature() {
    // The mirror case, and the reason dispatch reads the stored key rather than the signature
    // length: a STARK position takes the STARK path whatever the caller sends, so this is rejected
    // cheaply instead of paying for an elliptic-curve recovery that could never have succeeded.
    let (mut state, user) = setup_position(stark_signer('PRIVATE_KEY_1'));
    let args = set_owner_args(user: @user, expiration: day_ahead());
    submit_set_owner_request(
        ref :state, user: @user, args: @args, signature: array![1, 2, 3, 4, 1].span(),
    );
}

// ---------------------------------------------------------------- malleability

#[test]
#[should_panic(expected: 'INVALID_SECP256K1_SIGNATURE')]
fn test_malleable_twin_is_rejected() {
    // `(r, n - s, !y_parity)` recovers the same key as `(r, s, y_parity)` — that is arithmetic,
    // not a policy choice. It is nonetheless rejected, because corelib requires a low `s`; see
    // `test_corelib_enforces_low_s` for the direct demonstration.
    //
    // This test exists to keep that guarantee visible. If a corelib upgrade ever relaxes the rule,
    // this is what should start failing, and signature uniqueness stops holding at that point.
    let (mut state, user) = setup_position(secp256k1_signer(SECP_SECRET_KEY));
    let args = set_owner_args(user: @user, expiration: day_ahead());
    let msg_hash = args.get_message_hash(public_key: user.get_public_key());

    let original = user.sign_message(message: msg_hash);
    let twin = flip_signature_malleability(original);
    assert!(original != twin);

    submit_set_owner_request(ref :state, user: @user, args: @args, signature: twin);
}

#[test]
fn test_corelib_enforces_low_s() {
    // Pins the property the test above depends on, at the layer that actually provides it.
    //
    // Both members of each pair recover the same address — verified independently outside Cairo
    // —
    // so acceptance is decided purely by the low-`s` rule and not by the mathematics. This is
    // corelib behaviour, and behaviour that changed: Cairo 2.13 accepted the high-`s` twin.
    let key_pair = Secp256k1CurveKeyPairImpl::from_secret_key(SECP_SECRET_KEY);
    let eth_address = public_key_point_to_eth_address(key_pair.public_key);
    let curve_order = Secp256Trait::<Secp256k1Point>::get_curve_size();
    let half_order = curve_order / 2;

    for i in 0_u8..5_u8 {
        let digest: u256 = 0x1111111111111111111111111111111111111111111111111111111111111100_u256
            + i.into();
        let (r, s) = key_pair.sign(digest).unwrap();
        assert!(s <= half_order, "snforge should produce low-s signatures");

        let y_parity = !is_eth_signature_valid(
            digest, Secp256Signature { r, s, y_parity: false }, eth_address,
        )
            .is_ok();
        let original_ok = is_eth_signature_valid(
            digest, Secp256Signature { r, s, y_parity }, eth_address,
        )
            .is_ok();
        assert!(original_ok, "the original must verify");
        let twin_ok = is_eth_signature_valid(
            digest, Secp256Signature { r, s: curve_order - s, y_parity: !y_parity }, eth_address,
        )
            .is_ok();
        assert!(!twin_ok, "the high-s twin must be rejected");
    }
}

#[test]
#[should_panic(expected: 'REQUEST_ALREADY_REGISTERED')]
fn test_request_cannot_be_registered_twice() {
    // Replay protection keys on the request hash, independently of the signature. That is what
    // makes signature uniqueness a defence in depth here rather than the thing being relied on.
    let (mut state, user) = setup_position(secp256k1_signer(SECP_SECRET_KEY));
    let args = set_owner_args(user: @user, expiration: day_ahead());
    let msg_hash = args.get_message_hash(public_key: user.get_public_key());
    let signature = user.sign_message(message: msg_hash);

    submit_set_owner_request(ref :state, user: @user, args: @args, :signature);
    submit_set_owner_request(ref :state, user: @user, args: @args, :signature);
}

// ---------------------------------------------------------------- key rotation

#[test]
fn test_rotate_stark_position_to_secp_key() {
    let cfg: PerpetualsInitConfig = Default::default();
    let token_state = cfg.collateral_cfg.token_cfg.deploy();
    let mut state = setup_state_with_active_synthetic(cfg: @cfg, token_state: @token_state);
    let user: User = Default::default();
    init_position_with_owner(cfg: @cfg, ref :state, :user);

    let old_public_key = user.get_public_key();
    let new_signer: Signer = secp256k1_signer(SECP_SECRET_KEY);
    let args = SetPublicKeyArgs {
        position_id: user.position_id,
        old_public_key,
        new_public_key: new_signer.public_key(),
        new_public_key_type: new_signer.key_type(),
        expiration: day_ahead(),
    };
    // Signed by the *new* key, so this is a secp signature checked against the incoming address.
    let msg_hash = args.get_message_hash(public_key: new_signer.public_key());
    let signature = new_signer.sign_message(message: msg_hash);

    cheat_caller_address_once(contract_address: test_address(), caller_address: user.address);
    state
        .set_public_key_request(
            :signature,
            position_id: args.position_id,
            new_public_key: args.new_public_key,
            new_public_key_type: args.new_public_key_type,
            expiration: args.expiration,
        );

    cheat_caller_address_once(contract_address: test_address(), caller_address: cfg.operator);
    state
        .set_public_key(
            operator_nonce: state.get_operator_nonce(),
            position_id: args.position_id,
            new_public_key: args.new_public_key,
            new_public_key_type: args.new_public_key_type,
            expiration: args.expiration,
        );

    let position = state.positions.get_position_mut(position_id: user.position_id);
    assert_eq!(position.get_owner_public_key(), new_signer.public_key());
    assert_eq!(position.get_owner_key_type(), key_type::SECP256K1);
}

#[test]
#[should_panic(expected: 'KEY_TYPE_MISMATCH')]
fn test_rotation_rejects_mismatched_declared_curve() {
    // The operator cannot install a secp key under the STARK type: the curve sits inside the
    // signed struct, so the user's approval covers it.
    let cfg: PerpetualsInitConfig = Default::default();
    let token_state = cfg.collateral_cfg.token_cfg.deploy();
    let mut state = setup_state_with_active_synthetic(cfg: @cfg, token_state: @token_state);
    let user: User = Default::default();
    init_position_with_owner(cfg: @cfg, ref :state, :user);

    let new_signer: Signer = secp256k1_signer(SECP_SECRET_KEY);
    cheat_caller_address_once(contract_address: test_address(), caller_address: user.address);
    state
        .set_public_key_request(
            signature: array![0, 0, 0, 0, 0].span(),
            position_id: user.position_id,
            new_public_key: new_signer.public_key(),
            new_public_key_type: key_type::STARK,
            expiration: day_ahead(),
        );
}

// ---------------------------------------------------------------- regression

#[test]
fn test_stark_positions_are_unaffected() {
    // The guard that matters most: an all-STARK flow must behave exactly as it did before the
    // secp path existed, down to producing a two-felt signature.
    let cfg: PerpetualsInitConfig = Default::default();
    let token_state = cfg.collateral_cfg.token_cfg.deploy();
    let mut state = setup_state_with_active_synthetic(cfg: @cfg, token_state: @token_state);
    let user: User = Default::default();
    init_position(cfg: @cfg, ref :state, :user);

    let args = set_owner_args(user: @user, expiration: day_ahead());
    let msg_hash = args.get_message_hash(public_key: user.get_public_key());
    let signature = user.sign_message(message: msg_hash);
    assert_eq!(signature.len(), 2);

    submit_set_owner_request(ref :state, user: @user, args: @args, :signature);
    assert_eq!(
        state.request_approvals.get_request_status(request_hash: msg_hash), RequestStatus::PENDING,
    );
    assert_eq!(
        state.positions.get_position_mut(position_id: user.position_id).get_owner_key_type(),
        key_type::STARK,
    );
}

#[test]
fn test_both_curves_coexist() {
    // Two positions, two curves, one contract — the mixed-settlement shape in miniature.
    let cfg: PerpetualsInitConfig = Default::default();
    let token_state = cfg.collateral_cfg.token_cfg.deploy();
    let mut state = setup_state_with_active_synthetic(cfg: @cfg, token_state: @token_state);

    let stark_user: User = Default::default();
    init_position(cfg: @cfg, ref :state, user: stark_user);
    let secp = UserTrait::new_with_signer(
        position_id: POSITION_ID_200,
        key_pair: KEY_PAIR_2(),
        signer: secp256k1_signer(SECP_SECRET_KEY),
    );
    init_position(cfg: @cfg, ref :state, user: secp);

    assert_eq!(
        state.positions.get_position_mut(position_id: stark_user.position_id).get_owner_key_type(),
        key_type::STARK,
    );
    assert_eq!(
        state.positions.get_position_mut(position_id: secp.position_id).get_owner_key_type(),
        key_type::SECP256K1,
    );
}
