use perpetuals::core::types::asset::AssetId;
use perpetuals::core::types::position::PositionId;


#[derive(Debug, Drop, PartialEq, starknet::Event)]
pub struct VaultOpened {
    #[key]
    pub position_id: PositionId,
    #[key]
    pub asset_id: AssetId,
}


#[derive(Debug, Drop, PartialEq, starknet::Event)]
pub struct InvestInVault {
    #[key]
    pub vault_position_id: PositionId,
    #[key]
    pub investing_position_id: PositionId,
    #[key]
    pub receiving_position_id: PositionId,
    #[key]
    pub vault_asset_id: AssetId,
    #[key]
    pub invested_asset_id: AssetId,
    pub shares_received: u64,
    pub user_investment: u64,
    pub correlation_id: felt252,
}


#[derive(Debug, Drop, PartialEq, starknet::Event)]
pub struct LiquidateVaultShares {
    #[key]
    pub vault_position_id: PositionId,
    #[key]
    pub liquidated_position_id: PositionId,
    #[key]
    pub vault_asset_id: AssetId,
    #[key]
    pub shares_liquidated: u64,
    pub collateral_received: u64,
}

#[derive(Debug, Drop, PartialEq, starknet::Event)]
pub struct RedeemVaultShares {
    #[key]
    pub vault_position_id: PositionId,
    #[key]
    pub redeeming_position_id: PositionId,
    #[key]
    pub receiving_position_id: PositionId,
    #[key]
    pub vault_asset_id: AssetId,
    #[key]
    pub invested_asset_id: AssetId,
    pub shares_redeemed: u64,
    pub collateral_received: u64,
    pub collateral_requested: u64,
}


#[derive(Debug, Drop, PartialEq, starknet::Event)]
pub struct VaultProtectionReset {
    #[key]
    pub vault_position_id: PositionId,
    pub old_tv_at_check: i128,
    pub old_max_tv_loss: u128,
    pub new_tv_at_check: i128,
    pub new_max_tv_loss: u128,
}
