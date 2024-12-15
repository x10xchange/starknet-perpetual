use contracts_commons::types::time::Timestamp;
use perpetuals::core::types::asset::AssetId;
use perpetuals::core::types::order::Order;
use perpetuals::core::types::{Fee, Signature};
use starknet::ContractAddress;

#[starknet::interface]
pub trait ICore<TContractState> {
    // Flows
    fn deleverage(self: @TContractState);
    fn deposit(self: @TContractState);
    fn liquidate(self: @TContractState);
    fn trade(
        ref self: TContractState,
        order_a: Order,
        order_b: Order,
        actual_fee_a: Fee,
        actual_fee_b: Fee,
        actual_amount_base_a: i128,
        actual_amount_quote_a: i128,
        system_nonce: felt252,
    );
    fn transfer(self: @TContractState);
    fn withdraw(
        ref self: TContractState,
        signature: Signature,
        system_nonce: felt252,
        // WithdrawMessage
        position_id: felt252,
        salt: felt252,
        expiration: Timestamp,
        collateral_id: AssetId,
        amount: u128,
        recipient: ContractAddress,
    );

    // Funding
    fn funding_tick(self: @TContractState);

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
