use contracts_commons::errors::assert_with_byte_array;
use contracts_commons::math::{Abs, FractionTrait};
use contracts_commons::types::time::time::{Time, Timestamp};
use contracts_commons::types::{PublicKey, Signature};
use openzeppelin::account::utils::is_valid_stark_signature;
use perpetuals::core::errors::INVALID_STARK_SIGNATURE;

pub fn validate_stark_signature(public_key: PublicKey, msg_hash: felt252, signature: Signature) {
    assert(is_valid_stark_signature(:msg_hash, :public_key, :signature), INVALID_STARK_SIGNATURE);
}

pub fn validate_expiration(expiration: Timestamp, err: felt252) {
    assert(Time::now() < expiration, err);
}

pub fn validate_ratio(n1: i64, d1: i64, n2: i64, d2: i64, err: ByteArray) {
    let f1 = FractionTrait::new(numerator: n1, denominator: d1.abs());
    let f2 = FractionTrait::new(numerator: n2, denominator: d2.abs());
    assert_with_byte_array(f1 <= f2, err);
}
