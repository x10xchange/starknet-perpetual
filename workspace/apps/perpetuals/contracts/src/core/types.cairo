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
pub type UnchangedAssets = PositionData;

#[derive(Copy, Debug, Default, Drop, Serde)]
pub struct BalanceDiff {
    pub before: Balance,
    pub after: Balance,
}

#[derive(Copy, Debug, Default, Drop, Serde)]
pub struct AssetDiff {
    pub id: AssetId,
    pub balance: BalanceDiff,
}

#[derive(Copy, Debug, Default, Drop, Serde)]
pub struct AssetDiffEnriched {
    pub asset: AssetDiff,
    pub price: Price,
    pub risk_factor_before: FixedTwoDecimal,
    pub risk_factor_after: FixedTwoDecimal,
}

#[derive(Copy, Debug, Drop, Serde)]
pub struct PositionDiff {
    pub collaterals: Span<AssetDiff>,
    pub synthetics: Span<AssetDiff>,
}

#[derive(Copy, Debug, Drop, Serde)]
pub struct PositionDiffEnriched {
    pub collaterals: Span<AssetDiffEnriched>,
    pub synthetics: Span<AssetDiffEnriched>,
}

pub impl DefaultPositionDiffImpl of Default<PositionDiff> {
    fn default() -> PositionDiff {
        PositionDiff { collaterals: array![].span(), synthetics: array![].span() }
    }
}

pub impl DefaultPositionDiffEnrichedImpl of Default<PositionDiffEnriched> {
    fn default() -> PositionDiffEnriched {
        PositionDiffEnriched { collaterals: array![].span(), synthetics: array![].span() }
    }
}
