use contracts_commons::types::fixed_two_decimal::FixedTwoDecimal;
use contracts_commons::types::time::Timestamp;
use core::num::traits::Zero;
use perpetuals::core::types::asset::AssetId;
use perpetuals::core::types::balance::Balance;
use perpetuals::core::types::funding::FundingIndex;
use perpetuals::core::types::node::Node;

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
    pub next: Option<AssetId>,
}

pub impl SyntheticTimelyDataImpl of Node<SyntheticTimelyData> {
    fn head() -> SyntheticTimelyData {
        SyntheticTimelyData {
            version: VERSION,
            price: Zero::zero(),
            last_price_update: Zero::zero(),
            funding_index: Zero::zero(),
            next: Option::None,
        }
    }
}

/// Synthetic asset in a position.
/// - balance: The amount of the synthetic asset held in the position.
/// - funding_index: The funding index at the time of the last update.
/// - next: The next synthetic asset id in the position.
#[derive(Drop, Copy, Serde, starknet::Store)]
pub struct SyntheticAsset {
    pub version: u8,
    pub balance: Balance,
    pub funding_index: FundingIndex,
    pub next: Option<AssetId>,
}

pub impl SyntheticNodeImpl of Node<SyntheticAsset> {
    fn head() -> SyntheticAsset {
        SyntheticAsset {
            version: VERSION,
            balance: Zero::zero(),
            funding_index: Zero::zero(),
            next: Option::None,
        }
    }
}
