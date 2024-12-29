use contracts_commons::components::roles::interface::IRoles;
use contracts_commons::message_hash::OffchainMessageHash;
use contracts_commons::test_utils::{TokenState, TokenTrait, cheat_caller_address_once};
use contracts_commons::types::time::Time;
use core::num::traits::Zero;
use openzeppelin::utils::interfaces::INonces;
use perpetuals::core::core::{Core, Core::InternalCoreFunctionsTrait, Core::SNIP12MetadataImpl};
use perpetuals::core::interface::ICore;
use perpetuals::core::types::AssetAmount;
use perpetuals::core::types::asset::AssetId;
use perpetuals::core::types::asset::collateral::VERSION as COLLATERAL_VERSION;
use perpetuals::core::types::asset::collateral::{CollateralConfig, CollateralTimelyData};
use perpetuals::core::types::asset::synthetic::VERSION as SYNTHETIC_VERSION;
use perpetuals::core::types::asset::synthetic::{SyntheticConfig, SyntheticTimelyData};
use perpetuals::core::types::withdraw_message::WithdrawMessage;
use perpetuals::tests::constants::*;
use perpetuals::tests::test_utils::{
    PerpetualsInitConfig, User, UserTrait, generate_collateral_config, set_roles,
};
use snforge_std::start_cheat_block_timestamp_global;
use snforge_std::test_address;
use starknet::storage::StoragePathEntry;

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

fn setup_state(cfg: @PerpetualsInitConfig, token_state: @TokenState) -> Core::ContractState {
    let mut state = INITIALIZED_CONTRACT_STATE();
    set_roles(ref :state, :cfg);
    state.last_funding_tick.write(Time::now());
    state.last_price_validation.write(Time::now());
    state.funding_validation_interval.write(*cfg.funding_validation_interval);
    let collateral_config = generate_collateral_config(:token_state);
    state.collateral_configs.write(*cfg.collateral_cfg.asset_id, Option::Some(collateral_config));
    state
}

fn init_user_for_withdraw(
    cfg: @PerpetualsInitConfig,
    ref state: Core::ContractState,
    ref user: User,
    token_state: @TokenState,
) {
    let position = state.positions.entry(user.position_id);
    position.owner_public_key.write(user.key_pair.public_key);
    let asset_balance = position.collateral_assets.entry(*cfg.collateral_cfg.asset_id).balance;
    let current_amount = asset_balance.read();
    asset_balance.write(WITHDRAW_AMOUNT.into() + current_amount);
    (*token_state).fund(recipient: test_address(), amount: WITHDRAW_AMOUNT.try_into().unwrap());
    user.deposited_collateral = current_amount.into() + WITHDRAW_AMOUNT;
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

#[test]
fn test_successful_withdraw() {
    // Setup state, token and user:
    let cfg: PerpetualsInitConfig = Default::default();
    let token_state = cfg.collateral_cfg.token_cfg.deploy();
    let mut state = setup_state(cfg: @cfg, token_state: @token_state);
    let mut user = Default::default();
    init_user_for_withdraw(cfg: @cfg, ref :state, ref :user, token_state: @token_state);

    // Setup parameters:
    let mut expiration = Time::now();
    expiration += Time::days(1);

    let mut withdraw_message = WithdrawMessage {
        position_id: user.position_id,
        salt: user.salt_counter,
        expiration,
        collateral: AssetAmount {
            asset_id: cfg.collateral_cfg.asset_id, amount: user.deposited_collateral,
        },
        recipient: user.address,
    };
    let signature = user.sign_message(withdraw_message.get_message_hash(user.key_pair.public_key));
    cheat_caller_address_once(contract_address: test_address(), caller_address: cfg.operator);
    let system_nonce = state.nonces.nonces(owner: test_address());

    // Test:
    state.withdraw(:system_nonce, :signature, :withdraw_message);

    // Check:
    let user_balance = token_state.balance_of(user.address);
    assert_eq!(user_balance, WITHDRAW_AMOUNT.try_into().unwrap());
    let contract_state_balance = token_state.balance_of(test_address());
    assert_eq!(contract_state_balance, Zero::zero());
}
