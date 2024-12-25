pub mod asset;
pub mod balance;
pub mod funding;
pub mod order;
pub mod withdraw_message;

use perpetuals::core::types::asset::AssetId;
use perpetuals::core::types::balance::Balance;

pub type Signature = Array<felt252>;

#[derive(Copy, Drop, Hash, Serde)]
pub struct AssetAmount {
    pub asset_id: AssetId,
    pub amount: i128,
}

#[derive(Drop, Serde)]
pub struct PositionData {
    pub asset_entries: Span<AssetEntry>,
}

#[derive(Drop, Serde, Copy)]
pub struct AssetEntry {
    pub id: AssetId,
    pub balance: Balance,
    pub price: u64,
}

#[derive(Drop, Serde)]
pub struct AssetDiffEntry {
    pub id: AssetId,
    pub before: Balance,
    pub after: Balance,
    pub price: u64,
}

pub type PositionDiff = Span<AssetDiffEntry>;
