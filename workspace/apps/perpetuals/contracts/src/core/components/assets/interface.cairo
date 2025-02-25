use contracts_commons::types::PublicKey;
use contracts_commons::types::fixed_two_decimal::FixedTwoDecimal;
use contracts_commons::types::time::time::{TimeDelta, Timestamp};
use perpetuals::core::types::asset::AssetId;
use perpetuals::core::types::asset::collateral::CollateralConfig;
use perpetuals::core::types::asset::synthetic::{SyntheticConfig, SyntheticTimelyData};
use perpetuals::core::types::funding::FundingTick;
use perpetuals::core::types::price::SignedPrice;
use starknet::ContractAddress;


#[starknet::interface]
pub trait IAssets<TContractState> {
    fn register_collateral(
        ref self: TContractState, asset_id: AssetId, token_address: ContractAddress, quantum: u64,
    );
    fn add_oracle_to_asset(
        ref self: TContractState,
        asset_id: AssetId,
        oracle_public_key: PublicKey,
        oracle_name: felt252,
        asset_name: felt252,
    );
    fn add_synthetic_asset(
        ref self: TContractState,
        asset_id: AssetId,
        risk_factor_tiers: Span<u8>,
        risk_factor_first_tier_boundary: u128,
        risk_factor_tier_size: u128,
        quorum: u8,
        resolution: u64,
    );
    fn deactivate_synthetic(ref self: TContractState, synthetic_id: AssetId);
    fn funding_tick(
        ref self: TContractState, operator_nonce: u64, funding_ticks: Span<FundingTick>,
    );
    fn price_tick(
        ref self: TContractState,
        operator_nonce: u64,
        asset_id: AssetId,
        price: u128,
        signed_prices: Span<SignedPrice>,
    );
    fn get_collateral_config(self: @TContractState, collateral_id: AssetId) -> CollateralConfig;
    fn get_funding_validation_interval(self: @TContractState) -> TimeDelta;
    fn get_last_funding_tick(self: @TContractState) -> Timestamp;
    fn get_last_price_validation(self: @TContractState) -> Timestamp;
    fn get_max_funding_rate(self: @TContractState) -> u32;
    fn get_max_oracle_price_validity(self: @TContractState) -> TimeDelta;
    fn get_num_of_active_synthetic_assets(self: @TContractState) -> usize;
    fn get_price_validation_interval(self: @TContractState) -> TimeDelta;
    fn get_synthetic_config(self: @TContractState, synthetic_id: AssetId) -> SyntheticConfig;
    fn get_synthetic_timely_data(
        self: @TContractState, synthetic_id: AssetId,
    ) -> SyntheticTimelyData;
    fn get_risk_factor_tiers(self: @TContractState, asset_id: AssetId) -> Span<FixedTwoDecimal>;
    fn remove_oracle_from_asset(
        ref self: TContractState, asset_id: AssetId, oracle_public_key: PublicKey,
    );
    fn update_synthetic_quorum(ref self: TContractState, synthetic_id: AssetId, quorum: u8);
}
