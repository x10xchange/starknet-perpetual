use core::num::traits::zero::Zero;

pub mod collateral;
pub mod synthetic;

#[derive(Copy, Debug, Drop, Hash, Serde, starknet::Store)]
pub struct AssetId {
    pub value: felt252,
}

impl AssetIdZero of Zero<AssetId> {
    fn zero() -> AssetId {
        AssetId { value: 0 }
    }
    fn is_zero(self: @AssetId) -> bool {
        self.value.is_zero()
    }
    fn is_non_zero(self: @AssetId) -> bool {
        self.value.is_non_zero()
    }
}

impl AssetIdlOrd of PartialOrd<AssetId> {
    fn lt(lhs: AssetId, rhs: AssetId) -> bool {
        let l: u256 = lhs.value.into();
        let r: u256 = rhs.value.into();
        l < r
    }
    fn le(lhs: AssetId, rhs: AssetId) -> bool {
        let l: u256 = lhs.value.into();
        let r: u256 = rhs.value.into();
        l <= r
    }
}
