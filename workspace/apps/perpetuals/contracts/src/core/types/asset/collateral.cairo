use openzeppelin::token::erc20::interface::IERC20Dispatcher;
use perpetuals::core::types::balance::Balance;
use starknet::ContractAddress;

const VERSION: u8 = 1;

#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct CollateralConfig {
    version: u8,
    // Collateral ERC20 contract
    pub token_contract: IERC20Dispatcher,
    // Configurable
    // Smallest unit of a token in the system.
    pub quantum: u64,
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
    fn config(token_address: ContractAddress, quantum: u64) -> CollateralConfig {
        let token_contract = IERC20Dispatcher { contract_address: token_address };
        CollateralConfig { version: VERSION, token_contract, quantum }
    }
}
