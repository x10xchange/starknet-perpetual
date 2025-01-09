use contracts_commons::types::fixed_two_decimal::FixedTwoDecimal;
use contracts_commons::types::time::time::Timestamp;
use perpetuals::core::types::asset::AssetId;
use perpetuals::core::types::balance::Balance;
use perpetuals::core::types::price::Price;
use starknet::ContractAddress;

pub const VERSION: u8 = 0;

#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct CollateralConfig {
    pub version: u8,
    // Collateral ERC20 contract address
    pub address: ContractAddress,
    // Configurable
    pub is_active: bool,
    pub risk_factor: FixedTwoDecimal,
    // Smallest unit of a token in the system.
    pub quantum: u64,
    // Number of oracles that need to sign on the price to accept it.
    pub quorum: u8,
    // TODO: Oracels
}

#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct CollateralTimelyData {
    pub version: u8,
    pub price: Price,
    pub last_price_update: Timestamp,
    pub next: Option<AssetId>,
}

/// Collateral asset in a position.
/// - balance: The amount of the collateral asset held in the position.
/// - next: The next collateral asset id in the position.
#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct CollateralAsset {
    pub version: u8,
    pub balance: Balance,
    pub next: Option<AssetId>,
}
