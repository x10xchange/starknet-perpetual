use openzeppelin::interfaces::erc20::IERC20Dispatcher;
use perpetuals::core::types::asset::AssetId;
use perpetuals::core::types::asset::synthetic::{AssetConfig, TimelyData};
use perpetuals::core::types::funding::FundingTick;
use perpetuals::core::types::price::SignedPrice;
use perpetuals::core::types::risk_factor::RiskFactor;
use starknet::ContractAddress;
use starkware_utils::signature::stark::{HashType, PublicKey};
use starkware_utils::time::time::{TimeDelta, Timestamp};

/// Raw per-asset record for state export: everything stored about one asset
/// except the oracle registry (whose keys are not enumerable on-chain). Both
/// optional fields mirror the raw storage slots exactly (`asset_config` is a
/// `Map<AssetId, Option<AssetConfig>>`; `timely_data` is an `IterableMap`,
/// which reads `None` for a key it never held). Every registration path
/// writes both together and nothing ever clears them, so for a registered id
/// (deactivated or not) both are `Some`; for an id that was never registered
/// both are `None` and `risk_factor_tiers` is empty. A copier must treat a
/// `None` as "no such slot", never as zero-valued config/data.
#[derive(Drop, Serde)]
pub struct AssetDump {
    pub asset_id: AssetId,
    pub config: Option<AssetConfig>,
    pub timely_data: Option<TimelyData>,
    pub risk_factor_tiers: Array<RiskFactor>,
}

/// The assets component's scalars (everything not keyed by asset id) in one
/// record; the per-asset records are exported separately, per page of ids,
/// via `export_assets`. Collateral lives in no per-asset map; it round-trips
/// entirely through these scalars.
#[derive(Drop, Serde)]
pub struct AssetsDumpScalars {
    pub max_funding_rate: u32,
    pub max_price_interval: TimeDelta,
    pub max_funding_interval: TimeDelta,
    pub last_price_validation: Timestamp,
    pub last_funding_tick: Timestamp,
    pub collateral_token_address: ContractAddress,
    pub collateral_quantum: u64,
    pub num_of_active_synthetic_assets: usize,
    pub max_oracle_price_validity: TimeDelta,
    pub collateral_id: Option<AssetId>,
    pub risk_factor_request_hash: HashType,
}

#[starknet::interface]
pub trait IAssets<TContractState> {
    // Write functions.
    fn funding_tick(
        ref self: TContractState,
        operator_nonce: u64,
        funding_ticks: Span<FundingTick>,
        timestamp: Timestamp,
    );
    fn price_tick(
        ref self: TContractState,
        operator_nonce: u64,
        asset_id: AssetId,
        oracle_price: u128,
        signed_prices: Span<SignedPrice>,
    );

    // View functions.
    fn get_collateral_token_contract_address(
        self: @TContractState, asset_id: AssetId,
    ) -> ContractAddress;
    fn get_base_collateral_token_contract(self: @TContractState) -> IERC20Dispatcher;
    fn get_collateral_quantum(self: @TContractState) -> u64;
    fn get_last_funding_tick(self: @TContractState) -> Timestamp;
    fn get_last_price_validation(self: @TContractState) -> Timestamp;
    fn get_num_of_active_synthetic_assets(self: @TContractState) -> usize;
    fn get_base_collateral_id(self: @TContractState) -> AssetId;
    fn get_asset_config(self: @TContractState, asset_id: AssetId) -> AssetConfig;
    fn get_timely_data(self: @TContractState, asset_id: AssetId) -> TimelyData;
    fn get_risk_factor_tiers(self: @TContractState, asset_id: AssetId) -> Span<RiskFactor>;
}


#[starknet::interface]
pub trait IAssetsManager<TContractState> {
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
    fn update_asset_risk_factor(
        ref self: TContractState,
        operator_nonce: u64,
        asset_id: AssetId,
        risk_factor_tiers: Span<u16>,
        risk_factor_first_tier_boundary: u128,
        risk_factor_tier_size: u128,
    );
    fn update_asset_risk_factor_request(
        ref self: TContractState,
        asset_id: AssetId,
        risk_factor_tiers: Span<u16>,
        risk_factor_first_tier_boundary: u128,
        risk_factor_tier_size: u128,
    );
    fn add_vault_collateral_asset(
        ref self: TContractState,
        asset_id: AssetId,
        erc20_contract_address: ContractAddress,
        quantum: u64,
        risk_factor: u16,
        quorum: u8,
    );
    fn add_spot_asset(
        ref self: TContractState,
        asset_id: AssetId,
        erc20_contract_address: ContractAddress,
        quantum: u64,
        resolution_factor: u64,
        risk_factor: u16,
        quorum: u8,
    );
    fn deactivate_synthetic(ref self: TContractState, synthetic_id: AssetId);
    fn remove_oracle_from_asset(
        ref self: TContractState, asset_id: AssetId, oracle_public_key: PublicKey,
    );
    fn update_asset_quorum(ref self: TContractState, asset_id: AssetId, quorum: u8);

    // View functions.
    fn get_max_price_interval(self: @TContractState) -> TimeDelta;
    fn get_max_funding_interval(self: @TContractState) -> TimeDelta;
    fn get_max_oracle_price_validity(self: @TContractState) -> TimeDelta;
    fn get_max_funding_rate(self: @TContractState) -> u32;
}
