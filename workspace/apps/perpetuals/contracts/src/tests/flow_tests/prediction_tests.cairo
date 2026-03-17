use perpetuals::predictions::types::PredictionOrder;
use perpetuals::tests::flow_tests::infra::*;
use perpetuals::tests::flow_tests::perps_tests_facade::*;
use snforge_std::signature::stark_curve::StarkCurveKeyPairImpl;
use starkware_utils::time::time::Time;

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

    // Deposit from perps position to prediction account (signed by position owner).
    state
        .facade
        .deposit_to_prediction_account(
            from_position_id: user.position_id,
            :client_id,
            quantized_amount: 50_000,
            signing_key_pair: user.account.key_pair,
        );

    // Validate balances after deposit.
    state
        .facade
        .validate_collateral_balance(
            position_id: user.position_id, expected_balance: 50_000_i64.into(),
        );
    state.facade.validate_prediction_collateral(:client_id, expected_collateral: 50_000);

    // Withdraw from prediction account back to perps position (signed by prediction owner).
    state
        .facade
        .withdraw_from_prediction_account(
            to_position_id: user.position_id,
            :client_id,
            quantized_amount: 30_000,
            signing_key_pair: owning_key_pair,
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
            signing_key_pair: user.account.key_pair,
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
            signing_key_pair: owning_key_pair,
        );

    state
        .facade
        .validate_collateral_balance(
            position_id: user.position_id, expected_balance: amount.into(),
        );
    state.facade.validate_prediction_collateral(:client_id, expected_collateral: 0);
}

#[test]
#[should_panic(expected: 'INSUFFICIENT_COLLATERAL')]
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
            signing_key_pair: user.account.key_pair,
        );
    state.facade.validate_prediction_collateral(:client_id, expected_collateral: 10_000);

    // Try to withdraw 20,000 — should panic.
    state
        .facade
        .withdraw_from_prediction_account(
            to_position_id: user.position_id,
            :client_id,
            quantized_amount: 20_000,
            signing_key_pair: owning_key_pair,
        );
}

#[test]
#[should_panic(expected: 'ACCOUNT_ALREADY_EXISTS')]
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
#[should_panic(expected: 'INVALID_ZERO_OWNING_KEY')]
fn test_prediction_create_account_zero_owning_key() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    state.facade.create_prediction_account(client_id: 1, owning_key: 0);
}

#[test]
#[should_panic(expected: 'ACCOUNT_DOES_NOT_EXIST')]
fn test_prediction_deposit_nonexistent_account() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let user = state.new_user_with_position();

    let deposit_info = state
        .facade
        .deposit(
            depositor: user.account, position_id: user.position_id, quantized_amount: 100_000,
        );
    state.facade.process_deposit(deposit_info: deposit_info);

    // Deposit to non-existent prediction account — should panic.
    state
        .facade
        .deposit_to_prediction_account(
            from_position_id: user.position_id,
            client_id: 999,
            quantized_amount: 10_000,
            signing_key_pair: user.account.key_pair,
        );
}

#[test]
#[should_panic(expected: 'ACCOUNT_DOES_NOT_EXIST')]
fn test_prediction_withdraw_nonexistent_account() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let user = state.new_user_with_position();

    let owning_key_pair = StarkCurveKeyPairImpl::from_secret_key(42);
    // Withdraw from non-existent prediction account — should panic.
    state
        .facade
        .withdraw_from_prediction_account(
            to_position_id: user.position_id,
            client_id: 999,
            quantized_amount: 10_000,
            signing_key_pair: owning_key_pair,
        );
}

#[test]
fn test_create_and_finalize_market() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    let market_id: felt252 = 100;
    let oracle_key_pair = StarkCurveKeyPairImpl::from_secret_key(777);
    let outcomes: Array<felt252> = array![1, 2, 3];

    state
        .facade
        .create_prediction_market(:market_id, oracle: oracle_key_pair.public_key, outcomes: outcomes.span());
    state
        .facade
        .finalize_prediction_market(:market_id, outcome: 2, :oracle_key_pair);
}

#[test]
#[should_panic(expected: 'MARKET_ALREADY_EXISTS')]
fn test_create_duplicate_market() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    let market_id: felt252 = 100;
    let oracle_key_pair = StarkCurveKeyPairImpl::from_secret_key(777);
    let outcomes: Array<felt252> = array![1, 2];

    state
        .facade
        .create_prediction_market(:market_id, oracle: oracle_key_pair.public_key, outcomes: outcomes.span());
    state
        .facade
        .create_prediction_market(:market_id, oracle: oracle_key_pair.public_key, outcomes: outcomes.span());
}

#[test]
#[should_panic(expected: 'MARKET_NOT_FOUND')]
fn test_finalize_nonexistent_market() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    let oracle_key_pair = StarkCurveKeyPairImpl::from_secret_key(777);
    state.facade.finalize_prediction_market(market_id: 999, outcome: 1, :oracle_key_pair);
}

#[test]
#[should_panic(expected: 'MARKET_ALREADY_FINALIZED')]
fn test_finalize_market_twice() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    let market_id: felt252 = 100;
    let oracle_key_pair = StarkCurveKeyPairImpl::from_secret_key(777);
    let outcomes: Array<felt252> = array![1, 2];

    state
        .facade
        .create_prediction_market(:market_id, oracle: oracle_key_pair.public_key, outcomes: outcomes.span());
    state.facade.finalize_prediction_market(:market_id, outcome: 1, :oracle_key_pair);
    state.facade.finalize_prediction_market(:market_id, outcome: 2, :oracle_key_pair);
}

#[test]
#[should_panic(expected: 'INVALID_OUTCOME')]
fn test_finalize_market_invalid_winner() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    let market_id: felt252 = 100;
    let oracle_key_pair = StarkCurveKeyPairImpl::from_secret_key(777);
    let outcomes: Array<felt252> = array![1, 2];

    state
        .facade
        .create_prediction_market(:market_id, oracle: oracle_key_pair.public_key, outcomes: outcomes.span());
    state.facade.finalize_prediction_market(:market_id, outcome: 99, :oracle_key_pair);
}

#[test]
#[should_panic(expected: 'INVALID_STARK_KEY_SIGNATURE')]
fn test_finalize_market_wrong_oracle_key() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    let market_id: felt252 = 100;
    let oracle_key_pair = StarkCurveKeyPairImpl::from_secret_key(777);
    let wrong_key_pair = StarkCurveKeyPairImpl::from_secret_key(888);
    let outcomes: Array<felt252> = array![1, 2];

    state
        .facade
        .create_prediction_market(:market_id, oracle: oracle_key_pair.public_key, outcomes: outcomes.span());
    // Sign with wrong key — should panic.
    state.facade.finalize_prediction_market(:market_id, outcome: 1, oracle_key_pair: wrong_key_pair);
}

#[test]
fn test_prediction_trade_skeleton() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let user_a = state.new_user_with_position();
    let user_b = state.new_user_with_position();

    // Fund perps positions.
    let deposit_a = state
        .facade
        .deposit(depositor: user_a.account, position_id: user_a.position_id, quantized_amount: 100_000);
    state.facade.process_deposit(deposit_info: deposit_a);
    let deposit_b = state
        .facade
        .deposit(depositor: user_b.account, position_id: user_b.position_id, quantized_amount: 100_000);
    state.facade.process_deposit(deposit_info: deposit_b);

    // Create prediction accounts.
    let client_a: felt252 = 1;
    let client_b: felt252 = 2;
    let key_pair_a = StarkCurveKeyPairImpl::from_secret_key(42);
    let key_pair_b = StarkCurveKeyPairImpl::from_secret_key(43);
    state.facade.create_prediction_account(client_id: client_a, owning_key: key_pair_a.public_key);
    state.facade.create_prediction_account(client_id: client_b, owning_key: key_pair_b.public_key);

    // Deposit collateral to prediction accounts.
    state
        .facade
        .deposit_to_prediction_account(
            from_position_id: user_a.position_id,
            client_id: client_a,
            quantized_amount: 50_000,
            signing_key_pair: user_a.account.key_pair,
        );
    state
        .facade
        .deposit_to_prediction_account(
            from_position_id: user_b.position_id,
            client_id: client_b,
            quantized_amount: 50_000,
            signing_key_pair: user_b.account.key_pair,
        );

    // Create a market.
    let market_id: felt252 = 100;
    let oracle_key_pair = StarkCurveKeyPairImpl::from_secret_key(777);
    state
        .facade
        .create_prediction_market(
            :market_id, oracle: oracle_key_pair.public_key, outcomes: array![1, 2].span(),
        );

    // Build orders: A buys 10 shares of outcome 1, B sells 10 shares of outcome 1.
    let expiration = Time::now().add(delta: Time::days(1));
    let order_a = PredictionOrder {
        client_id: client_a,
        market_id,
        outcome: 1,
        is_long: true,
        amount: 10,
        price: 600, // willing to pay 600 per share
        fee_amount: 100,
        expiration,
        salt: 1,
    };
    let order_b = PredictionOrder {
        client_id: client_b,
        market_id,
        outcome: 1,
        is_long: false,
        amount: -10,
        price: 600,
        fee_amount: 100,
        expiration,
        salt: 2,
    };

    // Execute the trade (skeleton — only validates sigs and tracks fulfillment).
    state
        .facade
        .prediction_trade(
            :order_a,
            :order_b,
            actual_amount: 10,
            actual_fee_a: 50,
            actual_fee_b: 50,
            signing_key_pair_a: key_pair_a,
            signing_key_pair_b: key_pair_b,
        );
}
