use perpetuals::core::types::asset::{AssetId};
use openzeppelin::token::erc20::interface::IERC20Dispatcher;


#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct CollateralConfig {
    pub id: AssetId,
    pub token_contract: IERC20Dispatcher,
    pub quantum: u64,
}