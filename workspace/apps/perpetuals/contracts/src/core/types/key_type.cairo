//! The curve a position's owner key belongs to.
//!
//! Stored as a `u8` rather than an enum so that a position written before this field existed —
//! whose slot reads back as zero — is a STARK position with no migration. `STARK` must therefore
//! stay `0` forever.
//!
//! Note what this value is *not* used for: signature verification never reads it. The curve is
//! derived from the key itself (see `derive_key_type`), because the key is already loaded on every
//! verification path and a second storage read would cost more than the branch. What the stored
//! value does is record declared intent at write time, so that `validate_key_type` can enforce the
//! range invariant the derivation depends on, and so events can carry the curve for indexers.

use core::num::traits::Zero;
use perpetuals::core::components::positions::errors::INVALID_ZERO_PUBLIC_KEY;
use starknet::eth_address::EthAddress;
use starkware_utils::signature::stark::PublicKey;

/// STARK curve. The default for every position that predates this field.
pub const STARK: u8 = 0;
/// secp256k1, with the position's `owner_public_key` holding a 160-bit Ethereum address.
pub const SECP256K1: u8 = 1;

pub const INVALID_KEY_TYPE: felt252 = 'INVALID_KEY_TYPE';
pub const KEY_TYPE_MISMATCH: felt252 = 'KEY_TYPE_MISMATCH';

/// Which curve `public_key` belongs to, decided by its magnitude.
///
/// An Ethereum address is below 2^160; a STARK public key is a curve x-coordinate and sits near
/// 2^251. The two ranges cannot be confused in either direction: a secp256k1 signature recovers an
/// address that can never equal a STARK key, and producing a STARK signature valid for a stored
/// address would require finding a private key whose public x-coordinate is that address.
///
/// `validate_key_type` turns that from a statistical argument into one checked at every write.
pub fn derive_key_type(public_key: PublicKey) -> u8 {
    // `TryInto<felt252, EthAddress>` is the 2^160 bound: it succeeds for 2^160 - 1 and fails for
    // 2^160. Using it rather than a hand-written comparison keeps this in step with the bound
    // `is_eth_signature_valid` itself applies.
    let as_address: Option<EthAddress> = public_key.try_into();
    match as_address {
        Option::Some(_) => SECP256K1,
        Option::None => STARK,
    }
}

/// Asserts that `public_key` is non-zero, that `key_type` is a curve we know, and that the key
/// lies in that curve's range.
///
/// Called on every path that writes a position's key. Without it an operator could store an
/// Ethereum address while declaring `STARK`, which no signature could ever satisfy — a position
/// bricked by a typo rather than by an attack, but bricked all the same.
pub fn validate_key_type(public_key: PublicKey, key_type: u8) {
    assert(public_key.is_non_zero(), INVALID_ZERO_PUBLIC_KEY);
    assert(key_type == STARK || key_type == SECP256K1, INVALID_KEY_TYPE);
    assert(derive_key_type(public_key) == key_type, KEY_TYPE_MISMATCH);
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 2^160 - 1: the largest value that is still an Ethereum address.
    const MAX_ETH_ADDRESS: felt252 = 0xffffffffffffffffffffffffffffffffffffffff;
    /// 2^160: the smallest value that is not.
    const MIN_STARK_RANGE: felt252 = 0x10000000000000000000000000000000000000000;

    #[test]
    fn test_derive_key_type_boundary() {
        assert_eq!(derive_key_type(MAX_ETH_ADDRESS), SECP256K1);
        assert_eq!(derive_key_type(MIN_STARK_RANGE), STARK);
    }

    #[test]
    fn test_derive_key_type_real_keys() {
        // A real STARK public key.
        assert_eq!(
            derive_key_type(0x51db5f8e4e8dbbc1b3b16b0b9d4b1b18e7c5f0dbaa8ff4b0d0bbaa48b3e2d0f),
            STARK,
        );
        // A real Ethereum address.
        assert_eq!(derive_key_type(0x47c9d5b1e2a3f8c60d4e7b9a2f150c83de6f4a91), SECP256K1);
    }

    #[test]
    fn test_validate_key_type_accepts_matching() {
        validate_key_type(MIN_STARK_RANGE, STARK);
        validate_key_type(MAX_ETH_ADDRESS, SECP256K1);
    }

    #[test]
    #[should_panic(expected: 'KEY_TYPE_MISMATCH')]
    fn test_validate_key_type_rejects_address_declared_stark() {
        validate_key_type(MAX_ETH_ADDRESS, STARK);
    }

    #[test]
    #[should_panic(expected: 'KEY_TYPE_MISMATCH')]
    fn test_validate_key_type_rejects_stark_key_declared_secp() {
        validate_key_type(MIN_STARK_RANGE, SECP256K1);
    }

    #[test]
    #[should_panic(expected: 'INVALID_KEY_TYPE')]
    fn test_validate_key_type_rejects_unknown_curve() {
        validate_key_type(MAX_ETH_ADDRESS, 2);
    }

    #[test]
    #[should_panic(expected: 'INVALID_ZERO_PUBLIC_KEY')]
    fn test_validate_key_type_rejects_zero_key() {
        validate_key_type(0, STARK);
    }
}
