use contracts_commons::types::time::time::TimeDelta;

#[starknet::interface]
pub trait IAssets<TContractState> {
    fn get_price_validation_interval(self: @TContractState) -> TimeDelta;
    fn get_funding_validation_interval(self: @TContractState) -> TimeDelta;
    fn get_max_funding_rate(self: @TContractState) -> u32;
}
