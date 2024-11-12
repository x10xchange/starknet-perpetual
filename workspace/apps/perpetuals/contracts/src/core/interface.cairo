use contracts_commons::types::time::TimeStamp;
use perpetuals::core::types::Signature;
use perpetuals::core::types::asset::AssetId;
use starknet::ContractAddress;

#[starknet::interface]
pub trait ICore<TContractState> {
    // Flows
    fn deleverage(self: @TContractState);
    fn deposit(self: @TContractState);
    fn liquidate(self: @TContractState);
    fn trade(self: @TContractState);
    fn transfer(self: @TContractState);
    fn withdraw(
        ref self: TContractState,
        position_id: felt252,
        collateral_id: AssetId,
        recipient: ContractAddress,
        nonce: felt252,
        expiry: TimeStamp,
        amount: u128,
        salt: felt252,
        signature: Signature,
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
