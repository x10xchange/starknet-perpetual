use Core::InternalCoreFunctionsTrait;
use contracts_commons::components::nonce::interface::INonce;
use contracts_commons::components::roles::interface::IRoles;
use contracts_commons::math::Abs;
use contracts_commons::message_hash::OffchainMessageHash;
use contracts_commons::test_utils::{Deployable, TokenState, TokenTrait, cheat_caller_address_once};
use contracts_commons::types::time::time::Time;
use core::num::traits::Zero;
use perpetuals::core::components::assets::AssetsComponent::InternalTrait as AssetsInternal;
use perpetuals::core::components::assets::interface::IAssets;
use perpetuals::core::core::Core;
use perpetuals::core::core::Core::SNIP12MetadataImpl;
use perpetuals::core::interface::ICore;
use perpetuals::core::types::asset::AssetId;
use perpetuals::core::types::deposit::DepositArgs;
use perpetuals::core::types::order::Order;
use perpetuals::core::types::withdraw::WithdrawArgs;
use perpetuals::core::types::{AssetAmount, PositionId};
use perpetuals::tests::constants::*;
use perpetuals::tests::test_utils::{
    PerpetualsInitConfig, User, UserTrait, deploy_value_risk_calculator_contract,
    generate_collateral, set_roles,
};
use snforge_std::{start_cheat_block_timestamp_global, test_address};
use starknet::get_caller_address;
use starknet::storage::{
    StorageMapWriteAccess, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess,
};

fn CONTRACT_STATE() -> Core::ContractState {
    Core::contract_state_for_testing()
}

fn setup_state(cfg: @PerpetualsInitConfig, token_state: @TokenState) -> Core::ContractState {
    let mut state = initialized_contract_state();
    set_roles(ref :state, :cfg);
    state
        .assets
        .initialize(
            max_price_interval: *cfg.max_price_interval,
            max_funding_interval: *cfg.max_funding_interval,
            max_funding_rate: *cfg.max_funding_rate,
        );
    // Collateral asset configs.
    let (collateral_config, collateral_timely_data) = generate_collateral(:token_state);
    state
        .assets
        .collateral_config
        .write(*cfg.collateral_cfg.asset_id, Option::Some(collateral_config));
    state.assets.collateral_timely_data.write(*cfg.collateral_cfg.asset_id, collateral_timely_data);
    state.assets.collateral_timely_data_head.write(Option::Some(*cfg.collateral_cfg.asset_id));

    // Synthetic asset configs.
    state
        .assets
        .synthetic_config
        .write(*cfg.synthetic_cfg.asset_id, Option::Some(SYNTHETIC_CONFIG()));
    state.assets.synthetic_timely_data.write(*cfg.synthetic_cfg.asset_id, SYNTHETIC_TIMELY_DATA());
    state.assets.synthetic_timely_data_head.write(Option::Some(*cfg.synthetic_cfg.asset_id));

    // Fund the contract.
    (*token_state)
        .fund(recipient: test_address(), amount: CONTRACT_INIT_BALANCE.try_into().unwrap());

    state
}

fn init_position(cfg: @PerpetualsInitConfig, ref state: Core::ContractState, user: User) {
    let position = state.positions.entry(user.position_id);
    position.owner_public_key.write(user.key_pair.public_key);
    state
        ._apply_funding_and_set_balance(
            position_id: user.position_id,
            asset_id: *cfg.collateral_cfg.asset_id,
            balance: COLLATERAL_BALANCE_AMOUNT.into(),
        );
    position.collateral_assets_head.write(Option::Some(*cfg.collateral_cfg.asset_id));
}

fn add_synthetic(
    ref state: Core::ContractState, asset_id: AssetId, position_id: PositionId, balance: i64,
) {
    let position = state.positions.entry(position_id);
    match position.synthetic_assets_head.read() {
        Option::Some(head) => {
            position.synthetic_assets_head.write(Option::Some(asset_id));
            position.synthetic_assets.entry(asset_id).next.write(Option::Some(head));
        },
        Option::None => position.synthetic_assets_head.write(Option::Some(asset_id)),
    }
    position.synthetic_assets.entry(asset_id).balance.write(balance.into());
}

fn initialized_contract_state() -> Core::ContractState {
    let mut state = CONTRACT_STATE();
    Core::constructor(
        ref state,
        governance_admin: GOVERNANCE_ADMIN(),
        value_risk_calculator: deploy_value_risk_calculator_contract(),
        max_price_interval: MAX_PRICE_INTERVAL,
        max_funding_interval: MAX_FUNDING_INTERVAL,
        max_funding_rate: MAX_FUNDING_RATE,
    );
    state
}

#[test]
fn test_constructor() {
    let mut state = initialized_contract_state();
    assert!(state.roles.is_governance_admin(GOVERNANCE_ADMIN()));
    assert_eq!(state.assets.get_price_validation_interval(), MAX_PRICE_INTERVAL);
    assert_eq!(state.assets.get_funding_validation_interval(), MAX_FUNDING_INTERVAL);
    assert_eq!(state.assets.get_max_funding_rate(), MAX_FUNDING_RATE);
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
    init_position(cfg: @cfg, ref :state, :user);

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
    let operator_nonce = state.nonce();

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
    init_position(cfg: @cfg, ref :state, :user);

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

    let mut deposit_args = DepositArgs {
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
    state.deposit(:deposit_args);
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
        state.fact_registry.entry(deposit_args.get_message_hash(get_caller_address())).read(),
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
    init_position(cfg: @cfg, ref :state, user: user_a);

    let mut user_b = User {
        position_id: POSITION_ID_2,
        address: POSITION_OWNER_2(),
        key_pair: KEY_PAIR_2(),
        ..Default::default(),
    };
    init_position(cfg: @cfg, ref :state, user: user_b);

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
    let operator_nonce = state.nonce();

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
    let user_a_collateral_balance = state
        ._get_provisional_balance(position_id: user_a.position_id, asset_id: collateral_id);
    let user_a_synthetic_balance = state
        ._get_provisional_balance(position_id: user_a.position_id, asset_id: synthetic_id);
    assert_eq!(user_a_collateral_balance, (COLLATERAL_BALANCE_AMOUNT - FEE + QUOTE).into());
    assert_eq!(user_a_synthetic_balance, (BASE).into());

    let user_b_collateral_balance = state
        ._get_provisional_balance(position_id: user_b.position_id, asset_id: collateral_id);
    let user_b_synthetic_balance = state
        ._get_provisional_balance(position_id: user_b.position_id, asset_id: synthetic_id);
    assert_eq!(user_b_collateral_balance, (COLLATERAL_BALANCE_AMOUNT - FEE - QUOTE).into());
    assert_eq!(user_b_synthetic_balance, (-BASE).into());
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
    init_position(cfg: @cfg, ref :state, user: user);

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
    let operator_nonce = state.nonce();

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
    init_position(cfg: @cfg, ref :state, user: user_a);

    let mut user_b = User {
        position_id: POSITION_ID_2,
        address: POSITION_OWNER_2(),
        key_pair: KEY_PAIR_2(),
        ..Default::default(),
    };
    init_position(cfg: @cfg, ref :state, user: user_b);

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
    let operator_nonce = state.nonce();

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

#[test]
fn test_successful_liquidate() {
    // Setup state, token and user:
    let cfg: PerpetualsInitConfig = Default::default();
    let token_state = cfg.collateral_cfg.token_cfg.deploy();
    let mut state = setup_state(cfg: @cfg, token_state: @token_state);

    let mut liquidator = Default::default();
    init_position(cfg: @cfg, ref :state, user: liquidator);

    let mut liquidated = User {
        position_id: POSITION_ID_2,
        address: POSITION_OWNER_2(),
        key_pair: KEY_PAIR_2(),
        ..Default::default(),
    };
    init_position(cfg: @cfg, ref :state, user: liquidated);
    add_synthetic(
        ref :state,
        asset_id: cfg.synthetic_cfg.asset_id,
        position_id: liquidated.position_id,
        balance: -SYNTHETIC_BALANCE_AMOUNT,
    );

    // Test params:
    let BASE = 10;
    let QUOTE = -5;
    let FEE = 1;

    // Setup parameters:
    let mut expiration = Time::now();
    expiration += Time::days(1);
    let operator_nonce = state.nonce();

    let collateral_id = cfg.collateral_cfg.asset_id;
    let synthetic_id = cfg.synthetic_cfg.asset_id;

    let order_liquidator = Order {
        position_id: liquidator.position_id,
        base: AssetAmount { asset_id: synthetic_id, amount: -BASE },
        quote: AssetAmount { asset_id: collateral_id, amount: -QUOTE },
        fee: AssetAmount { asset_id: collateral_id, amount: FEE },
        expiration,
        salt: liquidator.salt_counter,
    };

    let liquidator_signature = liquidator
        .sign_message(order_liquidator.get_message_hash(liquidator.key_pair.public_key));

    // Test:
    cheat_caller_address_once(contract_address: test_address(), caller_address: cfg.operator);

    state
        .liquidate(
            :operator_nonce,
            :liquidator_signature,
            liquidated_position_id: liquidated.position_id,
            liquidator_order: order_liquidator,
            actual_amount_base_liquidated: BASE,
            actual_amount_quote_liquidated: QUOTE,
            actual_liquidator_fee: FEE,
            insurance_fund_fee: AssetAmount { asset_id: collateral_id, amount: FEE },
        );

    // Check:
    let position_a = state.positions.entry(liquidated.position_id);
    let position_b = state.positions.entry(liquidator.position_id);

    let user_a_collateral_balance = position_a
        .collateral_assets
        .entry(collateral_id)
        .balance
        .read();
    let user_a_synthetic_balance = position_a.synthetic_assets.entry(synthetic_id).balance.read();
    assert_eq!(user_a_collateral_balance, (COLLATERAL_BALANCE_AMOUNT - FEE + QUOTE).into());
    assert_eq!(user_a_synthetic_balance, (-SYNTHETIC_BALANCE_AMOUNT + BASE).into());

    let user_b_collateral_balance = position_b
        .collateral_assets
        .entry(collateral_id)
        .balance
        .read();
    let user_b_synthetic_balance = position_b.synthetic_assets.entry(synthetic_id).balance.read();
    assert_eq!(user_b_collateral_balance, (COLLATERAL_BALANCE_AMOUNT - FEE - QUOTE).into());
    assert_eq!(user_b_synthetic_balance, (-BASE).into());
}
