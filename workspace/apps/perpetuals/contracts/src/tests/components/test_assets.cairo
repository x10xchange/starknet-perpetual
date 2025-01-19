use contracts_commons::test_utils::{Deployable, TokenState, TokenTrait};
use contracts_commons::types::time::time::Time;
use perpetuals::core::components::assets::AssetsComponent::InternalTrait as AssetsInternal;
use perpetuals::core::components::assets::assets::AssetsComponent;
use perpetuals::core::core::Core;
use perpetuals::core::core::Core::SNIP12MetadataImpl;
use perpetuals::tests::constants::*;
use perpetuals::tests::test_utils::{PerpetualsInitConfig, generate_collateral};
use snforge_std::{start_cheat_block_timestamp_global, test_address};
use starknet::storage::{
    StorageMapWriteAccess, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess,
};

fn COMPONENT_STATE() -> AssetsComponent::ComponentState<Core::ContractState> {
    AssetsComponent::component_state_for_testing()
}

fn initialized_component_state() -> AssetsComponent::ComponentState<Core::ContractState> {
    let mut state = COMPONENT_STATE();
    state
}

fn setup_state(
    cfg: @PerpetualsInitConfig, token_state: @TokenState,
) -> AssetsComponent::ComponentState<Core::ContractState> {
    let mut state = initialized_component_state();
    state
        .initialize(
            max_price_interval: *cfg.max_price_interval,
            max_funding_interval: *cfg.max_funding_interval,
            max_funding_rate: *cfg.max_funding_rate,
        );
    add_colateral(ref :state, :cfg, :token_state);
    // Synthetic asset configs.
    add_synthetic(ref :state, :cfg);
    // Fund the contract.
    (*token_state)
        .fund(recipient: test_address(), amount: CONTRACT_INIT_BALANCE.try_into().unwrap());

    state
}


fn add_colateral(
    ref state: AssetsComponent::ComponentState<Core::ContractState>,
    cfg: @PerpetualsInitConfig,
    token_state: @TokenState,
) {
    let (collateral_config, mut collateral_timely_data) = generate_collateral(:token_state);
    state.collateral_config.write(*cfg.collateral_cfg.asset_id, Option::Some(collateral_config));
    state.collateral_timely_data.write(*cfg.collateral_cfg.asset_id, collateral_timely_data);
    state.collateral_timely_data_head.write(Option::Some(*cfg.collateral_cfg.asset_id));
}

fn add_synthetic(
    ref state: AssetsComponent::ComponentState<Core::ContractState>, cfg: @PerpetualsInitConfig,
) {
    state.synthetic_timely_data.write(*cfg.synthetic_cfg.asset_id, SYNTHETIC_TIMELY_DATA());
    state.synthetic_timely_data_head.write(Option::Some(*cfg.synthetic_cfg.asset_id));
    state.synthetic_config.write(*cfg.synthetic_cfg.asset_id, Option::Some(SYNTHETIC_CONFIG()));
}

#[test]
fn test_validate_collateral_prices() {
    let cfg: PerpetualsInitConfig = Default::default();
    let token_state = cfg.collateral_cfg.token_cfg.deploy();
    let mut state = setup_state(cfg: @cfg, token_state: @token_state);
    // Call the function
    state._validate_collateral_prices(now: Time::now(), max_price_interval: MAX_PRICE_INTERVAL);
    // If no assertion error is thrown, the test passes
}

#[test]
#[should_panic(expected: 'COLLATERAL_EXPIRED_PRICE')]
fn test_validate_collateral_prices_expired() {
    let cfg: PerpetualsInitConfig = Default::default();
    let token_state = cfg.collateral_cfg.token_cfg.deploy();
    let mut state = setup_state(cfg: @cfg, token_state: @token_state);
    // Set the block timestamp to be after the price validation interval
    let now = Time::now().add(MAX_PRICE_INTERVAL);
    start_cheat_block_timestamp_global(block_timestamp: now.into());
    // Call the function, should panic with EXPIRED_PRICE error
    state._validate_collateral_prices(:now, max_price_interval: MAX_PRICE_INTERVAL);
}

#[test]
fn test_validate_synthetic_prices() {
    let cfg: PerpetualsInitConfig = Default::default();
    let token_state = cfg.collateral_cfg.token_cfg.deploy();
    let mut state = setup_state(cfg: @cfg, token_state: @token_state);
    state._validate_synthetic_prices(now: Time::now(), max_price_interval: MAX_PRICE_INTERVAL);
    // If no assertion error is thrown, the test passes
}

#[test]
#[should_panic(expected: 'SYNTHETIC_EXPIRED_PRICE')]
fn test_validate_synthetic_prices_expired() {
    let cfg: PerpetualsInitConfig = Default::default();
    let token_state = cfg.collateral_cfg.token_cfg.deploy();
    let mut state = setup_state(cfg: @cfg, token_state: @token_state);
    // Set the block timestamp to be after the price validation interval
    let now = Time::now().add(MAX_PRICE_INTERVAL);
    start_cheat_block_timestamp_global(block_timestamp: now.into());
    // Call the function, should panic with EXPIRED_PRICE error
    state._validate_synthetic_prices(:now, max_price_interval: MAX_PRICE_INTERVAL);
}

#[test]
fn test_validate_prices() {
    let cfg: PerpetualsInitConfig = Default::default();
    let token_state = cfg.collateral_cfg.token_cfg.deploy();
    let mut state = setup_state(cfg: @cfg, token_state: @token_state);
    let new_time = Time::now().add(delta: Time::days(count: 1));
    start_cheat_block_timestamp_global(block_timestamp: new_time.into());
    // Update last price updates for assets
    let now = Time::now();
    state.synthetic_timely_data.entry(cfg.synthetic_cfg.asset_id).last_price_update.write(now);
    state.collateral_timely_data.entry(cfg.collateral_cfg.asset_id).last_price_update.write(now);
    state._validate_prices(:now);
    assert_eq!(state.last_price_validation.read(), new_time);
}

#[test]
fn test_validate_prices_no_update_needed() {
    let cfg: PerpetualsInitConfig = Default::default();
    let token_state = cfg.collateral_cfg.token_cfg.deploy();
    let mut state = setup_state(cfg: @cfg, token_state: @token_state);
    let old_time = Time::now();
    assert_eq!(state.last_price_validation.read(), old_time);
    let new_time = Time::now().add(delta: Time::seconds(count: 1));
    start_cheat_block_timestamp_global(block_timestamp: new_time.into());
    state._validate_prices(now: new_time);
    assert_eq!(state.last_price_validation.read(), old_time);
}
