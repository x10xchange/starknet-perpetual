use perpetuals::core::types::asset::AssetId;
use perpetuals::core::types::order::{LimitOrder, Order};
use perpetuals::core::types::position::PositionId;
use starknet::{ClassHash, ContractAddress};
use starkware_utils::signature::stark::Signature;
use starkware_utils::time::time::Timestamp;
use super::types::vault::ConvertPositionToVault;

#[derive(Copy, Drop, Serde)]
pub struct Settlement {
    pub signature_a: Signature,
    pub signature_b: Signature,
    pub order_a: Order,
    pub order_b: Order,
    pub actual_amount_base_a: i64,
    pub actual_amount_quote_a: i64,
    pub actual_fee_a: u64,
    pub actual_fee_b: u64,
}

pub const EXTERNAL_COMPONENT_VAULT: felt252 = 0x1;
pub const EXTERNAL_COMPONENT_WITHDRAWALS: felt252 = 0x2;

#[starknet::interface]
pub trait ICore<TContractState> {
    fn withdraw_request(
        ref self: TContractState,
        signature: Signature,
        recipient: ContractAddress,
        position_id: PositionId,
        amount: u64,
        expiration: Timestamp,
        salt: felt252,
    );
    fn withdraw(
        ref self: TContractState,
        operator_nonce: u64,
        recipient: ContractAddress,
        position_id: PositionId,
        amount: u64,
        expiration: Timestamp,
        salt: felt252,
    );
    fn transfer_request(
        ref self: TContractState,
        signature: Signature,
        asset_id: AssetId,
        recipient: PositionId,
        position_id: PositionId,
        amount: u64,
        expiration: Timestamp,
        salt: felt252,
    );
    fn transfer(
        ref self: TContractState,
        operator_nonce: u64,
        asset_id: AssetId,
        recipient: PositionId,
        position_id: PositionId,
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
    fn multi_trade(ref self: TContractState, operator_nonce: u64, trades: Span<Settlement>);
    fn liquidate(
        ref self: TContractState,
        operator_nonce: u64,
        liquidator_signature: Signature,
        liquidated_position_id: PositionId,
        liquidator_order: Order,
        actual_amount_base_liquidated: i64,
        actual_amount_quote_liquidated: i64,
        actual_liquidator_fee: u64,
        liquidated_fee_amount: u64,
    );
    fn deleverage(
        ref self: TContractState,
        operator_nonce: u64,
        deleveraged_position_id: PositionId,
        deleverager_position_id: PositionId,
        base_asset_id: AssetId,
        deleveraged_base_amount: i64,
        deleveraged_quote_amount: i64,
    );
    fn reduce_inactive_asset_position(
        ref self: TContractState,
        operator_nonce: u64,
        position_id_a: PositionId,
        position_id_b: PositionId,
        base_asset_id: AssetId,
        base_amount_a: i64,
    );

    fn register_vault_component(ref self: TContractState, component_address: ClassHash);
    fn register_withdraw_component(ref self: TContractState, component_address: ClassHash);
    fn activate_vault(ref self: TContractState, operator_nonce: u64, order: ConvertPositionToVault);
    fn invest_in_vault(
        ref self: TContractState, operator_nonce: u64, signature: Signature, order: LimitOrder,
    );
    fn redeem_from_vault(
        ref self: TContractState,
        operator_nonce: u64,
        signature: Signature,
        order: LimitOrder,
        vault_approval: LimitOrder,
        vault_signature: Signature,
        actual_shares_user: i64,
        actual_collateral_user: i64,
    );

    fn liquidate_vault_shares(
        ref self: TContractState,
        operator_nonce: u64,
        liquidated_position_id: PositionId,
        vault_approval: LimitOrder,
        vault_signature: Signature,
        liquidated_asset_id: AssetId,
        actual_shares_user: i64,
        actual_collateral_user: i64,
    );
}
