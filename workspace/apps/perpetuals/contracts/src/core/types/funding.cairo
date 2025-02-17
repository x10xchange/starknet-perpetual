use contracts_commons::constants::TWO_POW_32;
use contracts_commons::errors::assert_with_byte_array;
use core::num::traits::zero::Zero;
use perpetuals::core::errors::invalid_funding_rate_err;
use perpetuals::core::types::asset::AssetId;
use perpetuals::core::types::balance::{Balance, BalanceTrait};
use perpetuals::core::types::price::{Price, PriceMulTrait};

#[derive(Copy, Debug, Drop, PartialEq, starknet::Store, Serde)]
pub struct FundingIndex {
    /// Signed 64-bit fixed-point number:
    /// 1 sign bit, 31-bits integer part, 32-bits fractional part.
    /// Represents values as: actual_value = stored_value / 2**32.
    pub value: i64,
}

pub trait FundingIndexMulTrait {
    /// Multiply the funding index with a balance.
    /// The funding is calculated as: funding = funding_index * balance / 2^32.
    fn mul(self: @FundingIndex, balance: Balance) -> Balance;
}

impl FundingIndexMul of FundingIndexMulTrait {
    fn mul(self: @FundingIndex, balance: Balance) -> Balance {
        let lhs: i128 = (*self.value).into();
        let result = lhs * balance.into() / TWO_POW_32.into();
        BalanceTrait::new(result.try_into().unwrap())
    }
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

/// Validates the funding rate using the following formula:
/// `max_funding_rate * time_diff * synthetic_price / 2^32`.
pub fn validate_funding_rate(
    synthetic_id: AssetId,
    index_diff: u64,
    max_funding_rate: u32,
    time_diff: u64,
    synthetic_price: Price,
) {
    assert_with_byte_array(
        condition: index_diff.into() <= synthetic_price.mul(rhs: max_funding_rate)
            * time_diff.into(),
        err: invalid_funding_rate_err(:synthetic_id),
    );
}


#[cfg(test)]
mod tests {
    use core::num::traits::zero::Zero;
    use super::{BalanceTrait, FundingIndex, FundingIndexMulTrait, TWO_POW_32};

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

    #[test]
    fn test_funding_mul() {
        /// Test the case that the funding is half.
        let index = FundingIndex { value: TWO_POW_32.try_into().unwrap() / 2 };
        let balance = BalanceTrait::new(1_000_000_000);
        let result: i64 = index.mul(balance).into();
        assert!(result == 500_000_000, "Expected 500000000, got {}", result);

        /// Test the case that the funding is 1.
        let index = FundingIndex { value: TWO_POW_32.try_into().unwrap() };
        let balance = BalanceTrait::new(1_000_000_000);
        let result: i64 = index.mul(balance).into();
        assert!(result == 1_000_000_000, "Expected 1000000000, got {}", result);

        /// Test the case that the balance is odd number and the funding is half.
        let index = FundingIndex { value: TWO_POW_32.try_into().unwrap() / 2 };
        let balance = BalanceTrait::new(1_000_000_001);
        let result: i64 = index.mul(balance).into();
        assert!(result == 500_000_000, "Expected 500000000, got {}", result);

        /// Test the case that the funding is 0.
        let index = FundingIndex { value: 0 };
        let balance = BalanceTrait::new(1_000_000_000);
        let result: i64 = index.mul(balance).into();
        assert!(result == 0, "Expected 0, got {}", result);

        /// Test the case that the balance is 0.
        let index = FundingIndex { value: TWO_POW_32.try_into().unwrap() };
        let balance = BalanceTrait::new(0);
        let result: i64 = index.mul(balance).into();
        assert!(result == 0, "Expected 0, got {}", result);

        /// Test the case that the balance is negative.
        let index = FundingIndex { value: TWO_POW_32.try_into().unwrap() };
        let balance = BalanceTrait::new(-1_000_000_000);
        let result: i64 = index.mul(balance).into();
        assert!(result == -1_000_000_000, "Expected -1000000000, got {}", result);

        /// Test the case that the funding is negative.
        let index = FundingIndex { value: -TWO_POW_32.try_into().unwrap() };
        let balance = BalanceTrait::new(1_000_000_000);
        let result: i64 = index.mul(balance).into();
        assert!(result == -1_000_000_000, "Expected -1000000000, got {}", result);

        /// Test the case that the funding is negative and the balance is negative.
        let index = FundingIndex { value: -TWO_POW_32.try_into().unwrap() };
        let balance = BalanceTrait::new(-1_000_000_000);
        let result: i64 = index.mul(balance).into();
        assert!(result == 1_000_000_000, "Expected 1000000000, got {}", result);

        /// Test the case that the funding is half and the balance is negative and odd.
        let index = FundingIndex { value: TWO_POW_32.try_into().unwrap() / 2 };
        let balance = BalanceTrait::new(-1_000_000_001);
        let result: i64 = index.mul(balance).into();
        assert!(result == -500_000_000, "Expected -500000000, got {}", result);
    }
}
