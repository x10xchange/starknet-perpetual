use contracts_commons::components::deposit::interface::{DepositStatus, IDeposit};
use contracts_commons::components::nonce::interface::INonce;
use contracts_commons::components::request_approvals::interface::RequestStatus;
use contracts_commons::components::roles::interface::IRoles;
use contracts_commons::constants::TEN_POW_15;
use contracts_commons::message_hash::OffchainMessageHash;
use contracts_commons::test_utils::{Deployable, TokenTrait, cheat_caller_address_once};
use contracts_commons::types::time::time::{Time, Timestamp};
use core::num::traits::Zero;
use perpetuals::core::components::assets::interface::IAssets;
use perpetuals::core::components::positions::Positions::POSITION_VERSION;
use perpetuals::core::components::positions::interface::IPositions;
use perpetuals::core::components::positions::{
    Positions, Positions::InternalTrait as PositionsInternal,
};
use perpetuals::core::core::Core::SNIP12MetadataImpl;
use perpetuals::core::interface::ICore;
use perpetuals::core::types::asset::status::AssetStatus;
use perpetuals::core::types::order::Order;
use perpetuals::core::types::price::{PriceTrait, SignedPrice};
use perpetuals::core::types::set_public_key::SetPublicKeyArgs;
use perpetuals::core::types::transfer::TransferArgs;
use perpetuals::core::types::withdraw::WithdrawArgs;
use perpetuals::tests::constants::*;
use perpetuals::tests::event_test_utils::{
    assert_add_oracle_event_with_expected, assert_add_synthetic_event_with_expected,
    assert_asset_activated_event_with_expected,
    assert_deactivate_synthetic_asset_event_with_expected, assert_deleverage_event_with_expected,
    assert_deposit_event_with_expected, assert_liquidate_event_with_expected,
    assert_new_position_event_with_expected, assert_price_tick_event_with_expected,
    assert_set_public_key_event_with_expected, assert_set_public_key_request_event_with_expected,
    assert_trade_event_with_expected, assert_transfer_event_with_expected,
    assert_transfer_request_event_with_expected, assert_withdraw_event_with_expected,
    assert_withdraw_request_event_with_expected,
};
use perpetuals::tests::test_utils::{
    Oracle, OracleTrait, PerpetualsInitConfig, User, UserTrait, add_synthetic_to_position,
    check_synthetic_asset, init_position, init_position_with_owner, initialized_contract_state,
    setup_state_with_active_asset, setup_state_with_pending_asset,
};
use snforge_std::cheatcodes::events::{EventSpyTrait, EventsFilterTrait};
use snforge_std::{start_cheat_block_timestamp_global, test_address};
use starknet::storage::{
    StorageMapReadAccess, StorageMapWriteAccess, StoragePathEntry, StoragePointerReadAccess,
    StoragePointerWriteAccess,
};


#[test]
fn test_constructor() {
    let mut state = initialized_contract_state();
    assert!(state.roles.is_governance_admin(GOVERNANCE_ADMIN()));
    assert_eq!(state.replaceability.upgrade_delay.read(), UPGRADE_DELAY);
    assert_eq!(state.assets.get_funding_validation_interval(), MAX_FUNDING_INTERVAL);
    assert_eq!(state.assets.get_max_funding_rate(), MAX_FUNDING_RATE);

    assert_eq!(
        state
            .positions
            .get_position_const(position_id: Positions::FEE_POSITION)
            .owner_account
            .read(),
        OPERATOR(),
    );
    assert_eq!(
        state
            .positions
            .get_position_const(position_id: Positions::FEE_POSITION)
            .owner_public_key
            .read(),
        OPERATOR_PUBLIC_KEY(),
    );
    assert_eq!(
        state
            .positions
            .get_position_const(position_id: Positions::INSURANCE_FUND_POSITION)
            .owner_account
            .read(),
        OPERATOR(),
    );
    assert_eq!(
        state
            .positions
            .get_position_const(position_id: Positions::INSURANCE_FUND_POSITION)
            .owner_public_key
            .read(),
        OPERATOR_PUBLIC_KEY(),
    );
}

#[test]
fn test_new_position() {
    // Setup state, token:
    let cfg: PerpetualsInitConfig = Default::default();
    let token_state = cfg.collateral_cfg.token_cfg.deploy();
    let mut state = setup_state_with_active_asset(cfg: @cfg, token_state: @token_state);
    let mut spy = snforge_std::spy_events();

    // Parameters:
    let position_id = POSITION_ID_1;
    let owner_public_key = KEY_PAIR_1().public_key;
    let owner_account = POSITION_OWNER_1();

    // Test.
    cheat_caller_address_once(contract_address: test_address(), caller_address: cfg.operator);
    state
        .new_position(
            operator_nonce: state.nonce(), :position_id, :owner_public_key, :owner_account,
        );

    // Catch the event.
    let events = spy.get_events().emitted_by(test_address()).events;
    assert_new_position_event_with_expected(
        spied_event: events[0], :position_id, :owner_public_key, :owner_account,
    );

    // Check.
    assert_eq!(state.positions.get_position_const(:position_id).version.read(), POSITION_VERSION);
    assert_eq!(
        state.positions.get_position_const(:position_id).owner_public_key.read(), owner_public_key,
    );
    assert_eq!(
        state.positions.get_position_const(:position_id).owner_account.read(), owner_account,
    );
}

// Add synthetic asset tests.

#[test]
fn test_successful_add_synthetic_asset() {
    // Setup state, token:
    let cfg: PerpetualsInitConfig = Default::default();
    let token_state = cfg.collateral_cfg.token_cfg.deploy();
    let mut state = setup_state_with_active_asset(cfg: @cfg, token_state: @token_state);
    let mut spy = snforge_std::spy_events();

    // Setup test parameters:
    let synthetic_id_1 = SYNTHETIC_ASSET_ID_2();
    let synthetic_id_2 = SYNTHETIC_ASSET_ID_3();
    let risk_factor_1 = 10;
    let risk_factor_2 = 20;
    let quorum_1 = 1_u8;
    let quorum_2 = 2_u8;
    let resolution_1 = 1_000_000_000;
    let resolution_2 = 2_000_000_000;

    // Test:
    cheat_caller_address_once(contract_address: test_address(), caller_address: cfg.app_governor);
    state
        .add_synthetic_asset(
            asset_id: synthetic_id_1,
            risk_factor: risk_factor_1,
            quorum: quorum_1,
            resolution: resolution_1,
        );

    cheat_caller_address_once(contract_address: test_address(), caller_address: cfg.app_governor);
    state
        .add_synthetic_asset(
            asset_id: synthetic_id_2,
            risk_factor: risk_factor_2,
            quorum: quorum_2,
            resolution: resolution_2,
        );

    // Catch the event.
    let events = spy.get_events().emitted_by(test_address()).events;
    assert_add_synthetic_event_with_expected(
        spied_event: events[0],
        asset_id: synthetic_id_1,
        risk_factor: risk_factor_1,
        resolution: resolution_1,
        quorum: quorum_1,
    );

    // Check:
    check_synthetic_asset(
        state: @state,
        synthetic_id: synthetic_id_1,
        status: AssetStatus::PENDING,
        risk_factor: risk_factor_1,
        quorum: quorum_1,
        resolution: resolution_1,
        price: Zero::zero(),
        last_price_update: Zero::zero(),
        funding_index: Zero::zero(),
    );
    check_synthetic_asset(
        state: @state,
        synthetic_id: synthetic_id_2,
        status: AssetStatus::PENDING,
        risk_factor: risk_factor_2,
        quorum: quorum_2,
        resolution: resolution_2,
        price: Zero::zero(),
        last_price_update: Zero::zero(),
        funding_index: Zero::zero(),
    );
}

#[test]
#[should_panic(expected: 'SYNTHETIC_ALREADY_EXISTS')]
fn test_add_synthetic_asset_existed_asset() {
    // Setup state, token:
    let cfg: PerpetualsInitConfig = Default::default();
    let token_state = cfg.collateral_cfg.token_cfg.deploy();
    let mut state = setup_state_with_active_asset(cfg: @cfg, token_state: @token_state);

    // Test:
    cheat_caller_address_once(contract_address: test_address(), caller_address: cfg.app_governor);
    state
        .add_synthetic_asset(
            // Setup state already added `SYNTHETIC_ASSET_ID_1`.
            asset_id: SYNTHETIC_ASSET_ID_1(),
            risk_factor: Zero::zero(),
            quorum: Zero::zero(),
            resolution: Zero::zero(),
        );
}

// Deactivate synthetic asset tests.

#[test]
fn test_successful_deactivate_synthetic_asset() {
    // Setup state, token and user:
    let cfg: PerpetualsInitConfig = Default::default();
    let token_state = cfg.collateral_cfg.token_cfg.deploy();
    let mut state = setup_state_with_active_asset(cfg: @cfg, token_state: @token_state);
    let mut spy = snforge_std::spy_events();

    // Setup parameters:
    let synthetic_id = cfg.synthetic_cfg.synthetic_id;
    assert!(
        state
            .assets
            .synthetic_config
            .entry(synthetic_id)
            .read()
            .unwrap()
            .status == AssetStatus::ACTIVATED,
    );

    // Test:
    cheat_caller_address_once(contract_address: test_address(), caller_address: cfg.app_governor);
    state.deactivate_synthetic(:synthetic_id);

    // Catch the event.
    let events = spy.get_events().emitted_by(test_address()).events;
    assert_deactivate_synthetic_asset_event_with_expected(
        spied_event: events[0], asset_id: synthetic_id,
    );

    // Check:
    assert!(
        state
            .assets
            .synthetic_config
            .entry(synthetic_id)
            .read()
            .unwrap()
            .status == AssetStatus::DEACTIVATED,
    );
}

#[test]
#[should_panic(expected: 'SYNTHETIC_NOT_EXISTS')]
fn test_deactivate_unexisted_synthetic_asset() {
    // Setup state, token and user:
    let cfg: PerpetualsInitConfig = Default::default();
    let token_state = cfg.collateral_cfg.token_cfg.deploy();
    let mut state = setup_state_with_active_asset(cfg: @cfg, token_state: @token_state);
    // Setup parameters:
    let synthetic_id = SYNTHETIC_ASSET_ID_2();

    // Test:
    cheat_caller_address_once(contract_address: test_address(), caller_address: cfg.app_governor);
    state.deactivate_synthetic(:synthetic_id);
}


#[test]
fn test_successful_withdraw() {
    // Set a non zero timestamp as Time::now().
    start_cheat_block_timestamp_global(block_timestamp: Time::now().add(Time::seconds(100)).into());

    // Setup state, token and user:
    let cfg: PerpetualsInitConfig = Default::default();
    let token_state = cfg.collateral_cfg.token_cfg.deploy();
    let mut state = setup_state_with_active_asset(cfg: @cfg, token_state: @token_state);
    let user = Default::default();
    init_position(cfg: @cfg, ref :state, :user);

    // Setup parameters:
    let expiration = Time::now().add(Time::days(1));

    let mut withdraw_args = WithdrawArgs {
        position_id: user.position_id,
        salt: user.salt_counter,
        expiration,
        collateral_id: cfg.collateral_cfg.collateral_id,
        amount: WITHDRAW_AMOUNT,
        recipient: user.address,
    };
    let hash = withdraw_args.get_message_hash(user.get_public_key());
    let signature = user.sign_message(hash);
    let operator_nonce = state.nonce();

    let contract_state_balance = token_state.balance_of(test_address());
    assert_eq!(contract_state_balance, CONTRACT_INIT_BALANCE.into());

    let mut spy = snforge_std::spy_events();
    // Test:
    state
        .withdraw_request(
            :signature,
            recipient: withdraw_args.recipient,
            position_id: withdraw_args.position_id,
            collateral_id: withdraw_args.collateral_id,
            amount: withdraw_args.amount,
            expiration: withdraw_args.expiration,
            salt: withdraw_args.salt,
        );
    cheat_caller_address_once(contract_address: test_address(), caller_address: cfg.operator);
    state
        .withdraw(
            :operator_nonce,
            recipient: withdraw_args.recipient,
            position_id: withdraw_args.position_id,
            collateral_id: withdraw_args.collateral_id,
            amount: withdraw_args.amount,
            expiration: withdraw_args.expiration,
            salt: withdraw_args.salt,
        );

    // Catch the event.
    let events = spy.get_events().emitted_by(test_address()).events;
    assert_withdraw_request_event_with_expected(
        spied_event: events[0],
        position_id: withdraw_args.position_id,
        recipient: withdraw_args.recipient,
        collateral_id: withdraw_args.collateral_id,
        amount: withdraw_args.amount,
        expiration: withdraw_args.expiration,
        withdraw_request_hash: hash,
    );
    assert_withdraw_event_with_expected(
        spied_event: events[1],
        position_id: withdraw_args.position_id,
        recipient: withdraw_args.recipient,
        collateral_id: withdraw_args.collateral_id,
        amount: withdraw_args.amount,
        expiration: withdraw_args.expiration,
        withdraw_request_hash: hash,
    );
    // Check:
    let user_balance = token_state.balance_of(user.address);
    let onchain_amount = (WITHDRAW_AMOUNT * COLLATERAL_QUANTUM);
    assert_eq!(user_balance, onchain_amount.into());
    let contract_state_balance = token_state.balance_of(test_address());
    assert_eq!(contract_state_balance, (CONTRACT_INIT_BALANCE - onchain_amount.into()).into());
}

#[test]
fn test_successful_deposit() {
    // Setup state, token and user:
    let cfg: PerpetualsInitConfig = Default::default();
    let token_state = cfg.collateral_cfg.token_cfg.deploy();
    let mut state = setup_state_with_active_asset(cfg: @cfg, token_state: @token_state);
    let mut user = Default::default();
    init_position(cfg: @cfg, ref :state, :user);

    // Fund user.
    token_state.fund(recipient: user.address, amount: USER_INIT_BALANCE.try_into().unwrap());
    token_state
        .approve(
            owner: user.address,
            spender: test_address(),
            amount: DEPOSIT_AMOUNT * cfg.collateral_cfg.quantum.into(),
        );

    // Setup parameters:
    let expected_time = Time::now().add(delta: Time::days(1));
    start_cheat_block_timestamp_global(block_timestamp: expected_time.into());

    // Check before deposit:
    let user_balance_before_deposit = token_state.balance_of(user.address);
    assert_eq!(user_balance_before_deposit, USER_INIT_BALANCE.try_into().unwrap());
    let contract_state_balance_before_deposit = token_state.balance_of(test_address());
    assert_eq!(contract_state_balance_before_deposit, CONTRACT_INIT_BALANCE.try_into().unwrap());
    let mut spy = snforge_std::spy_events();
    // Test:
    cheat_caller_address_once(contract_address: test_address(), caller_address: user.address);
    let deposit_hash = state
        .deposit(
            beneficiary: user.position_id.value,
            asset_id: cfg.collateral_cfg.collateral_id.into(),
            quantized_amount: DEPOSIT_AMOUNT,
            salt: user.salt_counter,
        );

    // Catch the event.
    let events = spy.get_events().emitted_by(test_address()).events;
    assert_deposit_event_with_expected(
        spied_event: events[0],
        position_id: user.position_id.value,
        depositing_address: user.address,
        asset_id: cfg.collateral_cfg.collateral_id.into(),
        quantized_amount: DEPOSIT_AMOUNT,
        unquantized_amount: DEPOSIT_AMOUNT * COLLATERAL_QUANTUM.into(),
        deposit_request_hash: deposit_hash,
    );

    // Check after deposit:
    let user_balance_after_deposit = token_state.balance_of(user.address);
    assert_eq!(
        user_balance_after_deposit,
        (USER_INIT_BALANCE - DEPOSIT_AMOUNT * COLLATERAL_QUANTUM.into()).into(),
    );
    let contract_state_balance_after_deposit = token_state.balance_of(test_address());
    assert_eq!(
        contract_state_balance_after_deposit,
        (CONTRACT_INIT_BALANCE + DEPOSIT_AMOUNT * COLLATERAL_QUANTUM.into()).into(),
    );
    let status = state.deposits.registered_deposits.entry(deposit_hash).read();
    if let DepositStatus::PENDING(timestamp) = status {
        assert_eq!(timestamp, expected_time);
    } else {
        panic!("Deposit not found");
    }
}

// Trade tests.

#[test]
fn test_successful_trade() {
    // Setup state, token and user:
    let cfg: PerpetualsInitConfig = Default::default();
    let token_state = cfg.collateral_cfg.token_cfg.deploy();
    let mut state = setup_state_with_active_asset(cfg: @cfg, token_state: @token_state);

    let mut user_a = Default::default();
    init_position(cfg: @cfg, ref :state, user: user_a);

    let mut user_b = UserTrait::new(position_id: POSITION_ID_2, key_pair: KEY_PAIR_2());
    init_position(cfg: @cfg, ref :state, user: user_b);

    // Test params:
    let BASE = 10;
    let QUOTE = -5;
    let FEE = 1;

    // Setup parameters:
    let mut expiration = Time::now();
    expiration += Time::days(1);

    let collateral_id = cfg.collateral_cfg.collateral_id;
    let synthetic_id = cfg.synthetic_cfg.synthetic_id;

    let order_a = Order {
        position_id: user_a.position_id,
        salt: user_a.salt_counter,
        base_asset_id: synthetic_id,
        base_amount: BASE,
        quote_asset_id: collateral_id,
        quote_amount: QUOTE,
        fee_asset_id: collateral_id,
        fee_amount: FEE,
        expiration,
    };

    let order_b = Order {
        position_id: user_b.position_id,
        base_asset_id: synthetic_id,
        base_amount: -BASE,
        quote_asset_id: collateral_id,
        quote_amount: -QUOTE,
        fee_asset_id: collateral_id,
        fee_amount: FEE,
        expiration,
        salt: user_b.salt_counter,
    };

    let hash_a = order_a.get_message_hash(user_a.get_public_key());
    let hash_b = order_b.get_message_hash(user_b.get_public_key());
    let signature_a = user_a.sign_message(hash_a);
    let signature_b = user_b.sign_message(hash_b);
    let operator_nonce = state.nonce();

    let mut spy = snforge_std::spy_events();
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

    // Catch the event.
    let events = spy.get_events().emitted_by(test_address()).events;
    assert_trade_event_with_expected(
        spied_event: events[0],
        order_a_position_id: user_a.position_id,
        order_a_base_asset_id: synthetic_id,
        order_a_base_amount: BASE,
        order_a_quote_asset_id: collateral_id,
        order_a_quote_amount: QUOTE,
        fee_a_asset_id: collateral_id,
        fee_a_amount: FEE,
        order_b_position_id: user_b.position_id,
        order_b_base_asset_id: synthetic_id,
        order_b_base_amount: -BASE,
        order_b_quote_asset_id: collateral_id,
        order_b_quote_amount: -QUOTE,
        fee_b_asset_id: collateral_id,
        fee_b_amount: FEE,
        actual_amount_base_a: BASE,
        actual_amount_quote_a: QUOTE,
        actual_fee_a: FEE,
        actual_fee_b: FEE,
        order_a_hash: hash_a,
        order_b_hash: hash_b,
    );

    // Check:
    let user_a_collateral_balance = state
        .positions
        .get_provisional_balance(position_id: user_a.position_id, asset_id: collateral_id);
    let user_a_synthetic_balance = state
        .positions
        .get_provisional_balance(position_id: user_a.position_id, asset_id: synthetic_id);
    assert_eq!(
        user_a_collateral_balance, (COLLATERAL_BALANCE_AMOUNT.into() - FEE.into() + QUOTE.into()),
    );
    assert_eq!(user_a_synthetic_balance, (BASE).into());

    let user_b_collateral_balance = state
        .positions
        .get_provisional_balance(position_id: user_b.position_id, asset_id: collateral_id);
    let user_b_synthetic_balance = state
        .positions
        .get_provisional_balance(position_id: user_b.position_id, asset_id: synthetic_id);
    assert_eq!(
        user_b_collateral_balance, (COLLATERAL_BALANCE_AMOUNT.into() - FEE.into() - QUOTE.into()),
    );
    assert_eq!(user_b_synthetic_balance, (-BASE).into());

    let fee_position_balance = state
        .positions
        .get_provisional_balance(position_id: Positions::FEE_POSITION, asset_id: collateral_id);
    assert_eq!(fee_position_balance, (FEE + FEE).into());
}

#[test]
#[should_panic(expected: 'INVALID_TRADE_WRONG_AMOUNT_SIGN')]
fn test_invalid_trade_same_base_signs() {
    // Setup state, token and user:
    let cfg: PerpetualsInitConfig = Default::default();
    let token_state = cfg.collateral_cfg.token_cfg.deploy();
    let mut state = setup_state_with_active_asset(cfg: @cfg, token_state: @token_state);

    let mut user_a = Default::default();
    init_position(cfg: @cfg, ref :state, user: user_a);

    let mut user_b = UserTrait::new(position_id: POSITION_ID_2, key_pair: KEY_PAIR_2());
    init_position(cfg: @cfg, ref :state, user: user_b);

    // Test params:
    let BASE = 10;
    let QUOTE = -5;
    let FEE = 1;

    // Setup parameters:
    let mut expiration = Time::now();
    expiration += Time::days(1);

    let collateral_id = cfg.collateral_cfg.collateral_id;
    let synthetic_id = cfg.synthetic_cfg.synthetic_id;

    let order_a = Order {
        position_id: user_a.position_id,
        salt: user_a.salt_counter,
        base_asset_id: synthetic_id,
        base_amount: BASE,
        quote_asset_id: collateral_id,
        quote_amount: QUOTE,
        fee_asset_id: collateral_id,
        fee_amount: FEE,
        expiration,
    };

    // Wrong sign for base amount.
    let order_b = Order {
        position_id: user_b.position_id,
        salt: user_b.salt_counter,
        base_asset_id: synthetic_id,
        base_amount: BASE,
        quote_asset_id: collateral_id,
        quote_amount: -QUOTE,
        fee_asset_id: collateral_id,
        fee_amount: FEE,
        expiration,
    };

    let signature_a = user_a.sign_message(order_a.get_message_hash(user_a.get_public_key()));
    let signature_b = user_b.sign_message(order_b.get_message_hash(user_b.get_public_key()));
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
fn test_successful_withdraw_request_with_public_key() {
    // Setup state, token and user:
    let cfg: PerpetualsInitConfig = Default::default();
    let token_state = cfg.collateral_cfg.token_cfg.deploy();
    let mut state = setup_state_with_active_asset(cfg: @cfg, token_state: @token_state);
    let mut user = Default::default();
    init_position(cfg: @cfg, ref :state, :user);
    let recipient = UserTrait::new(position_id: POSITION_ID_2, key_pair: KEY_PAIR_2());

    // Setup parameters:
    start_cheat_block_timestamp_global(
        block_timestamp: Time::now().add(delta: Time::days(1)).into(),
    );
    let expiration = Time::now().add(delta: Time::days(1));

    let mut withdraw_args = WithdrawArgs {
        position_id: user.position_id,
        salt: user.salt_counter,
        expiration,
        collateral_id: cfg.collateral_cfg.collateral_id,
        amount: WITHDRAW_AMOUNT,
        recipient: recipient.address,
    };
    let msg_hash = withdraw_args.get_message_hash(public_key: user.get_public_key());
    let signature = user.sign_message(message: msg_hash);

    // Test:
    cheat_caller_address_once(contract_address: test_address(), caller_address: user.address);
    state
        .withdraw_request(
            :signature,
            recipient: withdraw_args.recipient,
            position_id: withdraw_args.position_id,
            collateral_id: withdraw_args.collateral_id,
            amount: withdraw_args.amount,
            expiration: withdraw_args.expiration,
            salt: withdraw_args.salt,
        );

    // Check:
    let status = state.request_approvals.approved_requests.entry(msg_hash).read();
    assert_eq!(status, RequestStatus::PENDING);
}

#[test]
fn test_successful_withdraw_request_with_owner() {
    // Setup state, token and user:
    let cfg: PerpetualsInitConfig = Default::default();
    let token_state = cfg.collateral_cfg.token_cfg.deploy();
    let mut state = setup_state_with_active_asset(cfg: @cfg, token_state: @token_state);
    let mut user = Default::default();
    init_position_with_owner(cfg: @cfg, ref :state, :user);
    let recipient = UserTrait::new(position_id: POSITION_ID_2, key_pair: KEY_PAIR_2());

    // Setup parameters:
    start_cheat_block_timestamp_global(
        block_timestamp: Time::now().add(delta: Time::days(1)).into(),
    );
    let expiration = Time::now().add(delta: Time::days(1));

    let mut withdraw_args = WithdrawArgs {
        position_id: user.position_id,
        salt: user.salt_counter,
        recipient: recipient.address,
        collateral_id: cfg.collateral_cfg.collateral_id,
        amount: WITHDRAW_AMOUNT,
        expiration,
    };
    let msg_hash = withdraw_args.get_message_hash(public_key: user.get_public_key());
    let signature = user.sign_message(message: msg_hash);

    // Test:
    cheat_caller_address_once(contract_address: test_address(), caller_address: user.address);
    state
        .withdraw_request(
            :signature,
            recipient: withdraw_args.recipient,
            position_id: withdraw_args.position_id,
            collateral_id: withdraw_args.collateral_id,
            amount: withdraw_args.amount,
            expiration: withdraw_args.expiration,
            salt: withdraw_args.salt,
        );

    // Check:
    let status = state.request_approvals.approved_requests.entry(msg_hash).read();
    assert_eq!(status, RequestStatus::PENDING);
}

// Deleverage tests.

#[test]
fn test_successful_deleverage() {
    // Setup state, token and user:
    let cfg: PerpetualsInitConfig = Default::default();
    let token_state = cfg.collateral_cfg.token_cfg.deploy();
    let mut state = setup_state_with_active_asset(cfg: @cfg, token_state: @token_state);

    let deleveraged = Default::default();
    init_position(cfg: @cfg, ref :state, user: deleveraged);
    add_synthetic_to_position(
        ref :state,
        asset_id: cfg.synthetic_cfg.synthetic_id,
        position_id: deleveraged.position_id,
        // To make the position deleveragable, the total value must be negative, which requires a
        // negative synthetic balance.
        balance: -2 * SYNTHETIC_BALANCE_AMOUNT,
    );

    let deleverager = UserTrait::new(position_id: POSITION_ID_2, key_pair: KEY_PAIR_2());
    init_position(cfg: @cfg, ref :state, user: deleverager);
    add_synthetic_to_position(
        ref :state,
        asset_id: cfg.synthetic_cfg.synthetic_id,
        position_id: deleverager.position_id,
        balance: SYNTHETIC_BALANCE_AMOUNT,
    );

    // Test params:
    let operator_nonce = state.nonce();
    // For a fair deleverage, the TV/TR ratio of the deleveraged position should remain the same
    // before and after the deleverage. This is the reasoning behind the choice
    // of QUOTE and BASE.
    let BASE = 10;
    let QUOTE = -500;

    let collateral_id = cfg.collateral_cfg.collateral_id;
    let synthetic_id = cfg.synthetic_cfg.synthetic_id;

    // State change:
    //                            TV                            TR                          TV/TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // Deleveraged before:     2000-40*100=-2000              40*100*0.5=2000                 -1
    // Deleveraged after:    (2000-500)+(-40+10)*100=-1500           1500                     -1
    // Deleverager before:     2000+20*100=4000               20*100*0.5=1000                 4
    // Deleverager after:    (2000+500)+(20-10)*100=3500            1500                      7/3

    let mut spy = snforge_std::spy_events();
    // Test:
    cheat_caller_address_once(contract_address: test_address(), caller_address: cfg.operator);
    state
        .deleverage(
            :operator_nonce,
            deleveraged_position: deleveraged.position_id,
            deleverager_position: deleverager.position_id,
            deleveraged_base_asset_id: synthetic_id,
            deleveraged_base_amount: BASE,
            deleveraged_quote_asset_id: collateral_id,
            deleveraged_quote_amount: QUOTE,
        );

    // Catch the event.
    let events = spy.get_events().emitted_by(test_address()).events;
    assert_deleverage_event_with_expected(
        spied_event: events[0],
        deleveraged_position: deleveraged.position_id,
        deleverager_position: deleverager.position_id,
        deleveraged_base_asset_id: synthetic_id,
        deleveraged_base_amount: BASE,
        deleveraged_quote_asset_id: collateral_id,
        deleveraged_quote_amount: QUOTE,
    );

    // Check:
    let deleveraged_position = state
        .positions
        .get_position_const(position_id: deleveraged.position_id);
    let deleverager_position = state
        .positions
        .get_position_const(position_id: deleverager.position_id);

    let deleveraged_collateral_balance = deleveraged_position
        .collateral_assets
        .entry(collateral_id)
        .balance
        .read();
    let deleveraged_synthetic_balance = deleveraged_position
        .synthetic_assets
        .entry(synthetic_id)
        .balance
        .read();
    assert_eq!(deleveraged_collateral_balance, (COLLATERAL_BALANCE_AMOUNT + QUOTE).into());
    assert_eq!(deleveraged_synthetic_balance, (-2 * SYNTHETIC_BALANCE_AMOUNT + BASE).into());

    let deleverager_collateral_balance = deleverager_position
        .collateral_assets
        .entry(collateral_id)
        .balance
        .read();
    let deleverager_synthetic_balance = deleverager_position
        .synthetic_assets
        .entry(synthetic_id)
        .balance
        .read();
    assert_eq!(deleverager_collateral_balance, (COLLATERAL_BALANCE_AMOUNT - QUOTE).into());
    assert_eq!(deleverager_synthetic_balance, (SYNTHETIC_BALANCE_AMOUNT - BASE).into());
}

#[test]
#[should_panic(expected: 'POSITION_IS_NOT_FAIR_DELEVERAGE')]
fn test_unfair_deleverage() {
    // Setup state, token and user:
    let cfg: PerpetualsInitConfig = Default::default();
    let token_state = cfg.collateral_cfg.token_cfg.deploy();
    let mut state = setup_state_with_active_asset(cfg: @cfg, token_state: @token_state);

    let deleveraged = Default::default();
    init_position(cfg: @cfg, ref :state, user: deleveraged);
    add_synthetic_to_position(
        ref :state,
        asset_id: cfg.synthetic_cfg.synthetic_id,
        position_id: deleveraged.position_id,
        // To make the position deleveragable, the total value must be negative, which requires a
        // negative synthetic balance.
        balance: -2 * SYNTHETIC_BALANCE_AMOUNT,
    );

    let deleverager = UserTrait::new(position_id: POSITION_ID_2, key_pair: KEY_PAIR_2());
    init_position(cfg: @cfg, ref :state, user: deleverager);
    add_synthetic_to_position(
        ref :state,
        asset_id: cfg.synthetic_cfg.synthetic_id,
        position_id: deleverager.position_id,
        balance: SYNTHETIC_BALANCE_AMOUNT,
    );

    // Test params:
    let operator_nonce = state.nonce();
    // The following value causes an unfair deleverage, as it breaks the TV/TR ratio.
    let BASE = 10;
    let QUOTE = -10;

    let collateral_id = cfg.collateral_cfg.collateral_id;
    let synthetic_id = cfg.synthetic_cfg.synthetic_id;

    // State change:
    //                            TV                            TR                         TV/TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // Deleveraged before:     2000-40*100=-2000              40*100*0.5=2000               -1
    // Deleveraged after:    (2000-10)+(-40+10)*100=-1010           1500                    -101/150
    // Deleverager before:     2000+20*100=4000               20*100*0.5=1000               4
    // Deleverager after:    (2000+10)+(20-10)*100=3010            1500                     301/150

    // Test:
    cheat_caller_address_once(contract_address: test_address(), caller_address: cfg.operator);
    state
        .deleverage(
            :operator_nonce,
            deleveraged_position: deleveraged.position_id,
            deleverager_position: deleverager.position_id,
            deleveraged_base_asset_id: synthetic_id,
            deleveraged_base_amount: BASE,
            deleveraged_quote_asset_id: collateral_id,
            deleveraged_quote_amount: QUOTE,
        );
}

#[test]
fn test_successful_liquidate() {
    // Setup state, token and user:
    let cfg: PerpetualsInitConfig = Default::default();
    let token_state = cfg.collateral_cfg.token_cfg.deploy();
    let mut state = setup_state_with_active_asset(cfg: @cfg, token_state: @token_state);

    let mut liquidator = Default::default();
    init_position(cfg: @cfg, ref :state, user: liquidator);
    let mut liquidated = UserTrait::new(position_id: POSITION_ID_2, key_pair: KEY_PAIR_2());
    init_position(cfg: @cfg, ref :state, user: liquidated);
    add_synthetic_to_position(
        ref :state,
        asset_id: cfg.synthetic_cfg.synthetic_id,
        position_id: liquidated.position_id,
        balance: -SYNTHETIC_BALANCE_AMOUNT,
    );

    // Test params:
    let BASE = 10;
    let QUOTE = -5;
    let INSURANCE_FEE = 1;
    let FEE = 2;

    // Setup parameters:
    let mut expiration = Time::now();
    expiration += Time::days(1);
    let operator_nonce = state.nonce();

    let collateral_id = cfg.collateral_cfg.collateral_id;
    let synthetic_id = cfg.synthetic_cfg.synthetic_id;

    let order_liquidator = Order {
        position_id: liquidator.position_id,
        salt: liquidator.salt_counter,
        base_asset_id: synthetic_id,
        base_amount: -BASE,
        quote_asset_id: collateral_id,
        quote_amount: -QUOTE,
        fee_asset_id: collateral_id,
        fee_amount: FEE,
        expiration,
    };

    let liquidator_hash = order_liquidator.get_message_hash(liquidator.get_public_key());
    let liquidator_signature = liquidator.sign_message(liquidator_hash);

    let mut spy = snforge_std::spy_events();
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
            fee_asset_id: collateral_id,
            fee_amount: INSURANCE_FEE,
        );
    // Catch the event.
    let events = spy.get_events().emitted_by(test_address()).events;
    assert_liquidate_event_with_expected(
        spied_event: events[0],
        liquidated_position_id: liquidated.position_id,
        liquidator_order_position_id: liquidator.position_id,
        liquidator_order_base_asset_id: synthetic_id,
        liquidator_order_base_amount: -BASE,
        liquidator_order_quote_asset_id: collateral_id,
        liquidator_order_quote_amount: -QUOTE,
        liquidator_order_fee_asset_id: collateral_id,
        liquidator_order_fee_amount: FEE,
        actual_amount_base_liquidated: BASE,
        actual_amount_quote_liquidated: QUOTE,
        actual_liquidator_fee: FEE,
        insurance_fund_fee_asset_id: collateral_id,
        insurance_fund_fee_amount: INSURANCE_FEE,
        liquidator_order_hash: liquidator_hash,
    );

    // Check:
    let liquidated_position = state
        .positions
        .get_position_const(position_id: liquidated.position_id);
    let liquidator_position = state
        .positions
        .get_position_const(position_id: liquidator.position_id);

    let liquidated_collateral_balance = liquidated_position
        .collateral_assets
        .entry(collateral_id)
        .balance
        .read();
    let liquidated_synthetic_balance = liquidated_position
        .synthetic_assets
        .entry(synthetic_id)
        .balance
        .read();
    assert_eq!(
        liquidated_collateral_balance,
        (COLLATERAL_BALANCE_AMOUNT.into() - INSURANCE_FEE.into() + QUOTE.into()),
    );
    assert_eq!(liquidated_synthetic_balance, (-SYNTHETIC_BALANCE_AMOUNT + BASE).into());

    let liquidator_collateral_balance = liquidator_position
        .collateral_assets
        .entry(collateral_id)
        .balance
        .read();
    let liquidator_synthetic_balance = liquidator_position
        .synthetic_assets
        .entry(synthetic_id)
        .balance
        .read();
    assert_eq!(
        liquidator_collateral_balance,
        (COLLATERAL_BALANCE_AMOUNT.into() - FEE.into() - QUOTE.into()),
    );
    assert_eq!(liquidator_synthetic_balance, (-BASE).into());

    let fee_position_balance = state
        .positions
        .get_provisional_balance(position_id: Positions::FEE_POSITION, asset_id: collateral_id);
    assert_eq!(fee_position_balance, FEE.into());

    let insurance_position_balance = state
        .positions
        .get_provisional_balance(
            position_id: Positions::INSURANCE_FUND_POSITION, asset_id: collateral_id,
        );
    assert_eq!(insurance_position_balance, INSURANCE_FEE.into());
}

#[test]
fn test_successful_transfer_request_using_public_key() {
    // Setup state, token and user:
    let cfg: PerpetualsInitConfig = Default::default();
    let token_state = cfg.collateral_cfg.token_cfg.deploy();
    let mut state = setup_state_with_active_asset(cfg: @cfg, token_state: @token_state);
    let mut user = Default::default();
    init_position(cfg: @cfg, ref :state, :user);
    let mut recipient = UserTrait::new(position_id: POSITION_ID_2, key_pair: KEY_PAIR_2());

    // Setup parameters:
    let expected_time = Time::now().add(delta: Time::days(1));
    start_cheat_block_timestamp_global(block_timestamp: expected_time.into());
    let expiration = expected_time.add(delta: Time::days(1));

    let mut transfer_args = TransferArgs {
        position_id: user.position_id,
        salt: user.salt_counter,
        recipient: recipient.position_id,
        collateral_id: cfg.collateral_cfg.collateral_id,
        amount: TRANSFER_AMOUNT,
        expiration,
    };
    let msg_hash = transfer_args.get_message_hash(public_key: user.get_public_key());
    let signature = user.sign_message(msg_hash);

    // Test:
    cheat_caller_address_once(contract_address: test_address(), caller_address: user.address);
    state
        .transfer_request(
            :signature,
            recipient: transfer_args.recipient,
            position_id: transfer_args.position_id,
            collateral_id: transfer_args.collateral_id,
            amount: transfer_args.amount,
            expiration: transfer_args.expiration,
            salt: transfer_args.salt,
        );

    // Check:
    let status = state.request_approvals.approved_requests.entry(msg_hash).read();
    assert_eq!(status, RequestStatus::PENDING);
}

#[test]
fn test_successful_transfer_request_with_owner() {
    // Setup state, token and user:
    let cfg: PerpetualsInitConfig = Default::default();
    let token_state = cfg.collateral_cfg.token_cfg.deploy();
    let mut state = setup_state_with_active_asset(cfg: @cfg, token_state: @token_state);
    let mut user = Default::default();
    let mut recipient = UserTrait::new(position_id: POSITION_ID_2, key_pair: KEY_PAIR_2());
    init_position_with_owner(cfg: @cfg, ref :state, :user);

    // Setup parameters:
    let expected_time = Time::now().add(delta: Time::days(1));
    start_cheat_block_timestamp_global(block_timestamp: expected_time.into());
    let expiration = expected_time.add(delta: Time::days(1));

    let mut transfer_args = TransferArgs {
        position_id: user.position_id,
        recipient: recipient.position_id,
        salt: user.salt_counter,
        expiration,
        collateral_id: cfg.collateral_cfg.collateral_id,
        amount: TRANSFER_AMOUNT,
    };
    let msg_hash = transfer_args.get_message_hash(public_key: user.get_public_key());
    let signature = user.sign_message(message: msg_hash);

    // Test:
    cheat_caller_address_once(contract_address: test_address(), caller_address: user.address);
    state
        .transfer_request(
            :signature,
            recipient: transfer_args.recipient,
            position_id: transfer_args.position_id,
            collateral_id: transfer_args.collateral_id,
            amount: transfer_args.amount,
            expiration: transfer_args.expiration,
            salt: transfer_args.salt,
        );

    // Check:
    let status = state.request_approvals.approved_requests.entry(msg_hash).read();
    assert_eq!(status, RequestStatus::PENDING);
}

#[test]
fn test_successful_set_public_key_request() {
    // Setup state, token and user:
    let cfg: PerpetualsInitConfig = Default::default();
    let token_state = cfg.collateral_cfg.token_cfg.deploy();
    let mut state = setup_state_with_active_asset(cfg: @cfg, token_state: @token_state);
    let mut user = Default::default();
    init_position_with_owner(cfg: @cfg, ref :state, :user);

    // Setup parameters:
    let expiration = Time::now().add(delta: Time::days(1));

    user.set_public_key(KEY_PAIR_2());
    assert_eq!(user.get_public_key(), KEY_PAIR_2().public_key);

    // Test change public key in perps:
    cheat_caller_address_once(contract_address: test_address(), caller_address: user.address);
    let mut set_public_key_args = SetPublicKeyArgs {
        position_id: user.position_id, expiration, new_public_key: user.get_public_key(),
    };
    let msg_hash = set_public_key_args.get_message_hash(public_key: user.get_public_key());
    let signature = user.sign_message(message: msg_hash);
    state
        .set_public_key_request(
            :signature,
            position_id: set_public_key_args.position_id,
            new_public_key: set_public_key_args.new_public_key,
            expiration: set_public_key_args.expiration,
        );

    // Check:
    let status = state.request_approvals.approved_requests.entry(msg_hash).read();
    assert_eq!(status, RequestStatus::PENDING);
}

#[test]
fn test_successful_set_public_key() {
    // Setup state, token and user:
    let cfg: PerpetualsInitConfig = Default::default();
    let token_state = cfg.collateral_cfg.token_cfg.deploy();
    let mut state = setup_state_with_active_asset(cfg: @cfg, token_state: @token_state);
    let mut user = Default::default();
    init_position_with_owner(cfg: @cfg, ref :state, :user);

    // Setup parameters:
    let expiration = Time::now().add(delta: Time::days(1));

    user.set_public_key(KEY_PAIR_2());
    assert_eq!(user.get_public_key(), KEY_PAIR_2().public_key);

    cheat_caller_address_once(contract_address: test_address(), caller_address: user.address);
    let mut set_public_key_args = SetPublicKeyArgs {
        position_id: user.position_id, expiration, new_public_key: user.get_public_key(),
    };
    let msg_hash = set_public_key_args.get_message_hash(public_key: user.get_public_key());
    let signature = user.sign_message(message: msg_hash);
    let mut spy = snforge_std::spy_events();
    state
        .set_public_key_request(
            :signature,
            position_id: set_public_key_args.position_id,
            new_public_key: set_public_key_args.new_public_key,
            expiration: set_public_key_args.expiration,
        );

    cheat_caller_address_once(contract_address: test_address(), caller_address: cfg.operator);
    state
        .set_public_key(
            operator_nonce: state.nonce(),
            position_id: set_public_key_args.position_id,
            new_public_key: set_public_key_args.new_public_key,
            expiration: set_public_key_args.expiration,
        );

    // Catch the event.
    let events = spy.get_events().emitted_by(test_address()).events;
    assert_set_public_key_request_event_with_expected(
        spied_event: events[0],
        position_id: set_public_key_args.position_id,
        new_public_key: set_public_key_args.new_public_key,
        expiration: set_public_key_args.expiration,
        set_public_key_request_hash: msg_hash,
    );
    assert_set_public_key_event_with_expected(
        spied_event: events[1],
        position_id: set_public_key_args.position_id,
        new_public_key: set_public_key_args.new_public_key,
        expiration: set_public_key_args.expiration,
        set_public_key_request_hash: msg_hash,
    );

    // Check:
    assert_eq!(
        user.get_public_key(),
        state.positions.get_position_const(position_id: user.position_id).owner_public_key.read(),
    );
}

#[test]
#[should_panic(expected: 'REQUEST_NOT_REGISTERED')]
fn test_successful_set_public_key_no_request() {
    // Setup state, token and user:
    let cfg: PerpetualsInitConfig = Default::default();
    let token_state = cfg.collateral_cfg.token_cfg.deploy();
    let mut state = setup_state_with_active_asset(cfg: @cfg, token_state: @token_state);
    let mut user = Default::default();
    init_position_with_owner(cfg: @cfg, ref :state, :user);

    // Setup parameters:
    let expiration = Time::now().add(delta: Time::days(1));

    user.set_public_key(KEY_PAIR_2());
    assert_eq!(user.get_public_key(), KEY_PAIR_2().public_key);

    let mut set_public_key_args = SetPublicKeyArgs {
        position_id: user.position_id, expiration, new_public_key: user.get_public_key(),
    };
    cheat_caller_address_once(contract_address: test_address(), caller_address: cfg.operator);
    state
        .set_public_key(
            operator_nonce: state.nonce(),
            position_id: set_public_key_args.position_id,
            new_public_key: set_public_key_args.new_public_key,
            expiration: set_public_key_args.expiration,
        );
}


#[test]
fn test_successful_transfer() {
    // Setup state, token and user:
    let cfg: PerpetualsInitConfig = Default::default();
    let token_state = cfg.collateral_cfg.token_cfg.deploy();
    let mut state = setup_state_with_active_asset(cfg: @cfg, token_state: @token_state);

    let mut sender = Default::default();
    init_position(cfg: @cfg, ref :state, user: sender);

    let mut recipient = UserTrait::new(position_id: POSITION_ID_2, key_pair: KEY_PAIR_2());
    init_position(cfg: @cfg, ref :state, user: recipient);

    // Setup parameters:
    let expiration = Time::now().add(delta: Time::days(1));
    let collateral_id = cfg.collateral_cfg.collateral_id;
    let operator_nonce = state.nonce();

    let transfer_args = TransferArgs {
        position_id: sender.position_id,
        recipient: recipient.position_id,
        salt: sender.salt_counter,
        expiration: expiration,
        collateral_id,
        amount: TRANSFER_AMOUNT,
    };

    let mut spy = snforge_std::spy_events();
    let msg_hash = transfer_args.get_message_hash(sender.get_public_key());
    let sender_signature = sender.sign_message(msg_hash);
    // Test:
    state
        .transfer_request(
            signature: sender_signature,
            recipient: transfer_args.recipient,
            position_id: transfer_args.position_id,
            collateral_id: transfer_args.collateral_id,
            amount: transfer_args.amount,
            expiration: transfer_args.expiration,
            salt: transfer_args.salt,
        );
    cheat_caller_address_once(contract_address: test_address(), caller_address: cfg.operator);
    state
        .transfer(
            :operator_nonce,
            recipient: transfer_args.recipient,
            position_id: transfer_args.position_id,
            collateral_id: transfer_args.collateral_id,
            amount: transfer_args.amount,
            expiration: transfer_args.expiration,
            salt: transfer_args.salt,
        );

    // Catch the event.
    let events = spy.get_events().emitted_by(test_address()).events;
    assert_transfer_request_event_with_expected(
        spied_event: events[0],
        position_id: transfer_args.position_id,
        recipient: transfer_args.recipient,
        collateral_id: transfer_args.collateral_id,
        amount: transfer_args.amount,
        expiration: transfer_args.expiration,
        transfer_request_hash: msg_hash,
    );
    assert_transfer_event_with_expected(
        spied_event: events[1],
        position_id: transfer_args.position_id,
        recipient: transfer_args.recipient,
        collateral_id: transfer_args.collateral_id,
        amount: transfer_args.amount,
        expiration: transfer_args.expiration,
        transfer_request_hash: msg_hash,
    );

    // Check:
    let sender_collateral_balance = state
        .positions
        .get_provisional_balance(position_id: sender.position_id, asset_id: collateral_id);
    assert_eq!(
        sender_collateral_balance, COLLATERAL_BALANCE_AMOUNT.into() - TRANSFER_AMOUNT.into(),
    );

    let recipient_collateral_balance = state
        .positions
        .get_provisional_balance(position_id: recipient.position_id, asset_id: collateral_id);
    assert_eq!(
        recipient_collateral_balance, COLLATERAL_BALANCE_AMOUNT.into() + TRANSFER_AMOUNT.into(),
    );
}

// `validate_synthetic_price` tests.

#[test]
#[should_panic(expected: 'SYNTHETIC_EXPIRED_PRICE')]
fn test_validate_synthetic_prices_expired() {
    // Setup state, token and user:
    let cfg: PerpetualsInitConfig = Default::default();
    let token_state = cfg.collateral_cfg.token_cfg.deploy();
    let mut state = setup_state_with_active_asset(cfg: @cfg, token_state: @token_state);
    let user: User = Default::default();
    init_position(cfg: @cfg, ref :state, :user);
    // Fund user.
    token_state.fund(recipient: user.address, amount: USER_INIT_BALANCE.try_into().unwrap());
    token_state
        .approve(
            owner: user.address,
            spender: test_address(),
            amount: DEPOSIT_AMOUNT * cfg.collateral_cfg.quantum.into(),
        );
    // Set the block timestamp to be after the price validation interval
    let now = Time::now().add(delta: Time::days(count: 2));
    start_cheat_block_timestamp_global(block_timestamp: now.into());
    state.assets.last_funding_tick.write(now);
    cheat_caller_address_once(contract_address: test_address(), caller_address: user.address);
    state
        .deposit(
            beneficiary: user.position_id.into(),
            asset_id: cfg.collateral_cfg.collateral_id.into(),
            quantized_amount: DEPOSIT_AMOUNT,
            salt: user.salt_counter,
        );
    cheat_caller_address_once(contract_address: test_address(), caller_address: cfg.operator);
    // Call the function, should panic with EXPIRED_PRICE error
    state
        .process_deposit(
            operator_nonce: state.nonce(),
            depositor: user.address,
            position_id: user.position_id,
            collateral_id: cfg.collateral_cfg.collateral_id,
            amount: DEPOSIT_AMOUNT,
            salt: user.salt_counter,
        );
}

#[test]
fn test_validate_synthetic_prices_uninitialized_asset() {
    // Setup state, token and user:
    let cfg: PerpetualsInitConfig = Default::default();
    let token_state = cfg.collateral_cfg.token_cfg.deploy();
    let mut state = setup_state_with_pending_asset(cfg: @cfg, token_state: @token_state);
    let user: User = Default::default();
    init_position(cfg: @cfg, ref :state, :user);
    // Fund user.
    token_state.fund(recipient: user.address, amount: USER_INIT_BALANCE.try_into().unwrap());
    token_state
        .approve(
            owner: user.address,
            spender: test_address(),
            amount: DEPOSIT_AMOUNT * cfg.collateral_cfg.quantum.into(),
        );
    state
        .assets
        .synthetic_timely_data
        .entry(cfg.synthetic_cfg.synthetic_id)
        .last_price_update
        .write(Time::now());
    // Set the block timestamp to be after the price validation interval
    let now = Time::now().add(delta: Time::days(count: 2));
    start_cheat_block_timestamp_global(block_timestamp: now.into());
    state.assets.last_funding_tick.write(Time::now());
    cheat_caller_address_once(contract_address: test_address(), caller_address: user.address);
    state
        .deposit(
            beneficiary: user.position_id.into(),
            asset_id: cfg.collateral_cfg.collateral_id.into(),
            quantized_amount: DEPOSIT_AMOUNT,
            salt: user.salt_counter,
        );
    cheat_caller_address_once(contract_address: test_address(), caller_address: cfg.operator);
    // Call the function, should panic with EXPIRED_PRICE error
    state
        .process_deposit(
            operator_nonce: state.nonce(),
            depositor: user.address,
            position_id: user.position_id,
            collateral_id: cfg.collateral_cfg.collateral_id,
            amount: DEPOSIT_AMOUNT,
            salt: user.salt_counter,
        );
    // If no assertion error is thrown, the test passes
}

#[test]
fn test_validate_prices() {
    // Setup state, token and user:
    let cfg: PerpetualsInitConfig = Default::default();
    let token_state = cfg.collateral_cfg.token_cfg.deploy();
    let mut state = setup_state_with_active_asset(cfg: @cfg, token_state: @token_state);
    let user: User = Default::default();
    init_position(cfg: @cfg, ref :state, :user);
    // Fund user.
    token_state.fund(recipient: user.address, amount: USER_INIT_BALANCE.try_into().unwrap());
    token_state
        .approve(
            owner: user.address,
            spender: test_address(),
            amount: DEPOSIT_AMOUNT * cfg.collateral_cfg.quantum.into(),
        );
    let new_time = Time::now().add(delta: Time::days(count: 1));
    start_cheat_block_timestamp_global(block_timestamp: new_time.into());
    state.assets.last_funding_tick.write(Time::now());
    cheat_caller_address_once(contract_address: test_address(), caller_address: user.address);
    state
        .deposit(
            beneficiary: user.position_id.into(),
            asset_id: cfg.collateral_cfg.collateral_id.into(),
            quantized_amount: DEPOSIT_AMOUNT,
            salt: user.salt_counter,
        );
    cheat_caller_address_once(contract_address: test_address(), caller_address: cfg.operator);
    state
        .process_deposit(
            operator_nonce: state.nonce(),
            depositor: user.address,
            position_id: user.position_id,
            collateral_id: cfg.collateral_cfg.collateral_id,
            amount: DEPOSIT_AMOUNT,
            salt: user.salt_counter,
        );
    assert_eq!(state.assets.last_price_validation.read(), new_time);
}

#[test]
fn test_validate_prices_no_update_needed() {
    // Setup state, token and user:
    let cfg: PerpetualsInitConfig = Default::default();
    let token_state = cfg.collateral_cfg.token_cfg.deploy();
    let mut state = setup_state_with_active_asset(cfg: @cfg, token_state: @token_state);
    let user: User = Default::default();
    init_position(cfg: @cfg, ref :state, :user);
    // Fund user.
    token_state.fund(recipient: user.address, amount: USER_INIT_BALANCE.try_into().unwrap());
    token_state
        .approve(
            owner: user.address,
            spender: test_address(),
            amount: DEPOSIT_AMOUNT * cfg.collateral_cfg.quantum.into(),
        );
    let old_time = Time::now();
    assert_eq!(state.assets.last_price_validation.read(), old_time);
    let new_time = Time::now().add(delta: Time::seconds(count: 1000));
    start_cheat_block_timestamp_global(block_timestamp: new_time.into());
    cheat_caller_address_once(contract_address: test_address(), caller_address: user.address);
    state
        .deposit(
            beneficiary: user.position_id.into(),
            asset_id: cfg.collateral_cfg.collateral_id.into(),
            quantized_amount: DEPOSIT_AMOUNT,
            salt: user.salt_counter,
        );
    cheat_caller_address_once(contract_address: test_address(), caller_address: cfg.operator);
    state
        .process_deposit(
            operator_nonce: state.nonce(),
            depositor: user.address,
            position_id: user.position_id,
            collateral_id: cfg.collateral_cfg.collateral_id,
            amount: DEPOSIT_AMOUNT,
            salt: user.salt_counter,
        );

    assert_eq!(state.assets.last_price_validation.read(), old_time);
}

// `price_tick` tests.

#[test]
fn test_price_tick_basic() {
    let cfg: PerpetualsInitConfig = Default::default();
    let token_state = cfg.collateral_cfg.token_cfg.deploy();
    let mut state = setup_state_with_active_asset(cfg: @cfg, token_state: @token_state);
    let mut spy = snforge_std::spy_events();
    let asset_name = 'ASSET_NAME';
    let oracle1_name = 'ORCL1';
    let oracle1 = Oracle { oracle_name: oracle1_name, asset_name, key_pair: KEY_PAIR_1() };
    let synthetic_id = cfg.synthetic_cfg.synthetic_id;
    cheat_caller_address_once(contract_address: test_address(), caller_address: cfg.app_governor);
    state
        .add_oracle_to_asset(
            asset_id: synthetic_id,
            oracle_public_key: oracle1.key_pair.public_key,
            oracle_name: oracle1_name,
            :asset_name,
        );
    let old_time: u64 = Time::now().into();
    state.assets.synthetic_config.write(synthetic_id, Option::Some(SYNTHETIC_PENDING_CONFIG()));
    state.assets.num_of_active_synthetic_assets.write(Zero::zero());
    assert_eq!(state.assets.get_num_of_active_synthetic_assets(), Zero::zero());
    let new_time = Time::now().add(delta: MAX_ORACLE_PRICE_VALIDITY);
    start_cheat_block_timestamp_global(block_timestamp: new_time.into());
    cheat_caller_address_once(contract_address: test_address(), caller_address: cfg.operator);
    let price: u128 = TEN_POW_15.into();
    let operator_nonce = state.nonce();
    state
        .price_tick(
            :operator_nonce,
            asset_id: synthetic_id,
            :price,
            signed_prices: [
                oracle1.get_signed_price(:price, timestamp: old_time.try_into().unwrap())
            ]
                .span(),
        );

    // Catch the event.
    let events = spy.get_events().emitted_by(test_address()).events;
    assert_add_oracle_event_with_expected(
        spied_event: events[0],
        asset_id: synthetic_id,
        oracle_public_key: oracle1.key_pair.public_key,
    );
    assert_asset_activated_event_with_expected(spied_event: events[1], asset_id: synthetic_id);
    assert_price_tick_event_with_expected(
        spied_event: events[2], asset_id: synthetic_id, price: PriceTrait::new(268),
    );

    assert!(state.assets.get_synthetic_config(synthetic_id).status == AssetStatus::ACTIVATED);
    assert_eq!(state.assets.get_num_of_active_synthetic_assets(), 1);

    let data = state.assets.synthetic_timely_data.read(synthetic_id);
    assert_eq!(data.last_price_update, new_time);
    assert_eq!(data.price.value(), 268);
}

#[test]
fn test_price_tick_odd() {
    let cfg: PerpetualsInitConfig = Default::default();
    let token_state = cfg.collateral_cfg.token_cfg.deploy();
    let mut state = setup_state_with_active_asset(cfg: @cfg, token_state: @token_state);
    let asset_name = 'ASSET_NAME';
    let oracle1_name = 'ORCL1';
    let oracle2_name = 'ORCL2';
    let oracle3_name = 'ORCL3';
    let oracle1 = Oracle { oracle_name: oracle1_name, asset_name, key_pair: KEY_PAIR_1() };
    let oracle2 = Oracle { oracle_name: oracle2_name, asset_name, key_pair: KEY_PAIR_2() };
    let oracle3 = Oracle { oracle_name: oracle3_name, asset_name, key_pair: KEY_PAIR_3() };
    let synthetic_id = cfg.synthetic_cfg.synthetic_id;
    cheat_caller_address_once(contract_address: test_address(), caller_address: cfg.app_governor);
    state
        .add_oracle_to_asset(
            asset_id: synthetic_id,
            oracle_public_key: oracle1.key_pair.public_key,
            oracle_name: oracle1_name,
            :asset_name,
        );
    cheat_caller_address_once(contract_address: test_address(), caller_address: cfg.app_governor);
    state
        .add_oracle_to_asset(
            asset_id: synthetic_id,
            oracle_public_key: oracle2.key_pair.public_key,
            oracle_name: oracle2_name,
            :asset_name,
        );
    cheat_caller_address_once(contract_address: test_address(), caller_address: cfg.app_governor);
    state
        .add_oracle_to_asset(
            asset_id: synthetic_id,
            oracle_public_key: oracle3.key_pair.public_key,
            oracle_name: oracle3_name,
            :asset_name,
        );
    let old_time: u64 = Time::now().into();
    state.assets.synthetic_config.write(synthetic_id, Option::Some(SYNTHETIC_PENDING_CONFIG()));
    state.assets.num_of_active_synthetic_assets.write(0);
    assert_eq!(state.assets.get_num_of_active_synthetic_assets(), 0);
    let new_time = Time::now().add(delta: MAX_ORACLE_PRICE_VALIDITY);
    start_cheat_block_timestamp_global(block_timestamp: new_time.into());
    cheat_caller_address_once(contract_address: test_address(), caller_address: cfg.operator);
    let price: u128 = TEN_POW_15.into();
    let operator_nonce = state.nonce();
    state
        .price_tick(
            :operator_nonce,
            asset_id: synthetic_id,
            :price,
            signed_prices: [
                oracle2.get_signed_price(:price, timestamp: old_time.try_into().unwrap()),
                oracle3.get_signed_price(price: price + 1, timestamp: old_time.try_into().unwrap()),
                oracle1.get_signed_price(price: price - 1, timestamp: old_time.try_into().unwrap()),
            ]
                .span(),
        );
    assert!(state.assets.get_synthetic_config(synthetic_id).status == AssetStatus::ACTIVATED);
    assert_eq!(state.assets.get_num_of_active_synthetic_assets(), 1);
    let data = state.assets.synthetic_timely_data.read(synthetic_id);
    assert_eq!(data.last_price_update, new_time);
    assert_eq!(data.price.value(), 268);
}
#[test]
fn test_price_tick_even() {
    let cfg: PerpetualsInitConfig = Default::default();
    let token_state = cfg.collateral_cfg.token_cfg.deploy();
    let mut state = setup_state_with_active_asset(cfg: @cfg, token_state: @token_state);
    let asset_name = 'ASSET_NAME';
    let oracle1_name = 'ORCL1';
    let oracle3_name = 'ORCL3';
    let oracle1 = Oracle { oracle_name: oracle1_name, asset_name, key_pair: KEY_PAIR_1() };
    let oracle3 = Oracle { oracle_name: oracle3_name, asset_name, key_pair: KEY_PAIR_3() };
    let synthetic_id = cfg.synthetic_cfg.synthetic_id;
    cheat_caller_address_once(contract_address: test_address(), caller_address: cfg.app_governor);
    state
        .add_oracle_to_asset(
            asset_id: synthetic_id,
            oracle_public_key: oracle1.key_pair.public_key,
            oracle_name: oracle1_name,
            :asset_name,
        );
    cheat_caller_address_once(contract_address: test_address(), caller_address: cfg.app_governor);
    state
        .add_oracle_to_asset(
            asset_id: synthetic_id,
            oracle_public_key: oracle3.key_pair.public_key,
            oracle_name: oracle3_name,
            :asset_name,
        );
    let old_time: u64 = Time::now().into();
    state.assets.synthetic_config.write(synthetic_id, Option::Some(SYNTHETIC_PENDING_CONFIG()));
    state.assets.num_of_active_synthetic_assets.write(0);
    assert_eq!(state.assets.get_num_of_active_synthetic_assets(), 0);
    let new_time = Time::now().add(delta: MAX_ORACLE_PRICE_VALIDITY);
    start_cheat_block_timestamp_global(block_timestamp: new_time.into());
    cheat_caller_address_once(contract_address: test_address(), caller_address: cfg.operator);
    let price: u128 = TEN_POW_15.into();
    let operator_nonce = state.nonce();
    state
        .price_tick(
            :operator_nonce,
            asset_id: synthetic_id,
            :price,
            signed_prices: [
                oracle3.get_signed_price(price: price + 1, timestamp: old_time.try_into().unwrap()),
                oracle1.get_signed_price(price: price - 1, timestamp: old_time.try_into().unwrap()),
            ]
                .span(),
        );
    assert!(state.assets.get_synthetic_config(synthetic_id).status == AssetStatus::ACTIVATED);
    assert_eq!(state.assets.get_num_of_active_synthetic_assets(), 1);

    let data = state.assets.synthetic_timely_data.read(synthetic_id);
    assert_eq!(data.last_price_update, new_time);
    assert_eq!(data.price.value(), 268);
}

#[test]
#[should_panic(expected: 'QUORUM_NOT_REACHED')]
fn test_price_tick_no_quorum() {
    let cfg: PerpetualsInitConfig = Default::default();
    let token_state = cfg.collateral_cfg.token_cfg.deploy();
    let mut state = setup_state_with_active_asset(cfg: @cfg, token_state: @token_state);
    cheat_caller_address_once(contract_address: test_address(), caller_address: cfg.operator);
    let operator_nonce = state.nonce();
    state
        .price_tick(
            :operator_nonce,
            asset_id: cfg.synthetic_cfg.synthetic_id,
            price: Zero::zero(),
            signed_prices: [].span(),
        );
}

#[test]
#[should_panic(expected: 'SIGNED_PRICES_UNSORTED')]
fn test_price_tick_unsorted() {
    let cfg: PerpetualsInitConfig = Default::default();
    let token_state = cfg.collateral_cfg.token_cfg.deploy();
    let mut state = setup_state_with_active_asset(cfg: @cfg, token_state: @token_state);
    let asset_name = 'ASSET_NAME';
    let oracle1_name = 'ORCL1';
    let oracle2_name = 'ORCL2';
    let oracle1 = Oracle { oracle_name: oracle1_name, asset_name, key_pair: KEY_PAIR_1() };
    let oracle2 = Oracle { oracle_name: oracle2_name, asset_name, key_pair: KEY_PAIR_3() };
    let synthetic_id = cfg.synthetic_cfg.synthetic_id;
    cheat_caller_address_once(contract_address: test_address(), caller_address: cfg.app_governor);
    state
        .add_oracle_to_asset(
            asset_id: synthetic_id,
            oracle_public_key: oracle1.key_pair.public_key,
            oracle_name: oracle1_name,
            :asset_name,
        );
    cheat_caller_address_once(contract_address: test_address(), caller_address: cfg.app_governor);
    state
        .add_oracle_to_asset(
            asset_id: synthetic_id,
            oracle_public_key: oracle2.key_pair.public_key,
            oracle_name: oracle2_name,
            :asset_name,
        );
    let old_time: u64 = Time::now().into();
    state.assets.synthetic_config.write(synthetic_id, Option::Some(SYNTHETIC_PENDING_CONFIG()));
    cheat_caller_address_once(contract_address: test_address(), caller_address: cfg.operator);
    let price: u128 = TEN_POW_15.into();
    let operator_nonce = state.nonce();
    state
        .price_tick(
            :operator_nonce,
            asset_id: synthetic_id,
            :price,
            signed_prices: [
                oracle1.get_signed_price(price: price - 1, timestamp: old_time.try_into().unwrap()),
                oracle2.get_signed_price(price: price + 1, timestamp: old_time.try_into().unwrap()),
            ]
                .span(),
        );
}

#[test]
#[should_panic(expected: 'INVALID_PRICE_TIMESTAMP')]
fn test_price_tick_old_oracle() {
    let cfg: PerpetualsInitConfig = Default::default();
    let token_state = cfg.collateral_cfg.token_cfg.deploy();
    let mut state = setup_state_with_active_asset(cfg: @cfg, token_state: @token_state);
    let asset_name = 'ASSET_NAME';
    let oracle1_name = 'ORCL1';
    let oracle1 = Oracle { oracle_name: oracle1_name, asset_name, key_pair: KEY_PAIR_1() };
    let synthetic_id = cfg.synthetic_cfg.synthetic_id;
    cheat_caller_address_once(contract_address: test_address(), caller_address: cfg.app_governor);
    state
        .add_oracle_to_asset(
            asset_id: synthetic_id,
            oracle_public_key: oracle1.key_pair.public_key,
            oracle_name: oracle1_name,
            :asset_name,
        );
    let old_time: u64 = Time::now().into();
    let new_time = Time::now().add(delta: MAX_ORACLE_PRICE_VALIDITY + Time::seconds(1));
    start_cheat_block_timestamp_global(block_timestamp: new_time.into());
    cheat_caller_address_once(contract_address: test_address(), caller_address: cfg.operator);
    let price = 1000;
    let operator_nonce = state.nonce();
    state
        .price_tick(
            :operator_nonce,
            asset_id: synthetic_id,
            :price,
            signed_prices: [
                oracle1.get_signed_price(:price, timestamp: old_time.try_into().unwrap())
            ]
                .span(),
        );
}

#[test]
/// This test numbers were taken from an example of a real price tick that was sent to StarkEx.
fn test_price_tick_golden() {
    let cfg: PerpetualsInitConfig = Default::default();
    let token_state = cfg.collateral_cfg.token_cfg.deploy();
    let mut state = setup_state_with_active_asset(cfg: @cfg, token_state: @token_state);
    let asset_name = 'PENGUUSDMARK\x00\x00\x00\x00';
    let oracle0_name = 'Stkai';
    let oracle1_name = 'Stork';
    let oracle2_name = 'StCrw';
    let synthetic_id = cfg.synthetic_cfg.synthetic_id;
    cheat_caller_address_once(contract_address: test_address(), caller_address: cfg.app_governor);
    state
        .add_oracle_to_asset(
            asset_id: synthetic_id,
            oracle_public_key: 0x1f191d23b8825dcc3dba839b6a7155ea07ad0b42af76394097786aca0d9975c,
            oracle_name: oracle0_name,
            :asset_name,
        );
    cheat_caller_address_once(contract_address: test_address(), caller_address: cfg.app_governor);
    state
        .add_oracle_to_asset(
            asset_id: synthetic_id,
            oracle_public_key: 0xcc85afe4ca87f9628370c432c447e569a01dc96d160015c8039959db8521c4,
            oracle_name: oracle1_name,
            :asset_name,
        );
    cheat_caller_address_once(contract_address: test_address(), caller_address: cfg.app_governor);
    state
        .add_oracle_to_asset(
            asset_id: synthetic_id,
            oracle_public_key: 0x41dbe627aeab66504b837b3abd88ae2f58ba6d98ee7bbd7f226c4684d9e6225,
            oracle_name: oracle2_name,
            :asset_name,
        );

    let timestamp: u32 = 1737451956;
    let price = 23953641840000000;
    let signed_price0 = SignedPrice {
        signature: [
            0x23120d436ab1e115f883fd495206b80c9a9928f94df89c2bb63eb1997cc13d5,
            0x21469ce0da02bf1a5897077b238f536f78427f946dafde2b79884cf10131e74,
        ]
            .span(),
        signer_public_key: 0x1f191d23b8825dcc3dba839b6a7155ea07ad0b42af76394097786aca0d9975c,
        timestamp,
        price,
    };
    let signed_price1 = SignedPrice {
        signature: [
            0x6c4beab13946105513c157ca8498735af2c3ff0f75efe6e1d1747efcff8339f,
            0x94619200c9b03a647f6f29df52d2291e866b43e57dc1a8200deb5219c87b14,
        ]
            .span(),
        signer_public_key: 0xcc85afe4ca87f9628370c432c447e569a01dc96d160015c8039959db8521c4,
        timestamp,
        price,
    };
    let signed_price2 = SignedPrice {
        signature: [
            0x3aed46d0aff9d904faf5f76c2fb9f43c858e6f9e9c9bf99ca9fd4c1baa907b2,
            0x58523be606a55c57aedd5e030a349a478a22132b84d6f77e1e348a4991f5c80,
        ]
            .span(),
        signer_public_key: 0x41dbe627aeab66504b837b3abd88ae2f58ba6d98ee7bbd7f226c4684d9e6225,
        timestamp,
        price,
    };
    start_cheat_block_timestamp_global(block_timestamp: Timestamp { seconds: 1737451976 }.into());
    cheat_caller_address_once(contract_address: test_address(), caller_address: cfg.operator);
    let operator_nonce = state.nonce();
    state
        .price_tick(
            :operator_nonce,
            asset_id: synthetic_id,
            :price,
            signed_prices: [signed_price1, signed_price0, signed_price2].span(),
        );
    let data = state.assets.synthetic_timely_data.read(synthetic_id);
    assert_eq!(data.last_price_update, Time::now());
    assert_eq!(data.price.value(), 6430);
}
