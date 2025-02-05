use Core::InternalCoreFunctionsTrait;
use contracts_commons::components::deposit::interface::{DepositStatus, IDeposit};
use contracts_commons::components::nonce::interface::INonce;
use contracts_commons::components::request_approvals::interface::RequestStatus;
use contracts_commons::components::roles::interface::IRoles;
use contracts_commons::constants::TEN_POW_12;
use contracts_commons::math::Abs;
use contracts_commons::message_hash::OffchainMessageHash;
use contracts_commons::test_utils::{Deployable, TokenTrait, cheat_caller_address_once};
use contracts_commons::types::time::time::{Time, Timestamp};
use core::num::traits::Zero;
use perpetuals::core::components::assets::AssetsComponent::InternalTrait as AssetsInternal;
use perpetuals::core::components::assets::interface::IAssets;
use perpetuals::core::core::Core;
use perpetuals::core::core::Core::SNIP12MetadataImpl;
use perpetuals::core::interface::ICore;
use perpetuals::core::types::AssetAmount;
use perpetuals::core::types::asset::synthetic::SyntheticConfig;
use perpetuals::core::types::order::Order;
use perpetuals::core::types::price::{PriceTrait, SignedPrice};
use perpetuals::core::types::set_public_key::SetPublicKeyArgs;
use perpetuals::core::types::transfer::TransferArgs;
use perpetuals::core::types::withdraw::WithdrawArgs;
use perpetuals::tests::constants::*;
use perpetuals::tests::event_test_utils::assert_new_position_event_with_expected;
use perpetuals::tests::test_utils::{
    Oracle, OracleTrait, PerpetualsInitConfig, UserTrait, add_synthetic, check_synthetic_asset,
    init_position, init_position_with_owner, initialized_contract_state, setup_state,
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

    assert_eq!(state.positions.entry(Core::FEE_POSITION).owner_account.read(), OPERATOR());
    assert_eq!(
        state.positions.entry(Core::FEE_POSITION).owner_public_key.read(), OPERATOR_PUBLIC_KEY(),
    );
    assert_eq!(
        state.positions.entry(Core::INSURANCE_FUND_POSITION).owner_account.read(), OPERATOR(),
    );
    assert_eq!(
        state.positions.entry(Core::INSURANCE_FUND_POSITION).owner_public_key.read(),
        OPERATOR_PUBLIC_KEY(),
    );
}

#[test]
fn test_new_position() {
    // Setup state, token:
    let cfg: PerpetualsInitConfig = Default::default();
    let token_state = cfg.collateral_cfg.token_cfg.deploy();
    let mut state = setup_state(cfg: @cfg, token_state: @token_state);
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
    assert_eq!(state.positions.entry(position_id).version.read(), Core::POSITION_VERSION);
    assert_eq!(state.positions.entry(position_id).owner_public_key.read(), owner_public_key);
    assert_eq!(state.positions.entry(position_id).owner_account.read(), owner_account);
}

// Add synthetic asset tests.

#[test]
fn test_successful_add_synthetic_asset() {
    // Setup state, token:
    let cfg: PerpetualsInitConfig = Default::default();
    let token_state = cfg.collateral_cfg.token_cfg.deploy();
    let mut state = setup_state(cfg: @cfg, token_state: @token_state);

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

    // Check:
    check_synthetic_asset(
        state: @state,
        synthetic_id: synthetic_id_1,
        is_active: false,
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
        is_active: false,
        risk_factor: risk_factor_2,
        quorum: quorum_2,
        resolution: resolution_2,
        price: Zero::zero(),
        last_price_update: Zero::zero(),
        funding_index: Zero::zero(),
    );
}

#[test]
#[should_panic(expected: 'ASSET_ALREADY_EXISTS')]
fn test_add_synthetic_asset_existed_asset() {
    // Setup state, token:
    let cfg: PerpetualsInitConfig = Default::default();
    let token_state = cfg.collateral_cfg.token_cfg.deploy();
    let mut state = setup_state(cfg: @cfg, token_state: @token_state);

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
    let mut state = setup_state(cfg: @cfg, token_state: @token_state);
    // Setup parameters:
    let synthetic_id = cfg.synthetic_cfg.asset_id;
    assert!(state.assets.synthetic_config.entry(synthetic_id).read().unwrap().is_active);

    // Test:
    cheat_caller_address_once(contract_address: test_address(), caller_address: cfg.app_governor);
    state.deactivate_synthetic(:synthetic_id);

    // Check:
    assert!(!state.assets.synthetic_config.entry(synthetic_id).read().unwrap().is_active);
}

#[test]
#[should_panic(expected: 'SYNTHETIC_NOT_EXISTS')]
fn test_deactivate_unexisted_synthetic_asset() {
    // Setup state, token and user:
    let cfg: PerpetualsInitConfig = Default::default();
    let token_state = cfg.collateral_cfg.token_cfg.deploy();
    let mut state = setup_state(cfg: @cfg, token_state: @token_state);
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
    let mut state = setup_state(cfg: @cfg, token_state: @token_state);
    let user = Default::default();
    init_position(cfg: @cfg, ref :state, :user);

    // Setup parameters:
    let expiration = Time::now().add(Time::days(1));

    let mut withdraw_args = WithdrawArgs {
        position_id: user.position_id,
        salt: user.salt_counter,
        expiration,
        collateral: AssetAmount { asset_id: cfg.collateral_cfg.asset_id, amount: WITHDRAW_AMOUNT },
        recipient: user.address,
    };
    let signature = user.sign_message(withdraw_args.get_message_hash(user.get_public_key()));
    let operator_nonce = state.nonce();

    let contract_state_balance = token_state.balance_of(test_address());
    assert_eq!(contract_state_balance, CONTRACT_INIT_BALANCE.into());

    // Test:
    state
        .withdraw_request(
            :signature,
            position_id: withdraw_args.position_id,
            salt: withdraw_args.salt,
            expiration: withdraw_args.expiration,
            collateral: withdraw_args.collateral,
            recipient: withdraw_args.recipient,
        );
    cheat_caller_address_once(contract_address: test_address(), caller_address: cfg.operator);
    state
        .withdraw(
            :operator_nonce,
            position_id: withdraw_args.position_id,
            salt: withdraw_args.salt,
            expiration: withdraw_args.expiration,
            collateral: withdraw_args.collateral,
            recipient: withdraw_args.recipient,
        );
    // Check:
    let user_balance = token_state.balance_of(user.address);
    let onchain_amount = (WITHDRAW_AMOUNT.abs() * COLLATERAL_QUANTUM);
    assert_eq!(user_balance, onchain_amount.into());
    let contract_state_balance = token_state.balance_of(test_address());
    assert_eq!(contract_state_balance, (CONTRACT_INIT_BALANCE - onchain_amount.into()).into());
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

    // Test:
    cheat_caller_address_once(contract_address: test_address(), caller_address: user.address);
    let deposit_hash = state
        .deposit(
            asset_id: cfg.collateral_cfg.asset_id.into(),
            quantized_amount: DEPOSIT_AMOUNT,
            beneficiary: user.position_id.value,
            salt: user.salt_counter,
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
    let mut state = setup_state(cfg: @cfg, token_state: @token_state);

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

    let fee_position_balance = state
        ._get_provisional_balance(position_id: Core::FEE_POSITION, asset_id: collateral_id);
    assert_eq!(fee_position_balance, (FEE + FEE).into());
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

    let signature = user.sign_message(order.get_message_hash(user.get_public_key()));
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

    let mut user_b = UserTrait::new(position_id: POSITION_ID_2, key_pair: KEY_PAIR_2());
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
    let mut state = setup_state(cfg: @cfg, token_state: @token_state);
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
        collateral: AssetAmount { asset_id: cfg.collateral_cfg.asset_id, amount: WITHDRAW_AMOUNT },
        recipient: recipient.address,
    };
    let msg_hash = withdraw_args.get_message_hash(public_key: user.get_public_key());
    let signature = user.sign_message(message: msg_hash);

    // Test:
    cheat_caller_address_once(contract_address: test_address(), caller_address: user.address);
    state
        .withdraw_request(
            :signature,
            position_id: withdraw_args.position_id,
            salt: withdraw_args.salt,
            expiration: withdraw_args.expiration,
            collateral: withdraw_args.collateral,
            recipient: withdraw_args.recipient,
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
    let mut state = setup_state(cfg: @cfg, token_state: @token_state);
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
        expiration,
        collateral: AssetAmount { asset_id: cfg.collateral_cfg.asset_id, amount: WITHDRAW_AMOUNT },
        recipient: recipient.address,
    };
    let msg_hash = withdraw_args.get_message_hash(public_key: user.get_public_key());
    let signature = user.sign_message(message: msg_hash);

    // Test:
    cheat_caller_address_once(contract_address: test_address(), caller_address: user.address);
    state
        .withdraw_request(
            :signature,
            position_id: withdraw_args.position_id,
            salt: withdraw_args.salt,
            expiration: withdraw_args.expiration,
            collateral: withdraw_args.collateral,
            recipient: withdraw_args.recipient,
        );

    // Check:
    let status = state.request_approvals.approved_requests.entry(msg_hash).read();
    assert_eq!(status, RequestStatus::PENDING);
}

#[test]
fn test_successful_liquidate() {
    // Setup state, token and user:
    let cfg: PerpetualsInitConfig = Default::default();
    let token_state = cfg.collateral_cfg.token_cfg.deploy();
    let mut state = setup_state(cfg: @cfg, token_state: @token_state);

    let mut liquidator = Default::default();
    init_position(cfg: @cfg, ref :state, user: liquidator);

    let mut liquidated = UserTrait::new(position_id: POSITION_ID_2, key_pair: KEY_PAIR_2());
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
    let INSURANCE_FEE = 1;
    let FEE = 2;

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
        .sign_message(order_liquidator.get_message_hash(liquidator.get_public_key()));

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
            fee: AssetAmount { asset_id: collateral_id, amount: INSURANCE_FEE },
        );

    // Check:
    let liquidated_position = state.positions.entry(liquidated.position_id);
    let liquidator_position = state.positions.entry(liquidator.position_id);

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
        liquidated_collateral_balance, (COLLATERAL_BALANCE_AMOUNT - INSURANCE_FEE + QUOTE).into(),
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
    assert_eq!(liquidator_collateral_balance, (COLLATERAL_BALANCE_AMOUNT - FEE - QUOTE).into());
    assert_eq!(liquidator_synthetic_balance, (-BASE).into());

    let fee_position_balance = state
        ._get_provisional_balance(position_id: Core::FEE_POSITION, asset_id: collateral_id);
    assert_eq!(fee_position_balance, FEE.into());

    let insurance_position_balance = state
        ._get_provisional_balance(
            position_id: Core::INSURANCE_FUND_POSITION, asset_id: collateral_id,
        );
    assert_eq!(insurance_position_balance, INSURANCE_FEE.into());
}

#[test]
fn test_successful_transfer_request_using_public_key() {
    // Setup state, token and user:
    let cfg: PerpetualsInitConfig = Default::default();
    let token_state = cfg.collateral_cfg.token_cfg.deploy();
    let mut state = setup_state(cfg: @cfg, token_state: @token_state);
    let mut user = Default::default();
    init_position(cfg: @cfg, ref :state, :user);
    let mut recipient = UserTrait::new(position_id: POSITION_ID_2, key_pair: KEY_PAIR_2());

    // Setup parameters:
    let expected_time = Time::now().add(delta: Time::days(1));
    start_cheat_block_timestamp_global(block_timestamp: expected_time.into());
    let expiration = expected_time.add(delta: Time::days(1));

    let mut transfer_args = TransferArgs {
        position_id: user.position_id,
        recipient: recipient.position_id,
        salt: user.salt_counter,
        expiration,
        collateral: AssetAmount { asset_id: cfg.collateral_cfg.asset_id, amount: TRANSFER_AMOUNT },
    };
    let msg_hash = transfer_args.get_message_hash(public_key: user.get_public_key());
    let signature = user.sign_message(msg_hash);

    // Test:
    cheat_caller_address_once(contract_address: test_address(), caller_address: user.address);
    state
        .transfer_request(
            :signature,
            position_id: transfer_args.position_id,
            recipient: transfer_args.recipient,
            salt: transfer_args.salt,
            expiration: transfer_args.expiration,
            collateral: transfer_args.collateral,
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
    let mut state = setup_state(cfg: @cfg, token_state: @token_state);
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
        collateral: AssetAmount { asset_id: cfg.collateral_cfg.asset_id, amount: TRANSFER_AMOUNT },
    };
    let msg_hash = transfer_args.get_message_hash(public_key: user.get_public_key());
    let signature = user.sign_message(message: msg_hash);

    // Test:
    cheat_caller_address_once(contract_address: test_address(), caller_address: user.address);
    state
        .transfer_request(
            :signature,
            position_id: transfer_args.position_id,
            recipient: transfer_args.recipient,
            salt: transfer_args.salt,
            expiration: transfer_args.expiration,
            collateral: transfer_args.collateral,
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
    let mut state = setup_state(cfg: @cfg, token_state: @token_state);
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
            expiration: set_public_key_args.expiration,
            new_public_key: set_public_key_args.new_public_key,
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
    let mut state = setup_state(cfg: @cfg, token_state: @token_state);
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
    state
        .set_public_key_request(
            :signature,
            position_id: set_public_key_args.position_id,
            expiration: set_public_key_args.expiration,
            new_public_key: set_public_key_args.new_public_key,
        );

    cheat_caller_address_once(contract_address: test_address(), caller_address: cfg.operator);
    state
        .set_public_key(
            operator_nonce: state.nonce(),
            position_id: set_public_key_args.position_id,
            expiration: set_public_key_args.expiration,
            new_public_key: set_public_key_args.new_public_key,
        );
    // Check:
    assert_eq!(
        user.get_public_key(), state.positions.entry(user.position_id).owner_public_key.read(),
    );
}

#[test]
#[should_panic(expected: 'REQUEST_NOT_REGISTERED')]
fn test_successful_set_public_key_no_request() {
    // Setup state, token and user:
    let cfg: PerpetualsInitConfig = Default::default();
    let token_state = cfg.collateral_cfg.token_cfg.deploy();
    let mut state = setup_state(cfg: @cfg, token_state: @token_state);
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
            expiration: set_public_key_args.expiration,
            new_public_key: set_public_key_args.new_public_key,
        );
}


#[test]
fn test_successful_transfer() {
    // Setup state, token and user:
    let cfg: PerpetualsInitConfig = Default::default();
    let token_state = cfg.collateral_cfg.token_cfg.deploy();
    let mut state = setup_state(cfg: @cfg, token_state: @token_state);

    let mut sender = Default::default();
    init_position(cfg: @cfg, ref :state, user: sender);

    let mut recipient = UserTrait::new(position_id: POSITION_ID_2, key_pair: KEY_PAIR_2());
    init_position(cfg: @cfg, ref :state, user: recipient);

    // Setup parameters:
    let expiration = Time::now().add(delta: Time::days(1));
    let collateral_id = cfg.collateral_cfg.asset_id;
    let operator_nonce = state.nonce();
    let collateral = AssetAmount { asset_id: cfg.collateral_cfg.asset_id, amount: TRANSFER_AMOUNT };

    let transfer_args = TransferArgs {
        position_id: sender.position_id,
        recipient: recipient.position_id,
        salt: sender.salt_counter,
        expiration: expiration,
        collateral: collateral,
    };

    let sender_signature = sender
        .sign_message(transfer_args.get_message_hash(sender.get_public_key()));
    // Test:
    state
        .transfer_request(
            signature: sender_signature,
            position_id: transfer_args.position_id,
            recipient: transfer_args.recipient,
            salt: transfer_args.salt,
            expiration: transfer_args.expiration,
            collateral: transfer_args.collateral,
        );
    cheat_caller_address_once(contract_address: test_address(), caller_address: cfg.operator);
    state
        .transfer(
            :operator_nonce,
            position_id: transfer_args.position_id,
            recipient: transfer_args.recipient,
            salt: transfer_args.salt,
            expiration: transfer_args.expiration,
            collateral: transfer_args.collateral,
        );

    // Check:
    let sender_collateral_balance = state
        ._get_provisional_balance(position_id: sender.position_id, asset_id: collateral_id);
    assert_eq!(sender_collateral_balance, (COLLATERAL_BALANCE_AMOUNT - TRANSFER_AMOUNT).into());

    let recipient_collateral_balance = state
        ._get_provisional_balance(position_id: recipient.position_id, asset_id: collateral_id);
    assert_eq!(recipient_collateral_balance, (COLLATERAL_BALANCE_AMOUNT + TRANSFER_AMOUNT).into());
}

#[test]
fn test_price_tick_basic() {
    let cfg: PerpetualsInitConfig = Default::default();
    let token_state = cfg.collateral_cfg.token_cfg.deploy();
    let mut state = setup_state(cfg: @cfg, token_state: @token_state);
    let asset_name = 'ASSET_NAME';
    let oracle1_name = 'ORCL1';
    let oracle1 = Oracle { oracle_name: oracle1_name, asset_name, key_pair: KEY_PAIR_1() };
    let asset_id = cfg.synthetic_cfg.asset_id;
    let resolution = state.assets.synthetic_config.read(asset_id).unwrap().resolution;
    cheat_caller_address_once(contract_address: test_address(), caller_address: cfg.app_governor);
    state
        .add_oracle_to_asset(
            :asset_id,
            oracle_public_key: oracle1.key_pair.public_key,
            oracle_name: oracle1_name,
            :asset_name,
        );
    let old_time: u64 = Time::now().into();
    state
        .assets
        .synthetic_config
        .write(asset_id, Option::Some(SyntheticConfig { is_active: false, ..SYNTHETIC_CONFIG() }));
    state.assets.num_of_active_synthetic_assets.write(Zero::zero());
    assert_eq!(state.assets._get_num_of_active_synthetic_assets(), Zero::zero());
    let new_time = Time::now().add(delta: MAX_ORACLE_PRICE_VALIDITY);
    start_cheat_block_timestamp_global(block_timestamp: new_time.into());
    cheat_caller_address_once(contract_address: test_address(), caller_address: cfg.operator);
    let price: u128 = TEN_POW_12.into();
    let operator_nonce = state.nonce();
    state
        .price_tick(
            :operator_nonce,
            :asset_id,
            :price,
            signed_prices: [
                oracle1.get_signed_price(:price, timestamp: old_time.try_into().unwrap())
            ]
                .span(),
        );
    assert!(state.assets._get_synthetic_config(asset_id).is_active);
    assert_eq!(state.assets._get_num_of_active_synthetic_assets(), 1);
    let data = state.assets.synthetic_timely_data.read(asset_id);
    assert_eq!(data.last_price_update, new_time);
    assert_eq!(data.price, price.convert(:resolution));
}

#[test]
fn test_price_tick_odd() {
    let cfg: PerpetualsInitConfig = Default::default();
    let token_state = cfg.collateral_cfg.token_cfg.deploy();
    let mut state = setup_state(cfg: @cfg, token_state: @token_state);
    let asset_name = 'ASSET_NAME';
    let oracle1_name = 'ORCL1';
    let oracle2_name = 'ORCL2';
    let oracle3_name = 'ORCL3';
    let oracle1 = Oracle { oracle_name: oracle1_name, asset_name, key_pair: KEY_PAIR_1() };
    let oracle2 = Oracle { oracle_name: oracle2_name, asset_name, key_pair: KEY_PAIR_2() };
    let oracle3 = Oracle { oracle_name: oracle3_name, asset_name, key_pair: KEY_PAIR_3() };
    let asset_id = cfg.synthetic_cfg.asset_id;
    let resolution = state.assets.synthetic_config.read(asset_id).unwrap().resolution;
    cheat_caller_address_once(contract_address: test_address(), caller_address: cfg.app_governor);
    state
        .add_oracle_to_asset(
            :asset_id,
            oracle_public_key: oracle1.key_pair.public_key,
            oracle_name: oracle1_name,
            :asset_name,
        );
    cheat_caller_address_once(contract_address: test_address(), caller_address: cfg.app_governor);
    state
        .add_oracle_to_asset(
            :asset_id,
            oracle_public_key: oracle2.key_pair.public_key,
            oracle_name: oracle2_name,
            :asset_name,
        );
    cheat_caller_address_once(contract_address: test_address(), caller_address: cfg.app_governor);
    state
        .add_oracle_to_asset(
            :asset_id,
            oracle_public_key: oracle3.key_pair.public_key,
            oracle_name: oracle3_name,
            :asset_name,
        );
    let old_time: u64 = Time::now().into();
    state
        .assets
        .synthetic_config
        .write(asset_id, Option::Some(SyntheticConfig { is_active: false, ..SYNTHETIC_CONFIG() }));
    state.assets.num_of_active_synthetic_assets.write(0);
    assert_eq!(state.assets._get_num_of_active_synthetic_assets(), 0);
    let new_time = Time::now().add(delta: MAX_ORACLE_PRICE_VALIDITY);
    start_cheat_block_timestamp_global(block_timestamp: new_time.into());
    cheat_caller_address_once(contract_address: test_address(), caller_address: cfg.operator);
    let price: u128 = TEN_POW_12.into();
    let operator_nonce = state.nonce();
    state
        .price_tick(
            :operator_nonce,
            :asset_id,
            :price,
            signed_prices: [
                oracle2.get_signed_price(:price, timestamp: old_time.try_into().unwrap()),
                oracle3.get_signed_price(price: price + 1, timestamp: old_time.try_into().unwrap()),
                oracle1.get_signed_price(price: price - 1, timestamp: old_time.try_into().unwrap()),
            ]
                .span(),
        );
    assert!(state.assets._get_synthetic_config(asset_id).is_active);
    assert_eq!(state.assets._get_num_of_active_synthetic_assets(), 1);
    let data = state.assets.synthetic_timely_data.read(asset_id);
    assert_eq!(data.last_price_update, new_time);
    assert_eq!(data.price, price.convert(:resolution));
}
#[test]
fn test_price_tick_even() {
    let cfg: PerpetualsInitConfig = Default::default();
    let token_state = cfg.collateral_cfg.token_cfg.deploy();
    let mut state = setup_state(cfg: @cfg, token_state: @token_state);
    let asset_name = 'ASSET_NAME';
    let oracle1_name = 'ORCL1';
    let oracle3_name = 'ORCL3';
    let oracle1 = Oracle { oracle_name: oracle1_name, asset_name, key_pair: KEY_PAIR_1() };
    let oracle3 = Oracle { oracle_name: oracle3_name, asset_name, key_pair: KEY_PAIR_3() };
    let asset_id = cfg.synthetic_cfg.asset_id;
    let resolution = state.assets.synthetic_config.read(asset_id).unwrap().resolution;
    cheat_caller_address_once(contract_address: test_address(), caller_address: cfg.app_governor);
    state
        .add_oracle_to_asset(
            :asset_id,
            oracle_public_key: oracle1.key_pair.public_key,
            oracle_name: oracle1_name,
            :asset_name,
        );
    cheat_caller_address_once(contract_address: test_address(), caller_address: cfg.app_governor);
    state
        .add_oracle_to_asset(
            :asset_id,
            oracle_public_key: oracle3.key_pair.public_key,
            oracle_name: oracle3_name,
            :asset_name,
        );
    let old_time: u64 = Time::now().into();
    state
        .assets
        .synthetic_config
        .write(asset_id, Option::Some(SyntheticConfig { is_active: false, ..SYNTHETIC_CONFIG() }));
    state.assets.num_of_active_synthetic_assets.write(0);
    assert_eq!(state.assets._get_num_of_active_synthetic_assets(), 0);
    let new_time = Time::now().add(delta: MAX_ORACLE_PRICE_VALIDITY);
    start_cheat_block_timestamp_global(block_timestamp: new_time.into());
    cheat_caller_address_once(contract_address: test_address(), caller_address: cfg.operator);
    let price: u128 = TEN_POW_12.into();
    let operator_nonce = state.nonce();
    state
        .price_tick(
            :operator_nonce,
            :asset_id,
            :price,
            signed_prices: [
                oracle3.get_signed_price(price: price + 1, timestamp: old_time.try_into().unwrap()),
                oracle1.get_signed_price(price: price - 1, timestamp: old_time.try_into().unwrap()),
            ]
                .span(),
        );
    assert!(state.assets._get_synthetic_config(asset_id).is_active);
    assert_eq!(state.assets._get_num_of_active_synthetic_assets(), 1);
    let data = state.assets.synthetic_timely_data.read(asset_id);
    assert_eq!(data.last_price_update, new_time);
    assert_eq!(data.price, price.convert(:resolution));
}

#[test]
#[should_panic(expected: 'QUORUM_NOT_REACHED')]
fn test_price_tick_no_quorum() {
    let cfg: PerpetualsInitConfig = Default::default();
    let token_state = cfg.collateral_cfg.token_cfg.deploy();
    let mut state = setup_state(cfg: @cfg, token_state: @token_state);
    cheat_caller_address_once(contract_address: test_address(), caller_address: cfg.operator);
    let operator_nonce = state.nonce();
    state
        .price_tick(
            :operator_nonce,
            asset_id: cfg.synthetic_cfg.asset_id,
            price: Zero::zero(),
            signed_prices: [].span(),
        );
}

#[test]
#[should_panic(expected: 'SIGNED_PRICES_UNSORTED')]
fn test_price_tick_unsorted() {
    let cfg: PerpetualsInitConfig = Default::default();
    let token_state = cfg.collateral_cfg.token_cfg.deploy();
    let mut state = setup_state(cfg: @cfg, token_state: @token_state);
    let asset_name = 'ASSET_NAME';
    let oracle1_name = 'ORCL1';
    let oracle2_name = 'ORCL2';
    let oracle1 = Oracle { oracle_name: oracle1_name, asset_name, key_pair: KEY_PAIR_1() };
    let oracle2 = Oracle { oracle_name: oracle2_name, asset_name, key_pair: KEY_PAIR_3() };
    let asset_id = cfg.synthetic_cfg.asset_id;
    cheat_caller_address_once(contract_address: test_address(), caller_address: cfg.app_governor);
    state
        .add_oracle_to_asset(
            :asset_id,
            oracle_public_key: oracle1.key_pair.public_key,
            oracle_name: oracle1_name,
            :asset_name,
        );
    cheat_caller_address_once(contract_address: test_address(), caller_address: cfg.app_governor);
    state
        .add_oracle_to_asset(
            :asset_id,
            oracle_public_key: oracle2.key_pair.public_key,
            oracle_name: oracle2_name,
            :asset_name,
        );
    let old_time: u64 = Time::now().into();
    state
        .assets
        .synthetic_config
        .write(asset_id, Option::Some(SyntheticConfig { is_active: false, ..SYNTHETIC_CONFIG() }));
    cheat_caller_address_once(contract_address: test_address(), caller_address: cfg.operator);
    let price: u128 = TEN_POW_12.into();
    let operator_nonce = state.nonce();
    state
        .price_tick(
            :operator_nonce,
            :asset_id,
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
    let mut state = setup_state(cfg: @cfg, token_state: @token_state);
    let asset_name = 'ASSET_NAME';
    let oracle1_name = 'ORCL1';
    let oracle1 = Oracle { oracle_name: oracle1_name, asset_name, key_pair: KEY_PAIR_1() };
    let asset_id = cfg.synthetic_cfg.asset_id;
    cheat_caller_address_once(contract_address: test_address(), caller_address: cfg.app_governor);
    state
        .add_oracle_to_asset(
            :asset_id,
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
            asset_id: cfg.synthetic_cfg.asset_id,
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
    let mut state = setup_state(cfg: @cfg, token_state: @token_state);
    let asset_name = 'PENGUUSDMARK\x00\x00\x00\x00';
    let oracle0_name = 'Stkai';
    let oracle1_name = 'Stork';
    let oracle2_name = 'StCrw';
    let asset_id = cfg.synthetic_cfg.asset_id;
    cheat_caller_address_once(contract_address: test_address(), caller_address: cfg.app_governor);
    state
        .add_oracle_to_asset(
            asset_id: asset_id,
            oracle_public_key: 0x1f191d23b8825dcc3dba839b6a7155ea07ad0b42af76394097786aca0d9975c,
            oracle_name: oracle0_name,
            :asset_name,
        );
    cheat_caller_address_once(contract_address: test_address(), caller_address: cfg.app_governor);
    state
        .add_oracle_to_asset(
            asset_id: asset_id,
            oracle_public_key: 0xcc85afe4ca87f9628370c432c447e569a01dc96d160015c8039959db8521c4,
            oracle_name: oracle1_name,
            :asset_name,
        );
    cheat_caller_address_once(contract_address: test_address(), caller_address: cfg.app_governor);
    state
        .add_oracle_to_asset(
            asset_id: asset_id,
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
            :asset_id,
            :price,
            signed_prices: [signed_price1, signed_price0, signed_price2].span(),
        );
    let data = state.assets.synthetic_timely_data.read(asset_id);
    assert_eq!(data.last_price_update, Time::now());
    assert_eq!(data.price.value(), 6430);
}
