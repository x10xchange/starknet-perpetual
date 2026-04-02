use starknet::ContractAddress;

#[starknet::interface]
pub trait ITreasury<TState> {
    fn get_perps_contract(self: @TState) -> ContractAddress;
    fn deposit_into(ref self: TState, collateral_address: ContractAddress, amount: u256);
    fn withdraw_from(ref self: TState, collateral_address: ContractAddress, amount: u256);
    fn reset_protection_limit(ref self: TState, collateral_address: ContractAddress);
    fn change_protection_limit_percent(ref self: TState, collateral_address: ContractAddress, percent: u64);
}
