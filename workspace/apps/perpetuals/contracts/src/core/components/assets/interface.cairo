use contracts_commons::types::PublicKey;
use contracts_commons::types::time::time::TimeDelta;
use perpetuals::core::types::asset::AssetId;


#[starknet::interface]
pub trait IAssets<TContractState> {
    fn add_synthetic_asset(
        ref self: TContractState, asset_id: AssetId, risk_factor: u8, quorum: u8, resolution: u64,
    );
    fn add_oracle_to_asset(
        ref self: TContractState,
        asset_id: AssetId,
        oracle_public_key: PublicKey,
        oracle_name: felt252,
        asset_name: felt252,
    );
    fn deactivate_synthetic(ref self: TContractState, synthetic_id: AssetId);
    fn get_price_validation_interval(self: @TContractState) -> TimeDelta;
    fn get_funding_validation_interval(self: @TContractState) -> TimeDelta;
    fn get_max_funding_rate(self: @TContractState) -> u32;
    fn remove_oracle_from_asset(
        ref self: TContractState, asset_id: AssetId, oracle_public_key: PublicKey,
    );
    fn update_synthetic_quorum(ref self: TContractState, synthetic_id: AssetId, quorum: u8);
}
