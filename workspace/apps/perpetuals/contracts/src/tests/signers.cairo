//! A curve-agnostic signer for tests.
//!
//! Position owner keys may sit on the STARK curve or on secp256k1. Tests that exercise a signed
//! flow should not care which, so they take a `Signer` and call `sign_message` with the SNIP-12
//! message hash — exactly what a real client holds — and this decides how to turn it into a
//! signature the contract will accept.

use core::num::traits::Zero;
use perpetuals::core::eip712::eip712_request_digest;
use perpetuals::core::types::key_type;
use snforge_std::signature::secp256k1_curve::{
    Secp256k1CurveKeyPair, Secp256k1CurveKeyPairImpl, Secp256k1CurveSignerImpl,
};
use snforge_std::signature::stark_curve::StarkCurveSignerImpl;
use snforge_std::signature::{KeyPairTrait, SignerTrait as SnforgeSignerTrait};
use starknet::eth_address::EthAddress;
use starknet::eth_signature::{is_eth_signature_valid, public_key_point_to_eth_address};
use starknet::secp256_trait::{Secp256Trait, Signature as Secp256Signature};
use starknet::secp256k1::Secp256k1Point;
use starkware_utils::signature::stark::{HashType, PublicKey, Signature};
use starkware_utils_testing::signing::StarkKeyPair;

#[derive(Copy, Drop)]
pub enum Signer {
    Stark: StarkKeyPair,
    Secp256k1: Secp256k1CurveKeyPair,
}

pub fn stark_signer(secret_key: felt252) -> Signer {
    Signer::Stark(
        snforge_std::signature::stark_curve::StarkCurveKeyPairImpl::from_secret_key(secret_key),
    )
}

pub fn secp256k1_signer(secret_key: u256) -> Signer {
    Signer::Secp256k1(Secp256k1CurveKeyPairImpl::from_secret_key(secret_key))
}

#[generate_trait]
pub impl SignerImpl of SignerTrait {
    /// What gets stored in `Position.owner_public_key`: the STARK public key, or — for
    /// secp256k1 — the 160-bit Ethereum address derived from the public point.
    fn public_key(self: @Signer) -> PublicKey {
        match self {
            Signer::Stark(key_pair) => *key_pair.public_key,
            Signer::Secp256k1(key_pair) => public_key_point_to_eth_address(*key_pair.public_key)
                .into(),
        }
    }

    fn key_type(self: @Signer) -> u8 {
        match self {
            Signer::Stark(_) => key_type::STARK,
            Signer::Secp256k1(_) => key_type::SECP256K1,
        }
    }

    /// Signs the SNIP-12 message hash. On secp256k1 the wallet actually signs the EIP-712 wrapping
    /// of that hash, which is what `validate_signature` verifies against.
    fn sign_message(self: @Signer, message: HashType) -> Signature {
        match self {
            Signer::Stark(key_pair) => {
                let (r, s) = (*key_pair).sign(message).unwrap();
                array![r, s].span()
            },
            Signer::Secp256k1(key_pair) => {
                let digest = eip712_request_digest(request_hash: message);
                let (r, s) = (*key_pair).sign(digest).unwrap();
                let eth_address = public_key_point_to_eth_address(*key_pair.public_key);
                let signature = Secp256Signature {
                    r, s, y_parity: recover_y_parity(:digest, :r, :s, :eth_address),
                };
                let mut serialized = array![];
                signature.serialize(ref serialized);
                serialized.span()
            },
        }
    }
}

/// snforge's secp256k1 signer returns only `(r, s)`; a real Ethereum wallet also returns the
/// recovery bit. Recover it the only way available: try both and keep the one that verifies.
pub fn recover_y_parity(digest: u256, r: u256, s: u256, eth_address: EthAddress) -> bool {
    if is_eth_signature_valid(
        msg_hash: digest, signature: Secp256Signature { r, s, y_parity: false }, :eth_address,
    )
        .is_ok() {
        false
    } else {
        true
    }
}

/// Produces the malleable twin `(r, n - s, !y_parity)` of a secp256k1 signature.
///
/// Used to pin the documented malleability property: this is accepted by verification, which is
/// safe only for as long as nothing in the protocol is keyed by signature bytes.
pub fn flip_signature_malleability(signature: Signature) -> Signature {
    let mut serialized = signature;
    let parsed: Secp256Signature = Serde::deserialize(ref serialized).unwrap();
    let curve_order = Secp256Trait::<Secp256k1Point>::get_curve_size();
    let flipped = Secp256Signature {
        r: parsed.r, s: curve_order - parsed.s, y_parity: !parsed.y_parity,
    };
    let mut out = array![];
    flipped.serialize(ref out);
    out.span()
}

/// A secp256k1 key pair's Ethereum address as a felt, without building a `Signer`.
pub fn eth_address_of(key_pair: Secp256k1CurveKeyPair) -> PublicKey {
    public_key_point_to_eth_address(key_pair.public_key).into()
}

/// Asserts the two curves' key ranges really are disjoint for the fixtures a test uses, so a
/// failure here points at the fixture rather than at the dispatch logic.
pub fn assert_disjoint_ranges(stark: Signer, secp: Signer) {
    assert!(stark.public_key().is_non_zero() && secp.public_key().is_non_zero());
    assert_eq!(key_type::derive_key_type(stark.public_key()), key_type::STARK);
    assert_eq!(key_type::derive_key_type(secp.public_key()), key_type::SECP256K1);
}
