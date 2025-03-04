use contracts_commons::types::time::time::Timestamp;
use perpetuals::core::types::asset::AssetStatus;
use perpetuals::core::types::balance::Balance;
use perpetuals::core::types::funding::FundingIndex;
use perpetuals::core::types::price::Price;

const VERSION: u8 = 1;

#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct SyntheticConfig {
    version: u8,
    // Configurable
    pub status: AssetStatus,
    pub risk_factor_first_tier_boundary: u128,
    pub risk_factor_tier_size: u128,
    pub quorum: u8,
    // Smallest unit of a synthetic asset in the system.
    pub resolution: u64,
}

#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct SyntheticTimelyData {
    version: u8,
    pub price: Price,
    pub last_price_update: Timestamp,
    pub funding_index: FundingIndex,
}

/// Synthetic asset in a position.
/// - balance: The amount of the synthetic asset held in the position.
/// - funding_index: The funding index at the time of the last update.
/// - next: The next synthetic asset id in the position.
#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct SyntheticAsset {
    version: u8,
    pub balance: Balance,
    pub funding_index: FundingIndex,
}

#[generate_trait]
pub impl SyntheticImpl of SyntheticTrait {
    fn asset(balance: Balance, funding_index: FundingIndex) -> SyntheticAsset {
        SyntheticAsset { version: VERSION, balance, funding_index }
    }
    fn config(
        status: AssetStatus,
        risk_factor_first_tier_boundary: u128,
        risk_factor_tier_size: u128,
        quorum: u8,
        resolution: u64,
    ) -> SyntheticConfig {
        SyntheticConfig {
            version: VERSION,
            status,
            risk_factor_first_tier_boundary,
            risk_factor_tier_size,
            quorum,
            resolution,
        }
    }
    fn timely_data(
        price: Price, last_price_update: Timestamp, funding_index: FundingIndex,
    ) -> SyntheticTimelyData {
        SyntheticTimelyData { version: VERSION, price, last_price_update, funding_index }
    }
}
