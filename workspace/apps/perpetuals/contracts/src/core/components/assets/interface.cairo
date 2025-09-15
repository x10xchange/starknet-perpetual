use starknet::ContractAddress;
use openzeppelin::interfaces::token::erc20::IERC20Dispatcher;
use perpetuals::core::types::asset::AssetId;
use perpetuals::core::types::asset::synthetic::{AssetConfig, SyntheticTimelyData};
use perpetuals::core::types::funding::FundingTick;
use perpetuals::core::types::price::SignedPrice;
use perpetuals::core::types::risk_factor::RiskFactor;
use starkware_utils::signature::stark::PublicKey;
use starkware_utils::time::time::{TimeDelta, Timestamp};


#[starknet::interface]
pub trait IAssets<TContractState> {
    // Write functions.
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
        risk_factor_tiers: Span<u16>,
        risk_factor_first_tier_boundary: u128,
        risk_factor_tier_size: u128,
        quorum: u8,
        resolution_factor: u64,
    );
    fn add_vault_share_asset(
        ref self: TContractState,
        asset_id: AssetId,
        risk_factor_tiers: Span<u16>,
        risk_factor_first_tier_boundary: u128,
        risk_factor_tier_size: u128,
        quorum: u8,
        resolution_factor: u64,
        quantum: u64,
        erc20_address: ContractAddress,
    );
    fn deactivate_synthetic(ref self: TContractState, synthetic_id: AssetId);
    fn funding_tick(
        ref self: TContractState, operator_nonce: u64, funding_ticks: Span<FundingTick>,
    );
    fn price_tick(
        ref self: TContractState,
        operator_nonce: u64,
        asset_id: AssetId,
        oracle_price: u128,
        signed_prices: Span<SignedPrice>,
    );
    fn remove_oracle_from_asset(
        ref self: TContractState, asset_id: AssetId, oracle_public_key: PublicKey,
    );
    fn update_synthetic_quorum(ref self: TContractState, synthetic_id: AssetId, quorum: u8);

    // View functions.
    fn get_collateral_token_contract(self: @TContractState) -> IERC20Dispatcher;
    fn get_collateral_quantum(self: @TContractState) -> u64;
    fn get_last_funding_tick(self: @TContractState) -> Timestamp;
    fn get_last_price_validation(self: @TContractState) -> Timestamp;
    fn get_max_funding_interval(self: @TContractState) -> TimeDelta;
    fn get_max_funding_rate(self: @TContractState) -> u32;
    fn get_max_price_interval(self: @TContractState) -> TimeDelta;
    fn get_max_oracle_price_validity(self: @TContractState) -> TimeDelta;
    fn get_num_of_active_synthetic_assets(self: @TContractState) -> usize;
    fn get_collateral_id(self: @TContractState) -> AssetId;
    fn get_asset_config(self: @TContractState, synthetic_id: AssetId) -> AssetConfig;
    fn get_synthetic_timely_data(
        self: @TContractState, synthetic_id: AssetId,
    ) -> SyntheticTimelyData;
    fn get_risk_factor_tiers(self: @TContractState, asset_id: AssetId) -> Span<RiskFactor>;

    fn get_asset_erc20_contract(self: @TContractState, asset_id: AssetId) -> IERC20Dispatcher;
}
