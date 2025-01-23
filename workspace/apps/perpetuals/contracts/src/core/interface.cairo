use perpetuals::core::types::asset::AssetId;
use perpetuals::core::types::funding::FundingTick;
use perpetuals::core::types::order::Order;
use perpetuals::core::types::set_position_owner::SetPositionOwnerArgs;
use perpetuals::core::types::set_public_key::SetPublicKeyArgs;
use perpetuals::core::types::transfer::TransferArgs;
use perpetuals::core::types::withdraw::WithdrawArgs;
use perpetuals::core::types::{AssetAmount, PositionId, Signature};
use starknet::ContractAddress;

#[starknet::interface]
pub trait ICore<TContractState> {
    // Flows
    fn deleverage(self: @TContractState);
    fn liquidate(
        ref self: TContractState,
        operator_nonce: u64,
        liquidator_signature: Signature,
        liquidated_position_id: PositionId,
        liquidator_order: Order,
        actual_amount_base_liquidated: i64,
        actual_amount_quote_liquidated: i64,
        actual_liquidator_fee: i64,
        insurance_fund_fee: AssetAmount,
    );
    fn set_position_owner(
        ref self: TContractState,
        operator_nonce: u64,
        signature: Signature,
        set_position_owner_args: SetPositionOwnerArgs,
    );
    fn transfer(ref self: TContractState, operator_nonce: u64, transfer_args: TransferArgs);
    fn new_position(
        ref self: TContractState,
        operator_nonce: u64,
        position_id: PositionId,
        owner_public_key: felt252,
        owner_account: ContractAddress,
    );
    fn process_deposit(
        ref self: TContractState,
        operator_nonce: u64,
        depositor: ContractAddress,
        collateral_id: AssetId,
        amount: i64,
        position_id: PositionId,
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
        actual_fee_a: i64,
        actual_fee_b: i64,
    );
    fn transfer_request(
        ref self: TContractState, signature: Signature, transfer_args: TransferArgs,
    );
    fn set_public_key(
        ref self: TContractState, operator_nonce: u64, set_public_key_args: SetPublicKeyArgs,
    );
    fn set_public_key_request(
        ref self: TContractState, signature: Signature, set_public_key_args: SetPublicKeyArgs,
    );
    fn withdraw(ref self: TContractState, operator_nonce: u64, withdraw_args: WithdrawArgs);
    fn withdraw_request(
        ref self: TContractState, signature: Signature, withdraw_args: WithdrawArgs,
    );

    // Funding
    fn funding_tick(
        ref self: TContractState, funding_ticks: Span<FundingTick>, operator_nonce: u64,
    );

    // Configuration
    fn add_asset(self: @TContractState);
    fn add_oracle(self: @TContractState);
    fn add_oracle_to_asset(self: @TContractState);
    fn remove_oracle(self: @TContractState);
    fn remove_oracle_from_asset(self: @TContractState);
    fn update_asset_price(self: @TContractState) {}
    fn update_max_funding_rate(self: @TContractState);
    fn update_oracle_identifiers(self: @TContractState);
}
