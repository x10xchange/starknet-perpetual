use perpetuals::tests::flow_tests::infra::*;
use perpetuals::tests::flow_tests::perps_tests_facade::*;
use snforge_std::signature::stark_curve::StarkCurveKeyPairImpl;

#[test]
fn test_prediction_deposit_and_withdraw() {
    // Setup.
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let user = state.new_user_with_position();

    // Deposit collateral to perps position.
    let deposit_info = state
        .facade
        .deposit(
            depositor: user.account, position_id: user.position_id, quantized_amount: 100_000,
        );
    state.facade.process_deposit(deposit_info: deposit_info);

    // Create prediction account with a real key pair.
    let client_id: felt252 = 1;
    let owning_key_pair = StarkCurveKeyPairImpl::from_secret_key(42);
    state
        .facade
        .create_prediction_account(:client_id, owning_key: owning_key_pair.public_key);
    state.facade.validate_prediction_collateral(:client_id, expected_collateral: 0);

    // Deposit from perps position to prediction account.
    state
        .facade
        .deposit_to_prediction_account(
            from_position_id: user.position_id,
            :client_id,
            quantized_amount: 50_000,
            :owning_key_pair,
        );

    // Validate balances after deposit.
    state
        .facade
        .validate_collateral_balance(
            position_id: user.position_id, expected_balance: 50_000_i64.into(),
        );
    state.facade.validate_prediction_collateral(:client_id, expected_collateral: 50_000);

    // Withdraw from prediction account back to perps position.
    state
        .facade
        .withdraw_from_prediction_account(
            to_position_id: user.position_id,
            :client_id,
            quantized_amount: 30_000,
            :owning_key_pair,
        );

    // Validate balances after withdraw.
    state
        .facade
        .validate_collateral_balance(
            position_id: user.position_id, expected_balance: 80_000_i64.into(),
        );
    state.facade.validate_prediction_collateral(:client_id, expected_collateral: 20_000);
}

#[test]
fn test_prediction_deposit_full_and_withdraw_full() {
    // Setup.
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let user = state.new_user_with_position();

    let amount: u64 = 100_000;
    let deposit_info = state
        .facade
        .deposit(
            depositor: user.account, position_id: user.position_id, quantized_amount: amount,
        );
    state.facade.process_deposit(deposit_info: deposit_info);

    // Create prediction account and deposit full amount.
    let client_id: felt252 = 1;
    let owning_key_pair = StarkCurveKeyPairImpl::from_secret_key(42);
    state
        .facade
        .create_prediction_account(:client_id, owning_key: owning_key_pair.public_key);
    state
        .facade
        .deposit_to_prediction_account(
            from_position_id: user.position_id,
            :client_id,
            quantized_amount: amount,
            :owning_key_pair,
        );

    state
        .facade
        .validate_collateral_balance(position_id: user.position_id, expected_balance: 0_i64.into());
    state.facade.validate_prediction_collateral(:client_id, expected_collateral: amount);

    // Withdraw full amount back.
    state
        .facade
        .withdraw_from_prediction_account(
            to_position_id: user.position_id,
            :client_id,
            quantized_amount: amount,
            :owning_key_pair,
        );

    state
        .facade
        .validate_collateral_balance(
            position_id: user.position_id, expected_balance: amount.into(),
        );
    state.facade.validate_prediction_collateral(:client_id, expected_collateral: 0);
}

#[test]
#[should_panic(expected: "INSUFFICIENT_PREDICTION_COLLATERAL")]
fn test_prediction_withdraw_insufficient_collateral() {
    // Setup.
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let user = state.new_user_with_position();

    let deposit_info = state
        .facade
        .deposit(
            depositor: user.account, position_id: user.position_id, quantized_amount: 100_000,
        );
    state.facade.process_deposit(deposit_info: deposit_info);

    let client_id: felt252 = 1;
    let owning_key_pair = StarkCurveKeyPairImpl::from_secret_key(42);
    state
        .facade
        .create_prediction_account(:client_id, owning_key: owning_key_pair.public_key);

    // Deposit 10,000.
    state
        .facade
        .deposit_to_prediction_account(
            from_position_id: user.position_id,
            :client_id,
            quantized_amount: 10_000,
            :owning_key_pair,
        );
    state.facade.validate_prediction_collateral(:client_id, expected_collateral: 10_000);

    // Try to withdraw 20,000 — should panic.
    state
        .facade
        .withdraw_from_prediction_account(
            to_position_id: user.position_id,
            :client_id,
            quantized_amount: 20_000,
            :owning_key_pair,
        );
}

#[test]
#[should_panic(expected: "ACCOUNT_ALREADY_EXISTS")]
fn test_prediction_create_duplicate_account() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    let client_id: felt252 = 1;
    let owning_key_pair = StarkCurveKeyPairImpl::from_secret_key(42);
    state
        .facade
        .create_prediction_account(:client_id, owning_key: owning_key_pair.public_key);

    // Create again with same client_id — should panic.
    let other_key_pair = StarkCurveKeyPairImpl::from_secret_key(99);
    state
        .facade
        .create_prediction_account(:client_id, owning_key: other_key_pair.public_key);
}

#[test]
#[should_panic(expected: "INVALID_ZERO_OWNING_KEY")]
fn test_prediction_create_account_zero_owning_key() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    state.facade.create_prediction_account(client_id: 1, owning_key: 0);
}
