use contracts_commons::types::Signature;
use contracts_commons::types::time::time::Timestamp;
use perpetuals::core::types::PositionId;
use perpetuals::core::types::asset::AssetId;
use perpetuals::core::types::order::Order;
use starknet::ContractAddress;


#[starknet::interface]
pub trait ICore<TContractState> {
    fn process_deposit(
        ref self: TContractState,
        operator_nonce: u64,
        depositor: ContractAddress,
        position_id: PositionId,
        collateral_id: AssetId,
        amount: u64,
        salt: felt252,
    );
    fn withdraw_request(
        ref self: TContractState,
        signature: Signature,
        recipient: ContractAddress,
        position_id: PositionId,
        collateral_id: AssetId,
        amount: u64,
        expiration: Timestamp,
        salt: felt252,
    );
    fn withdraw(
        ref self: TContractState,
        operator_nonce: u64,
        recipient: ContractAddress,
        position_id: PositionId,
        collateral_id: AssetId,
        amount: u64,
        expiration: Timestamp,
        salt: felt252,
    );
    fn transfer_request(
        ref self: TContractState,
        signature: Signature,
        recipient: PositionId,
        position_id: PositionId,
        collateral_id: AssetId,
        amount: u64,
        expiration: Timestamp,
        salt: felt252,
    );
    fn transfer(
        ref self: TContractState,
        operator_nonce: u64,
        recipient: PositionId,
        position_id: PositionId,
        collateral_id: AssetId,
        amount: u64,
        expiration: Timestamp,
        salt: felt252,
    );
    fn trade(
        ref self: TContractState,
        operator_nonce: u64,
        signature_a: Signature,
        signature_b: Signature,
        order_a: Order,
        order_b: Order,
        actual_amount_base_a: i64,
        actual_amount_quote_a: i64,
        actual_fee_a: u64,
        actual_fee_b: u64,
    );
    fn liquidate(
        ref self: TContractState,
        operator_nonce: u64,
        liquidator_signature: Signature,
        liquidated_position_id: PositionId,
        liquidator_order: Order,
        actual_amount_base_liquidated: i64,
        actual_amount_quote_liquidated: i64,
        actual_liquidator_fee: u64,
        fee_asset_id: AssetId,
        fee_amount: u64,
    );
    fn deleverage(
        ref self: TContractState,
        operator_nonce: u64,
        deleveraged_position_id: PositionId,
        deleverager_position_id: PositionId,
        deleveraged_base_asset_id: AssetId,
        deleveraged_base_amount: i64,
        deleveraged_quote_asset_id: AssetId,
        deleveraged_quote_amount: i64,
    );
}
