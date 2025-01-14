use contracts_commons::components::roles::interface::IRoles;
use contracts_commons::math::Abs;
use contracts_commons::message_hash::OffchainMessageHash;
use contracts_commons::test_utils::{Deployable, TokenState, TokenTrait, cheat_caller_address_once};
use contracts_commons::types::time::time::Time;
use core::num::traits::Zero;
use openzeppelin::utils::interfaces::INonces;
use perpetuals::core::components::assets::AssetsComponent::InternalTrait as AssetsInternal;
use perpetuals::core::components::assets::interface::IAssets;
use perpetuals::core::core::Core;
use perpetuals::core::core::Core::SNIP12MetadataImpl;
use perpetuals::core::interface::ICore;
use perpetuals::core::types::AssetAmount;
use perpetuals::core::types::asset::AssetId;
use perpetuals::core::types::asset::collateral::{
    CollateralConfig, CollateralTimelyData, VERSION as COLLATERAL_VERSION,
};
use perpetuals::core::types::asset::synthetic::{
    SyntheticConfig, SyntheticTimelyData, VERSION as SYNTHETIC_VERSION,
};
use perpetuals::core::types::deposit::DepositArgs;
use perpetuals::core::types::order::Order;
use perpetuals::core::types::withdraw::WithdrawArgs;
use perpetuals::tests::constants::*;
use perpetuals::tests::test_utils::{
    PerpetualsInitConfig, User, UserTrait, deploy_value_risk_calculator_contract,
    generate_collateral_config, set_roles,
};
use snforge_std::{start_cheat_block_timestamp_global, test_address};
use starknet::get_caller_address;
use starknet::storage::{
    StorageMapWriteAccess, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess,
};

fn CONTRACT_STATE() -> Core::ContractState {
    Core::contract_state_for_testing()
}

fn add_colateral(
    ref state: Core::ContractState,
    collateral_id: AssetId,
    mut collateral_timely_data: CollateralTimelyData,
    collateral_config: CollateralConfig,
) {
    if let Option::Some(head) = state.assets.collateral_timely_data_head.read() {
        collateral_timely_data.next = Option::Some(head);
    }
    state.assets.collateral_timely_data.write(collateral_id, collateral_timely_data);
    state.assets.collateral_timely_data_head.write(Option::Some(collateral_id));
    state.assets.collateral_configs.write(collateral_id, Option::Some(collateral_config));
}

fn add_synthetic(
    ref state: Core::ContractState,
    synthetic_id: AssetId,
    mut synthetic_timely_data: SyntheticTimelyData,
    synthetic_config: SyntheticConfig,
) {
    if let Option::Some(head) = state.assets.synthetic_timely_data_head.read() {
        synthetic_timely_data.next = Option::Some(head);
    }
    state.assets.synthetic_timely_data.write(synthetic_id, synthetic_timely_data);
    state.assets.synthetic_timely_data_head.write(Option::Some(synthetic_id));
    state.assets.synthetic_configs.write(synthetic_id, Option::Some(synthetic_config));
}

fn setup_state(cfg: @PerpetualsInitConfig, token_state: @TokenState) -> Core::ContractState {
    let mut state = initialized_contract_state();
    set_roles(ref :state, :cfg);
    state
        .assets
        .initialize(
            price_validation_interval: *cfg.price_validation_interval,
            funding_validation_interval: *cfg.funding_validation_interval,
            max_funding_rate: *cfg.max_funding_rate,
        );
    // Collateral asset configs.
    let collateral_config = generate_collateral_config(:token_state);
    state
        .assets
        .collateral_configs
        .write(*cfg.collateral_cfg.asset_id, Option::Some(collateral_config));

    // Synthetic asset configs.
    let synthetic_config = SYNTHETIC_CONFIG();
    state
        .assets
        .synthetic_configs
        .write(*cfg.synthetic_cfg.asset_id, Option::Some(synthetic_config));

    // Fund the contract.
    (*token_state)
        .fund(recipient: test_address(), amount: CONTRACT_INIT_BALANCE.try_into().unwrap());

    state
}

fn init_position(
    cfg: @PerpetualsInitConfig,
    ref state: Core::ContractState,
    user: User,
    token_state: @TokenState,
) {
    let position = state.positions.entry(user.position_id);
    position.owner_public_key.write(user.key_pair.public_key);
    let collateral_asset_balance = position
        .collateral_assets
        .entry(*cfg.collateral_cfg.asset_id)
        .balance;
    collateral_asset_balance.write(COLLATERAL_BALANCE_AMOUNT.into());

    let synthetic_asset_balance = position
        .synthetic_assets
        .entry(*cfg.synthetic_cfg.asset_id)
        .balance;
    synthetic_asset_balance.write(SYNTHETIC_BALANCE_AMOUNT.into());
}

fn initialized_contract_state() -> Core::ContractState {
    let mut state = CONTRACT_STATE();
    Core::constructor(
        ref state,
        governance_admin: GOVERNANCE_ADMIN(),
        value_risk_calculator: deploy_value_risk_calculator_contract(),
        price_validation_interval: PRICE_VALIDATION_INTERVAL,
        funding_validation_interval: FUNDING_VALIDATION_INTERVAL,
        max_funding_rate: MAX_FUNDING_RATE,
    );
    state
}

#[test]
fn test_constructor() {
    let mut state = initialized_contract_state();
    assert!(state.roles.is_governance_admin(GOVERNANCE_ADMIN()));
    assert_eq!(state.assets.get_price_validation_interval(), PRICE_VALIDATION_INTERVAL);
    assert_eq!(state.assets.get_funding_validation_interval(), FUNDING_VALIDATION_INTERVAL);
    assert_eq!(state.assets.get_max_funding_rate(), MAX_FUNDING_RATE);
}

#[test]
fn test_validate_collateral_prices() {
    let mut state = initialized_contract_state();
    let now = Time::now();
    let collateral_id = ASSET_ID_1();
    let collateral_config = CollateralConfig {
        version: COLLATERAL_VERSION,
        address: TOKEN_ADDRESS(),
        quantum: COLLATERAL_QUANTUM,
        is_active: true,
        risk_factor: RISK_FACTOR(),
        quorum: COLLATERAL_QUORUM,
    };
    // Add collateral timely data with valid last price update
    let collateral_timely_data = CollateralTimelyData {
        version: COLLATERAL_VERSION, price: PRICE_1(), last_price_update: now, next: Option::None,
    };
    add_colateral(ref state, collateral_id, collateral_timely_data, collateral_config);

    // Call the function
    state
        .assets
        ._validate_collateral_prices(:now, price_validation_interval: PRICE_VALIDATION_INTERVAL);
    // If no assertion error is thrown, the test passes
}

#[test]
#[should_panic(expected: 'COLLATERAL_EXPIRED_PRICE')]
fn test_validate_collateral_prices_expired() {
    let mut state = CONTRACT_STATE();
    let now = Time::now();
    let collateral_id = ASSET_ID_1();
    let collateral_config = CollateralConfig {
        version: COLLATERAL_VERSION,
        address: TOKEN_ADDRESS(),
        quantum: COLLATERAL_QUANTUM,
        is_active: true,
        risk_factor: RISK_FACTOR(),
        quorum: COLLATERAL_QUORUM,
    };
    // Add collateral timely data with valid last price update
    let collateral_timely_data = CollateralTimelyData {
        version: COLLATERAL_VERSION, price: PRICE_1(), last_price_update: now, next: Option::None,
    };
    add_colateral(ref state, collateral_id, collateral_timely_data, collateral_config);
    let now = now.add(PRICE_VALIDATION_INTERVAL);
    // Set the block timestamp to be after the price validation interval
    start_cheat_block_timestamp_global(block_timestamp: now.into());
    // Call the function, should panic with EXPIRED_PRICE error
    state
        .assets
        ._validate_collateral_prices(:now, price_validation_interval: PRICE_VALIDATION_INTERVAL);
}
#[test]
fn test_validate_synthetic_prices() {
    let mut state = CONTRACT_STATE();
    let now = Time::now();
    let synthetic_id = ASSET_ID_1();
    let synthetic_config = SYNTHETIC_CONFIG();
    // Add synthetic timely data with expired last price update
    let synthetic_timely_data = SyntheticTimelyData {
        version: SYNTHETIC_VERSION,
        price: PRICE_1(),
        last_price_update: now,
        funding_index: Zero::zero(),
        next: Option::None,
    };
    add_synthetic(ref state, synthetic_id, synthetic_timely_data, synthetic_config);
    // Call the function
    state
        .assets
        ._validate_synthetic_prices(:now, price_validation_interval: PRICE_VALIDATION_INTERVAL);
    // If no assertion error is thrown, the test passes
}

#[test]
#[should_panic(expected: 'SYNTHETIC_EXPIRED_PRICE')]
fn test_validate_synthetic_prices_expired() {
    let mut state = CONTRACT_STATE();
    let now = Time::now();
    let synthetic_id = ASSET_ID_1();
    let synthetic_config = SYNTHETIC_CONFIG();
    // Add synthetic timely data with expired last price update
    let synthetic_timely_data = SyntheticTimelyData {
        version: SYNTHETIC_VERSION,
        price: PRICE_1(),
        last_price_update: now,
        funding_index: Zero::zero(),
        next: Option::None,
    };
    add_synthetic(ref state, synthetic_id, synthetic_timely_data, synthetic_config);

    let now = now.add(PRICE_VALIDATION_INTERVAL);
    // Set the block timestamp to be after the price validation interval
    start_cheat_block_timestamp_global(block_timestamp: now.into());
    // Call the function, should panic with EXPIRED_PRICE error
    state
        .assets
        ._validate_synthetic_prices(:now, price_validation_interval: PRICE_VALIDATION_INTERVAL);
}

#[test]
fn test_validate_prices() {
    let mut state = CONTRACT_STATE();
    let mut now = Time::now();

    state.assets.last_price_validation.write(now);
    assert_eq!(state.assets.last_price_validation.read(), now);
    let new_time = now.add(delta: Time::days(count: 1));
    start_cheat_block_timestamp_global(block_timestamp: new_time.into());
    now = Time::now();
    state.assets._validate_prices(:now);
    assert_eq!(state.assets.last_price_validation.read(), new_time);
}

#[test]
fn test_validate_prices_no_update_needed() {
    let mut state = CONTRACT_STATE();
    let now = Time::now();
    state.assets.last_price_validation.write(now);
    state.assets._validate_prices(:now);
    assert_eq!(state.assets.last_price_validation.read(), now);
}

#[test]
fn test_successful_withdraw() {
    // Set a non zero timestamp as Time::now().
    start_cheat_block_timestamp_global(block_timestamp: Time::now().add(Time::seconds(1)).into());

    // Setup state, token and user:
    let cfg: PerpetualsInitConfig = Default::default();
    let token_state = cfg.collateral_cfg.token_cfg.deploy();
    let mut state = setup_state(cfg: @cfg, token_state: @token_state);
    let mut user = Default::default();
    init_position(cfg: @cfg, ref :state, :user, token_state: @token_state);

    // Setup parameters:
    let mut expiration = Time::now();
    expiration += Time::days(1);

    let mut message = WithdrawArgs {
        position_id: user.position_id,
        salt: user.salt_counter,
        expiration,
        collateral: AssetAmount { asset_id: cfg.collateral_cfg.asset_id, amount: WITHDRAW_AMOUNT },
        recipient: user.address,
    };
    let signature = user.sign_message(message.get_message_hash(user.key_pair.public_key));
    let operator_nonce = state.nonces.nonces(owner: test_address());

    // Test:
    state.withdraw_request(:signature, :message);
    cheat_caller_address_once(contract_address: test_address(), caller_address: cfg.operator);
    state.withdraw(:operator_nonce, :message);

    // Check:
    let user_balance = token_state.balance_of(user.address);
    assert_eq!(user_balance, (WITHDRAW_AMOUNT.abs() * COLLATERAL_QUANTUM).into());
    let contract_state_balance = token_state.balance_of(test_address());
    assert_eq!(contract_state_balance, Zero::zero());
}

#[test]
fn test_successful_deposit() {
    // Setup state, token and user:
    let cfg: PerpetualsInitConfig = Default::default();
    let token_state = cfg.collateral_cfg.token_cfg.deploy();
    let mut state = setup_state(cfg: @cfg, token_state: @token_state);
    let mut user = Default::default();
    init_position(cfg: @cfg, ref :state, :user, token_state: @token_state);

    // Fund user.
    token_state.fund(recipient: user.address, amount: USER_INIT_BALANCE.try_into().unwrap());
    token_state
        .approve(
            owner: user.address,
            spender: test_address(),
            amount: USER_INIT_BALANCE.try_into().unwrap(),
        );

    let mut expected_time = Time::now();

    // Setup parameters:
    start_cheat_block_timestamp_global(block_timestamp: Time::days(count: 1).into());
    let mut expiration = Time::now();
    expiration += Time::days(2);

    let mut message = DepositArgs {
        position_id: user.position_id,
        salt: user.salt_counter,
        expiration,
        collateral: AssetAmount { asset_id: cfg.collateral_cfg.asset_id, amount: DEPOSIT_AMOUNT },
        owner_public_key: user.key_pair.public_key,
        owner_account: user.address,
    };

    // Check before deposit:
    let user_balance_before_deposit = token_state.balance_of(user.address);
    assert_eq!(user_balance_before_deposit, USER_INIT_BALANCE.try_into().unwrap());
    let contract_state_balance_before_deposit = token_state.balance_of(test_address());
    assert_eq!(contract_state_balance_before_deposit, CONTRACT_INIT_BALANCE.try_into().unwrap());

    // Test:
    cheat_caller_address_once(contract_address: test_address(), caller_address: user.address);
    state.deposit(deposit_args: message);
    expected_time += Time::days(1);

    // Check after deposit:
    let user_balance_after_deposit = token_state.balance_of(user.address);
    assert_eq!(
        user_balance_after_deposit,
        (USER_INIT_BALANCE - DEPOSIT_AMOUNT.try_into().unwrap() * COLLATERAL_QUANTUM)
            .try_into()
            .unwrap(),
    );
    let contract_state_balance_after_deposit = token_state.balance_of(test_address());
    assert_eq!(
        contract_state_balance_after_deposit,
        (CONTRACT_INIT_BALANCE + DEPOSIT_AMOUNT.try_into().unwrap() * COLLATERAL_QUANTUM)
            .try_into()
            .unwrap(),
    );
    assert_eq!(
        state.fact_registry.entry(message.get_message_hash(get_caller_address())).read(),
        expected_time,
    );
}

// Trade tests.

#[test]
fn test_successful_trade() {
    // Setup state, token and user:
    let cfg: PerpetualsInitConfig = Default::default();
    let token_state = cfg.collateral_cfg.token_cfg.deploy();
    let mut state = setup_state(cfg: @cfg, token_state: @token_state);

    let mut user_a = Default::default();
    init_position(cfg: @cfg, ref :state, user: user_a, token_state: @token_state);

    let mut user_b = User {
        position_id: POSITION_ID_2,
        address: POSITION_OWNER_2(),
        key_pair: KEY_PAIR_2(),
        ..Default::default(),
    };
    init_position(cfg: @cfg, ref :state, user: user_b, token_state: @token_state);

    // Test params:
    let BASE = 10;
    let QUOTE = -5;
    let FEE = 1;

    // Setup parameters:
    let mut expiration = Time::now();
    expiration += Time::days(1);

    let collateral_id = cfg.collateral_cfg.asset_id;
    let synthetic_id = cfg.synthetic_cfg.asset_id;

    let order_a = Order {
        position_id: user_a.position_id,
        base: AssetAmount { asset_id: synthetic_id, amount: BASE },
        quote: AssetAmount { asset_id: collateral_id, amount: QUOTE },
        fee: AssetAmount { asset_id: collateral_id, amount: FEE },
        expiration,
        salt: user_a.salt_counter,
    };

    let order_b = Order {
        position_id: user_b.position_id,
        base: AssetAmount { asset_id: synthetic_id, amount: -BASE },
        quote: AssetAmount { asset_id: collateral_id, amount: -QUOTE },
        fee: AssetAmount { asset_id: collateral_id, amount: FEE },
        expiration,
        salt: user_b.salt_counter,
    };

    let signature_a = user_a.sign_message(order_a.get_message_hash(user_a.key_pair.public_key));
    let signature_b = user_b.sign_message(order_b.get_message_hash(user_b.key_pair.public_key));
    let operator_nonce = state.nonces.nonces(owner: test_address());

    // Test:
    cheat_caller_address_once(contract_address: test_address(), caller_address: cfg.operator);
    state
        .trade(
            :operator_nonce,
            :signature_a,
            :signature_b,
            :order_a,
            :order_b,
            actual_amount_base_a: BASE,
            actual_amount_quote_a: QUOTE,
            actual_fee_a: FEE,
            actual_fee_b: FEE,
        );

    // Check:
    let position_a = state.positions.entry(user_a.position_id);
    let position_b = state.positions.entry(user_b.position_id);

    let user_a_collateral_balance = position_a
        .collateral_assets
        .entry(collateral_id)
        .balance
        .read();
    let user_a_synthetic_balance = position_a.synthetic_assets.entry(synthetic_id).balance.read();
    assert_eq!(user_a_collateral_balance, (COLLATERAL_BALANCE_AMOUNT - FEE + QUOTE).into());
    assert_eq!(user_a_synthetic_balance, (SYNTHETIC_BALANCE_AMOUNT + BASE).into());

    let user_b_collateral_balance = position_b
        .collateral_assets
        .entry(collateral_id)
        .balance
        .read();
    let user_b_synthetic_balance = position_b.synthetic_assets.entry(synthetic_id).balance.read();
    assert_eq!(user_b_collateral_balance, (COLLATERAL_BALANCE_AMOUNT - FEE - QUOTE).into());
    assert_eq!(user_b_synthetic_balance, (SYNTHETIC_BALANCE_AMOUNT - BASE).into());
}

// TODO: Add all the illegal trade cases once safe dispatcher is supported.
#[test]
#[should_panic(expected: 'INVALID_NEGATIVE_FEE')]
fn test_invalid_trade_non_positve_fee() {
    // Setup state, token and user:
    let cfg: PerpetualsInitConfig = Default::default();
    let token_state = cfg.collateral_cfg.token_cfg.deploy();
    let mut state = setup_state(cfg: @cfg, token_state: @token_state);

    let mut user = Default::default();
    init_position(cfg: @cfg, ref :state, user: user, token_state: @token_state);

    // Test params:
    let BASE = 10;
    let QUOTE = -5;
    let FEE = -1;

    // Setup parameters:
    let mut expiration = Time::now();
    expiration += Time::days(1);

    let collateral_id = cfg.collateral_cfg.asset_id;
    let synthetic_id = cfg.synthetic_cfg.asset_id;

    let order = Order {
        position_id: user.position_id,
        base: AssetAmount { asset_id: synthetic_id, amount: BASE },
        quote: AssetAmount { asset_id: collateral_id, amount: QUOTE },
        fee: AssetAmount { asset_id: collateral_id, amount: FEE },
        expiration,
        salt: user.salt_counter,
    };

    let signature = user.sign_message(order.get_message_hash(user.key_pair.public_key));
    let operator_nonce = state.nonces.nonces(owner: test_address());

    // Test:
    cheat_caller_address_once(contract_address: test_address(), caller_address: cfg.operator);
    state
        .trade(
            :operator_nonce,
            signature_a: signature,
            signature_b: signature,
            order_a: order,
            order_b: order,
            actual_amount_base_a: BASE,
            actual_amount_quote_a: QUOTE,
            actual_fee_a: 1,
            actual_fee_b: 1,
        );
}


#[test]
#[should_panic(expected: 'INVALID_TRADE_WRONG_AMOUNT_SIGN')]
fn test_invalid_trade_same_base_signs() {
    // Setup state, token and user:
    let cfg: PerpetualsInitConfig = Default::default();
    let token_state = cfg.collateral_cfg.token_cfg.deploy();
    let mut state = setup_state(cfg: @cfg, token_state: @token_state);

    let mut user_a = Default::default();
    init_position(cfg: @cfg, ref :state, user: user_a, token_state: @token_state);

    let mut user_b = User {
        position_id: POSITION_ID_2,
        address: POSITION_OWNER_2(),
        key_pair: KEY_PAIR_2(),
        ..Default::default(),
    };
    init_position(cfg: @cfg, ref :state, user: user_b, token_state: @token_state);

    // Test params:
    let BASE = 10;
    let QUOTE = -5;
    let FEE = 1;

    // Setup parameters:
    let mut expiration = Time::now();
    expiration += Time::days(1);

    let collateral_id = cfg.collateral_cfg.asset_id;
    let synthetic_id = cfg.synthetic_cfg.asset_id;

    let order_a = Order {
        position_id: user_a.position_id,
        base: AssetAmount { asset_id: synthetic_id, amount: BASE },
        quote: AssetAmount { asset_id: collateral_id, amount: QUOTE },
        fee: AssetAmount { asset_id: collateral_id, amount: FEE },
        expiration,
        salt: user_a.salt_counter,
    };

    // Wrong sign for base amount.
    let order_b = Order {
        position_id: user_b.position_id,
        base: AssetAmount { asset_id: synthetic_id, amount: BASE },
        quote: AssetAmount { asset_id: collateral_id, amount: -QUOTE },
        fee: AssetAmount { asset_id: collateral_id, amount: FEE },
        expiration,
        salt: user_b.salt_counter,
    };

    let signature_a = user_a.sign_message(order_a.get_message_hash(user_a.key_pair.public_key));
    let signature_b = user_b.sign_message(order_b.get_message_hash(user_b.key_pair.public_key));
    let operator_nonce = state.nonces.nonces(owner: test_address());

    // Test:
    cheat_caller_address_once(contract_address: test_address(), caller_address: cfg.operator);
    state
        .trade(
            :operator_nonce,
            :signature_a,
            :signature_b,
            :order_a,
            :order_b,
            actual_amount_base_a: BASE,
            actual_amount_quote_a: QUOTE,
            actual_fee_a: FEE,
            actual_fee_b: FEE,
        );
}
