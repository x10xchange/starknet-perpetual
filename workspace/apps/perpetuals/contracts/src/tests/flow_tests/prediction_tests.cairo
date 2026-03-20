use perpetuals::predictions::prediction_positions::{
    IPredictionPositionsDispatcher, IPredictionPositionsDispatcherTrait,
};
use perpetuals::predictions::types::{PRICE_SCALE, PredictionOrder};
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
        .deposit(depositor: user.account, position_id: user.position_id, quantized_amount: 100_000);
    state.facade.process_deposit(deposit_info: deposit_info);

    // Create prediction account with a real key pair.
    let client_id: felt252 = 1;
    let owning_key_pair = StarkCurveKeyPairImpl::from_secret_key(42);
    state.facade.create_prediction_account(:client_id, owning_key: owning_key_pair.public_key);
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
        .deposit(depositor: user.account, position_id: user.position_id, quantized_amount: amount);
    state.facade.process_deposit(deposit_info: deposit_info);

    // Create prediction account and deposit full amount.
    let client_id: felt252 = 1;
    let owning_key_pair = StarkCurveKeyPairImpl::from_secret_key(42);
    state.facade.create_prediction_account(:client_id, owning_key: owning_key_pair.public_key);
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
        .deposit(depositor: user.account, position_id: user.position_id, quantized_amount: 100_000);
    state.facade.process_deposit(deposit_info: deposit_info);

    let client_id: felt252 = 1;
    let owning_key_pair = StarkCurveKeyPairImpl::from_secret_key(42);
    state.facade.create_prediction_account(:client_id, owning_key: owning_key_pair.public_key);

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
    state.facade.create_prediction_account(:client_id, owning_key: owning_key_pair.public_key);

    // Create again with same client_id — should panic.
    let other_key_pair = StarkCurveKeyPairImpl::from_secret_key(99);
    state.facade.create_prediction_account(:client_id, owning_key: other_key_pair.public_key);
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
        .deposit(depositor: user.account, position_id: user.position_id, quantized_amount: 100_000);
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
        .create_prediction_market(
            :market_id, oracle: oracle_key_pair.public_key, outcomes: outcomes.span(),
        );
    state.facade.finalize_prediction_market(:market_id, outcome: 2, :oracle_key_pair);
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
        .create_prediction_market(
            :market_id, oracle: oracle_key_pair.public_key, outcomes: outcomes.span(),
        );
    state
        .facade
        .create_prediction_market(
            :market_id, oracle: oracle_key_pair.public_key, outcomes: outcomes.span(),
        );
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
        .create_prediction_market(
            :market_id, oracle: oracle_key_pair.public_key, outcomes: outcomes.span(),
        );
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
        .create_prediction_market(
            :market_id, oracle: oracle_key_pair.public_key, outcomes: outcomes.span(),
        );
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
        .create_prediction_market(
            :market_id, oracle: oracle_key_pair.public_key, outcomes: outcomes.span(),
        );
    // Sign with wrong key — should panic.
    state
        .facade
        .finalize_prediction_market(:market_id, outcome: 1, oracle_key_pair: wrong_key_pair);
}

#[test]
fn test_prediction_trade_skeleton() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let user_a = state.new_user_with_position();
    let user_b = state.new_user_with_position();

    // Fund perps positions.
    let deposit_a = state
        .facade
        .deposit(
            depositor: user_a.account,
            position_id: user_a.position_id,
            quantized_amount: 100_000_000,
        );
    state.facade.process_deposit(deposit_info: deposit_a);
    let deposit_b = state
        .facade
        .deposit(
            depositor: user_b.account,
            position_id: user_b.position_id,
            quantized_amount: 100_000_000,
        );
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
            quantized_amount: 50_000_000,
            signing_key_pair: user_a.account.key_pair,
        );
    state
        .facade
        .deposit_to_prediction_account(
            from_position_id: user_b.position_id,
            client_id: client_b,
            quantized_amount: 50_000_000,
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
    // Price 600_000 = 0.6 (60% probability) with PRICE_SCALE = 1_000_000.
    let expiration = Time::now().add(delta: Time::days(1));
    let order_a = PredictionOrder {
        client_id: client_a,
        market_id,
        outcome: 1,
        amount: 10,
        price: 600_000,
        fee_amount: 100,
        expiration,
        salt: 1,
    };
    let order_b = PredictionOrder {
        client_id: client_b,
        market_id,
        outcome: 1,
        amount: -10,
        price: 600_000,
        fee_amount: 100,
        expiration,
        salt: 2,
    };

    // Execute the trade.
    state
        .facade
        .prediction_trade(
            :order_a,
            :order_b,
            actual_amount: 10,
            actual_price: 600_000,
            actual_fee_a: 50,
            actual_fee_b: 50,
            signing_key_pair_a: key_pair_a,
            signing_key_pair_b: key_pair_b,
        );

    // Verify token balances.
    // Buyer A: 10 shares of outcome 1, 0 of outcome 2.
    let pos = IPredictionPositionsDispatcher { contract_address: state.facade.perpetuals_contract };
    assert_eq!(pos.get_prediction_position(client_id: client_a, :market_id, outcome_id: 1), 10);
    assert_eq!(pos.get_prediction_position(client_id: client_a, :market_id, outcome_id: 2), 0);

    // Seller B: 0 of outcome 1, 10 of outcome 2.
    assert_eq!(pos.get_prediction_position(client_id: client_b, :market_id, outcome_id: 1), 0);
    assert_eq!(pos.get_prediction_position(client_id: client_b, :market_id, outcome_id: 2), 10);

    // Verify collateral: buyer paid 10*600_000 + 50, seller paid 10*400_000 + 50.
    assert_eq!(pos.get_prediction_collateral(client_id: client_a), 50_000_000 - 6_000_050);
    assert_eq!(pos.get_prediction_collateral(client_id: client_b), 50_000_000 - 4_000_050);
}

// ============================================================
// Binary market: trade, resolution, and claim
// ============================================================
#[test]
fn test_binary_market_trade_and_claim() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let user_a = state.new_user_with_position();
    let user_b = state.new_user_with_position();

    let collateral: u64 = 50_000_000;

    // Fund and create prediction accounts.
    let deposit_a = state
        .facade
        .deposit(
            depositor: user_a.account,
            position_id: user_a.position_id,
            quantized_amount: collateral * 2,
        );
    state.facade.process_deposit(deposit_info: deposit_a);
    let deposit_b = state
        .facade
        .deposit(
            depositor: user_b.account,
            position_id: user_b.position_id,
            quantized_amount: collateral * 2,
        );
    state.facade.process_deposit(deposit_info: deposit_b);

    let client_a: felt252 = 1;
    let client_b: felt252 = 2;
    let key_pair_a = StarkCurveKeyPairImpl::from_secret_key(42);
    let key_pair_b = StarkCurveKeyPairImpl::from_secret_key(43);
    state.facade.create_prediction_account(client_id: client_a, owning_key: key_pair_a.public_key);
    state.facade.create_prediction_account(client_id: client_b, owning_key: key_pair_b.public_key);
    state
        .facade
        .deposit_to_prediction_account(
            from_position_id: user_a.position_id,
            client_id: client_a,
            quantized_amount: collateral,
            signing_key_pair: user_a.account.key_pair,
        );
    state
        .facade
        .deposit_to_prediction_account(
            from_position_id: user_b.position_id,
            client_id: client_b,
            quantized_amount: collateral,
            signing_key_pair: user_b.account.key_pair,
        );

    // Binary market: outcomes YES=1, NO=2.
    let market_id: felt252 = 100;
    let oracle_key_pair = StarkCurveKeyPairImpl::from_secret_key(777);
    state
        .facade
        .create_prediction_market(
            :market_id, oracle: oracle_key_pair.public_key, outcomes: array![1, 2].span(),
        );

    let pos = IPredictionPositionsDispatcher { contract_address: state.facade.perpetuals_contract };

    // Trade: A buys 10 YES at price 600_000 (0.6), B sells 10 YES.
    let expiration = Time::now().add(delta: Time::days(1));
    let price: u64 = 600_000; // 0.6
    let amount: u64 = 10;
    let order_a = PredictionOrder {
        client_id: client_a,
        market_id,
        outcome: 1,
        amount: 10,
        price,
        fee_amount: 0,
        expiration,
        salt: 1,
    };
    let order_b = PredictionOrder {
        client_id: client_b,
        market_id,
        outcome: 1,
        amount: -10,
        price,
        fee_amount: 0,
        expiration,
        salt: 2,
    };
    state
        .facade
        .prediction_trade(
            :order_a,
            :order_b,
            actual_amount: amount,
            actual_price: price,
            actual_fee_a: 0,
            actual_fee_b: 0,
            signing_key_pair_a: key_pair_a,
            signing_key_pair_b: key_pair_b,
        );

    // A has 10 YES, B has 10 NO.
    assert_eq!(pos.get_prediction_position(client_id: client_a, :market_id, outcome_id: 1), 10);
    assert_eq!(pos.get_prediction_position(client_id: client_a, :market_id, outcome_id: 2), 0);
    assert_eq!(pos.get_prediction_position(client_id: client_b, :market_id, outcome_id: 1), 0);
    assert_eq!(pos.get_prediction_position(client_id: client_b, :market_id, outcome_id: 2), 10);

    // A paid 10 * 600_000 = 6_000_000. B paid 10 * 400_000 = 4_000_000.
    let a_collateral_after_trade = collateral - amount * price;
    let b_collateral_after_trade = collateral - amount * (PRICE_SCALE - price);
    assert_eq!(pos.get_prediction_collateral(client_id: client_a), a_collateral_after_trade);
    assert_eq!(pos.get_prediction_collateral(client_id: client_b), b_collateral_after_trade);

    // Finalize: YES (outcome 1) wins.
    state.facade.finalize_prediction_market(:market_id, outcome: 1, :oracle_key_pair);

    // A claims winning shares.
    state.facade.claim(client_id: client_a, :market_id);
    // A gets 10 * PRICE_SCALE = 10_000_000 from pot.
    assert_eq!(
        pos.get_prediction_collateral(client_id: client_a),
        a_collateral_after_trade + amount * PRICE_SCALE,
    );
    // A's YES shares are zeroed.
    assert_eq!(pos.get_prediction_position(client_id: client_a, :market_id, outcome_id: 1), 0);

    // A's net P&L: paid 6_000_000, received 10_000_000 → profit 4_000_000.
    assert_eq!(pos.get_prediction_collateral(client_id: client_a), collateral + 4_000_000);

    // B holds losing NO shares — no claim possible. Collateral unchanged.
    assert_eq!(pos.get_prediction_collateral(client_id: client_b), b_collateral_after_trade);
}

// ============================================================
// Quadruple outcome market: trade, burn, resolution, and claim
// ============================================================
#[test]
fn test_quad_market_trade_and_claim() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let user_a = state.new_user_with_position();
    let user_b = state.new_user_with_position();

    let collateral: u64 = 50_000_000;

    // Fund and create prediction accounts.
    let deposit_a = state
        .facade
        .deposit(
            depositor: user_a.account,
            position_id: user_a.position_id,
            quantized_amount: collateral * 2,
        );
    state.facade.process_deposit(deposit_info: deposit_a);
    let deposit_b = state
        .facade
        .deposit(
            depositor: user_b.account,
            position_id: user_b.position_id,
            quantized_amount: collateral * 2,
        );
    state.facade.process_deposit(deposit_info: deposit_b);

    let client_a: felt252 = 1;
    let client_b: felt252 = 2;
    let key_pair_a = StarkCurveKeyPairImpl::from_secret_key(42);
    let key_pair_b = StarkCurveKeyPairImpl::from_secret_key(43);
    state.facade.create_prediction_account(client_id: client_a, owning_key: key_pair_a.public_key);
    state.facade.create_prediction_account(client_id: client_b, owning_key: key_pair_b.public_key);
    state
        .facade
        .deposit_to_prediction_account(
            from_position_id: user_a.position_id,
            client_id: client_a,
            quantized_amount: collateral,
            signing_key_pair: user_a.account.key_pair,
        );
    state
        .facade
        .deposit_to_prediction_account(
            from_position_id: user_b.position_id,
            client_id: client_b,
            quantized_amount: collateral,
            signing_key_pair: user_b.account.key_pair,
        );

    // 4-outcome market: outcomes 1, 2, 3, 4.
    let market_id: felt252 = 200;
    let oracle_key_pair = StarkCurveKeyPairImpl::from_secret_key(777);
    state
        .facade
        .create_prediction_market(
            :market_id, oracle: oracle_key_pair.public_key, outcomes: array![1, 2, 3, 4].span(),
        );

    let pos = IPredictionPositionsDispatcher { contract_address: state.facade.perpetuals_contract };
    let expiration = Time::now().add(delta: Time::days(1));

    // Trade 1: A buys 5 shares of outcome 1 at price 250_000 (0.25).
    // B sells (shorts) outcome 1 → gets 5 shares each of outcomes 2, 3, 4.
    let price_1: u64 = 250_000;
    let order_a1 = PredictionOrder {
        client_id: client_a,
        market_id,
        outcome: 1,
        amount: 5,
        price: price_1,
        fee_amount: 0,
        expiration,
        salt: 10,
    };
    let order_b1 = PredictionOrder {
        client_id: client_b,
        market_id,
        outcome: 1,
        amount: -5,
        price: price_1,
        fee_amount: 0,
        expiration,
        salt: 11,
    };
    state
        .facade
        .prediction_trade(
            order_a: order_a1,
            order_b: order_b1,
            actual_amount: 5,
            actual_price: price_1,
            actual_fee_a: 0,
            actual_fee_b: 0,
            signing_key_pair_a: key_pair_a,
            signing_key_pair_b: key_pair_b,
        );

    // After trade 1:
    // A: [5, 0, 0, 0], paid 5 * 250_000 = 1_250_000
    // B: [0, 5, 5, 5], paid 5 * 750_000 = 3_750_000
    assert_eq!(pos.get_prediction_position(client_id: client_a, :market_id, outcome_id: 1), 5);
    assert_eq!(pos.get_prediction_position(client_id: client_a, :market_id, outcome_id: 2), 0);
    assert_eq!(pos.get_prediction_position(client_id: client_b, :market_id, outcome_id: 2), 5);
    assert_eq!(pos.get_prediction_position(client_id: client_b, :market_id, outcome_id: 3), 5);
    assert_eq!(pos.get_prediction_position(client_id: client_b, :market_id, outcome_id: 4), 5);
    assert_eq!(pos.get_prediction_collateral(client_id: client_a), collateral - 1_250_000);
    assert_eq!(pos.get_prediction_collateral(client_id: client_b), collateral - 3_750_000);

    // Trade 2: A buys 5 shares of outcome 2 at price 250_000.
    // B sells outcome 2 → gets 5 more of outcomes 1, 3, 4.
    // B will then have [5, 5, 10, 10] → min = 5, burn 5 complete sets.
    let order_a2 = PredictionOrder {
        client_id: client_a,
        market_id,
        outcome: 2,
        amount: 5,
        price: price_1,
        fee_amount: 0,
        expiration,
        salt: 20,
    };
    let order_b2 = PredictionOrder {
        client_id: client_b,
        market_id,
        outcome: 2,
        amount: -5,
        price: price_1,
        fee_amount: 0,
        expiration,
        salt: 21,
    };
    state
        .facade
        .prediction_trade(
            order_a: order_a2,
            order_b: order_b2,
            actual_amount: 5,
            actual_price: price_1,
            actual_fee_a: 0,
            actual_fee_b: 0,
            signing_key_pair_a: key_pair_a,
            signing_key_pair_b: key_pair_b,
        );

    // After trade 2 (before burn):
    // A: [5, 5, 0, 0] → no burn (min = 0)
    // B: [5, 5, 10, 10] → burn 5 complete sets → [0, 0, 5, 5]
    //   B gross for this trade: 5 * 750_000 = 3_750_000
    //   B burn refund: 5 * PRICE_SCALE = 5_000_000
    //   B net: 5_000_000 - 3_750_000 = 1_250_000 gain

    assert_eq!(pos.get_prediction_position(client_id: client_a, :market_id, outcome_id: 1), 5);
    assert_eq!(pos.get_prediction_position(client_id: client_a, :market_id, outcome_id: 2), 5);
    assert_eq!(pos.get_prediction_position(client_id: client_a, :market_id, outcome_id: 3), 0);
    assert_eq!(pos.get_prediction_position(client_id: client_a, :market_id, outcome_id: 4), 0);

    assert_eq!(pos.get_prediction_position(client_id: client_b, :market_id, outcome_id: 1), 0);
    assert_eq!(pos.get_prediction_position(client_id: client_b, :market_id, outcome_id: 2), 0);
    assert_eq!(pos.get_prediction_position(client_id: client_b, :market_id, outcome_id: 3), 5);
    assert_eq!(pos.get_prediction_position(client_id: client_b, :market_id, outcome_id: 4), 5);

    // A collateral: paid 1_250_000 more (no burn).
    assert_eq!(pos.get_prediction_collateral(client_id: client_a), collateral - 2_500_000);
    // B collateral: paid 3_750_000 gross but got 5_000_000 burn refund → net +1_250_000.
    assert_eq!(
        pos.get_prediction_collateral(client_id: client_b),
        collateral - 3_750_000 - 3_750_000 + 5_000_000,
    );

    // Finalize: outcome 3 wins.
    state.facade.finalize_prediction_market(:market_id, outcome: 3, :oracle_key_pair);

    // B claims winning shares (5 shares of outcome 3).
    state.facade.claim(client_id: client_b, :market_id);
    let b_after_claim = collateral - 3_750_000 - 3_750_000 + 5_000_000 + 5 * PRICE_SCALE;
    assert_eq!(pos.get_prediction_collateral(client_id: client_b), b_after_claim);
    assert_eq!(pos.get_prediction_position(client_id: client_b, :market_id, outcome_id: 3), 0);
    // B still holds 5 of outcome 4 (worthless now).
    assert_eq!(pos.get_prediction_position(client_id: client_b, :market_id, outcome_id: 4), 5);

    // A has no winning shares — collateral unchanged.
    assert_eq!(pos.get_prediction_collateral(client_id: client_a), collateral - 2_500_000);

    // B net P&L: started with 50M, now has 50M - 7.5M + 5M + 5M = 52.5M → profit 2.5M.
    assert_eq!(pos.get_prediction_collateral(client_id: client_b), collateral + 2_500_000);
}
