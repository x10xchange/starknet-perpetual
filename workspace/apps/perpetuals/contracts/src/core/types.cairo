pub(crate) mod asset;
pub(crate) mod balance;
pub(crate) mod funding;
pub(crate) mod order;
pub(crate) mod price;
pub(crate) mod set_owner_account;
pub(crate) mod set_public_key;
pub(crate) mod transfer;
pub(crate) mod withdraw;
use contracts_commons::types::fixed_two_decimal::FixedTwoDecimal;
use perpetuals::core::types::asset::AssetId;
use perpetuals::core::types::balance::Balance;
use perpetuals::core::types::price::Price;

#[derive(Copy, Debug, Drop, Hash, PartialEq, Serde)]
pub struct PositionId {
    pub value: u32,
}

pub impl U32IntoPositionId of Into<u32, PositionId> {
    fn into(self: u32) -> PositionId {
        PositionId { value: self }
    }
}

pub impl PositionIdIntoU32 of Into<PositionId, u32> {
    fn into(self: PositionId) -> u32 {
        self.value
    }
}

#[derive(Copy, Debug, Drop, Serde)]
pub struct Asset {
    pub id: AssetId,
    pub balance: Balance,
    pub price: Price,
    pub risk_factor: FixedTwoDecimal,
}

pub type PositionData = Span<Asset>;

#[derive(Copy, Debug, Default, Drop, Serde)]
pub struct AssetDiff {
    pub id: AssetId,
    pub balance_before: Balance,
    pub balance_after: Balance,
    pub price: Price,
    pub risk_factor_before: FixedTwoDecimal,
    pub risk_factor_after: FixedTwoDecimal,
}

#[derive(Copy, Debug, Drop, Serde)]
pub struct PositionDiff {
    pub collaterals: Span<AssetDiff>,
    pub synthetics: Span<AssetDiff>,
}

pub impl DefaultPositionDiffImpl of Default<PositionDiff> {
    fn default() -> PositionDiff {
        PositionDiff { collaterals: array![].span(), synthetics: array![].span() }
    }
}
