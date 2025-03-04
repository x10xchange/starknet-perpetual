use contracts_commons::types::fixed_two_decimal::FixedTwoDecimal;
use contracts_commons::types::time::time::Timestamp;
use perpetuals::core::types::asset::AssetStatus;
use perpetuals::core::types::balance::Balance;
use perpetuals::core::types::price::Price;
use starknet::ContractAddress;

const VERSION: u8 = 1;

#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct CollateralConfig {
    version: u8,
    // Collateral ERC20 contract address
    pub token_address: ContractAddress,
    // Configurable
    pub status: AssetStatus,
    pub risk_factor: FixedTwoDecimal,
    // Smallest unit of a token in the system.
    pub quantum: u64,
    // Number of oracles that need to sign on the price to accept it.
    pub quorum: u8,
}

#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct CollateralTimelyData {
    version: u8,
    pub price: Price,
    pub last_price_update: Timestamp,
}

/// Collateral asset in a position.
/// - balance: The amount of the collateral asset held in the position.
/// - next: The next collateral asset id in the position.
#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct CollateralAsset {
    version: u8,
    pub balance: Balance,
}

#[generate_trait]
pub impl CollateralImpl of CollateralTrait {
    fn asset(balance: Balance) -> CollateralAsset {
        CollateralAsset { version: VERSION, balance }
    }
    fn config(
        token_address: ContractAddress,
        status: AssetStatus,
        risk_factor: FixedTwoDecimal,
        quantum: u64,
        quorum: u8,
    ) -> CollateralConfig {
        CollateralConfig { version: VERSION, token_address, status, risk_factor, quantum, quorum }
    }
    fn timely_data(price: Price, last_price_update: Timestamp) -> CollateralTimelyData {
        CollateralTimelyData { version: VERSION, price, last_price_update }
    }
}
