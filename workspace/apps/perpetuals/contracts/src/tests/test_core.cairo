use contracts_commons::components::roles::interface::IRoles;
use contracts_commons::types::time::Time;
use core::num::traits::Zero;
use perpetuals::core::core::{Core, Core::InternalCoreFunctionsTrait};
use perpetuals::core::types::asset::AssetId;
use perpetuals::core::types::asset::collateral::VERSION as COLLATERAL_VERSION;
use perpetuals::core::types::asset::collateral::{CollateralConfig, CollateralTimelyData};
use perpetuals::core::types::asset::synthetic::VERSION as SYNTHETIC_VERSION;
use perpetuals::core::types::asset::synthetic::{SyntheticConfig, SyntheticTimelyData};
use perpetuals::tests::constants::*;
use snforge_std::start_cheat_block_timestamp_global;

fn CONTRACT_STATE() -> Core::ContractState {
    Core::contract_state_for_testing()
}

fn add_colateral(
    ref state: Core::ContractState,
    collateral_id: AssetId,
    mut collateral_timely_data: CollateralTimelyData,
    collateral_config: CollateralConfig,
) {
    if let Option::Some(head) = state.collateral_timely_data_head.read() {
        collateral_timely_data.next = Option::Some(head);
    }
    state.collateral_timely_data.write(collateral_id, collateral_timely_data);
    state.collateral_timely_data_head.write(Option::Some(collateral_id));
    state.collateral_configs.write(collateral_id, Option::Some(collateral_config));
}

fn add_synthetic(
    ref state: Core::ContractState,
    synthetic_id: AssetId,
    mut synthetic_timely_data: SyntheticTimelyData,
    synthetic_config: SyntheticConfig,
) {
    if let Option::Some(head) = state.synthetic_timely_data_head.read() {
        synthetic_timely_data.next = Option::Some(head);
    }
    state.synthetic_timely_data.write(synthetic_id, synthetic_timely_data);
    state.synthetic_timely_data_head.write(Option::Some(synthetic_id));
    state.synthetic_configs.write(synthetic_id, Option::Some(synthetic_config));
}

fn INITIALIZED_CONTRACT_STATE() -> Core::ContractState {
    let mut state = CONTRACT_STATE();
    Core::constructor(
        ref state,
        governance_admin: GOVERNANCE_ADMIN(),
        value_risk_calculator: VALUE_RISK_CALCULATOR_CONTRACT_ADDRESS(),
        price_validation_interval: PRICE_VALIDATION_INTERVAL,
        funding_validation_interval: FUNDING_VALIDATION_INTERVAL,
        max_funding_rate: MAX_FUNDING_RATE,
    );
    state
}

#[test]
fn test_constructor() {
    let mut state = INITIALIZED_CONTRACT_STATE();
    assert!(state.roles.is_governance_admin(GOVERNANCE_ADMIN()));
    assert_eq!(
        state.value_risk_calculator_dispatcher.read().contract_address,
        VALUE_RISK_CALCULATOR_CONTRACT_ADDRESS(),
    );
    assert_eq!(state.price_validation_interval.read(), PRICE_VALIDATION_INTERVAL);
    assert_eq!(state.funding_validation_interval.read(), FUNDING_VALIDATION_INTERVAL);
    assert_eq!(state.max_funding_rate.read(), MAX_FUNDING_RATE);
    assert_eq!(state.price_validation_interval.read(), PRICE_VALIDATION_INTERVAL);
}

#[test]
fn test_validate_collateral_prices() {
    let mut state = INITIALIZED_CONTRACT_STATE();
    let now = Time::now();
    let collateral_id = ASSET_ID();
    let collateral_config = CollateralConfig {
        version: COLLATERAL_VERSION,
        address: TOKEN_ADDRESS(),
        quantum: COLLATERAL_QUANTUM,
        decimals: COLLATERAL_DECIMALS,
        is_active: true,
        risk_factor: RISK_FACTOR(),
        quorum: COLLATERAL_QUORUM,
    };
    // Add collateral timely data with valid last price update
    let collateral_timely_data = CollateralTimelyData {
        version: COLLATERAL_VERSION, price: PRICE(), last_price_update: now, next: Option::None,
    };
    add_colateral(ref state, collateral_id, collateral_timely_data, collateral_config);

    // Call the function
    state._validate_collateral_prices(:now, price_validation_interval: PRICE_VALIDATION_INTERVAL);
    // If no assertion error is thrown, the test passes
}

#[test]
#[should_panic(expected: 'COLLATERAL_EXPIRED_PRICE')]
fn test_validate_collateral_prices_expired() {
    let mut state = CONTRACT_STATE();
    let now = Time::now();
    let collateral_id = ASSET_ID();
    let collateral_config = CollateralConfig {
        version: COLLATERAL_VERSION,
        address: TOKEN_ADDRESS(),
        quantum: COLLATERAL_QUANTUM,
        decimals: COLLATERAL_DECIMALS,
        is_active: true,
        risk_factor: RISK_FACTOR(),
        quorum: COLLATERAL_QUORUM,
    };
    // Add collateral timely data with valid last price update
    let collateral_timely_data = CollateralTimelyData {
        version: COLLATERAL_VERSION, price: PRICE(), last_price_update: now, next: Option::None,
    };
    add_colateral(ref state, collateral_id, collateral_timely_data, collateral_config);
    let now = now.add(PRICE_VALIDATION_INTERVAL);
    // Set the block timestamp to be after the price validation interval
    start_cheat_block_timestamp_global(block_timestamp: now.into());
    // Call the function, should panic with EXPIRED_PRICE error
    state._validate_collateral_prices(:now, price_validation_interval: PRICE_VALIDATION_INTERVAL);
}
#[test]
fn test_validate_synthetic_prices() {
    let mut state = CONTRACT_STATE();
    let now = Time::now();
    let synthetic_id = ASSET_ID();
    let synthetic_config = SyntheticConfig {
        version: SYNTHETIC_VERSION,
        resolution: SYNTHETIC_RESOLUTION,
        decimals: SYNTHETIC_DECIMALS,
        is_active: true,
        risk_factor: RISK_FACTOR(),
        quorum: SYNTHETIC_QUORUM,
    };
    // Add synthetic timely data with expired last price update
    let synthetic_timely_data = SyntheticTimelyData {
        version: SYNTHETIC_VERSION,
        price: PRICE(),
        last_price_update: now,
        funding_index: Zero::zero(),
        next: Option::None,
    };
    add_synthetic(ref state, synthetic_id, synthetic_timely_data, synthetic_config);
    // Call the function
    state._validate_synthetic_prices(:now, price_validation_interval: PRICE_VALIDATION_INTERVAL);
    // If no assertion error is thrown, the test passes
}

#[test]
#[should_panic(expected: 'SYNTHETIC_EXPIRED_PRICE')]
fn test_validate_synthetic_prices_expired() {
    let mut state = CONTRACT_STATE();
    let now = Time::now();
    let synthetic_id = ASSET_ID();
    let synthetic_config = SyntheticConfig {
        version: SYNTHETIC_VERSION,
        resolution: SYNTHETIC_RESOLUTION,
        decimals: SYNTHETIC_DECIMALS,
        is_active: true,
        risk_factor: RISK_FACTOR(),
        quorum: SYNTHETIC_QUORUM,
    };
    // Add synthetic timely data with expired last price update
    let synthetic_timely_data = SyntheticTimelyData {
        version: SYNTHETIC_VERSION,
        price: PRICE(),
        last_price_update: now,
        funding_index: Zero::zero(),
        next: Option::None,
    };
    add_synthetic(ref state, synthetic_id, synthetic_timely_data, synthetic_config);

    let now = now.add(PRICE_VALIDATION_INTERVAL);
    // Set the block timestamp to be after the price validation interval
    start_cheat_block_timestamp_global(block_timestamp: now.into());
    // Call the function, should panic with EXPIRED_PRICE error
    state._validate_synthetic_prices(:now, price_validation_interval: PRICE_VALIDATION_INTERVAL);
}

#[test]
fn test_validate_prices() {
    let mut state = CONTRACT_STATE();
    let now = Time::now();

    state.last_price_validation.write(now);
    assert_eq!(state.last_price_validation.read(), now);
    let new_time = now.add(delta: Time::days(count: 1));
    start_cheat_block_timestamp_global(block_timestamp: new_time.into());
    let now = Time::now();
    state._validate_prices(:now);
    assert_eq!(state.last_price_validation.read(), new_time);
}

#[test]
fn test_validate_prices_no_update_needed() {
    let mut state = CONTRACT_STATE();
    let now = Time::now();
    state.last_price_validation.write(now);
    state._validate_prices(:now);
    assert_eq!(state.last_price_validation.read(), now);
}
