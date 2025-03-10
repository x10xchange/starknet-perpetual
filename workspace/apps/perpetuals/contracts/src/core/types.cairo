pub(crate) mod asset;
pub(crate) mod balance;
pub(crate) mod funding;
pub(crate) mod order;
pub(crate) mod position;
pub(crate) mod price;
pub(crate) mod set_owner_account;
pub(crate) mod set_public_key;
pub(crate) mod transfer;
pub(crate) mod withdraw;
use perpetuals::core::types::asset::AssetId;
use perpetuals::core::types::balance::Balance;
use perpetuals::core::types::price::Price;
use starkware_utils::types::fixed_two_decimal::FixedTwoDecimal;

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

#[derive(Copy, Debug, Drop, Serde, Default)]
pub struct PositionDiff {
    pub collateral: BalanceDiff,
    pub synthetic: Option<AssetDiff>,
}

#[derive(Copy, Debug, Drop, Serde, Default)]
pub struct PositionDiffEnriched {
    pub collateral: BalanceDiff,
    pub synthetic: Option<AssetDiffEnriched>,
}
