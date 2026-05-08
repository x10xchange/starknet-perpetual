use starknet::ContractAddress;

#[starknet::interface]
pub trait IDepositLimits<TContractState> {
    /// Sets the per-token deposit cap. `whole_amount` is in whole token units (e.g. 1 BTC,
    /// 100 ETH); the contract scales by `10^decimals` using the ERC20's reported decimals.
    /// Until this is called for a token, the cap is unset (treated as unlimited).
    fn set_max_deposit(
        ref self: TContractState, token_address: ContractAddress, whole_amount: u256,
    );
    fn get_max_deposit(self: @TContractState, token_address: ContractAddress) -> Option<u256>;
}
