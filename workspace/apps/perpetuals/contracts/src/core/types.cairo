pub mod asset;
pub mod balance;
pub mod deposit;
pub mod funding;
pub(crate) mod order;
pub mod position;
pub mod price;
pub(crate) mod set_position_owner;
pub mod transfer;
pub mod update_position_public_key;
pub mod withdraw;
use perpetuals::core::types::asset::AssetId;
use perpetuals::core::types::balance::Balance;
use perpetuals::core::types::price::Price;

pub type Signature = Span<felt252>;

#[derive(Copy, Debug, Drop, Hash, Serde)]
pub struct PositionId {
    pub value: u32,
}

#[derive(Copy, Drop, Hash, Serde)]
pub struct AssetAmount {
    pub asset_id: AssetId,
    pub amount: i64,
}

#[derive(Debug, Drop, Serde)]
pub struct PositionData {
    pub asset_entries: Span<AssetEntry>,
}

#[derive(Copy, Debug, Drop, Serde)]
pub struct AssetEntry {
    pub id: AssetId,
    pub balance: Balance,
    pub price: Price,
}

#[derive(Copy, Default, Drop, Serde)]
pub struct AssetDiffEntry {
    pub id: AssetId,
    pub before: Balance,
    pub after: Balance,
    pub price: Price,
}

pub type PositionDiff = Span<AssetDiffEntry>;
