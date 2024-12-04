use contracts_commons::types::fixed_two_decimal::FixedTwoDecimal;
use contracts_commons::types::time::Timestamp;
use perpetuals::core::types::funding_index::FundingIndex;

pub const VERSION: u8 = 0;

#[derive(Drop, Copy, starknet::Store, Serde)]
pub struct SyntheticConfig {
    pub version: u8,
    pub name: felt252,
    pub symbol: felt252,
    pub decimals: u8,
    // Configurable.
    pub is_active: bool,
    pub risk_factor: FixedTwoDecimal,
    pub quorum: u8,
    // TODO: Oracels
}

#[derive(Drop, Copy, starknet::Store, Serde)]
pub struct SyntheticTimelyData {
    pub version: u8,
    pub price: u64,
    pub last_price_update: Timestamp,
    pub funding_index: FundingIndex,
}
