use contracts_commons::types::fixed_two_decimal::FixedTwoDecimal;
use contracts_commons::types::time::time::Timestamp;
use perpetuals::core::types::asset::AssetId;
use perpetuals::core::types::asset::status::AssetStatus;
use perpetuals::core::types::balance::Balance;
use perpetuals::core::types::funding::FundingIndex;
use perpetuals::core::types::price::Price;


pub const VERSION: u8 = 1;

#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct SyntheticConfig {
    pub version: u8,
    // Configurable
    pub status: AssetStatus,
    pub risk_factor: FixedTwoDecimal,
    pub quorum: u8,
    // Smallest unit of a synthetic asset in the system.
    pub resolution: u64,
}

#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct SyntheticTimelyData {
    pub version: u8,
    pub price: Price,
    pub last_price_update: Timestamp,
    pub funding_index: FundingIndex,
    pub next: Option<AssetId>,
}

/// Synthetic asset in a position.
/// - balance: The amount of the synthetic asset held in the position.
/// - funding_index: The funding index at the time of the last update.
/// - next: The next synthetic asset id in the position.
#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct SyntheticAsset {
    pub version: u8,
    pub balance: Balance,
    pub funding_index: FundingIndex,
    pub next: Option<AssetId>,
}
