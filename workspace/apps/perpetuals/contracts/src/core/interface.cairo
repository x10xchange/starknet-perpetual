use perpetuals::core::types::Signature;
use perpetuals::core::types::deposit_message::DepositMessage;
use perpetuals::core::types::funding::FundingTick;
use perpetuals::core::types::order::Order;
use perpetuals::core::types::withdraw_message::WithdrawMessage;

#[starknet::interface]
pub trait ICore<TContractState> {
    // Flows
    fn deleverage(self: @TContractState);
    fn deposit(self: @TContractState);
    fn register_deposit(
        ref self: TContractState, signature: Signature, deposit_message: DepositMessage,
    );
    fn liquidate(self: @TContractState);
    fn trade(
        ref self: TContractState,
        system_nonce: felt252,
        signature_a: Signature,
        signature_b: Signature,
        order_a: Order,
        order_b: Order,
        actual_fee_a: i64,
        actual_fee_b: i64,
        actual_amount_base_a: i64,
        actual_amount_quote_a: i64,
    );
    fn transfer(self: @TContractState);
    fn withdraw(
        ref self: TContractState,
        system_nonce: felt252,
        signature: Signature,
        withdraw_message: WithdrawMessage,
    );

    // Funding
    fn funding_tick(
        ref self: TContractState, funding_ticks: Span<FundingTick>, system_nonce: felt252,
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
