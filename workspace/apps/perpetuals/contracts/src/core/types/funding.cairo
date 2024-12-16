use core::num::traits::zero::Zero;
use perpetuals::core::types::asset::AssetId;

#[derive(Copy, Drop, starknet::Store, Serde)]
pub struct FundingIndex {
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
