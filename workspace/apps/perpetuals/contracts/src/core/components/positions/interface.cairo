use perpetuals::core::types::asset::AssetId;
use perpetuals::core::types::balance::Balance;
use perpetuals::core::types::position::{AssetBalance, PositionData, PositionId};
use perpetuals::core::value_risk_calculator::PositionTVTR;
use starknet::ContractAddress;
use starkware_utils::signature::stark::{PublicKey, Signature};
use starkware_utils::time::time::Timestamp;

/// Full raw dump of a single `Position` for state replication between
/// contract deployments. Mirrors every stored field of `Position`, including the
/// enumerated per-asset balances.
#[derive(Drop, Serde)]
pub struct PositionDump {
    pub position_id: PositionId,
    pub version: u8,
    pub owner_account: Option<ContractAddress>,
    pub owner_public_key: PublicKey,
    pub collateral_balance: Balance,
    pub owner_protection_enabled: bool,
    pub last_interest_applied_time: Timestamp,
    pub asset_balances: Array<(AssetId, AssetBalance)>,
}

#[starknet::interface]
pub trait IPositions<TContractState> {
    fn get_position_assets(self: @TContractState, position_id: PositionId) -> PositionData;
    fn get_position_tv_tr(self: @TContractState, position_id: PositionId) -> PositionTVTR;
    fn is_deleveragable(self: @TContractState, position_id: PositionId) -> bool;
    fn is_healthy(self: @TContractState, position_id: PositionId) -> bool;
    fn is_liquidatable(self: @TContractState, position_id: PositionId) -> bool;
    // Position Flows
    fn new_position(
        ref self: TContractState,
        operator_nonce: u64,
        position_id: PositionId,
        owner_public_key: PublicKey,
        owner_account: ContractAddress,
        owner_protection_enabled: bool,
    );
    fn set_owner_account_request(
        ref self: TContractState,
        signature: Signature,
        position_id: PositionId,
        new_owner_account: ContractAddress,
        expiration: Timestamp,
    );
    fn set_owner_account(
        ref self: TContractState,
        operator_nonce: u64,
        position_id: PositionId,
        new_owner_account: ContractAddress,
        expiration: Timestamp,
    );
    fn set_public_key_request(
        ref self: TContractState,
        signature: Signature,
        position_id: PositionId,
        new_public_key: PublicKey,
        expiration: Timestamp,
    );
    fn set_public_key(
        ref self: TContractState,
        operator_nonce: u64,
        position_id: PositionId,
        new_public_key: PublicKey,
        expiration: Timestamp,
    );
    fn enable_owner_protection(
        ref self: TContractState,
        operator_nonce: u64,
        position_id: PositionId,
        signature: Signature,
    );
}
