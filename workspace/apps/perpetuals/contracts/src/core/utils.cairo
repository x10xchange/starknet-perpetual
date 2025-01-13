use contracts_commons::errors::assert_with_byte_array;
use contracts_commons::math::{Abs, FractionTrait};


pub fn validate_ratio(n1: i64, d1: i64, n2: i64, d2: i64, err: ByteArray) {
    let f1 = FractionTrait::new(numerator: n1, denominator: d1.abs());
    let f2 = FractionTrait::new(numerator: n2, denominator: d2.abs());
    assert_with_byte_array(f1 <= f2, err);
}
