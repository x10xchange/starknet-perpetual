pub mod asset;
pub mod balance;
pub mod funding_index;
pub mod node;
pub mod order;

use contracts_commons::types::fixed_two_decimal::FixedTwoDecimal;
use perpetuals::core::types::asset::AssetId;
use perpetuals::core::types::balance::Balance;
use starknet::ContractAddress;

pub struct Fee {
    pub value: u64,
}

pub type Signature = Array<felt252>;

#[derive(Drop, Serde)]
pub struct PositionData {
    pub version: u8,
    pub owner: ContractAddress,
    pub asset_entries: Span<AssetEntry>
}

#[derive(Drop, Serde)]
pub struct AssetEntry {
    pub id: AssetId,
    pub value: Balance,
    pub price: u64,
    pub risk_factor: FixedTwoDecimal
}

#[derive(Drop, Serde)]
pub struct AssetDiffEntry {
    pub id: AssetId,
    pub before: Balance,
    pub after: Balance,
    pub price: u64,
    pub risk_factor: FixedTwoDecimal
}

pub type PositionDiff = Span<AssetDiffEntry>;
