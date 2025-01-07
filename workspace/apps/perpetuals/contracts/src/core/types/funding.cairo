use contracts_commons::constants::TWO_POW_32;
use core::num::traits::zero::Zero;
use perpetuals::core::types::asset::AssetId;
use perpetuals::core::types::price::{Price, PriceMulTrait};

#[derive(Copy, Drop, starknet::Store, Serde)]
pub struct FundingIndex {
    /// Signed 64-bit fixed-point number:
    /// 1 sign bit, 31-bits integer part, 32-bits fractional part.
    /// Represents values as: actual_value = stored_value / 2**32.
    pub value: i64,
}

#[derive(Copy, Drop, starknet::Store, Serde)]
pub struct FundingTick {
    pub asset_id: AssetId,
    pub funding_index: FundingIndex,
}

impl FundingIndexZero of Zero<FundingIndex> {
    fn zero() -> FundingIndex {
        FundingIndex { value: 0 }
    }
    fn is_zero(self: @FundingIndex) -> bool {
        self.value.is_zero()
    }
    fn is_non_zero(self: @FundingIndex) -> bool {
        self.value.is_non_zero()
    }
}

impl FundingIndexSubImpl of Sub<FundingIndex> {
    fn sub(lhs: FundingIndex, rhs: FundingIndex) -> FundingIndex {
        FundingIndex { value: lhs.value - rhs.value }
    }
}

impl FundingIndexIntoImpl of Into<FundingIndex, i64> {
    fn into(self: FundingIndex) -> i64 {
        self.value
    }
}

/// Calculate the funding rate using the following formula:
/// `max_funding_rate * time_diff * synthetic_price / 2^32`.
pub fn funding_rate_calc(max_funding_rate: u32, time_diff: u64, synthetic_price: Price) -> u128 {
    synthetic_price.mul(rhs: max_funding_rate) * time_diff.into() / TWO_POW_32.into()
}

#[cfg(test)]
mod tests {
    use core::num::traits::zero::Zero;
    use super::FundingIndex;

    #[test]
    fn test_zero() {
        let index: FundingIndex = Zero::zero();
        assert_eq!(index.value, 0);
    }
    #[test]
    fn test_is_zero() {
        let index: FundingIndex = Zero::zero();
        assert!(index.is_zero());
        assert!(!index.is_non_zero());
    }
    #[test]
    fn test_is_non_zero() {
        let index = FundingIndex { value: 1 };
        assert!(!index.is_zero());
        assert!(index.is_non_zero());
    }
}
