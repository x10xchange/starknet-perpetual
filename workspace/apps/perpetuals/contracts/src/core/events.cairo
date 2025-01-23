use contracts_commons::types::time::time::Timestamp;
use perpetuals::core::types::{AssetAmount, PositionId};
use starknet::ContractAddress;

#[derive(Debug, Drop, PartialEq, starknet::Event)]
pub struct NewPosition {
    #[key]
    pub position_id: PositionId,
    #[key]
    pub owner_public_key: felt252,
    #[key]
    pub owner_account: ContractAddress,
}

#[derive(Debug, Drop, PartialEq, starknet::Event)]
pub struct WithdrawRequest {
    #[key]
    pub position_id: PositionId,
    #[key]
    pub recipient: ContractAddress,
    pub collateral: AssetAmount,
    pub expiration: Timestamp,
    #[key]
    pub withdraw_request_hash: felt252,
}

#[derive(Debug, Drop, PartialEq, starknet::Event)]
pub struct Withdraw {
    #[key]
    pub position_id: PositionId,
    #[key]
    pub recipient: ContractAddress,
    pub collateral: AssetAmount,
    pub expiration: Timestamp,
    #[key]
    pub withdraw_request_hash: felt252,
}

#[derive(Debug, Drop, PartialEq, starknet::Event)]
pub struct Trade {
    #[key]
    pub order_a_position_id: PositionId,
    pub order_a_base: AssetAmount,
    pub order_a_quote: AssetAmount,
    pub fee_a: AssetAmount,
    #[key]
    pub order_b_position_id: PositionId,
    pub order_b_base: AssetAmount,
    pub order_b_quote: AssetAmount,
    pub fee_b: AssetAmount,
    pub actual_amount_base_a: i64,
    pub actual_amount_quote_a: i64,
    pub actual_fee_a: i64,
    pub actual_fee_b: i64,
    #[key]
    pub order_a_hash: felt252,
    #[key]
    pub order_b_hash: felt252,
}

#[derive(Debug, Drop, PartialEq, starknet::Event)]
pub struct Liquidate {
    #[key]
    pub liquidated_position_id: PositionId,
    #[key]
    pub liquidator_order_position_id: PositionId,
    pub liquidator_order_base: AssetAmount,
    pub liquidator_order_quote: AssetAmount,
    pub liquidator_order_fee: AssetAmount,
    pub actual_amount_base_liquidated: i64,
    pub actual_amount_quote_liquidated: i64,
    pub actual_liquidator_fee: i64,
    pub insurance_fund_fee: AssetAmount,
    #[key]
    pub liquidator_order_hash: felt252,
}

#[derive(Debug, Drop, PartialEq, starknet::Event)]
pub struct TrasferRequest {
    #[key]
    pub position_id: PositionId,
    #[key]
    pub receipient: PositionId,
    pub expiration: Timestamp,
    #[key]
    pub transfer_request_hash: felt252,
}

#[derive(Debug, Drop, PartialEq, starknet::Event)]
pub struct Trasfer {
    #[key]
    pub position_id: PositionId,
    #[key]
    pub receipient: PositionId,
    pub expiration: Timestamp,
    #[key]
    pub transfer_request_hash: felt252,
}

#[derive(Debug, Drop, PartialEq, starknet::Event)]
pub struct SetOwnerAccount {
    #[key]
    pub position_id: PositionId,
    #[key]
    pub public_key: felt252,
    #[key]
    pub new_position_owner: ContractAddress,
    pub expiration: Timestamp,
}

#[derive(Debug, Drop, PartialEq, starknet::Event)]
pub struct SetPublicKeyRequest {
    #[key]
    pub position_id: PositionId,
    #[key]
    pub new_public_key: felt252,
    pub expiration: Timestamp,
    #[key]
    pub set_public_key_request_hash: felt252,
}

#[derive(Debug, Drop, PartialEq, starknet::Event)]
pub struct SetPublicKey {
    #[key]
    pub position_id: PositionId,
    #[key]
    pub new_public_key: felt252,
    pub expiration: Timestamp,
    #[key]
    pub set_public_key_request_hash: felt252,
}
