use core::num::traits::{Pow, Zero};
use perpetuals::core::components::positions::Positions::{FEE_POSITION, INSURANCE_FUND_POSITION};
use perpetuals::core::types::funding::{FUNDING_SCALE, FundingIndex, FundingTick};
use perpetuals::tests::constants::*;
use perpetuals::tests::flow_tests::infra::*;
use perpetuals::tests::flow_tests::perps_tests_facade::*;
use snforge_std::TokenTrait;
use starknet::storage::{StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess};
use starkware_utils::constants::{HOUR, MAX_U128, WEEK};
use starkware_utils::time::time::Timestamp;
use starkware_utils_testing::test_utils::TokenTrait as StarknetTokenTrait;
use super::perps_tests_facade::PerpsTestsFacadeTrait;

#[test]
fn test_deleverage_after_funding_tick() {
    // Setup.
    let risk_factor_data = RiskFactorTiers {
        tiers: array![10].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    // Create a custom asset configuration to test interesting risk factor scenarios.
    let synthetic_info = AssetInfoTrait::new(
        asset_name: 'BTC_1', :risk_factor_data, oracles_len: 1,
    );
    let asset_id = synthetic_info.asset_id;

    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    state.facade.add_active_synthetic(synthetic_info: @synthetic_info, initial_price: 100);

    // Create users.
    let deleveraged_user = state.new_user_with_position();
    let deleverager_user_1 = state.new_user_with_position();
    let deleverager_user_2 = state.new_user_with_position();

    // Deposit to users.
    let deposit_info_user_1 = state
        .facade
        .deposit(
            depositor: deleverager_user_1.account,
            position_id: deleverager_user_1.position_id,
            quantized_amount: 100000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_user_1);

    let deposit_info_user_2 = state
        .facade
        .deposit(
            depositor: deleverager_user_2.account,
            position_id: deleverager_user_2.position_id,
            quantized_amount: 100000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_user_2);

    // Create orders.
    // User willing to buy 2 synthetic assets for 168 (quote) + 20 (fee).
    let order_deleveraged_user = state
        .facade
        .create_order(
            user: deleveraged_user,
            base_amount: 2,
            base_asset_id: asset_id,
            quote_amount: -168,
            fee_amount: 20,
        );

    let order_deleverager_user_1 = state
        .facade
        .create_order(
            user: deleverager_user_1,
            base_amount: -1,
            base_asset_id: asset_id,
            quote_amount: 50,
            fee_amount: 2,
        );

    let order_deleverager_user_2 = state
        .facade
        .create_order(
            user: deleverager_user_2,
            base_amount: -1,
            base_asset_id: asset_id,
            quote_amount: 84,
            fee_amount: 2,
        );

    // Make trades.
    // User recieves 1 synthetic asset for 84 (quote) + 10 (fee).
    state
        .facade
        .trade(
            order_info_a: order_deleveraged_user,
            order_info_b: order_deleverager_user_1,
            base: 1,
            quote: -84,
            fee_a: 10,
            fee_b: 3,
        );

    // User recieves 1 synthetic asset for 84 (quote) + 10 (fee).
    state
        .facade
        .trade(
            order_info_a: order_deleveraged_user,
            order_info_b: order_deleverager_user_2,
            base: 1,
            quote: -84,
            fee_a: 10,
            fee_b: 1,
        );

    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // deleveraged User:   -188 + 2 * 100 = 12                 2 * 100 * 0.01 = 2           6
    state
        .facade
        .validate_total_value(position_id: deleveraged_user.position_id, expected_total_value: 12);
    state
        .facade
        .validate_total_risk(position_id: deleveraged_user.position_id, expected_total_risk: 2);

    state.facade.advance_time(10000);
    let mut new_funding_index = FundingIndex { value: 7 * FUNDING_SCALE };
    state
        .facade
        .funding_tick(
            funding_ticks: array![
                FundingTick { asset_id: asset_id, funding_index: new_funding_index },
            ]
                .span(),
        );

    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // deleveraged User:   -202 + 2 * 100 = -2                 2 * 100 * 0.01 = 2          - 1
    state
        .facade
        .validate_total_value(position_id: deleveraged_user.position_id, expected_total_value: -2);
    state
        .facade
        .validate_total_risk(position_id: deleveraged_user.position_id, expected_total_risk: 2);

    assert(
        state.facade.is_deleveragable(position_id: deleveraged_user.position_id),
        'user is not deleveragable',
    );

    state
        .facade
        .deleverage(
            deleveraged_user: deleveraged_user,
            deleverager_user: deleverager_user_1,
            base_asset_id: asset_id,
            deleveraged_base: -1,
            deleveraged_quote: 101,
        );

    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // deleveraged User:   -101 + 1 * 100 = -1                 1 * 100 * 0.01 = 1          - 1
    state
        .facade
        .validate_total_value(position_id: deleveraged_user.position_id, expected_total_value: -1);
    state
        .facade
        .validate_total_risk(position_id: deleveraged_user.position_id, expected_total_risk: 1);

    state
        .facade
        .deleverage(
            deleveraged_user: deleveraged_user,
            deleverager_user: deleverager_user_2,
            base_asset_id: asset_id,
            deleveraged_base: -1,
            deleveraged_quote: 101,
        );

    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // deleveraged User:     0 + 0 * 100 = 0                  0 * 100 * 0.01 = 0            -
    state
        .facade
        .validate_total_value(position_id: deleveraged_user.position_id, expected_total_value: 0);
    state
        .facade
        .validate_total_risk(position_id: deleveraged_user.position_id, expected_total_risk: 0);
}

#[test]
fn test_deleverage_after_price_tick() {
    // Setup.
    let risk_factor_data = RiskFactorTiers {
        tiers: array![100].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    // Create a custom asset configuration to test interesting risk factor scenarios.
    let synthetic_info = AssetInfoTrait::new(
        asset_name: 'BTC_1', :risk_factor_data, oracles_len: 1,
    );
    let asset_id = synthetic_info.asset_id;

    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    state.facade.add_active_synthetic(synthetic_info: @synthetic_info, initial_price: 20);

    // Create users.
    let deleveraged_user = state.new_user_with_position();
    let deleverager_user = state.new_user_with_position();

    // Deposit to users.
    let deposit_info_user = state
        .facade
        .deposit(
            depositor: deleverager_user.account,
            position_id: deleverager_user.position_id,
            quantized_amount: 100000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_user);

    // Create orders.
    // User willing to buy 2 synthetic assets for 33 (quote) + 3 (fee).
    let order_deleveraged_user = state
        .facade
        .create_order(
            user: deleveraged_user,
            base_amount: 2,
            base_asset_id: asset_id,
            quote_amount: -33,
            fee_amount: 3,
        );
    let order_deleverager_user = state
        .facade
        .create_order(
            user: deleverager_user,
            base_amount: -2,
            base_asset_id: asset_id,
            quote_amount: 30,
            fee_amount: 4,
        );

    // Make trades.
    // User recieves 2 synthetic asset for 3 (quote) + 3 (fee).
    state
        .facade
        .trade(
            order_info_a: order_deleveraged_user,
            order_info_b: order_deleverager_user,
            base: 2,
            quote: -33,
            fee_a: 3,
            fee_b: 4,
        );

    //                            TV                                  TR                    TV/TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // deleveraged User:   -36 + 2 * 20 = 4                    2 * 20 * 0.1 = 4               1
    state
        .facade
        .validate_total_value(position_id: deleveraged_user.position_id, expected_total_value: 4);
    state
        .facade
        .validate_total_risk(position_id: deleveraged_user.position_id, expected_total_risk: 4);

    state.facade.price_tick(asset_info: @synthetic_info, price: 10);

    //                            TV                                  TR                    TV/TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // deleveraged User:   -36 + 2 * 10 = -16                  2 * 10 * 0.1 = 2               -8
    state
        .facade
        .validate_total_value(position_id: deleveraged_user.position_id, expected_total_value: -16);
    state
        .facade
        .validate_total_risk(position_id: deleveraged_user.position_id, expected_total_risk: 2);

    assert(
        state.facade.is_deleveragable(position_id: deleveraged_user.position_id),
        'user is not deleveragable',
    );

    state
        .facade
        .deleverage(
            deleveraged_user: deleveraged_user,
            deleverager_user: deleverager_user,
            base_asset_id: asset_id,
            deleveraged_base: -1,
            deleveraged_quote: 18,
        );

    //                            TV                                  TR                    TV/TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // deleveraged User:    -18 + 1 * 10 = -8                 1 * 10 * 0.1 = 1               -8
    state
        .facade
        .validate_total_value(position_id: deleveraged_user.position_id, expected_total_value: -8);
    state
        .facade
        .validate_total_risk(position_id: deleveraged_user.position_id, expected_total_risk: 1);

    state
        .facade
        .deleverage(
            deleveraged_user: deleveraged_user,
            deleverager_user: deleverager_user,
            base_asset_id: asset_id,
            deleveraged_base: -1,
            deleveraged_quote: 18,
        );
    //                            TV                                  TR                    TV/TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // deleveraged User:     0 + 0 * 10 = 0                     0 * 10 * 0.1 = 0              0
    state
        .facade
        .validate_total_value(position_id: deleveraged_user.position_id, expected_total_value: 0);
    state
        .facade
        .validate_total_risk(position_id: deleveraged_user.position_id, expected_total_risk: 0);
}

#[test]
fn test_deleverage_by_recieving_asset() {
    // Setup.
    let risk_factor_data = RiskFactorTiers {
        tiers: array![10].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let synthetic_info = AssetInfoTrait::new(
        asset_name: 'BTC_1', :risk_factor_data, oracles_len: 1,
    );
    let asset_id = synthetic_info.asset_id;

    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    state.facade.add_active_synthetic(synthetic_info: @synthetic_info, initial_price: 100);

    // Create users.
    let deleveraged_user = state.new_user_with_position();
    let deleverager_user = state.new_user_with_position();

    // Deposit to users.
    let deposit_info_user_1 = state
        .facade
        .deposit(
            depositor: deleverager_user.account,
            position_id: deleverager_user.position_id,
            quantized_amount: 100000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_user_1);

    // Create orders.
    let order_deleveraged_user = state
        .facade
        .create_order(
            user: deleveraged_user,
            base_amount: -2,
            base_asset_id: asset_id,
            quote_amount: 210,
            fee_amount: 0,
        );

    let order_deleverager_user = state
        .facade
        .create_order(
            user: deleverager_user,
            base_amount: 2,
            base_asset_id: asset_id,
            quote_amount: -210,
            fee_amount: 0,
        );

    // Make trades.
    state
        .facade
        .trade(
            order_info_a: order_deleveraged_user,
            order_info_b: order_deleverager_user,
            base: -2,
            quote: 210,
            fee_a: 0,
            fee_b: 0,
        );

    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // deleveraged User:    210 - 2 * 100 = 10                 2 * 100 * 0.01 = 2           5
    state
        .facade
        .validate_total_value(position_id: deleveraged_user.position_id, expected_total_value: 10);
    state
        .facade
        .validate_total_risk(position_id: deleveraged_user.position_id, expected_total_risk: 2);

    state.facade.advance_time(10000);
    let mut new_funding_index = FundingIndex { value: -6 * FUNDING_SCALE };
    state
        .facade
        .funding_tick(
            funding_ticks: array![
                FundingTick { asset_id: asset_id, funding_index: new_funding_index },
            ]
                .span(),
        );

    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // deleveraged User:   198 - 2 * 100 = -2                 2 * 100 * 0.01 = 2           - 1
    state
        .facade
        .validate_total_value(position_id: deleveraged_user.position_id, expected_total_value: -2);
    state
        .facade
        .validate_total_risk(position_id: deleveraged_user.position_id, expected_total_risk: 2);

    assert(
        state.facade.is_deleveragable(position_id: deleveraged_user.position_id),
        'user is not deleveragable',
    );

    state
        .facade
        .deleverage(
            deleveraged_user: deleveraged_user,
            deleverager_user: deleverager_user,
            base_asset_id: asset_id,
            deleveraged_base: 1,
            deleveraged_quote: -99,
        );

    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // deleveraged User:     99 - 1 * 100 = -1                1 * 100 * 0.01 = 1           - 1
    state
        .facade
        .validate_total_value(position_id: deleveraged_user.position_id, expected_total_value: -1);
    state
        .facade
        .validate_total_risk(position_id: deleveraged_user.position_id, expected_total_risk: 1);

    assert(
        state.facade.is_deleveragable(position_id: deleveraged_user.position_id),
        'user is not deleveragable',
    );

    state
        .facade
        .deleverage(
            deleveraged_user: deleveraged_user,
            deleverager_user: deleverager_user,
            base_asset_id: asset_id,
            deleveraged_base: 1,
            deleveraged_quote: -99,
        );

    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // deleveraged User:     0 + 0 * 100 = 0                0 * 100 * 0.01 = 0              -
    state
        .facade
        .validate_total_value(position_id: deleveraged_user.position_id, expected_total_value: 0);
    state
        .facade
        .validate_total_risk(position_id: deleveraged_user.position_id, expected_total_risk: 0);
}

#[test]
fn test_liquidate_after_funding_tick() {
    // Setup.
    let risk_factor_data = RiskFactorTiers {
        tiers: array![10].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    // Create a custom asset configuration to test interesting risk factor scenarios.
    let synthetic_info = AssetInfoTrait::new(
        asset_name: 'BTC_1', :risk_factor_data, oracles_len: 1,
    );
    let asset_id = synthetic_info.asset_id;

    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    state.facade.add_active_synthetic(synthetic_info: @synthetic_info, initial_price: 100);

    // Create users.
    let liquidated_user = state.new_user_with_position();
    let liquidator_user_1 = state.new_user_with_position();
    let liquidator_user_2 = state.new_user_with_position();

    // Deposit to users.
    let deposit_info_user_1 = state
        .facade
        .deposit(
            depositor: liquidator_user_1.account,
            position_id: liquidator_user_1.position_id,
            quantized_amount: 100000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_user_1);

    let deposit_info_user_2 = state
        .facade
        .deposit(
            depositor: liquidator_user_2.account,
            position_id: liquidator_user_2.position_id,
            quantized_amount: 100000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_user_2);

    // Create orders.
    // User willing to buy 3 synthetic assets for 285 (quote) + 20 (fee).
    let order_liquidated_user = state
        .facade
        .create_order(
            user: liquidated_user,
            base_amount: 3,
            base_asset_id: asset_id,
            quote_amount: -285,
            fee_amount: 3,
        );

    let mut order_liquidator_user_1 = state
        .facade
        .create_order(
            user: liquidator_user_1,
            base_amount: -2,
            base_asset_id: asset_id,
            quote_amount: 100,
            fee_amount: 0,
        );

    let mut order_liquidator_user_2 = state
        .facade
        .create_order(
            user: liquidator_user_2,
            base_amount: -1,
            base_asset_id: asset_id,
            quote_amount: 50,
            fee_amount: 0,
        );

    // Make trade.
    // User recieves 2 synthetic asset for 190 (quote) + 2 (fee).
    state
        .facade
        .trade(
            order_info_a: order_liquidated_user,
            order_info_b: order_liquidator_user_1,
            base: 2,
            quote: -190,
            fee_a: 2,
            fee_b: 0,
        );

    // User recieves 1 synthetic asset for 95 (quote) + 0 (fee).
    state
        .facade
        .trade(
            order_info_a: order_liquidated_user,
            order_info_b: order_liquidator_user_2,
            base: 1,
            quote: -95,
            fee_a: 0,
            fee_b: 0,
        );

    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // liquidated User:    -287 + 3 * 100 = 13                3 * 100 * 0.01 = 3           4.3
    state
        .facade
        .validate_total_value(position_id: liquidated_user.position_id, expected_total_value: 13);
    state
        .facade
        .validate_total_risk(position_id: liquidated_user.position_id, expected_total_risk: 3);

    state.facade.advance_time(10000);
    let mut new_funding_index = FundingIndex { value: 4 * FUNDING_SCALE };
    state
        .facade
        .funding_tick(
            funding_ticks: array![
                FundingTick { asset_id: asset_id, funding_index: new_funding_index },
            ]
                .span(),
        );

    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // liquidated User:    -299 + 3 * 100 = 1                 3 * 100 * 0.01 = 3           0.3
    state
        .facade
        .validate_total_value(position_id: liquidated_user.position_id, expected_total_value: 1);
    state
        .facade
        .validate_total_risk(position_id: liquidated_user.position_id, expected_total_risk: 3);

    assert(
        state.facade.is_liquidatable(position_id: liquidated_user.position_id),
        'user is not liquidatable',
    );

    order_liquidator_user_1 = state
        .facade
        .create_order(
            user: liquidator_user_1,
            base_amount: 1,
            base_asset_id: asset_id,
            quote_amount: -101,
            fee_amount: 1,
        );
    state
        .facade
        .liquidate(
            :liquidated_user,
            liquidator_order: order_liquidator_user_1,
            liquidated_base: -1,
            liquidated_quote: 101,
            liquidated_insurance_fee: 1,
            liquidator_fee: 1,
        );

    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // deleveraged User:   -199 + 2 * 10 = 1                  2 * 100 * 0.01 = 2           0.5
    state
        .facade
        .validate_total_value(position_id: liquidated_user.position_id, expected_total_value: 1);
    state
        .facade
        .validate_total_risk(position_id: liquidated_user.position_id, expected_total_risk: 2);

    assert(
        state.facade.is_liquidatable(position_id: liquidated_user.position_id),
        'user is not liquidatable',
    );

    order_liquidator_user_2 = state
        .facade
        .create_order(
            user: liquidator_user_2,
            base_amount: 2,
            base_asset_id: asset_id,
            quote_amount: -201,
            fee_amount: 1,
        );
    state
        .facade
        .liquidate(
            :liquidated_user,
            liquidator_order: order_liquidator_user_2,
            liquidated_base: -2,
            liquidated_quote: 201,
            liquidated_insurance_fee: 2,
            liquidator_fee: 1,
        );

    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // deleveraged User:        0 + 0 = 0                     0 * 100 * 0.01 = 0            0
    state
        .facade
        .validate_total_value(position_id: liquidated_user.position_id, expected_total_value: 0);
    state
        .facade
        .validate_total_risk(position_id: liquidated_user.position_id, expected_total_risk: 0);
}

#[test]
fn test_liquidate_after_price_tick() {
    // Setup.
    let risk_factor_data = RiskFactorTiers {
        tiers: array![100].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    // Create a custom asset configuration to test interesting risk factor scenarios.
    let synthetic_info = AssetInfoTrait::new(
        asset_name: 'BTC_1', :risk_factor_data, oracles_len: 1,
    );
    let asset_id = synthetic_info.asset_id;

    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    state.facade.add_active_synthetic(synthetic_info: @synthetic_info, initial_price: 10);

    // Create users.
    let liquidated_user = state.new_user_with_position();
    let liquidator_user_1 = state.new_user_with_position();
    let liquidator_user_2 = state.new_user_with_position();

    // Deposit to users.
    let deposit_info_user_1 = state
        .facade
        .deposit(
            depositor: liquidator_user_1.account,
            position_id: liquidator_user_1.position_id,
            quantized_amount: 100000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_user_1);

    let deposit_info_user_2 = state
        .facade
        .deposit(
            depositor: liquidator_user_2.account,
            position_id: liquidator_user_2.position_id,
            quantized_amount: 100000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_user_2);

    // Create orders.
    // User willing to sell 3 synthetic assets for 66 (quote) - 6 (fee).
    let order_liquidated_user = state
        .facade
        .create_order(
            user: liquidated_user,
            base_amount: -3,
            base_asset_id: asset_id,
            quote_amount: 66,
            fee_amount: 6,
        );

    let mut order_liquidator_user_1 = state
        .facade
        .create_order(
            user: liquidator_user_1,
            base_amount: 2,
            base_asset_id: asset_id,
            quote_amount: -44,
            fee_amount: 4,
        );

    let mut order_liquidator_user_2 = state
        .facade
        .create_order(
            user: liquidator_user_2,
            base_amount: 1,
            base_asset_id: asset_id,
            quote_amount: -22,
            fee_amount: 2,
        );

    // Make trade.
    // User gives 2 synthetic asset for 44 (quote) - 2 (fee).
    state
        .facade
        .trade(
            order_info_a: order_liquidated_user,
            order_info_b: order_liquidator_user_1,
            base: -2,
            quote: 44,
            fee_a: 2,
            fee_b: 4,
        );

    // User recieves 1 synthetic asset for 22 (quote) - 1 (fee).
    state
        .facade
        .trade(
            order_info_a: order_liquidated_user,
            order_info_b: order_liquidator_user_2,
            base: -1,
            quote: 22,
            fee_a: 1,
            fee_b: 1,
        );

    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // liquidated User:     63 - 3 * 10 = 33                 |-3 * 10 * 0.1| = 3           12
    state
        .facade
        .validate_total_value(position_id: liquidated_user.position_id, expected_total_value: 33);
    state
        .facade
        .validate_total_risk(position_id: liquidated_user.position_id, expected_total_risk: 3);

    state.facade.price_tick(asset_info: @synthetic_info, price: 20);

    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // liquidated User:     63 - 3 * 20 = 3                  |-3 * 20 * 0.1| = 6            0.5
    state
        .facade
        .validate_total_value(position_id: liquidated_user.position_id, expected_total_value: 3);
    state
        .facade
        .validate_total_risk(position_id: liquidated_user.position_id, expected_total_risk: 6);

    assert(
        state.facade.is_liquidatable(position_id: liquidated_user.position_id),
        'user is not liquidatable',
    );

    order_liquidator_user_1 = state
        .facade
        .create_order(
            user: liquidator_user_1,
            base_amount: -4,
            base_asset_id: asset_id,
            quote_amount: 82,
            fee_amount: 2,
        );
    state
        .facade
        .liquidate(
            :liquidated_user,
            liquidator_order: order_liquidator_user_1,
            liquidated_base: 2,
            liquidated_quote: -41,
            liquidated_insurance_fee: 1,
            liquidator_fee: 1,
        );

    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // liquidated User:      21 - 1 * 20 = 1                  |-1 * 20 * 0.1| = 2          0.5
    state
        .facade
        .validate_total_value(position_id: liquidated_user.position_id, expected_total_value: 1);
    state
        .facade
        .validate_total_risk(position_id: liquidated_user.position_id, expected_total_risk: 2);

    assert(
        state.facade.is_liquidatable(position_id: liquidated_user.position_id),
        'user is not liquidatable',
    );

    order_liquidator_user_2 = state
        .facade
        .create_order(
            user: liquidator_user_2,
            base_amount: -1,
            base_asset_id: asset_id,
            quote_amount: 20,
            fee_amount: 1,
        );
    state
        .facade
        .liquidate(
            :liquidated_user,
            liquidator_order: order_liquidator_user_2,
            liquidated_base: 1,
            liquidated_quote: -20,
            liquidated_insurance_fee: 0,
            liquidator_fee: 1,
        );

    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // Delevereged User:        1 + 0 = 1                     0 * 100 * 0.01 = 0            -
    state
        .facade
        .validate_total_value(position_id: liquidated_user.position_id, expected_total_value: 1);
    state
        .facade
        .validate_total_risk(position_id: liquidated_user.position_id, expected_total_risk: 0);
}

#[test]
fn test_flow_get_risk_factor() {
    // Setup.
    let risk_factor_data = RiskFactorTiers {
        tiers: array![10, 500, 1000].span(), first_tier_boundary: 2001, tier_size: 1000,
    };
    // Create a custom asset configuration to test interesting risk factor scenarios.
    let synthetic_info = AssetInfoTrait::new(asset_name: 'BTC', :risk_factor_data, oracles_len: 1);
    let asset_id = synthetic_info.asset_id;

    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    state.facade.add_active_synthetic(synthetic_info: @synthetic_info, initial_price: 1000);

    // Create users.
    let user_1 = state.new_user_with_position();
    let user_2 = state.new_user_with_position();

    let deposit_info_user_1 = state
        .facade
        .deposit(
            depositor: user_1.account, position_id: user_1.position_id, quantized_amount: 10000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_user_1);

    let deposit_info_user_2 = state
        .facade
        .deposit(
            depositor: user_2.account, position_id: user_2.position_id, quantized_amount: 10000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_user_2);

    // Create orders.
    let order_user_1 = state
        .facade
        .create_order(
            user: user_1,
            base_amount: 10,
            base_asset_id: asset_id,
            quote_amount: -10000,
            fee_amount: 0,
        );
    let order_user_2 = state
        .facade
        .create_order(
            user: user_2,
            base_amount: -20,
            base_asset_id: asset_id,
            quote_amount: 20000,
            fee_amount: 0,
        );

    // Test:
    // No synthetic assets.
    state.facade.validate_total_risk(position_id: user_1.position_id, expected_total_risk: 0);

    // Partial fulfillment.
    state
        .facade
        .trade(
            order_info_a: order_user_1,
            order_info_b: order_user_2,
            base: 2,
            quote: -2000,
            fee_a: 0,
            fee_b: 0,
        );

    // 2000 * 1%.
    state.facade.validate_total_risk(position_id: user_1.position_id, expected_total_risk: 20);

    // Partial fulfillment.
    state
        .facade
        .trade(
            order_info_a: order_user_1,
            order_info_b: order_user_2,
            base: 1,
            quote: -1000,
            fee_a: 0,
            fee_b: 0,
        );

    // index = (3000 - 2001)/1000 = 1;
    // 3000 * 50%.
    state.facade.validate_total_risk(position_id: user_1.position_id, expected_total_risk: 1500);

    // Partial fulfillment.
    state
        .facade
        .trade(
            order_info_a: order_user_1,
            order_info_b: order_user_2,
            base: 1,
            quote: -1000,
            fee_a: 0,
            fee_b: 0,
        );

    // index = (4000 - 2001)/1000 = 2;
    // 4000 * 100%.
    state.facade.validate_total_risk(position_id: user_1.position_id, expected_total_risk: 4000);

    // Partial fulfillment.
    state
        .facade
        .trade(
            order_info_a: order_user_1,
            order_info_b: order_user_2,
            base: 5,
            quote: -5000,
            fee_a: 0,
            fee_b: 0,
        );
    // index = (9000 - 2001)/1000 = 7 > 3; (last index)
    // 9000 * 100%.
    state.facade.validate_total_risk(position_id: user_1.position_id, expected_total_risk: 9000);
}

#[test]
fn test_transfer() {
    // Setup.
    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    // Create users. user_2 and user_3 are additional positions under the same owner as user_1,
    // so the cross-position transfers below satisfy the same-owner guard. (Cross-owner transfers
    // are covered by test_transfer_to_different_owner_fails.)
    let user_1 = state.new_user_with_position();
    let user_2 = state.new_sibling_position(user_1);
    let user_3 = state.new_sibling_position(user_1);

    // Deposit to users.
    let deposit_info_user_1 = state
        .facade
        .deposit(
            depositor: user_1.account, position_id: user_1.position_id, quantized_amount: 100000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_user_1);

    // Transfer.
    let mut transfer_info = state
        .facade
        .transfer_request(sender: user_1, recipient: user_2, amount: 40000);
    state.facade.transfer(:transfer_info);

    transfer_info = state.facade.transfer_request(sender: user_1, recipient: user_3, amount: 20000);
    state.facade.transfer(:transfer_info);

    transfer_info = state.facade.transfer_request(sender: user_2, recipient: user_3, amount: 10000);
    state.facade.transfer(:transfer_info);

    transfer_info = state.facade.transfer_request(sender: user_2, recipient: user_1, amount: 5000);
    state.facade.transfer(:transfer_info);

    transfer_info = state.facade.transfer_request(sender: user_1, recipient: user_2, amount: 30000);
    state.facade.transfer(:transfer_info);

    //                 COLLATERAL
    // User 1:           15,000
    // User 2:           55,000
    // User 3:           30,000

    // Withdraw.
    let mut withdraw_info = state.facade.withdraw_request(user: user_1, amount: 15000);
    state.facade.withdraw(:withdraw_info);

    withdraw_info = state.facade.withdraw_request(user: user_2, amount: 15000);
    state.facade.withdraw(:withdraw_info);

    withdraw_info = state.facade.withdraw_request(user: user_2, amount: 10000);
    state.facade.withdraw(:withdraw_info);

    withdraw_info = state.facade.withdraw_request(user: user_2, amount: 30000);
    state.facade.withdraw(:withdraw_info);

    withdraw_info = state.facade.withdraw_request(user: user_3, amount: 30000);
    state.facade.withdraw(:withdraw_info);
}

#[test]
fn test_withdraw_with_owner() {
    // Setup.
    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    // Create users.
    let user_1 = state.new_user_with_position();

    // Deposit to users.
    let deposit_info_user_1 = state
        .facade
        .deposit(
            depositor: user_1.account, position_id: user_1.position_id, quantized_amount: 100000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_user_1);

    // Withdraw.
    let mut withdraw_info = state.facade.withdraw_request(user: user_1, amount: 15000);
    state.facade.withdraw(:withdraw_info);
}

#[test]
#[should_panic(expected: 'CALLER_IS_NOT_OWNER_ACCOUNT')]
fn test_withdraw_with_owner_fails_if_not_caller() {
    // Setup.
    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    // Create users.
    let user_1 = state.new_user_with_position();
    let user_2 = state.new_user_with_position();

    // Deposit to users.
    let deposit_info_user_1 = state
        .facade
        .deposit(
            depositor: user_1.account, position_id: user_1.position_id, quantized_amount: 100000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_user_1);

    // Withdraw.
    let mut withdraw_info = state
        .facade
        .withdraw_request_with_caller(
            user: user_1, asset_id: state.facade.collateral_id, amount: 15000, caller: user_2,
        );
    state.facade.withdraw(:withdraw_info);
}

#[test]
fn test_transfer_withdraw_with_negative_collateral() {
    // Setup.
    let risk_factor_data = RiskFactorTiers {
        tiers: array![10].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    // Create a custom asset configuration to test interesting risk factor scenarios.
    let synthetic_info = AssetInfoTrait::new(
        asset_name: 'BTC_1', :risk_factor_data, oracles_len: 1,
    );
    let asset_id = synthetic_info.asset_id;

    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    state.facade.add_active_synthetic(synthetic_info: @synthetic_info, initial_price: 100);

    // Create users.
    let user_1 = state.new_user_with_position();
    let user_2 = state.new_user_with_position();

    // Deposit to users.
    let deposit_info_user_2 = state
        .facade
        .deposit(
            depositor: user_2.account, position_id: user_2.position_id, quantized_amount: 100000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_user_2);

    // Create orders.
    let order_user_1 = state
        .facade
        .create_order(
            user: user_1, base_amount: 1, base_asset_id: asset_id, quote_amount: -5, fee_amount: 0,
        );

    let order_user_2 = state
        .facade
        .create_order(
            user: user_2, base_amount: -1, base_asset_id: asset_id, quote_amount: 5, fee_amount: 0,
        );

    // Make trade.
    state
        .facade
        .trade(
            order_info_a: order_user_1,
            order_info_b: order_user_2,
            base: 1,
            quote: -5,
            fee_a: 0,
            fee_b: 0,
        );

    // Drain base collateral out of user_1 (to a same-owner sink) to make it negative.
    state.drain_collateral(user_1, 20);

    //                    TV                                  TR                 TV / TR
    //         COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // User 1:      -25 + 1 * 100 = 75                 1 * 100 * 0.01 = 1          75
    state.facade.validate_total_value(position_id: user_1.position_id, expected_total_value: 75);
    state.facade.validate_total_risk(position_id: user_1.position_id, expected_total_risk: 1);

    // Withdraw.
    let withdraw_info = state.facade.withdraw_request(user: user_1, amount: 70);
    state.facade.withdraw(:withdraw_info);

    //                    TV                                  TR                 TV / TR
    //         COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // User 1:      -95 + 1 * 100 = 5                  1 * 100 * 0.01 = 1          5
    state.facade.validate_total_value(position_id: user_1.position_id, expected_total_value: 5);
    state.facade.validate_total_risk(position_id: user_1.position_id, expected_total_risk: 1);
}

#[test]
fn test_withdraw_spot_collateral() {
    // Setup.
    let risk_factor_data = RiskFactorTiers {
        tiers: array![10].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    // Create a custom asset configuration.
    let token = snforge_std::Token::STRK;
    let erc20_contract_address = token.contract_address();
    let asset_info = AssetInfoTrait::new_collateral(
        asset_name: 'COL', :risk_factor_data, oracles_len: 1, :erc20_contract_address,
    );
    let asset_id = asset_info.asset_id;
    state.facade.add_active_collateral(asset_info: @asset_info, initial_price: 100);

    // Create users.
    let user = state.new_user_with_position();
    snforge_std::set_balance(target: user.account.address, new_balance: 5000000, :token);

    // Deposit to users.
    let deposit_info_user = state
        .facade
        .deposit_spot(
            depositor: user.account,
            :asset_id,
            position_id: user.position_id,
            quantized_amount: 100000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_user);

    // Set treasury protection to 100% for spot token after deposit funds the treasury.
    state.facade.set_treasury_protection_percent_for_token(erc20_contract_address, 100);

    // Withdraw.
    let mut withdraw_info = state.facade.withdraw_spot_request(:user, :asset_id, amount: 15000);
    state.facade.withdraw(:withdraw_info);
}

#[test]
fn test_reduce_synthetic() {
    // Setup.
    let risk_factor_data = RiskFactorTiers {
        tiers: array![30].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    // Create a custom asset configuration to test interesting risk factor scenarios.
    let synthetic_info = AssetInfoTrait::new(
        asset_name: 'BTC_1', :risk_factor_data, oracles_len: 1,
    );
    let asset_id = synthetic_info.asset_id;

    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    state.facade.add_active_synthetic(synthetic_info: @synthetic_info, initial_price: 100);

    // Create users.
    let user_1 = state.new_user_with_position();
    let user_2 = state.new_user_with_position();

    // Deposit to users.
    let deposit_info_user_2 = state
        .facade
        .deposit(
            depositor: user_2.account, position_id: user_2.position_id, quantized_amount: 100000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_user_2);

    // Create orders.
    let order_user_1 = state
        .facade
        .create_order(
            user: user_1, base_amount: 1, base_asset_id: asset_id, quote_amount: -95, fee_amount: 0,
        );

    let mut order_user_2 = state
        .facade
        .create_order(
            user: user_2, base_amount: -1, base_asset_id: asset_id, quote_amount: 95, fee_amount: 0,
        );

    // Make trade.
    state
        .facade
        .trade(
            order_info_a: order_user_1,
            order_info_b: order_user_2,
            base: 1,
            quote: -95,
            fee_a: 0,
            fee_b: 0,
        );

    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // User 1:             -95 + 1 * 100 = 5                 |1 * 100 * 0.03| = 3          1.6
    state.facade.validate_total_value(position_id: user_1.position_id, expected_total_value: 5);
    state.facade.validate_total_risk(position_id: user_1.position_id, expected_total_risk: 3);

    state.facade.advance_time(10000);
    let mut new_funding_index = FundingIndex { value: 3 * FUNDING_SCALE };
    state
        .facade
        .funding_tick(
            funding_ticks: array![
                FundingTick { asset_id: asset_id, funding_index: new_funding_index },
            ]
                .span(),
        );

    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // User 1:             -98 + 1 * 100 = 2                 |1 * 100 * 0.03| = 3          0.6
    state.facade.validate_total_value(position_id: user_1.position_id, expected_total_value: 2);
    state.facade.validate_total_risk(position_id: user_1.position_id, expected_total_risk: 3);

    assert(
        state.facade.is_liquidatable(position_id: user_1.position_id), 'user is not liquidatable',
    );

    state.facade.deactivate_synthetic(synthetic_id: asset_id);
    state
        .facade
        .reduce_asset_position(
            position_id_a: user_1.position_id,
            position_id_b: user_2.position_id,
            base_asset_id: asset_id,
            base_amount_a: -1,
        );

    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // User 1:                2 + 0 = 2                      |0 * 100 * 0.03| = 0            -
    state.facade.validate_total_value(position_id: user_1.position_id, expected_total_value: 2);
    state.facade.validate_total_risk(position_id: user_1.position_id, expected_total_risk: 0);
}

/// The following test checks the transitions between healthy, liquidatable and deleveragable by
/// using funding tick and price tick.
/// We do so in the following way:
/// User is healthy -> Funding tick occurs -> User is liquidatable -> Funding tick occurs -> User is
/// deleveragable -> Price tick occurs -> User is liquidatable -> Price tick occurs -> User is
/// healthy -> Price tick occurs -> User is deleveragable -> Funding tick occurs -> User is healthy.
#[test]
fn test_status_change_healthy_liquidatable_deleveragable() {
    // Setup.
    let risk_factor_data = RiskFactorTiers {
        tiers: array![10].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    // Create a custom asset configuration to test interesting risk factor scenarios.
    let synthetic_info = AssetInfoTrait::new(
        asset_name: 'BTC_1', :risk_factor_data, oracles_len: 1,
    );
    let asset_id = synthetic_info.asset_id;

    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    state.facade.add_active_synthetic(synthetic_info: @synthetic_info, initial_price: 100);

    // Create users.
    let primary_user = state.new_user_with_position();
    let support_user = state.new_user_with_position();

    // Deposit to users.
    let deposit_info_support_user = state
        .facade
        .deposit(
            depositor: support_user.account,
            position_id: support_user.position_id,
            quantized_amount: 100000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_support_user);

    // Create orders.
    let mut order_primary_user = state
        .facade
        .create_order(
            user: primary_user,
            base_amount: 2,
            base_asset_id: asset_id,
            quote_amount: -195,
            fee_amount: 0,
        );

    let mut order_support_user = state
        .facade
        .create_order(
            user: support_user,
            base_amount: -2,
            base_asset_id: asset_id,
            quote_amount: 195,
            fee_amount: 0,
        );

    // Make trades.
    state
        .facade
        .trade(
            order_info_a: order_primary_user,
            order_info_b: order_support_user,
            base: 2,
            quote: -195,
            fee_a: 0,
            fee_b: 0,
        );

    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // deleveraged User:   -195 + 2 * 100 = 5                 2 * 100 * 0.01 = 2           2.5
    state
        .facade
        .validate_total_value(position_id: primary_user.position_id, expected_total_value: 5);
    state.facade.validate_total_risk(position_id: primary_user.position_id, expected_total_risk: 2);

    state.facade.advance_time(10000);
    let mut new_funding_index = FundingIndex { value: 2 * FUNDING_SCALE };
    state
        .facade
        .funding_tick(
            funding_ticks: array![
                FundingTick { asset_id: asset_id, funding_index: new_funding_index },
            ]
                .span(),
        );

    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // deleveraged User:   -199 + 2 * 100 = 1                 2 * 100 * 0.01 = 2           0.5
    state
        .facade
        .validate_total_value(position_id: primary_user.position_id, expected_total_value: 1);
    state.facade.validate_total_risk(position_id: primary_user.position_id, expected_total_risk: 2);

    assert(
        state.facade.is_liquidatable(position_id: primary_user.position_id),
        'user is not liquidatable',
    );

    state.facade.advance_time(10000);
    new_funding_index = FundingIndex { value: 4 * FUNDING_SCALE };
    state
        .facade
        .funding_tick(
            funding_ticks: array![
                FundingTick { asset_id: asset_id, funding_index: new_funding_index },
            ]
                .span(),
        );

    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // deleveraged User:   -203 + 2 * 100 = -3                 2 * 100 * 0.01 = 2         -1.5
    state
        .facade
        .validate_total_value(position_id: primary_user.position_id, expected_total_value: -3);
    state.facade.validate_total_risk(position_id: primary_user.position_id, expected_total_risk: 2);

    assert(
        state.facade.is_deleveragable(position_id: primary_user.position_id),
        'user is not deleveragable',
    );

    state.facade.price_tick(asset_info: @synthetic_info, price: 102);
    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // deleveraged User:   -203 + 2 * 102 = 1                 2 * 102 * 0.01 = 2           0.5
    state
        .facade
        .validate_total_value(position_id: primary_user.position_id, expected_total_value: 1);
    state.facade.validate_total_risk(position_id: primary_user.position_id, expected_total_risk: 2);

    assert(
        state.facade.is_liquidatable(position_id: primary_user.position_id),
        'user is not liquidatable',
    );

    state.facade.price_tick(asset_info: @synthetic_info, price: 103);
    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // deleveraged User:   -203 + 2 * 103 = 3                 2 * 103 * 0.01 = 2           1.5
    state
        .facade
        .validate_total_value(position_id: primary_user.position_id, expected_total_value: 3);
    state.facade.validate_total_risk(position_id: primary_user.position_id, expected_total_risk: 2);

    // Create orders.
    order_primary_user = state
        .facade
        .create_order(
            user: primary_user,
            base_amount: 1,
            base_asset_id: asset_id,
            quote_amount: -100,
            fee_amount: 0,
        );

    order_support_user = state
        .facade
        .create_order(
            user: support_user,
            base_amount: -1,
            base_asset_id: asset_id,
            quote_amount: 100,
            fee_amount: 0,
        );

    // Make trades.
    state
        .facade
        .trade(
            order_info_a: order_primary_user,
            order_info_b: order_support_user,
            base: 1,
            quote: -100,
            fee_a: 0,
            fee_b: 0,
        );

    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // deleveraged User:   -303 + 3 * 100 = 6                 3 * 103 * 0.01 = 3            2
    state
        .facade
        .validate_total_value(position_id: primary_user.position_id, expected_total_value: 6);
    state.facade.validate_total_risk(position_id: primary_user.position_id, expected_total_risk: 3);

    state.facade.price_tick(asset_info: @synthetic_info, price: 100);
    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // deleveraged User:   -303 + 3 * 100 = -3                 3 * 100 * 0.01 = 3          -1
    state
        .facade
        .validate_total_value(position_id: primary_user.position_id, expected_total_value: -3);
    state.facade.validate_total_risk(position_id: primary_user.position_id, expected_total_risk: 3);

    assert(
        state.facade.is_deleveragable(position_id: primary_user.position_id),
        'user is not deleveragable',
    );

    state.facade.advance_time(10000);
    new_funding_index = FundingIndex { value: FUNDING_SCALE };
    state
        .facade
        .funding_tick(
            funding_ticks: array![
                FundingTick { asset_id: asset_id, funding_index: new_funding_index },
            ]
                .span(),
        );

    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // deleveraged User:   -294 + 3 * 100 = 6                 3 * 100 * 0.01 = 3            2
    state
        .facade
        .validate_total_value(position_id: primary_user.position_id, expected_total_value: 6);
    state.facade.validate_total_risk(position_id: primary_user.position_id, expected_total_risk: 3);

    // Create orders.
    order_primary_user = state
        .facade
        .create_order(
            user: primary_user,
            base_amount: 1,
            base_asset_id: asset_id,
            quote_amount: -100,
            fee_amount: 0,
        );

    order_support_user = state
        .facade
        .create_order(
            user: support_user,
            base_amount: -1,
            base_asset_id: asset_id,
            quote_amount: 100,
            fee_amount: 0,
        );

    // Make trades.
    state
        .facade
        .trade(
            order_info_a: order_primary_user,
            order_info_b: order_support_user,
            base: 1,
            quote: -100,
            fee_a: 0,
            fee_b: 0,
        );
}

#[test]
fn test_status_change_by_deposit() {
    // Setup.
    let risk_factor_data = RiskFactorTiers {
        tiers: array![10].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let synthetic_info = AssetInfoTrait::new(
        asset_name: 'BTC_1', :risk_factor_data, oracles_len: 1,
    );
    let asset_id = synthetic_info.asset_id;

    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    state.facade.add_active_synthetic(synthetic_info: @synthetic_info, initial_price: 100);

    // Create users.
    let primary_user = state.new_user_with_position();
    let support_user = state.new_user_with_position();

    // Deposit to users.
    let mut deposit_info_user = state
        .facade
        .deposit(
            depositor: support_user.account,
            position_id: support_user.position_id,
            quantized_amount: 100000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_user);

    // Create orders.
    let mut order_primary_user = state
        .facade
        .create_order(
            user: primary_user,
            base_amount: 2,
            base_asset_id: asset_id,
            quote_amount: -195,
            fee_amount: 0,
        );

    let mut order_support_user = state
        .facade
        .create_order(
            user: support_user,
            base_amount: -2,
            base_asset_id: asset_id,
            quote_amount: 195,
            fee_amount: 0,
        );

    // Make trades.
    state
        .facade
        .trade(
            order_info_a: order_primary_user,
            order_info_b: order_support_user,
            base: 2,
            quote: -195,
            fee_a: 0,
            fee_b: 0,
        );

    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // deleveraged User:   -195 + 2 * 100 = 5                 2 * 100 * 0.01 = 2           2.5
    state
        .facade
        .validate_total_value(position_id: primary_user.position_id, expected_total_value: 5);
    state.facade.validate_total_risk(position_id: primary_user.position_id, expected_total_risk: 2);

    state.facade.advance_time(10000);
    let mut new_funding_index = FundingIndex { value: 4 * FUNDING_SCALE };
    state
        .facade
        .funding_tick(
            funding_ticks: array![
                FundingTick { asset_id: asset_id, funding_index: new_funding_index },
            ]
                .span(),
        );

    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // deleveraged User:   -203 + 2 * 100 = -3                 2 * 100 * 0.01 = 2         -1.5
    state
        .facade
        .validate_total_value(position_id: primary_user.position_id, expected_total_value: -3);
    state.facade.validate_total_risk(position_id: primary_user.position_id, expected_total_risk: 2);

    assert(
        state.facade.is_deleveragable(position_id: primary_user.position_id),
        'user is not deleveragable',
    );

    deposit_info_user = state
        .facade
        .deposit(
            depositor: primary_user.account,
            position_id: primary_user.position_id,
            quantized_amount: 4,
        );
    state.facade.process_deposit(deposit_info: deposit_info_user);

    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // deleveraged User:   -199 + 2 * 100 = 1                 2 * 100 * 0.01 = 2           0.5

    state
        .facade
        .validate_total_value(position_id: primary_user.position_id, expected_total_value: 1);
    state.facade.validate_total_risk(position_id: primary_user.position_id, expected_total_risk: 2);

    assert(
        state.facade.is_liquidatable(position_id: primary_user.position_id),
        'user is not liquidatable',
    );

    deposit_info_user = state
        .facade
        .deposit(
            depositor: primary_user.account,
            position_id: primary_user.position_id,
            quantized_amount: 1,
        );
    state.facade.process_deposit(deposit_info: deposit_info_user);

    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // deleveraged User:   -198 + 2 * 100 = 2                 2 * 100 * 0.01 = 2            1
    state
        .facade
        .validate_total_value(position_id: primary_user.position_id, expected_total_value: 2);
    state.facade.validate_total_risk(position_id: primary_user.position_id, expected_total_risk: 2);

    // Create orders.
    let mut order_primary_user = state
        .facade
        .create_order(
            user: primary_user,
            base_amount: -1,
            base_asset_id: asset_id,
            quote_amount: 100,
            fee_amount: 0,
        );

    let mut order_support_user = state
        .facade
        .create_order(
            user: support_user,
            base_amount: 1,
            base_asset_id: asset_id,
            quote_amount: -100,
            fee_amount: 0,
        );

    // Make trades.
    state
        .facade
        .trade(
            order_info_a: order_primary_user,
            order_info_b: order_support_user,
            base: -1,
            quote: 100,
            fee_a: 0,
            fee_b: 0,
        );

    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // deleveraged User:   -98 + 1 * 100 = 2                  1 * 100 * 0.01 = 1            2
    state
        .facade
        .validate_total_value(position_id: primary_user.position_id, expected_total_value: 2);
    state.facade.validate_total_risk(position_id: primary_user.position_id, expected_total_risk: 1);
}

#[test]
fn test_status_change_by_transfer() {
    // Setup.
    let risk_factor_data = RiskFactorTiers {
        tiers: array![10].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let synthetic_info = AssetInfoTrait::new(
        asset_name: 'BTC_1', :risk_factor_data, oracles_len: 1,
    );
    let asset_id = synthetic_info.asset_id;
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    state.facade.add_active_synthetic(synthetic_info: @synthetic_info, initial_price: 100);
    // Create users. support_user funds primary_user via transfer, so it must share
    // primary_user's owner_account (the same-owner transfer guard now applies to all owners).
    let primary_user = state.new_user_with_position();
    let support_user = state.new_sibling_position(primary_user);
    // Deposit to users.
    let deposit_info_user = state
        .facade
        .deposit(
            depositor: support_user.account,
            position_id: support_user.position_id,
            quantized_amount: 100000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_user);
    // Create orders.
    let mut order_primary_user = state
        .facade
        .create_order(
            user: primary_user,
            base_amount: 2,
            base_asset_id: asset_id,
            quote_amount: -195,
            fee_amount: 0,
        );
    let mut order_support_user = state
        .facade
        .create_order(
            user: support_user,
            base_amount: -2,
            base_asset_id: asset_id,
            quote_amount: 195,
            fee_amount: 0,
        );
    // Make trades.
    state
        .facade
        .trade(
            order_info_a: order_primary_user,
            order_info_b: order_support_user,
            base: 2,
            quote: -195,
            fee_a: 0,
            fee_b: 0,
        );
    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // deleveraged User:   -195 + 2 * 100 = 5                 2 * 100 * 0.01 = 2           2.5
    state
        .facade
        .validate_total_value(position_id: primary_user.position_id, expected_total_value: 5);
    state.facade.validate_total_risk(position_id: primary_user.position_id, expected_total_risk: 2);
    state.facade.advance_time(10000);
    let mut new_funding_index = FundingIndex { value: 4 * FUNDING_SCALE };
    state
        .facade
        .funding_tick(
            funding_ticks: array![
                FundingTick { asset_id: asset_id, funding_index: new_funding_index },
            ]
                .span(),
        );
    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // deleveraged User:   -203 + 2 * 100 = -3                 2 * 100 * 0.01 = 2         -1.5
    state
        .facade
        .validate_total_value(position_id: primary_user.position_id, expected_total_value: -3);
    state.facade.validate_total_risk(position_id: primary_user.position_id, expected_total_risk: 2);

    assert(
        state.facade.is_deleveragable(position_id: primary_user.position_id),
        'user is not deleveragable',
    );

    let mut transfer_info = state
        .facade
        .transfer_request(sender: support_user, recipient: primary_user, amount: 4);
    state.facade.transfer(:transfer_info);
    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // deleveraged User:   -199 + 2 * 100 = 1                 2 * 100 * 0.01 = 2           0.5
    state
        .facade
        .validate_total_value(position_id: primary_user.position_id, expected_total_value: 1);
    state.facade.validate_total_risk(position_id: primary_user.position_id, expected_total_risk: 2);

    assert(
        state.facade.is_liquidatable(position_id: primary_user.position_id),
        'user is not liquidatable',
    );

    transfer_info = state
        .facade
        .transfer_request(sender: support_user, recipient: primary_user, amount: 1);
    state.facade.transfer(:transfer_info);

    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // deleveraged User:   -198 + 2 * 100 = 2                 2 * 100 * 0.01 = 2            1
    state
        .facade
        .validate_total_value(position_id: primary_user.position_id, expected_total_value: 2);
    state.facade.validate_total_risk(position_id: primary_user.position_id, expected_total_risk: 2);

    // Create orders.
    let mut order_primary_user = state
        .facade
        .create_order(
            user: primary_user,
            base_amount: -1,
            base_asset_id: asset_id,
            quote_amount: 100,
            fee_amount: 0,
        );

    let mut order_support_user = state
        .facade
        .create_order(
            user: support_user,
            base_amount: 1,
            base_asset_id: asset_id,
            quote_amount: -100,
            fee_amount: 0,
        );

    // Make trades.
    state
        .facade
        .trade(
            order_info_a: order_primary_user,
            order_info_b: order_support_user,
            base: -1,
            quote: 100,
            fee_a: 0,
            fee_b: 0,
        );

    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // deleveraged User:   -98 + 1 * 100 = 2                  1 * 100 * 0.01 = 1            2
    state
        .facade
        .validate_total_value(position_id: primary_user.position_id, expected_total_value: 2);
    state.facade.validate_total_risk(position_id: primary_user.position_id, expected_total_risk: 1);
}

#[test]
fn test_status_change_by_trade() {
    // Setup.
    let risk_factor_data = RiskFactorTiers {
        tiers: array![10].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let synthetic_info = AssetInfoTrait::new(
        asset_name: 'BTC_1', :risk_factor_data, oracles_len: 1,
    );
    let asset_id = synthetic_info.asset_id;
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    state.facade.add_active_synthetic(synthetic_info: @synthetic_info, initial_price: 100);
    // Create users.
    let primary_user = state.new_user_with_position();
    let support_user = state.new_user_with_position();
    // Deposit to users.
    let deposit_info_user = state
        .facade
        .deposit(
            depositor: support_user.account,
            position_id: support_user.position_id,
            quantized_amount: 100000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_user);
    // Create orders.
    let mut order_primary_user = state
        .facade
        .create_order(
            user: primary_user,
            base_amount: 6,
            base_asset_id: asset_id,
            quote_amount: -594,
            fee_amount: 0,
        );
    let mut order_support_user = state
        .facade
        .create_order(
            user: support_user,
            base_amount: -6,
            base_asset_id: asset_id,
            quote_amount: 594,
            fee_amount: 0,
        );
    // Make trades.
    state
        .facade
        .trade(
            order_info_a: order_primary_user,
            order_info_b: order_support_user,
            base: 6,
            quote: -594,
            fee_a: 0,
            fee_b: 0,
        );
    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // deleveraged User:   -594 + 6 * 100 = 6                 6 * 100 * 0.01 = 6            1
    state
        .facade
        .validate_total_value(position_id: primary_user.position_id, expected_total_value: 6);
    state.facade.validate_total_risk(position_id: primary_user.position_id, expected_total_risk: 6);
    state.facade.advance_time(10000);
    let mut new_funding_index = FundingIndex { value: 2 * FUNDING_SCALE };
    state
        .facade
        .funding_tick(
            funding_ticks: array![
                FundingTick { asset_id: asset_id, funding_index: new_funding_index },
            ]
                .span(),
        );
    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // deleveraged User:   -606 + 6 * 100 = -6                 6 * 100 * 0.01 = 6          -1
    state
        .facade
        .validate_total_value(position_id: primary_user.position_id, expected_total_value: -6);
    state.facade.validate_total_risk(position_id: primary_user.position_id, expected_total_risk: 6);

    assert(
        state.facade.is_deleveragable(position_id: primary_user.position_id),
        'user is not deleveragable',
    );

    // Create orders.
    let mut order_primary_user = state
        .facade
        .create_order(
            user: primary_user,
            base_amount: -1,
            base_asset_id: asset_id,
            quote_amount: 104,
            fee_amount: 0,
        );
    let mut order_support_user = state
        .facade
        .create_order(
            user: support_user,
            base_amount: 1,
            base_asset_id: asset_id,
            quote_amount: -104,
            fee_amount: 0,
        );
    // Make trades.
    state
        .facade
        .trade(
            order_info_a: order_primary_user,
            order_info_b: order_support_user,
            base: -1,
            quote: 104,
            fee_a: 0,
            fee_b: 0,
        );
    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // deleveraged User:   -502 + 5 * 100 = -2                5 * 100 * 0.01 = 5          -0.4
    state
        .facade
        .validate_total_value(position_id: primary_user.position_id, expected_total_value: -2);
    state.facade.validate_total_risk(position_id: primary_user.position_id, expected_total_risk: 5);

    assert(
        state.facade.is_deleveragable(position_id: primary_user.position_id),
        'user is not deleveragable',
    );

    // Create orders.
    let mut order_primary_user = state
        .facade
        .create_order(
            user: primary_user,
            base_amount: -1,
            base_asset_id: asset_id,
            quote_amount: 102,
            fee_amount: 0,
        );
    let mut order_support_user = state
        .facade
        .create_order(
            user: support_user,
            base_amount: 1,
            base_asset_id: asset_id,
            quote_amount: -102,
            fee_amount: 0,
        );
    // Make trades.
    state
        .facade
        .trade(
            order_info_a: order_primary_user,
            order_info_b: order_support_user,
            base: -1,
            quote: 102,
            fee_a: 0,
            fee_b: 0,
        );
    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // deleveraged User:   -400 + 4 * 100 = 0                 4 * 100 * 0.01 = 4            0
    state
        .facade
        .validate_total_value(position_id: primary_user.position_id, expected_total_value: 0);
    state.facade.validate_total_risk(position_id: primary_user.position_id, expected_total_risk: 4);
    // Create orders.
    let mut order_primary_user = state
        .facade
        .create_order(
            user: primary_user,
            base_amount: -1,
            base_asset_id: asset_id,
            quote_amount: 100,
            fee_amount: 0,
        );
    let mut order_support_user = state
        .facade
        .create_order(
            user: support_user,
            base_amount: 1,
            base_asset_id: asset_id,
            quote_amount: -100,
            fee_amount: 0,
        );
    // Make trades.
    state
        .facade
        .trade(
            order_info_a: order_primary_user,
            order_info_b: order_support_user,
            base: -1,
            quote: 100,
            fee_a: 0,
            fee_b: 0,
        );
    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // deleveraged User:   -300 + 3 * 100 = 0                 3 * 100 * 0.01 = 3            0
    state
        .facade
        .validate_total_value(position_id: primary_user.position_id, expected_total_value: 0);
    state.facade.validate_total_risk(position_id: primary_user.position_id, expected_total_risk: 3);
    // Create orders.
    let mut order_primary_user = state
        .facade
        .create_order(
            user: primary_user,
            base_amount: -1,
            base_asset_id: asset_id,
            quote_amount: 101,
            fee_amount: 0,
        );
    let mut order_support_user = state
        .facade
        .create_order(
            user: support_user,
            base_amount: 1,
            base_asset_id: asset_id,
            quote_amount: -101,
            fee_amount: 0,
        );
    // Make trades.
    state
        .facade
        .trade(
            order_info_a: order_primary_user,
            order_info_b: order_support_user,
            base: -1,
            quote: 101,
            fee_a: 0,
            fee_b: 0,
        );
    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // deleveraged User:   -199 + 2 * 100 = 1                 2 * 100 * 0.01 = 2           0.5
    state
        .facade
        .validate_total_value(position_id: primary_user.position_id, expected_total_value: 1);
    state.facade.validate_total_risk(position_id: primary_user.position_id, expected_total_risk: 2);

    assert(
        state.facade.is_liquidatable(position_id: primary_user.position_id),
        'user is not liquidatable',
    );

    // Create orders.
    let mut order_primary_user = state
        .facade
        .create_order(
            user: primary_user,
            base_amount: -2,
            base_asset_id: asset_id,
            quote_amount: 199,
            fee_amount: 0,
        );
    let mut order_support_user = state
        .facade
        .create_order(
            user: support_user,
            base_amount: 2,
            base_asset_id: asset_id,
            quote_amount: -199,
            fee_amount: 0,
        );
    // Make trades.
    state
        .facade
        .trade(
            order_info_a: order_primary_user,
            order_info_b: order_support_user,
            base: -2,
            quote: 199,
            fee_a: 0,
            fee_b: 0,
        );

    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // deleveraged User:     0 + 0 * 100 = 0                 0 * 100 * 0.01 = 0            -
    state
        .facade
        .validate_total_value(position_id: primary_user.position_id, expected_total_value: 0);
    state.facade.validate_total_risk(position_id: primary_user.position_id, expected_total_risk: 0);
}

#[test]
#[should_panic(expected: 'SYNTHETIC_EXPIRED_PRICE')]
fn test_late_funding() {
    // Setup.
    let risk_factor_data = RiskFactorTiers {
        tiers: array![10].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    // Create a custom asset configuration to test interesting risk factor scenarios.
    let synthetic_info = AssetInfoTrait::new(
        asset_name: 'BTC_1', :risk_factor_data, oracles_len: 1,
    );
    let asset_id = synthetic_info.asset_id;

    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    state.facade.add_active_synthetic(synthetic_info: @synthetic_info, initial_price: 100);

    state.facade.advance_time(100000);
    let mut new_funding_index = FundingIndex { value: FUNDING_SCALE };
    state
        .facade
        .funding_tick(
            funding_ticks: array![
                FundingTick { asset_id: asset_id, funding_index: new_funding_index },
            ]
                .span(),
        );
}

#[test]
#[should_panic(expected: 'INVALID_BASE_CHANGE')]
fn test_liquidate_change_sign() {
    // Setup.
    let risk_factor_data = RiskFactorTiers {
        tiers: array![10].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let synthetic_info = AssetInfoTrait::new(
        asset_name: 'BTC_1', :risk_factor_data, oracles_len: 1,
    );
    let asset_id = synthetic_info.asset_id;

    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    state.facade.add_active_synthetic(synthetic_info: @synthetic_info, initial_price: 103);

    // Create users.
    let user_1 = state.new_user_with_position();
    let user_2 = state.new_user_with_position();

    // Deposit to users.
    let deposit_info_user_2 = state
        .facade
        .deposit(
            depositor: user_2.account, position_id: user_2.position_id, quantized_amount: 100000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_user_2);

    // Create orders.
    let mut order_user_1 = state
        .facade
        .create_order(
            user: user_1,
            base_amount: 3,
            base_asset_id: asset_id,
            quote_amount: -306,
            fee_amount: 0,
        );

    let mut order_user_2 = state
        .facade
        .create_order(
            user: user_2,
            base_amount: -3,
            base_asset_id: asset_id,
            quote_amount: 305,
            fee_amount: 0,
        );

    // Make trade.
    state
        .facade
        .trade(
            order_info_a: order_user_1,
            order_info_b: order_user_2,
            base: 3,
            quote: -305,
            fee_a: 0,
            fee_b: 0,
        );

    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // User 1:             -305 + 3 * 103 = 3                  3 * 103 * 0.01 = 3.09        1.29
    state.facade.validate_total_value(position_id: user_1.position_id, expected_total_value: 4);
    state.facade.validate_total_risk(position_id: user_1.position_id, expected_total_risk: 3);

    // Price tick.
    state.facade.price_tick(asset_info: @synthetic_info, price: 100);

    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // User 1:             -305 + 3 * 100 = -5                 3 * 100 * 0.01 = 3          -1.66

    state.facade.validate_total_value(position_id: user_1.position_id, expected_total_value: -5);
    state.facade.validate_total_risk(position_id: user_1.position_id, expected_total_risk: 3);

    // Liquidate.
    order_user_2 = state
        .facade
        .create_order(
            user: user_2,
            base_amount: 5,
            base_asset_id: asset_id,
            quote_amount: -505,
            fee_amount: 0,
        );
    state
        .facade
        .liquidate(
            liquidated_user: user_1,
            liquidator_order: order_user_2,
            liquidated_base: -5,
            liquidated_quote: 505,
            liquidated_insurance_fee: 0,
            liquidator_fee: 0,
        );
}

#[test]
fn test_funding_index_rounding() {
    let risk_factor_data = RiskFactorTiers {
        tiers: array![10].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let synthetic_info = AssetInfoTrait::new(asset_name: 'BTC', :risk_factor_data, oracles_len: 1);
    let asset_id = synthetic_info.asset_id;

    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    state.facade.add_active_synthetic(synthetic_info: @synthetic_info, initial_price: 100);

    let user_1 = state.new_user_with_position();
    let user_2 = state.new_user_with_position();

    let deposit_info_user_1 = state
        .facade
        .deposit(
            depositor: user_1.account, position_id: user_1.position_id, quantized_amount: 1100,
        );
    state.facade.process_deposit(deposit_info: deposit_info_user_1);

    let deposit_info_user_2 = state
        .facade
        .deposit(depositor: user_2.account, position_id: user_2.position_id, quantized_amount: 900);
    state.facade.process_deposit(deposit_info: deposit_info_user_2);

    let order_1 = state
        .facade
        .create_order(
            user: user_1,
            base_amount: 1,
            base_asset_id: asset_id,
            quote_amount: -100,
            fee_amount: 0,
        );

    let order_2 = state
        .facade
        .create_order(
            user: user_2,
            base_amount: -1,
            base_asset_id: asset_id,
            quote_amount: 100,
            fee_amount: 0,
        );

    state
        .facade
        .trade(
            order_info_a: order_1, order_info_b: order_2, base: 1, quote: -100, fee_a: 0, fee_b: 0,
        );

    // Collateral balance before is 1000 each.
    state.facade.validate_collateral_balance(user_1.position_id, 1000_i64.into());
    state.facade.validate_collateral_balance(user_2.position_id, 1000_i64.into());

    // funding tick of half
    state.facade.advance_time(10000);
    let mut new_funding_index = FundingIndex { value: FUNDING_SCALE / 2 };
    state
        .facade
        .funding_tick(
            funding_ticks: array![FundingTick { asset_id, funding_index: new_funding_index }]
                .span(),
        );

    /// Longer gets decremented by half, which rounds down to -1. Shorter gets incremented by half,
    /// which rounds down to 0.
    state.facade.validate_collateral_balance(user_1.position_id, 999_i64.into());
    state.facade.validate_collateral_balance(user_2.position_id, 1000_i64.into());

    // funding tick of minus half
    state.facade.advance_time(10000);
    let mut new_funding_index = FundingIndex { value: -FUNDING_SCALE / 2 };
    state
        .facade
        .funding_tick(
            funding_ticks: array![FundingTick { asset_id, funding_index: new_funding_index }]
                .span(),
        );

    /// Longer gets incremented by half, which rounds down to 0. Shorter gets decremented by half,
    /// which rounds down to -1.
    state.facade.validate_collateral_balance(user_1.position_id, 1000_i64.into());
    state.facade.validate_collateral_balance(user_2.position_id, 999_i64.into());
}

#[test]
#[should_panic(
    expected: "POSITION_IS_NOT_FAIR_DELEVERAGE position_id: PositionId { value: 101 } TV before -2, TR before 2, TV after 2, TR after 0",
)]
fn test_unfair_deleverage() {
    // Setup.
    let risk_factor_data = RiskFactorTiers {
        tiers: array![10].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    // Create a custom asset configuration to test interesting risk factor scenarios.
    let synthetic_info = AssetInfoTrait::new(
        asset_name: 'BTC_1', :risk_factor_data, oracles_len: 1,
    );
    let asset_id = synthetic_info.asset_id;

    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    state.facade.add_active_synthetic(synthetic_info: @synthetic_info, initial_price: 100);

    // Create users.
    let deleveraged_user = state.new_user_with_position();
    let deleverager_user = state.new_user_with_position();

    // Deposit to users.
    let deposit_info_user_1 = state
        .facade
        .deposit(
            depositor: deleverager_user.account,
            position_id: deleverager_user.position_id,
            quantized_amount: 100000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_user_1);

    // Create orders.
    // User willing to buy 2 synthetic assets for 168 (quote) + 20 (fee).
    let order_deleveraged_user = state
        .facade
        .create_order(
            user: deleveraged_user,
            base_amount: 2,
            base_asset_id: asset_id,
            quote_amount: -168,
            fee_amount: 20,
        );

    let order_deleverager_user = state
        .facade
        .create_order(
            user: deleverager_user,
            base_amount: -2,
            base_asset_id: asset_id,
            quote_amount: 168,
            fee_amount: 20,
        );

    // Make trades.
    // User recieves 2 synthetic asset for 168 (quote) + 20 (fee).
    state
        .facade
        .trade(
            order_info_a: order_deleveraged_user,
            order_info_b: order_deleverager_user,
            base: 2,
            quote: -168,
            fee_a: 20,
            fee_b: 20,
        );

    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // deleveraged User:   -188 + 2 * 100 = 12                 2 * 100 * 0.01 = 2           6
    state
        .facade
        .validate_total_value(position_id: deleveraged_user.position_id, expected_total_value: 12);
    state
        .facade
        .validate_total_risk(position_id: deleveraged_user.position_id, expected_total_risk: 2);

    state.facade.advance_time(10000);
    let mut new_funding_index = FundingIndex { value: 7 * FUNDING_SCALE };
    state
        .facade
        .funding_tick(
            funding_ticks: array![
                FundingTick { asset_id: asset_id, funding_index: new_funding_index },
            ]
                .span(),
        );

    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // deleveraged User:   -202 + 2 * 100 = -2                 2 * 100 * 0.01 = 2          - 1
    state
        .facade
        .validate_total_value(position_id: deleveraged_user.position_id, expected_total_value: -2);
    state
        .facade
        .validate_total_risk(position_id: deleveraged_user.position_id, expected_total_risk: 2);

    assert(
        state.facade.is_deleveragable(position_id: deleveraged_user.position_id),
        'user is not deleveragable',
    );

    state
        .facade
        .deleverage(
            deleveraged_user: deleveraged_user,
            deleverager_user: deleverager_user,
            base_asset_id: asset_id,
            deleveraged_base: -2,
            deleveraged_quote: 204,
        );
}

#[test]
fn test_spot_collateral_deposit_transfer_withdraw() {
    // Setup.
    let risk_factor_data = RiskFactorTiers {
        tiers: array![10].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    // Create a custom spot collateral asset (not the base collateral).
    let token = snforge_std::Token::STRK;
    let erc20_contract_address = token.contract_address();
    let asset_info = AssetInfoTrait::new_collateral(
        asset_name: 'SPOT', :risk_factor_data, oracles_len: 1, :erc20_contract_address,
    );
    let asset_id = asset_info.asset_id;
    state.facade.add_active_collateral(asset_info: @asset_info, initial_price: 100);

    // Create users. user_2 is a second position under the same owner as user_1, so the spot
    // transfer between them satisfies the same-owner guard.
    let user_1 = state.new_user_with_position();
    let user_2 = state.new_sibling_position(user_1);
    snforge_std::set_balance(target: user_1.account.address, new_balance: 5000000, :token);

    // Deposit spot collateral asset to user_1.
    let deposit_info_user_1 = state
        .facade
        .deposit_spot(
            depositor: user_1.account,
            :asset_id,
            position_id: user_1.position_id,
            quantized_amount: 100000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_user_1);

    // Set treasury protection to 100% for spot token after deposit funds the treasury.
    state.facade.set_treasury_protection_percent_for_token(erc20_contract_address, 100);

    // Transfer partial amount from user_1 to user_2.
    let transfer_info = state
        .facade
        .transfer_spot_request(sender: user_1, recipient: user_2, :asset_id, amount: 40000);
    state.facade.transfer(:transfer_info);
    // Withdraw from user_1 (first withdrawal).
    let mut withdraw_info = state
        .facade
        .withdraw_spot_request(user: user_1, :asset_id, amount: 30000);
    state.facade.withdraw(:withdraw_info);

    // Withdraw from user_2 (second withdrawal).
    withdraw_info = state.facade.withdraw_spot_request(user: user_2, :asset_id, amount: 40000);
    state.facade.withdraw(:withdraw_info);

    // Verify final balances.
    let balance_user_1: i64 = state
        .facade
        .get_position_asset_balance(user_1.position_id, asset_id)
        .into();
    let balance_user_2: i64 = state
        .facade
        .get_position_asset_balance(user_2.position_id, asset_id)
        .into();

    // user_1: 100000 (deposit) - 40000 (transfer) - 30000 (withdraw) = 30000
    assert_eq!(balance_user_1, 30000_i64);
    // user_2: 40000 (transfer) - 40000 (withdraw) = 0
    assert_eq!(balance_user_2, 0_i64);
}

#[test]
#[should_panic(expected: 'INVALID_SHRINK_TO_NEGATIVE')]
fn test_spot_collateral_deposit_transfer_withdraw_fails() {
    // Setup:
    let risk_factor_data = RiskFactorTiers {
        tiers: array![10].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    let token = snforge_std::Token::STRK;
    let erc20_contract_address = token.contract_address();
    let asset_info = AssetInfoTrait::new_collateral(
        asset_name: 'BTC', :risk_factor_data, oracles_len: 1, :erc20_contract_address,
    );
    let asset_id = asset_info.asset_id;
    state.facade.add_active_collateral(asset_info: @asset_info, initial_price: 100);

    let user_1 = state.new_user_with_position();
    let user_2 = state.new_sibling_position(user_1);
    snforge_std::set_balance(target: user_1.account.address, new_balance: 5000000, :token);

    // Deposit.
    let deposit_info_user_1 = state
        .facade
        .deposit_spot(
            depositor: user_1.account,
            :asset_id,
            position_id: user_1.position_id,
            quantized_amount: 100000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_user_1);

    // Transfer.
    let transfer_info = state
        .facade
        .transfer_spot_request(sender: user_1, recipient: user_2, :asset_id, amount: 40000);
    state.facade.transfer(:transfer_info);

    // Trying to withdraw.
    let withdraw_info = state.facade.withdraw_spot_request(user: user_1, :asset_id, amount: 70000);
    state.facade.withdraw(:withdraw_info);
}

#[test]
fn test_deposit_two_spot_collaterals() {
    // Setup.
    let risk_factor_data = RiskFactorTiers {
        tiers: array![10].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    // Create first spot collateral asset (BTC).
    let strk_token = snforge_std::Token::STRK;
    let btc_erc20_contract_address = strk_token.contract_address();
    let asset_info_btc = AssetInfoTrait::new_collateral(
        asset_name: 'BTC',
        :risk_factor_data,
        oracles_len: 1,
        erc20_contract_address: btc_erc20_contract_address,
    );
    let asset_id_btc = asset_info_btc.asset_id;
    state.facade.add_active_collateral(asset_info: @asset_info_btc, initial_price: 100);

    // Create second spot collateral asset (ETH).
    let eth_token = snforge_std::Token::ETH;
    let eth_erc20_contract_address = eth_token.contract_address();
    let asset_info_eth = AssetInfoTrait::new_collateral(
        asset_name: 'ETH',
        :risk_factor_data,
        oracles_len: 1,
        erc20_contract_address: eth_erc20_contract_address,
    );
    let asset_id_eth = asset_info_eth.asset_id;
    state.facade.add_active_collateral(asset_info: @asset_info_eth, initial_price: 50);

    // Create user.
    let user = state.new_user_with_position();
    snforge_std::set_balance(target: user.account.address, new_balance: 5000000, token: strk_token);
    snforge_std::set_balance(target: user.account.address, new_balance: 5000000, token: eth_token);

    // Deposit BTC spot collateral.
    let deposit_info_btc = state
        .facade
        .deposit_spot(
            depositor: user.account,
            asset_id: asset_id_btc,
            position_id: user.position_id,
            quantized_amount: 100000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_btc);

    // Deposit ETH spot collateral.
    let deposit_info_eth = state
        .facade
        .deposit_spot(
            depositor: user.account,
            asset_id: asset_id_eth,
            position_id: user.position_id,
            quantized_amount: 200000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_eth);

    // Set treasury protection to 100% for both spot tokens after deposits fund the treasury.
    state.facade.set_treasury_protection_percent_for_token(btc_erc20_contract_address, 100);
    state.facade.set_treasury_protection_percent_for_token(eth_erc20_contract_address, 100);

    // Verify both balances are correct.
    let balance_btc: i64 = state
        .facade
        .get_position_asset_balance(user.position_id, asset_id_btc)
        .into();
    let balance_eth: i64 = state
        .facade
        .get_position_asset_balance(user.position_id, asset_id_eth)
        .into();

    assert_eq!(balance_btc, 100000_i64);
    assert_eq!(balance_eth, 200000_i64);

    // Verify that operations work independently on both spot collaterals.
    // Withdraw some BTC.
    let withdraw_info_btc = state
        .facade
        .withdraw_spot_request(user: user, asset_id: asset_id_btc, amount: 30000);
    state.facade.withdraw(withdraw_info: withdraw_info_btc);

    // Withdraw some ETH.
    let withdraw_info_eth = state
        .facade
        .withdraw_spot_request(user: user, asset_id: asset_id_eth, amount: 50000);
    state.facade.withdraw(withdraw_info: withdraw_info_eth);

    // Verify final balances after withdrawals.
    let balance_btc_after: i64 = state
        .facade
        .get_position_asset_balance(user.position_id, asset_id_btc)
        .into();
    let balance_eth_after: i64 = state
        .facade
        .get_position_asset_balance(user.position_id, asset_id_eth)
        .into();

    // user: 100000 (BTC deposit) - 30000 (BTC withdraw) = 70000
    assert_eq!(balance_btc_after, 70000_i64);
    // user: 200000 (ETH deposit) - 50000 (ETH withdraw) = 150000
    assert_eq!(balance_eth_after, 150000_i64);
}

#[test]
#[should_panic(expected: "POSITION_NOT_HEALTHY_NOR_HEALTHIER")]
fn test_spot_collateral_deposit_buy_synthetic_transfer_then_withdraw_fails() {
    // Setup.
    let risk_factor_data = RiskFactorTiers {
        tiers: array![10].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    // Create BTC spot collateral asset.
    let token = snforge_std::Token::STRK;
    let erc20_contract_address = token.contract_address();
    let asset_info_btc = AssetInfoTrait::new_collateral(
        asset_name: 'BTC', :risk_factor_data, oracles_len: 1, :erc20_contract_address,
    );
    let asset_id_btc = asset_info_btc.asset_id;
    state.facade.add_active_collateral(asset_info: @asset_info_btc, initial_price: 100);

    // Create synthetic asset.
    let synthetic_info = AssetInfoTrait::new(
        asset_name: 'ETH_PERP', :risk_factor_data, oracles_len: 1,
    );
    let synthetic_id = synthetic_info.asset_id;
    state.facade.add_active_synthetic(synthetic_info: @synthetic_info, initial_price: 100);

    // Create users. user_2 shares user_1's owner so the BTC spot transfer below is same-owner;
    // it still acts as an independent trade counterparty (trades are not owner-restricted).
    let user_1 = state.new_user_with_position();
    let user_2 = state.new_sibling_position(user_1);
    snforge_std::set_balance(target: user_1.account.address, new_balance: 5000000, :token);

    // Deposit 2 BTC spot collateral to user_1.
    // This allows us to transfer 1 unit BTC later.
    let deposit_info_btc = state
        .facade
        .deposit_spot(
            depositor: user_1.account,
            asset_id: asset_id_btc,
            position_id: user_1.position_id,
            quantized_amount: 2,
        );
    state.facade.process_deposit(deposit_info: deposit_info_btc);

    // Deposit base collateral to user_2 for trading.
    let deposit_info_user_2 = state
        .facade
        .deposit(
            depositor: user_2.account, position_id: user_2.position_id, quantized_amount: 100000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_user_2);

    // Create orders to buy synthetic asset.
    // user_1 buys 1 synthetic for 100 (quote) = 100 total cost
    // This will make base collateral negative: -100.
    // Total value remains similar: BTC value (200) + synthetic value (100) - 100 usdc = ~200
    let order_user_1 = state
        .facade
        .create_order(
            user: user_1,
            base_amount: 1,
            base_asset_id: synthetic_id,
            quote_amount: -100,
            fee_amount: 0,
        );

    let order_user_2 = state
        .facade
        .create_order(
            user: user_2,
            base_amount: -1,
            base_asset_id: synthetic_id,
            quote_amount: 100,
            fee_amount: 0,
        );

    // Make trade - user_1 buys synthetic asset.
    // Position now has: negative base collateral (-100), BTC spot (2), synthetic (1)
    state
        .facade
        .trade(
            order_info_a: order_user_1,
            order_info_b: order_user_2,
            base: 1,
            quote: -100,
            fee_a: 0,
            fee_b: 0,
        );

    // Transfer 1 BTC - should succeed.
    let transfer_info = state
        .facade
        .transfer_spot_request(
            sender: user_1, recipient: user_2, asset_id: asset_id_btc, amount: 1,
        );
    state.facade.transfer(:transfer_info);

    // User_1 still has 1 BTC remaining.
    assert_eq!(
        state.facade.get_position_asset_balance(user_1.position_id, asset_id_btc), 1_u64.into(),
    );

    // Now try to withdraw the remaining 1 BTC - should fail because position would
    // become unhealthy.
    let withdraw_info = state
        .facade
        .withdraw_spot_request(user: user_1, asset_id: asset_id_btc, amount: 1);
    state.facade.withdraw(:withdraw_info);
}

#[test]
fn test_liquidate_spot_collateral_after_price_drop() {
    // Setup.
    let risk_factor_data = RiskFactorTiers {
        tiers: array![100].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    // Create a spot collateral asset.
    let token = snforge_std::Token::STRK;
    let erc20_contract_address = token.contract_address();
    let asset_info = AssetInfoTrait::new_collateral(
        asset_name: 'SPOT', :risk_factor_data, oracles_len: 1, :erc20_contract_address,
    );
    let asset_id = asset_info.asset_id;
    state.facade.add_active_collateral(asset_info: @asset_info, initial_price: 100);

    // Create users.
    let liquidated_user = state.new_user_with_position();
    let liquidator_user = state.new_user_with_position();
    snforge_std::set_balance(target: liquidated_user.account.address, new_balance: 5000000, :token);
    snforge_std::set_balance(target: liquidator_user.account.address, new_balance: 5000000, :token);

    // Deposit spot collateral to liquidated user.
    let deposit_info_liquidated = state
        .facade
        .deposit_spot(
            depositor: liquidated_user.account,
            :asset_id,
            position_id: liquidated_user.position_id,
            quantized_amount: 9800,
        );
    state.facade.process_deposit(deposit_info: deposit_info_liquidated);

    // Deposit base collateral to liquidator.
    let deposit_info_liquidator = state
        .facade
        .deposit(
            depositor: liquidator_user.account,
            position_id: liquidator_user.position_id,
            quantized_amount: 200000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_liquidator);

    // Create negative base collateral for liquidated user via transfer.
    state.drain_collateral(liquidated_user, 9500);

    // Position state after transfer (at price = 100):
    // Balances:
    //   - Base collateral: -9500 (negative from transfer)
    //   - Spot collateral: 9800 units (at price 100)
    // Calculations:
    //   TV = base_collateral + spot_collateral * spot_price - spot_risk
    //      = -9500 + (9800 * 100) - 9800 * 100 * 0.1 = -9500 + 980000 - 98000 = 872500
    //   TR = 0 (spot has no risk)
    //   TV/TR = 872500 / 0 = inf (healthy, > 1)
    state
        .facade
        .validate_total_value(
            position_id: liquidated_user.position_id, expected_total_value: 872500,
        );
    state
        .facade
        .validate_total_risk(position_id: liquidated_user.position_id, expected_total_risk: 0);

    // Price drop makes position liquidatable.
    state.facade.price_tick(asset_info: @asset_info, price: 1);

    // Position state after price drop (at price = 1):
    // Balances:
    //   - Base collateral: -9500 (unchanged)
    //   - Spot collateral: 9800 units (at new price 1)
    // Calculations:
    //   TV = base_collateral + spot_collateral * spot_price - spot_risk
    //      = -9500 + (9800 * 1) - 980 = -9500 + 9800 - 980 = -680
    //   TR = 0
    //   TV/TR = -680 / 0 = -inf (liquidatable, < 1)
    state
        .facade
        .validate_total_value(position_id: liquidated_user.position_id, expected_total_value: -680);
    state
        .facade
        .validate_total_risk(position_id: liquidated_user.position_id, expected_total_risk: 0);

    assert(
        state.facade.is_liquidatable(position_id: liquidated_user.position_id),
        'user is not liquidatable',
    );

    // Create liquidator order.
    let liquidator_order_info = state
        .facade
        .create_limit_order(
            user: liquidator_user,
            base_asset_id: asset_id,
            base_amount: 9500,
            quote_amount: -9600,
            fee_amount: 100,
            receive_position_id: Option::None,
        );

    // Liquidate spot asset.
    state
        .facade
        .liquidate_spot_asset(
            :liquidated_user,
            :liquidator_order_info,
            actual_amount_spot_collateral: -9500,
            actual_amount_base_collateral: 9600,
            actual_liquidator_fee: 100,
            liquidated_fee_amount: 100,
        );

    // Position state after liquidation (at price = 1):
    // Liquidation changes:
    //   - Spot collateral: 9800 - 9500 = 300 units (transferred to liquidator)
    //   - Base collateral: -9500 + 9600 - 100(fee) = 0 (received from liquidator)
    // Balances:
    //   - Base collateral: 0
    //   - Spot collateral: 300 units (at price 1)
    // Calculations:
    //   TV = base_collateral + spot_collateral * spot_price
    //      = 0 + (300 * 1) = 300
    //   TR = |spot_collateral * spot_price| * risk_factor
    //      = |300 * 1| * 0.1 = 300 * 0.1 = 30
    //   TV/TR = 300 / 30 = 10 (healthy, > 1)
    state
        .facade
        .validate_total_value(position_id: liquidated_user.position_id, expected_total_value: 270);
    state
        .facade
        .validate_total_risk(position_id: liquidated_user.position_id, expected_total_risk: 0);

    assert(state.facade.is_healthy(position_id: liquidated_user.position_id), 'should be healthy');
}

#[test]
fn test_liquidate_spot_collateral_multiple_steps() {
    // Setup.
    let risk_factor_data = RiskFactorTiers {
        tiers: array![100].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    // Create a spot collateral asset.
    let token = snforge_std::Token::STRK;
    let erc20_contract_address = token.contract_address();
    let asset_info = AssetInfoTrait::new_collateral(
        asset_name: 'SPOT', :risk_factor_data, oracles_len: 1, :erc20_contract_address,
    );
    let asset_id = asset_info.asset_id;
    state.facade.add_active_collateral(asset_info: @asset_info, initial_price: 100);

    // Create users.
    let liquidated_user = state.new_user_with_position();
    let liquidator_user = state.new_user_with_position();
    snforge_std::set_balance(target: liquidated_user.account.address, new_balance: 5000000, :token);
    snforge_std::set_balance(target: liquidator_user.account.address, new_balance: 5000000, :token);

    // Deposit spot collateral to liquidated user.
    let deposit_info_liquidated = state
        .facade
        .deposit_spot(
            depositor: liquidated_user.account,
            :asset_id,
            position_id: liquidated_user.position_id,
            quantized_amount: 9800,
        );
    state.facade.process_deposit(deposit_info: deposit_info_liquidated);

    // Deposit base collateral to liquidator.
    let deposit_info_liquidator = state
        .facade
        .deposit(
            depositor: liquidator_user.account,
            position_id: liquidator_user.position_id,
            quantized_amount: 200000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_liquidator);

    // Create negative base collateral for liquidated user.
    state.drain_collateral(liquidated_user, 9500);

    // Price drop makes position liquidatable.
    state.facade.price_tick(asset_info: @asset_info, price: 1);

    assert(
        state.facade.is_liquidatable(position_id: liquidated_user.position_id),
        'user is not liquidatable',
    );

    // First liquidation step.
    let liquidator_order_info_1 = state
        .facade
        .create_limit_order(
            user: liquidator_user,
            base_asset_id: asset_id,
            base_amount: 4750,
            quote_amount: -4800,
            fee_amount: 50,
            receive_position_id: Option::None,
        );

    state
        .facade
        .liquidate_spot_asset(
            :liquidated_user,
            liquidator_order_info: liquidator_order_info_1,
            actual_amount_spot_collateral: -4750,
            actual_amount_base_collateral: 4800,
            actual_liquidator_fee: 50,
            liquidated_fee_amount: 50,
        );

    // Position still liquidatable.
    assert(
        state.facade.is_liquidatable(position_id: liquidated_user.position_id),
        'still liquidatable',
    );

    // Second liquidation step.
    let liquidator_order_info_2 = state
        .facade
        .create_limit_order(
            user: liquidator_user,
            base_asset_id: asset_id,
            base_amount: 4750,
            quote_amount: -4800,
            fee_amount: 50,
            receive_position_id: Option::None,
        );

    state
        .facade
        .liquidate_spot_asset(
            :liquidated_user,
            liquidator_order_info: liquidator_order_info_2,
            actual_amount_spot_collateral: -4750,
            actual_amount_base_collateral: 4800,
            actual_liquidator_fee: 50,
            liquidated_fee_amount: 50,
        );

    // Position now healthy.
    assert(state.facade.is_healthy(position_id: liquidated_user.position_id), 'should be healthy');
}

#[test]
#[should_panic(expected: 'INVALID_ASSET_TYPE')]
fn test_liquidate_spot_not_spot_asset() {
    // Setup.
    let risk_factor_data = RiskFactorTiers {
        tiers: array![100].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    // Create synthetic asset (not spot).
    let synthetic_info = AssetInfoTrait::new(asset_name: 'BTC', :risk_factor_data, oracles_len: 1);
    let synthetic_id = synthetic_info.asset_id;
    state.facade.add_active_synthetic(synthetic_info: @synthetic_info, initial_price: 100);

    // Create users.
    let liquidated_user = state.new_user_with_position();
    let liquidator_user = state.new_user_with_position();

    // Deposit to users.
    let deposit_info_liquidator = state
        .facade
        .deposit(
            depositor: liquidator_user.account,
            position_id: liquidator_user.position_id,
            quantized_amount: 100000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_liquidator);

    // Try to liquidate synthetic asset as spot - should fail.
    let liquidator_order_info = state
        .facade
        .create_limit_order(
            user: liquidator_user,
            base_asset_id: synthetic_id,
            base_amount: 1,
            quote_amount: -100,
            fee_amount: 1,
            receive_position_id: Option::None,
        );

    state
        .facade
        .liquidate_spot_asset(
            :liquidated_user,
            liquidator_order_info: liquidator_order_info,
            actual_amount_spot_collateral: -1,
            actual_amount_base_collateral: 100,
            actual_liquidator_fee: 1,
            liquidated_fee_amount: 1,
        );
}

#[test]
fn test_liquidate_spot_exact_position_amount() {
    // Test liquidating exactly the full spot collateral amount in the position.
    // Setup.
    let risk_factor_data = RiskFactorTiers {
        tiers: array![100].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    // Create a spot collateral asset.
    let token = snforge_std::Token::STRK;
    let erc20_contract_address = token.contract_address();
    let asset_info = AssetInfoTrait::new_collateral(
        asset_name: 'SPOT', :risk_factor_data, oracles_len: 1, :erc20_contract_address,
    );
    let asset_id = asset_info.asset_id;
    state.facade.add_active_collateral(asset_info: @asset_info, initial_price: 100);

    // Create users.
    let liquidated_user = state.new_user_with_position();
    let liquidator_user = state.new_user_with_position();
    snforge_std::set_balance(target: liquidated_user.account.address, new_balance: 5000000, :token);
    snforge_std::set_balance(target: liquidator_user.account.address, new_balance: 5000000, :token);

    // Deposit spot collateral to liquidated user.
    let deposit_info_liquidated = state
        .facade
        .deposit_spot(
            depositor: liquidated_user.account,
            :asset_id,
            position_id: liquidated_user.position_id,
            quantized_amount: 10000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_liquidated);

    // Deposit base collateral to liquidator.
    let deposit_info_liquidator = state
        .facade
        .deposit(
            depositor: liquidator_user.account,
            position_id: liquidator_user.position_id,
            quantized_amount: 200000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_liquidator);

    // Create negative base collateral for liquidated user via transfer.
    // At price 100: TV = -9700 + 10000*100 = 990300, TR = 10000*100*0.1 = 100000, ratio = 9.9
    // (healthy)
    state.drain_collateral(liquidated_user, 9700);

    // Price drop makes position liquidatable.
    // At price 1: TV = -9700 + 10000*1 = 300, TR = 10000*1*0.1 = 1000, ratio = 0.3 (liquidatable)
    state.facade.price_tick(asset_info: @asset_info, price: 1);

    assert(
        state.facade.is_liquidatable(position_id: liquidated_user.position_id),
        'user is not liquidatable',
    );

    // Create liquidator order for EXACTLY the full spot asset amount.
    let liquidator_order_info = state
        .facade
        .create_limit_order(
            user: liquidator_user,
            base_asset_id: asset_id,
            base_amount: 10000, // Exactly the full spot collateral balance
            quote_amount: -10000,
            fee_amount: 100,
            receive_position_id: Option::None,
        );

    // Liquidate exactly the full spot asset.
    state
        .facade
        .liquidate_spot_asset(
            :liquidated_user,
            liquidator_order_info: liquidator_order_info,
            actual_amount_spot_collateral: -10000, // Exactly the full amount
            actual_amount_base_collateral: 10000,
            actual_liquidator_fee: 100,
            liquidated_fee_amount: 100,
        );

    // Position should have zero spot collateral now.
    state
        .facade
        .validate_asset_balance(
            position_id: liquidated_user.position_id,
            asset_id: asset_id,
            expected_balance: 0_i64.into(),
        );

    // Position state after liquidation:
    // TV = -9700 + 10000 - 100 = 200 (positive, healthy)
    // TR = 0 (no assets)
    state
        .facade
        .validate_total_value(position_id: liquidated_user.position_id, expected_total_value: 200);
    state
        .facade
        .validate_total_risk(position_id: liquidated_user.position_id, expected_total_risk: 0);

    assert(state.facade.is_healthy(position_id: liquidated_user.position_id), 'should be healthy');
}

#[test]
fn test_liquidate_to_empty_position() {
    // Test liquidating to an empty position.
    // Setup.
    let risk_factor_data = RiskFactorTiers {
        tiers: array![100].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    // Create a spot collateral asset.
    let token = snforge_std::Token::STRK;
    let erc20_contract_address = token.contract_address();
    let asset_info = AssetInfoTrait::new_collateral(
        asset_name: 'SPOT', :risk_factor_data, oracles_len: 1, :erc20_contract_address,
    );
    let asset_id = asset_info.asset_id;
    state.facade.add_active_collateral(asset_info: @asset_info, initial_price: 100);

    // Create users.
    let liquidated_user = state.new_user_with_position();
    let liquidator_user = state.new_user_with_position();
    snforge_std::set_balance(target: liquidated_user.account.address, new_balance: 5000000, :token);
    snforge_std::set_balance(target: liquidator_user.account.address, new_balance: 5000000, :token);

    // Deposit spot collateral to liquidated user.
    let deposit_info_liquidated = state
        .facade
        .deposit_spot(
            depositor: liquidated_user.account,
            :asset_id,
            position_id: liquidated_user.position_id,
            quantized_amount: 10000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_liquidated);

    // Deposit base collateral to liquidator.
    let deposit_info_liquidator = state
        .facade
        .deposit(
            depositor: liquidator_user.account,
            position_id: liquidator_user.position_id,
            quantized_amount: 200000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_liquidator);

    // Create negative base collateral for liquidated user via transfer.
    // At price 100: TV = -10000 + 10000*100 = 990000, TR = 10000*100*0.1 = 100000, ratio = 9.9
    // (healthy)
    state.drain_collateral(liquidated_user, 10000);

    // Price drop makes position liquidatable.
    // At price 1: TV = -10000 + 10000*1 = 0, TR = 10000*1*0.1 = 1000, (liquidatable)
    state.facade.price_tick(asset_info: @asset_info, price: 1);

    assert(
        state.facade.is_liquidatable(position_id: liquidated_user.position_id),
        'user is not liquidatable',
    );

    // Create liquidator order for EXACTLY the full spot asset amount.
    let liquidator_order_info = state
        .facade
        .create_limit_order(
            user: liquidator_user,
            base_asset_id: asset_id,
            base_amount: 10000, // Exactly the full spot collateral balance
            quote_amount: -10000,
            fee_amount: 100,
            receive_position_id: Option::None,
        );

    // Liquidate exactly the full spot asset.
    state
        .facade
        .liquidate_spot_asset(
            :liquidated_user,
            liquidator_order_info: liquidator_order_info,
            actual_amount_spot_collateral: -10000, // Exactly the full amount
            actual_amount_base_collateral: 10000,
            actual_liquidator_fee: 100,
            liquidated_fee_amount: 0,
        );

    // Position should have zero spot collateral now.
    state
        .facade
        .validate_asset_balance(
            position_id: liquidated_user.position_id,
            asset_id: asset_id,
            expected_balance: 0_i64.into(),
        );

    // Position state after liquidation:
    // TV = -10000 + 10000 - 100 = 0
    // TR = 0 (no assets)
    // TV = TR = 0 (healthy)
    state
        .facade
        .validate_total_value(position_id: liquidated_user.position_id, expected_total_value: 0);
    state
        .facade
        .validate_total_risk(position_id: liquidated_user.position_id, expected_total_risk: 0);

    assert(state.facade.is_healthy(position_id: liquidated_user.position_id), 'should be healthy');
}

#[test]
#[should_panic(expected: 'INVALID_QUOTE_FEE_AMOUNT')]
fn test_liquidate_spot_very_small_amount() {
    // Test liquidating a very small amount fails due to invalid quote/fee ratio validation.
    // Setup.
    let risk_factor_data = RiskFactorTiers {
        tiers: array![100].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    // Create a spot collateral asset.
    let token = snforge_std::Token::STRK;
    let erc20_contract_address = token.contract_address();
    let asset_info = AssetInfoTrait::new_collateral(
        asset_name: 'SPOT', :risk_factor_data, oracles_len: 1, :erc20_contract_address,
    );
    let asset_id = asset_info.asset_id;
    state.facade.add_active_collateral(asset_info: @asset_info, initial_price: 100);

    // Create users.
    let liquidated_user = state.new_user_with_position();
    let liquidator_user = state.new_user_with_position();
    snforge_std::set_balance(target: liquidated_user.account.address, new_balance: 5000000, :token);
    snforge_std::set_balance(target: liquidator_user.account.address, new_balance: 5000000, :token);

    // Deposit spot collateral to liquidated user.
    let deposit_info_liquidated = state
        .facade
        .deposit_spot(
            depositor: liquidated_user.account,
            :asset_id,
            position_id: liquidated_user.position_id,
            quantized_amount: 2000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_liquidated);

    // Deposit base collateral to liquidator.
    let deposit_info_liquidator = state
        .facade
        .deposit(
            depositor: liquidator_user.account,
            position_id: liquidator_user.position_id,
            quantized_amount: 200000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_liquidator);

    // Create negative base collateral for liquidated user via transfer.
    state.drain_collateral(liquidated_user, 1900);

    // Price drop makes position liquidatable.
    // At price 1: TV = -1900 + 2000*1 = 100, TR = 2000*1*0.1 = 200, ratio = 0.5 (liquidatable)
    state.facade.price_tick(asset_info: @asset_info, price: 1);

    assert(
        state.facade.is_liquidatable(position_id: liquidated_user.position_id),
        'user is not liquidatable',
    );

    // Create liquidator order for a VERY SMALL amount (1 unit) with high fee.
    // This should FAIL because fee (100) > collateral received (2), making TV worse
    let liquidator_order_info = state
        .facade
        .create_limit_order(
            user: liquidator_user,
            base_asset_id: asset_id,
            base_amount: 1, // Very small amount
            quote_amount: -2,
            fee_amount: 1,
            receive_position_id: Option::None,
        );

    // This should pass: TV_before = 100, TV_after = -1900 + 2 - 1 + 1999*1 = 100
    state
        .facade
        .liquidate_spot_asset(
            :liquidated_user,
            liquidator_order_info: liquidator_order_info,
            actual_amount_spot_collateral: -1, // Very small amount
            actual_amount_base_collateral: 2,
            actual_liquidator_fee: 1,
            liquidated_fee_amount: 1 // Large fee makes it worse!
        );

    // This should fail: TV_before = 100, TR_before = 199.9
    // TV_after = -1900 + 2 - 2 + 1998*1 = 98, TR_after = 1998*1*0.1 = 199.8
    // TV_after / TR_after = 98 / 199.8 = 0.4905 < TV_before / TR_before = 100 / 199.9 = 0.5005
    // This is not healthier.
    state
        .facade
        .liquidate_spot_asset(
            :liquidated_user,
            liquidator_order_info: liquidator_order_info,
            actual_amount_spot_collateral: -1,
            actual_amount_base_collateral: 2,
            actual_liquidator_fee: 2,
            liquidated_fee_amount: 2,
        );
}

#[test]
#[should_panic(expected: 'INVALID_ASSET_TYPE')]
fn test_liquidate_spot_for_vault_share_asset() {
    // Test that liquidate_spot_asset fails when trying to liquidate a vault share asset.
    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    // Create vault.
    let vault_user = state.new_user_with_position();
    let vault_init_deposit = state
        .facade
        .deposit(vault_user.account, vault_user.position_id, 5000_u64);
    state.facade.process_deposit(vault_init_deposit);
    let vault_config = state.facade.register_vault_share_spot_asset(vault_user, asset_name: 'VS_1');
    state.facade.price_tick(@vault_config.asset_info, 1);

    // Create users.
    let liquidated_user = state.new_user_with_position();
    let liquidator_user = state.new_user_with_position();

    // Deposit base collateral to liquidator.
    let deposit_info_liquidator = state
        .facade
        .deposit(
            depositor: liquidator_user.account,
            position_id: liquidator_user.position_id,
            quantized_amount: 100000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_liquidator);

    // Try to liquidate vault share asset using liquidate_spot_asset - should fail.
    let liquidator_order_info = state
        .facade
        .create_limit_order(
            user: liquidator_user,
            base_asset_id: vault_config.asset_id,
            base_amount: 100,
            quote_amount: -100,
            fee_amount: 1,
            receive_position_id: Option::None,
        );

    state
        .facade
        .liquidate_spot_asset(
            :liquidated_user,
            liquidator_order_info: liquidator_order_info,
            actual_amount_spot_collateral: -100,
            actual_amount_base_collateral: 100,
            actual_liquidator_fee: 1,
            liquidated_fee_amount: 1,
        );
}

#[test]
fn test_liquidate_spot_with_different_source_and_receive_positions() {
    // Test that spot liquidation works when the liquidator order has different
    // source_position (paying base collateral) and receive_position (receiving spot assets).
    let risk_factor_data = RiskFactorTiers {
        tiers: array![100].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    // Create a spot collateral asset.
    let token = snforge_std::Token::STRK;
    let erc20_contract_address = token.contract_address();
    let asset_info = AssetInfoTrait::new_collateral(
        asset_name: 'SPOT', :risk_factor_data, oracles_len: 1, :erc20_contract_address,
    );
    let asset_id = asset_info.asset_id;
    state.facade.add_active_collateral(asset_info: @asset_info, initial_price: 100);

    // Create users.
    let liquidated_user = state.new_user_with_position();
    let liquidator_source_user = state.new_user_with_position(); // Pays base collateral
    let liquidator_receive_user = state.new_user_with_position(); // Receives spot collateral
    snforge_std::set_balance(target: liquidated_user.account.address, new_balance: 5000000, :token);

    // Deposit spot collateral to liquidated user.
    let deposit_info_liquidated = state
        .facade
        .deposit_spot(
            depositor: liquidated_user.account,
            :asset_id,
            position_id: liquidated_user.position_id,
            quantized_amount: 9800,
        );
    state.facade.process_deposit(deposit_info: deposit_info_liquidated);

    // Deposit base collateral to liquidator source position.
    let deposit_info_liquidator = state
        .facade
        .deposit(
            depositor: liquidator_source_user.account,
            position_id: liquidator_source_user.position_id,
            quantized_amount: 200000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_liquidator);

    // Create negative base collateral for liquidated user via transfer.
    state.drain_collateral(liquidated_user, 9500);

    // Position state after transfer (at price = 100):
    // TV = -9500 + (9800 * 100) - 9800 * 100 *  0.1 = 872500
    // TR = 0
    // TV/TR = 9.9 (healthy)
    state
        .facade
        .validate_total_value(
            position_id: liquidated_user.position_id, expected_total_value: 872500,
        );
    state
        .facade
        .validate_total_risk(position_id: liquidated_user.position_id, expected_total_risk: 0);

    // Price drop makes position liquidatable.
    state.facade.price_tick(asset_info: @asset_info, price: 1);

    // Position state after price drop (at price = 1):
    // TV = -9500 + (9800 * 1) - 9800 * 1 * 0.1 = -680
    // TR = 9800 * 1 * 0.1 = 980
    // TV/TR = 0.306 (liquidatable)
    state
        .facade
        .validate_total_value(position_id: liquidated_user.position_id, expected_total_value: -680);
    state
        .facade
        .validate_total_risk(position_id: liquidated_user.position_id, expected_total_risk: 0);

    assert(
        state.facade.is_liquidatable(position_id: liquidated_user.position_id),
        'user is not liquidatable',
    );

    // Create liquidator order with different source and receive positions.
    let liquidator_order_info = state
        .facade
        .create_limit_order(
            user: liquidator_source_user,
            base_asset_id: asset_id,
            base_amount: 9500,
            quote_amount: -9600,
            fee_amount: 100,
            receive_position_id: Option::Some(liquidator_receive_user.position_id),
        );

    // Record balances before liquidation.
    let source_balance_before: i64 = state
        .facade
        .get_position_collateral_balance(liquidator_source_user.position_id)
        .into();
    let receive_spot_balance_before: i64 = state
        .facade
        .get_position_asset_balance(liquidator_receive_user.position_id, asset_id)
        .into();

    // Liquidate spot asset.
    state
        .facade
        .liquidate_spot_asset(
            :liquidated_user,
            liquidator_order_info: liquidator_order_info,
            actual_amount_spot_collateral: -9500,
            actual_amount_base_collateral: 9600,
            actual_liquidator_fee: 100,
            liquidated_fee_amount: 100,
        );

    // Verify source position paid base collateral.
    // source_balance: 200000 - 9600 - 100 (fee) = 190300
    let source_balance_after: i64 = state
        .facade
        .get_position_collateral_balance(liquidator_source_user.position_id)
        .into();
    assert_eq!(source_balance_after, source_balance_before - 9600 - 100);

    // Verify receive position got spot collateral.
    // receive_spot_balance: 0 + 9500 = 9500
    let receive_spot_balance_after: i64 = state
        .facade
        .get_position_asset_balance(liquidator_receive_user.position_id, asset_id)
        .into();
    assert_eq!(receive_spot_balance_after, receive_spot_balance_before + 9500);

    // Verify liquidated position state after liquidation (at price = 1):
    // Spot collateral: 9800 - 9500 = 300
    // Base collateral: -9500 + 9600 - 100(fee) = 0
    // TV = 0 + (300 * 1) - 300 * 1 * 0.1 = 270
    // TR = 0
    // TV/TR = 10 (healthy)
    state
        .facade
        .validate_total_value(position_id: liquidated_user.position_id, expected_total_value: 270);
    state
        .facade
        .validate_total_risk(position_id: liquidated_user.position_id, expected_total_risk: 0);

    assert(state.facade.is_healthy(position_id: liquidated_user.position_id), 'should be healthy');
}

#[test]
#[should_panic(expected: "INVALID_INTEREST_RATE position_id: PositionId { value: 101 }")]
fn test_apply_interest_to_position_with_zero_balance() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let user_1 = state.new_user_with_position();
    let user_2 = state.new_user_with_position();

    let BALANCE = 10_000;

    // Deposit some collateral
    let deposit_info = state
        .facade
        .deposit(
            depositor: user_1.account, position_id: user_1.position_id, quantized_amount: BALANCE,
        );
    state.facade.process_deposit(deposit_info: deposit_info);

    // Test uninitialized positions.
    snforge_std::interact_with_state(
        state.facade.perpetuals_contract,
        || {
            let mut state = perpetuals::core::core::Core::contract_state_for_testing();

            state
                .positions
                .positions
                .entry(user_1.position_id)
                .last_interest_applied_time
                .write(Timestamp { seconds: 0 });
            state
                .positions
                .positions
                .entry(user_2.position_id)
                .last_interest_applied_time
                .write(Timestamp { seconds: 0 });
        },
    );

    // Apply zero interest to position with balance (first time, timestamp is zero)
    let position_interest_amounts = array![(user_1.position_id, 0)].span();
    state.facade.apply_interests(:position_interest_amounts);

    // Advance time by 1 hour
    state.facade.advance_time(seconds: HOUR);

    let position_interest_amounts = array![(user_1.position_id, 100), (user_2.position_id, 100)]
        .span();
    state.facade.apply_interests(:position_interest_amounts);
}

#[test]
fn test_apply_interest_to_multiple_positions() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let user_a = state.new_user_with_position();
    let user_b = state.new_user_with_position();

    // Deposit collateral to both users
    let deposit_info_a = state
        .facade
        .deposit(
            depositor: user_a.account, position_id: user_a.position_id, quantized_amount: 10_000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_a);

    let deposit_info_b = state
        .facade
        .deposit(
            depositor: user_b.account, position_id: user_b.position_id, quantized_amount: 5_000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_b);

    // Advance time by 1 hour
    state.facade.advance_time(seconds: HOUR);

    // Calculate valid interest amounts for both positions
    let balance_a: u128 = 10_000;
    let balance_b: u128 = 5_000;
    let time_diff: u128 = HOUR.into();
    let max_rate: u128 = 1200;
    let scale: u128 = 2_u128.pow(32);
    let max_allowed_a: u128 = (balance_a * time_diff * max_rate) / scale;
    let max_allowed_b: u128 = (balance_b * time_diff * max_rate) / scale;

    // Apply valid interest to both positions
    let interest_a: i64 = (max_allowed_a / 2).try_into().unwrap();
    let interest_b: i64 = (max_allowed_b / 2).try_into().unwrap();
    let position_interest_amounts = array![
        (user_a.position_id, interest_a), (user_b.position_id, interest_b),
    ]
        .span();
    state.facade.apply_interests(:position_interest_amounts);

    // Validate balances
    let expected_balance_a: i64 = 10_000 + interest_a;
    let expected_balance_b: i64 = 5_000 + interest_b;
    state.facade.validate_collateral_balance(user_a.position_id, expected_balance_a.into());
    state.facade.validate_collateral_balance(user_b.position_id, expected_balance_b.into());
}

#[test]
#[should_panic(expected: "INVALID_INTEREST_RATE position_id: PositionId { value: 101 }")]
fn test_apply_interest_exceeds_max_rate() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let user = state.new_user_with_position();

    // Deposit collateral
    let deposit_info = state
        .facade
        .deposit(depositor: user.account, position_id: user.position_id, quantized_amount: 10_000);
    state.facade.process_deposit(deposit_info: deposit_info);

    // Advance time by 1 hour
    state.facade.advance_time(seconds: HOUR);

    // Calculate max allowed interest
    let balance: u128 = 10_000;
    let time_diff: u128 = HOUR.into();
    let max_rate: u128 = 1200;
    let scale: u128 = 2_u128.pow(32);
    let max_allowed: u128 = (balance * time_diff * max_rate) / scale;

    // Try to apply interest that exceeds max rate
    let invalid_interest: i64 = (max_allowed + 1).try_into().unwrap();
    let position_interest_amounts = array![(user.position_id, invalid_interest)].span();
    state.facade.apply_interests(:position_interest_amounts);
}

#[test]
#[should_panic(expected: "INVALID_INTEREST_RATE position_id: PositionId { value: 101 }")]
fn test_apply_non_zero_interest_to_zero_balance() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let user = state.new_user_with_position();

    // Don't deposit anything, pnl is zero.

    // Try to apply non-zero interest to zero balance (first time)
    let position_interest_amounts = array![(user.position_id, 100)].span();
    state.facade.apply_interests(:position_interest_amounts);
}

#[test]
fn test_apply_negative_interest() {
    let risk_factor_data = RiskFactorTiers {
        tiers: array![10].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let synthetic_info = AssetInfoTrait::new(
        asset_name: 'BTC_1', :risk_factor_data, oracles_len: 1,
    );
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let user = state.new_user_with_negative_collateral(synthetic_info: @synthetic_info);

    state.facade.validate_collateral_balance(user.position_id, (-10_000_i64).into());
    state.facade.advance_time(seconds: HOUR);

    // Negative-balance position pays interest (negative amount).
    let position_interest_amounts = array![(user.position_id, -1_i64)].span();
    state.facade.apply_interests(:position_interest_amounts);

    state.facade.validate_collateral_balance(user.position_id, (-10_001_i64).into());
}

#[test]
fn test_apply_interest_sequential_updates() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let user = state.new_user_with_position();

    // Deposit collateral
    let deposit_info = state
        .facade
        .deposit(depositor: user.account, position_id: user.position_id, quantized_amount: 10_000);
    state.facade.process_deposit(deposit_info: deposit_info);

    // Advance time by 1 hour
    state.facade.advance_time(seconds: HOUR);

    // Calculate and apply first interest
    let balance: u128 = 10_000;
    let time_diff: u128 = HOUR.into();
    let max_rate: u128 = 1200;
    let scale: u128 = 2_u128.pow(32);
    let max_allowed: u128 = (balance * time_diff * max_rate) / scale;
    let interest_1: i64 = (max_allowed / 2).try_into().unwrap();
    let position_interest_amounts = array![(user.position_id, interest_1)].span();
    state.facade.apply_interests(:position_interest_amounts);

    let balance_after_first: i64 = 10_000 + interest_1;
    state.facade.validate_collateral_balance(user.position_id, balance_after_first.into());

    // Advance time by another hour
    state.facade.advance_time(seconds: HOUR);

    // Calculate and apply second interest (based on new balance)
    let new_balance: u128 = balance_after_first.try_into().unwrap();
    let max_allowed_2: u128 = (new_balance * time_diff * max_rate) / scale;
    let interest_2: i64 = (max_allowed_2 / 2).try_into().unwrap();
    let position_interest_amounts = array![(user.position_id, interest_2)].span();
    state.facade.apply_interests(:position_interest_amounts);

    let expected_final_balance: i64 = balance_after_first + interest_2;
    state.facade.validate_collateral_balance(user.position_id, expected_final_balance.into());
}

#[test]
#[should_panic(expected: "INVALID_INTEREST_RATE position_id: PositionId { value: 101 }")]
fn test_apply_interest_twice_without_advancing_time() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let user = state.new_user_with_position();

    // Deposit collateral
    let deposit_info = state
        .facade
        .deposit(depositor: user.account, position_id: user.position_id, quantized_amount: 10_000);
    state.facade.process_deposit(deposit_info: deposit_info);

    // Calculate and apply first interest
    let balance: u128 = 10_000;
    let time_diff: u128 = HOUR.into();
    let max_rate: u128 = 1200;
    let scale: u128 = 2_u128.pow(32);
    let max_allowed: u128 = (balance * time_diff * max_rate) / scale;
    let interest_1: i64 = (max_allowed / 2).try_into().unwrap();

    let position_interest_amounts = array![(user.position_id, interest_1)].span();
    state.facade.apply_interests(:position_interest_amounts);

    // Since time hasn't advanced, time_diff will be 0, so max_allowed_change will be 0
    // Any non-zero interest should fail with INVALID_INTEREST_RATE
    let position_interest_amounts = array![(user.position_id, interest_1)].span();
    state.facade.apply_interests(:position_interest_amounts);
}

#[test]
fn test_apply_zero_interest_does_not_update_last_time() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let user = state.new_user_with_position();

    let prev_time = snforge_std::interact_with_state(
        state.facade.perpetuals_contract,
        || {
            let mut state = perpetuals::core::core::Core::contract_state_for_testing();

            let prev_time = state
                .positions
                .positions
                .entry(user.position_id)
                .last_interest_applied_time
                .read();

            assert!(prev_time.is_non_zero());

            prev_time
        },
    );

    let position_interest_amounts = array![(user.position_id, 0)].span();
    state.facade.apply_interests(:position_interest_amounts);

    // Check last applied time wasnt changed.
    snforge_std::interact_with_state(
        state.facade.perpetuals_contract,
        || {
            let mut state = perpetuals::core::core::Core::contract_state_for_testing();

            let new_time = state
                .positions
                .positions
                .entry(user.position_id)
                .last_interest_applied_time
                .read();

            assert_eq!(prev_time, new_time);
        },
    );
}

#[test]
fn test_apply_interest_unhealthy_becomes_healthier_but_still_unhealthy() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    // Setup synthetic asset with risk factor
    let risk_factor_data = RiskFactorTiers {
        tiers: array![10].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let synthetic_info = AssetInfoTrait::new(
        asset_name: 'BTC_1', :risk_factor_data, oracles_len: 1,
    );
    let asset_id = synthetic_info.asset_id;
    state.facade.add_active_synthetic(synthetic_info: @synthetic_info, initial_price: 100);

    let user_a = state.new_user_with_position();
    let user_b = state.new_user_with_position();

    // Deposit collateral to both users
    state
        .facade
        .process_deposit(
            deposit_info: state
                .facade
                .deposit(
                    depositor: user_a.account,
                    position_id: user_a.position_id,
                    quantized_amount: 10_000,
                ),
        );

    state
        .facade
        .process_deposit(
            deposit_info: state
                .facade
                .deposit(
                    depositor: user_b.account,
                    position_id: user_b.position_id,
                    quantized_amount: 100_000,
                ),
        );

    // Trade: user_a SHORTS 200 BTC at price 100 (sign-rule-friendly inversion of the long case).
    // After trade: user_a collateral = 10_000 + 20_000 = 30_000, BTC = -200.
    // At price 100: TV = 30_000 + (-200)*100 = 10_000, TR = 200*100*0.1 = 2_000, ratio = 5
    // (healthy).
    let order_a = state
        .facade
        .create_order(
            user: user_a,
            base_amount: -300,
            base_asset_id: asset_id,
            quote_amount: 30_000,
            fee_amount: 23,
        );
    let order_b = state
        .facade
        .create_order(
            user: user_b,
            base_amount: 200,
            base_asset_id: asset_id,
            quote_amount: -20_000,
            fee_amount: 15,
        );
    state
        .facade
        .trade(
            order_info_a: order_a,
            order_info_b: order_b,
            base: -200,
            quote: 20_000,
            fee_a: 0,
            fee_b: 0,
        );

    // Price RISE makes the short unhealthy.
    state.facade.price_tick(asset_info: @synthetic_info, price: 200);

    // Now: TV = 30_000 + (-200)*200 = -10_000, TR = 200*200*0.1 = 4_000, ratio negative
    // (deleveragable).
    assert(
        state.facade.is_deleveragable(position_id: user_a.position_id),
        'user should be deleveragable',
    );

    // Advance time by 23 hours to allow larger interest amounts
    state.facade.advance_time(seconds: 23 * HOUR);

    // Positive collateral → receives interest (positive). New TV = -9_977, still deleveragable
    // but strictly less so → "healthy or healthier" check passes.
    let position_interest_amounts = array![(user_a.position_id, 23)].span();
    state.facade.apply_interests(:position_interest_amounts);

    // Verify position is still deleveragable but healthier
    assert(
        state.facade.is_deleveragable(position_id: user_a.position_id), 'should be liquidatable',
    );

    // Verify collateral balance increased by interest amount
    let expected_balance: i64 = 30_000 + 23;
    state.facade.validate_collateral_balance(user_a.position_id, expected_balance.into());
}

#[test]
#[should_panic(expected: "POSITION_NOT_HEALTHY_NOR_HEALTHIER")]
fn test_apply_interest_healthy_becomes_unhealthy_should_fail() {
    // Sign-rule-friendly reframe: helper user with negative collateral, 50% risk factor lands
    // TV exactly at TR (just healthy). A small negative interest pushes TV below TR.
    let risk_factor_data = RiskFactorTiers {
        tiers: array![500].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let synthetic_info = AssetInfoTrait::new(
        asset_name: 'BTC_1', :risk_factor_data, oracles_len: 1,
    );
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let user = state.new_user_with_negative_collateral(synthetic_info: @synthetic_info);

    state.facade.advance_time(seconds: HOUR);

    // Pre: TV=10000, TR=10000 (healthy). |PnL|=10000, max_allowed for HOUR ≈ 10.
    // -1 interest → TV=9999, TR=10000 → Liquidatable. Health check rejects.
    let position_interest_amounts = array![(user.position_id, -1_i64)].span();
    state.facade.apply_interests(:position_interest_amounts);
}

#[test]
#[should_panic(expected: 'INVALID_SHRINK_TO_NEGATIVE')]
fn test_withdraw_spot_collateral_negative_balance() {
    // Setup.
    let risk_factor_data = RiskFactorTiers {
        tiers: array![10].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    // Create a custom spot collateral asset.
    let token = snforge_std::Token::STRK;
    let erc20_contract_address = token.contract_address();
    let asset_info = AssetInfoTrait::new_collateral(
        asset_name: 'COL', :risk_factor_data, oracles_len: 1, :erc20_contract_address,
    );
    let asset_id = asset_info.asset_id;
    state.facade.add_active_collateral(asset_info: @asset_info, initial_price: 100);

    // Create user.
    let user = state.new_user_with_position();
    snforge_std::set_balance(target: user.account.address, new_balance: 5000000, :token);

    // Deposit base collateral (USDC) to ensure position stays healthy.
    // This ensures the position health validation passes and we hit the specific
    // spot balance validation we're testing.
    let deposit_info_base = state
        .facade
        .deposit(depositor: user.account, position_id: user.position_id, quantized_amount: 200000);
    state.facade.process_deposit(deposit_info: deposit_info_base);

    // Deposit 1000 units of spot collateral to user.
    let deposit_info_user = state
        .facade
        .deposit_spot(
            depositor: user.account,
            :asset_id,
            position_id: user.position_id,
            quantized_amount: 1000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_user);

    // Verify user has 1000 units of spot collateral.
    state
        .facade
        .validate_asset_balance(
            position_id: user.position_id, asset_id: asset_id, expected_balance: 1000_i64.into(),
        );

    // Attempt to withdraw 1500 units (more than available) - should panic with
    // INVALID_BASE_CHANGE.
    // The position has enough base collateral to stay healthy, so the validation
    // should fail specifically on the spot balance check.
    let withdraw_info = state.facade.withdraw_spot_request(:user, :asset_id, amount: 1500);
    state.facade.withdraw(:withdraw_info);
}

#[test]
#[should_panic(expected: 'NOT_TRANSFERABLE_ASSET')]
fn test_transfer_synthetic_asset_fails() {
    // Setup.
    let risk_factor_data = RiskFactorTiers {
        tiers: array![10].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let synthetic_info = AssetInfoTrait::new(
        asset_name: 'BTC_1', :risk_factor_data, oracles_len: 1,
    );
    let asset_id = synthetic_info.asset_id;

    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    state.facade.add_active_synthetic(synthetic_info: @synthetic_info, initial_price: 100);

    // Create users. user_2 shares user_1's owner so the transfer reaches the intended
    // NOT_TRANSFERABLE_ASSET check rather than the same-owner guard.
    let user_1 = state.new_user_with_position();
    let user_2 = state.new_sibling_position(user_1);

    // Deposit to users - give user_1 plenty of collateral to stay healthy.
    let deposit_info_user_1 = state
        .facade
        .deposit(
            depositor: user_1.account, position_id: user_1.position_id, quantized_amount: 100000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_user_1);

    let deposit_info_user_2 = state
        .facade
        .deposit(
            depositor: user_2.account, position_id: user_2.position_id, quantized_amount: 100000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_user_2);

    // Create orders to give user_1 a small synthetic position.
    let order_user_1 = state
        .facade
        .create_order(
            user: user_1,
            base_amount: 10,
            base_asset_id: asset_id,
            quote_amount: -1000,
            fee_amount: 0,
        );

    let order_user_2 = state
        .facade
        .create_order(
            user: user_2,
            base_amount: -10,
            base_asset_id: asset_id,
            quote_amount: 1000,
            fee_amount: 0,
        );

    // Make trade.
    // User 1 position: collateral = 99000, synthetic = 10
    // TV = 99000 + 10*100 = 100000, TR = 10*100*0.01 = 10, TV/TR = 10000 (very healthy)
    state
        .facade
        .trade(
            order_info_a: order_user_1,
            order_info_b: order_user_2,
            base: 10,
            quote: -1000,
            fee_a: 0,
            fee_b: 0,
        );

    // Verify user_1 is very healthy before attempting transfer.
    state
        .facade
        .validate_total_value(position_id: user_1.position_id, expected_total_value: 100000);
    state.facade.validate_total_risk(position_id: user_1.position_id, expected_total_risk: 10);

    // Try to transfer synthetic asset - should fail with NOT_TRANSFERABLE_ASSET
    // before any health checks.
    state
        .facade
        .transfer(
            transfer_info: state
                .facade
                .transfer_spot_request(sender: user_1, recipient: user_2, :asset_id, amount: 5),
        );
}

#[test]
#[should_panic(expected: 'INVALID_SHRINK_TO_NEGATIVE')]
fn test_transfer_spot_collateral_negative_balance_fails() {
    // Setup.
    let risk_factor_data = RiskFactorTiers {
        tiers: array![10].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    // Create a custom spot collateral asset.
    let token = snforge_std::Token::STRK;
    let erc20_contract_address = token.contract_address();
    let asset_info = AssetInfoTrait::new_collateral(
        asset_name: 'SPOT', :risk_factor_data, oracles_len: 1, :erc20_contract_address,
    );
    let asset_id = asset_info.asset_id;
    state.facade.add_active_collateral(asset_info: @asset_info, initial_price: 100);

    // Create users. user_2 shares user_1's owner so the transfer reaches the intended
    // INVALID_SHRINK_TO_NEGATIVE check rather than the same-owner guard.
    let user_1 = state.new_user_with_position();
    let user_2 = state.new_sibling_position(user_1);
    snforge_std::set_balance(target: user_1.account.address, new_balance: 5000000, :token);

    // User 1 deposits plenty of base collateral to ensure position stays healthy.
    let deposit_info_base = state
        .facade
        .deposit(
            depositor: user_1.account, position_id: user_1.position_id, quantized_amount: 200000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_base);

    // User 1 deposits only 1000 units of spot collateral.
    let deposit_info_spot = state
        .facade
        .deposit_spot(
            depositor: user_1.account,
            :asset_id,
            position_id: user_1.position_id,
            quantized_amount: 1000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_spot);

    // Position before transfer:
    // Base collateral: 200000
    // Spot collateral: 1000 (at price 100, value = 100000, with 0.01 risk factor, TR = 1000)
    // TV = 200000 + 100000 = 300000, TR = 1000, TV/TR = 300 (very healthy)

    // If we could transfer 1500 spot collateral (which we can't):
    // Base collateral: 200000 (unchanged)
    // Spot collateral: -500 (invalid!)
    // But hypothetically, TV = 200000 + (-500*100) = 150000, TR = 500*100*0.01 = 500
    // TV/TR = 300 (still very healthy if this were allowed)

    // Try to transfer more spot collateral than user_1 has - should fail with INVALID_BASE_CHANGE
    // before health check because balance would go negative.
    state
        .facade
        .transfer(
            transfer_info: state
                .facade
                .transfer_spot_request(sender: user_1, recipient: user_2, :asset_id, amount: 1500),
        );
}

#[test]
#[should_panic(expected: 'VAULT_CANNOT_HOLD_SHARES')]
fn test_protocol_vault_transfer_vault_shares_to_vault_position() {
    // Setup:
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let vault_user = state.new_user_with_position();
    // `user` shares vault_user's owner so the transfer reaches the intended
    // VAULT_CANNOT_HOLD_SHARES check rather than the same-owner guard.
    let user = state.new_sibling_position(vault_user);

    let vault_init_deposit = state
        .facade
        .deposit(vault_user.account, vault_user.position_id, 5000_u64);
    state.facade.process_deposit(vault_init_deposit);
    let user_init_deposit = state.facade.deposit(user.account, user.position_id, 5000_u64);
    state.facade.process_deposit(user_init_deposit);

    let vault_config = state.facade.register_vault_share_spot_asset(vault_user, asset_name: 'VS');

    state
        .facade
        .deposit_into_vault(
            vault: vault_config,
            amount_to_invest: 100,
            min_shares_to_receive: 100,
            depositing_user: user,
            receiving_user: user,
        );

    state
        .facade
        .transfer(
            transfer_info: state
                .facade
                .transfer_spot_request(
                    sender: user,
                    recipient: vault_user,
                    asset_id: vault_config.asset_id,
                    amount: 50,
                ),
        );
}

#[test]
#[should_panic(expected: "POSITION_NOT_HEALTHY_NOR_HEALTHIER")]
fn test_withdraw_with_negative_interest_becomes_unhealthy() {
    // Sign-rule-friendly reframe: helper gives the user negative USDC. Use a 50% risk factor on
    // BTC so the position lands at the TV=TR boundary; a small spot deposit makes it just
    // healthy; spot withdrawal + tiny negative interest pushes TV < TR.
    //
    // After helper (50% risk):     collateral=-10000, BTC=200@100. TV=10000, TR=10000 (healthy).
    // After spot deposit (2@100):  TV adds 200 - 200*0.5 = 100. TV=10100, TR=10000.
    // After withdraw 2 spot + -1 interest:
    //                              collateral=-10001, spot=0. TV=9999, TR=10000 → Liquidatable.
    let risk_factor_data = RiskFactorTiers {
        tiers: array![500].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let synthetic_info = AssetInfoTrait::new(
        asset_name: 'BTC_1', :risk_factor_data, oracles_len: 1,
    );
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let user = state.new_user_with_negative_collateral(synthetic_info: @synthetic_info);

    let token = snforge_std::Token::STRK;
    let erc20_contract_address = token.contract_address();
    let spot_info = AssetInfoTrait::new_collateral(
        asset_name: 'COL', :risk_factor_data, oracles_len: 1, :erc20_contract_address,
    );
    let asset_id = spot_info.asset_id;
    state.facade.add_active_collateral(asset_info: @spot_info, initial_price: 100);
    snforge_std::set_balance(target: user.account.address, new_balance: 5_000_000, :token);

    let deposit_info_user = state
        .facade
        .deposit_spot(
            depositor: user.account, :asset_id, position_id: user.position_id, quantized_amount: 2,
        );
    state.facade.process_deposit(deposit_info: deposit_info_user);
    state.facade.set_treasury_protection_percent_for_token(erc20_contract_address, 100);

    state.facade.advance_time(seconds: HOUR);

    // |PnL| = 10000. max_allowed for HOUR ≈ 10. -1 fits and pushes TV from 10100 → 9999.
    let withdraw_info = state.facade.withdraw_spot_request(:user, :asset_id, amount: 2);
    state.facade.withdraw_with_interest(:withdraw_info, interest_amount: -1);
}

#[test]
fn test_withdraw_with_positive_interest_allows_to_withdraw() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    state.facade.token_state.fund(state.facade.perpetuals_contract, 1_000_000);

    let user = state.new_user_with_position();

    // Deposit collateral
    let deposit_info = state
        .facade
        .deposit(depositor: user.account, position_id: user.position_id, quantized_amount: 10_000);
    state.facade.process_deposit(deposit_info: deposit_info);
    state.facade.validate_collateral_balance(user.position_id, 10_000_u64.into());

    // Advance time by 1 hour
    state.facade.advance_time(seconds: HOUR);

    // Calculate and apply interest
    let balance: u64 = 10_000;
    let time_diff: u64 = HOUR.into();
    let scale: u64 = 2_u64.pow(32);
    let max_allowed: u64 = (balance * time_diff * MAX_INTEREST_RATE_PER_SEC.into()) / scale;
    let interest_amount: i64 = max_allowed.try_into().unwrap();

    // Withdraw with interest
    let withdraw_info = state.facade.withdraw_request(user: user, amount: 10_005);
    state.facade.withdraw_with_interest(:withdraw_info, :interest_amount);
    state.facade.validate_collateral_balance(user.position_id, 5_u64.into());
}

#[test]
fn test_withdraw_spot_with_interest() {
    // Sign-rule-friendly setup: helper gives the user negative USDC collateral (-10_000) and a
    // 200-BTC long, then we add spot collateral and exercise spot withdrawal with negative
    // interest. Negative collateral → negative interest is allowed by the sign rule.
    let risk_factor_data = RiskFactorTiers {
        tiers: array![10].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let synthetic_info = AssetInfoTrait::new(
        asset_name: 'BTC_1', :risk_factor_data, oracles_len: 1,
    );
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let user = state.new_user_with_negative_collateral(synthetic_info: @synthetic_info);

    // Register a spot collateral asset and give the user STRK to deposit.
    let token = snforge_std::Token::STRK;
    let erc20_contract_address = token.contract_address();
    let spot_info = AssetInfoTrait::new_collateral(
        asset_name: 'COL', :risk_factor_data, oracles_len: 1, :erc20_contract_address,
    );
    let asset_id = spot_info.asset_id;
    state.facade.add_active_collateral(asset_info: @spot_info, initial_price: 100);
    snforge_std::set_balance(target: user.account.address, new_balance: 5_000_000, :token);

    // Deposit 2 units of spot collateral.
    let deposit_info_user = state
        .facade
        .deposit_spot(
            depositor: user.account, :asset_id, position_id: user.position_id, quantized_amount: 2,
        );
    state.facade.process_deposit(deposit_info: deposit_info_user);

    state.facade.set_treasury_protection_percent_for_token(erc20_contract_address, 100);
    state.facade.advance_time(seconds: HOUR);

    // |PnL| = |-10_000 + 200*100| = 10_000. max_allowed for HOUR ≈ 10.
    let balance: u64 = 10_000;
    let time_diff: u64 = HOUR.into();
    let scale: u64 = 2_u64.pow(32);
    let max_allowed: u64 = (balance * time_diff * MAX_INTEREST_RATE_PER_SEC.into()) / scale;
    let interest_amount: i64 = -(max_allowed).try_into().unwrap();

    // Withdraw 1 spot unit + apply negative interest.
    let withdraw_info = state.facade.withdraw_spot_request(:user, :asset_id, amount: 1);
    state.facade.withdraw_with_interest(:withdraw_info, :interest_amount);
    state
        .facade
        .validate_asset_balance(
            position_id: user.position_id, :asset_id, expected_balance: 1_u64.into(),
        );
    let expected_collateral: i64 = -10_000 + interest_amount;
    state.facade.validate_collateral_balance(user.position_id, expected_collateral.into());
}

#[test]
fn test_deposit_spot_with_positive_interest() {
    // Setup.
    let risk_factor_data = RiskFactorTiers {
        tiers: array![10].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    state.facade.token_state.fund(state.facade.perpetuals_contract, 1_000_000);

    // Create a custom asset configuration.
    let token = snforge_std::Token::STRK;
    let erc20_contract_address = token.contract_address();
    let asset_info = AssetInfoTrait::new_collateral(
        asset_name: 'COL', :risk_factor_data, oracles_len: 1, :erc20_contract_address,
    );
    let asset_id = asset_info.asset_id;
    state.facade.add_active_collateral(asset_info: @asset_info, initial_price: 100);

    // Create user
    let user = state.new_user_with_position();
    snforge_std::set_balance(target: user.account.address, new_balance: 5000000, :token);

    // Deposit base collateral for PnL so it will be non-zero
    let deposit_info = state
        .facade
        .deposit(depositor: user.account, position_id: user.position_id, quantized_amount: 10_000);
    state.facade.process_deposit(deposit_info: deposit_info);
    state.facade.validate_collateral_balance(user.position_id, 10_000_u64.into());

    // Deposit spot collateral to user.
    let deposit_info_user = state
        .facade
        .deposit_spot(
            depositor: user.account, :asset_id, position_id: user.position_id, quantized_amount: 2,
        );
    state.facade.process_deposit(deposit_info: deposit_info_user);

    // Advance time by 1 hour
    state.facade.advance_time(seconds: HOUR);

    // Calculate positive interest
    let balance: u64 = 10_000;
    let time_diff: u64 = HOUR.into();
    let scale: u64 = 2_u64.pow(32);
    let max_allowed: u64 = (balance * time_diff * MAX_INTEREST_RATE_PER_SEC.into()) / scale;
    let interest_amount: i64 = max_allowed.try_into().unwrap();

    // Second spot deposit with positive interest
    let deposit_info_2 = state
        .facade
        .deposit_spot(
            depositor: user.account, :asset_id, position_id: user.position_id, quantized_amount: 1,
        );
    state.facade.process_deposit_with_interest(deposit_info: deposit_info_2, :interest_amount);
    state
        .facade
        .validate_asset_balance(
            position_id: user.position_id, :asset_id, expected_balance: 3_u64.into(),
        );
    state.facade.validate_collateral_balance(user.position_id, (10_000_u64 + max_allowed).into());
}

#[test]
fn test_deposit_spot_with_negative_interest() {
    // Sign-rule-friendly reframe: helper user has negative collateral. We add a spot asset,
    // deposit some, then deposit more spot with negative interest applied to base collateral.
    let risk_factor_data = RiskFactorTiers {
        tiers: array![10].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let synthetic_info = AssetInfoTrait::new(
        asset_name: 'BTC_1', :risk_factor_data, oracles_len: 1,
    );
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let user = state.new_user_with_negative_collateral(synthetic_info: @synthetic_info);

    let token = snforge_std::Token::STRK;
    let erc20_contract_address = token.contract_address();
    let spot_info = AssetInfoTrait::new_collateral(
        asset_name: 'COL', :risk_factor_data, oracles_len: 1, :erc20_contract_address,
    );
    let asset_id = spot_info.asset_id;
    state.facade.add_active_collateral(asset_info: @spot_info, initial_price: 100);
    snforge_std::set_balance(target: user.account.address, new_balance: 5_000_000, :token);

    // Deposit 2 spot first (no interest).
    let deposit_info_user = state
        .facade
        .deposit_spot(
            depositor: user.account, :asset_id, position_id: user.position_id, quantized_amount: 2,
        );
    state.facade.process_deposit(deposit_info: deposit_info_user);

    state.facade.advance_time(seconds: HOUR);

    // |PnL| = 10000, max_allowed for HOUR ≈ 10. Sign rule (negative collateral) allows negative.
    let interest_amount: i64 = -10;
    let deposit_info_2 = state
        .facade
        .deposit_spot(
            depositor: user.account, :asset_id, position_id: user.position_id, quantized_amount: 1,
        );
    state.facade.process_deposit_with_interest(deposit_info: deposit_info_2, :interest_amount);
    state
        .facade
        .validate_asset_balance(
            position_id: user.position_id, :asset_id, expected_balance: 3_u64.into(),
        );
    // Base collateral = -10000 + interest = -10010.
    state.facade.validate_collateral_balance(user.position_id, (-10_010_i64).into());
}

#[test]
#[should_panic(expected: "POSITION_NOT_HEALTHY_NOR_HEALTHIER")]
fn test_deposit_base_with_negative_interest_becomes_unhealthy() {
    // Sign-rule-friendly reframe: helper user with 50% risk → TV exactly at TR after the trade.
    // A small base deposit + negative interest larger than the deposit pushes TV below TR.
    let risk_factor_data = RiskFactorTiers {
        tiers: array![500].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let synthetic_info = AssetInfoTrait::new(
        asset_name: 'BTC_1', :risk_factor_data, oracles_len: 1,
    );
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let user = state.new_user_with_negative_collateral(synthetic_info: @synthetic_info);

    state.facade.advance_time(seconds: HOUR);

    // Pre: TV=10000, TR=10000. |PnL|=10000, max_allowed ≈ 10.
    // Deposit 5 + interest -10: collateral=-10005, TV=9995 < TR=10000 → Liquidatable.
    let deposit_info_2 = state
        .facade
        .deposit(depositor: user.account, position_id: user.position_id, quantized_amount: 5);
    state.facade.process_deposit_with_interest(deposit_info: deposit_info_2, interest_amount: -10);
}

#[test]
fn test_deposit_base_with_negative_interest_exceeds_deposit_but_healthy() {
    // Sign-rule-friendly reframe: helper user has negative collateral, so the sign rule allows
    // negative interest. We deposit 5 base collateral and apply negative interest of magnitude
    // larger than the deposit; the position stays healthy (1% risk → 50x overcollateralized).
    let risk_factor_data = RiskFactorTiers {
        tiers: array![10].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let synthetic_info = AssetInfoTrait::new(
        asset_name: 'BTC_1', :risk_factor_data, oracles_len: 1,
    );
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let user = state.new_user_with_negative_collateral(synthetic_info: @synthetic_info);

    state.facade.advance_time(seconds: HOUR);

    // |PnL| = 10000, max_allowed for HOUR ≈ 10.
    let interest_amount: i64 = -10;
    let deposit_info_2 = state
        .facade
        .deposit(depositor: user.account, position_id: user.position_id, quantized_amount: 5);
    state.facade.process_deposit_with_interest(deposit_info: deposit_info_2, :interest_amount);
    // collateral = -10000 + 5 + (-10) = -10005.
    state.facade.validate_collateral_balance(user.position_id, (-10_005_i64).into());
}

#[test]
#[should_panic(expected: "POSITION_NOT_HEALTHY_NOR_HEALTHIER")]
fn test_deposit_spot_with_negative_interest_becomes_unhealthy() {
    // Sign-rule-friendly reframe: helper user with 50% risk → TV exactly at TR. A spot deposit
    // with high spot risk gives little TV cushion; a small negative interest pushes TV<TR.
    let risk_factor_data = RiskFactorTiers {
        tiers: array![500].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let synthetic_info = AssetInfoTrait::new(
        asset_name: 'BTC_1', :risk_factor_data, oracles_len: 1,
    );
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let user = state.new_user_with_negative_collateral(synthetic_info: @synthetic_info);

    // Spot collateral asset with 50% risk: 1 unit @ price 100 contributes 100 - 50 = 50 to TV.
    let token = snforge_std::Token::STRK;
    let erc20_contract_address = token.contract_address();
    let spot_info = AssetInfoTrait::new_collateral(
        asset_name: 'COL', :risk_factor_data, oracles_len: 1, :erc20_contract_address,
    );
    let asset_id = spot_info.asset_id;
    state.facade.add_active_collateral(asset_info: @spot_info, initial_price: 100);
    snforge_std::set_balance(target: user.account.address, new_balance: 5_000_000, :token);

    state.facade.advance_time(seconds: HOUR);

    // Pre: TV=10000, TR=10000. |PnL|=10000, max_allowed ≈ 10.
    // Spot deposit 1 adds 50 to TV. + interest -10 reduces collateral by 10.
    // Net TV change: +50 - 10 = +40. New TV=10040, TR=10000. Wait — that's healthier!
    //
    // We need interest > spot TV contribution to push unhealthy. Use larger negative interest
    // by depositing more spot to bump max_allowed... but that's circular. Better: keep spot
    // deposit at 1 and use spot's own value haircut to make the contribution smaller.
    //
    // Actually with 50% risk on spot, value=100, risk=50 → TV contribution=50. To push TV<TR
    // with -10 interest: 50 - 10 = 40 net positive change → 10040 not unhealthy.
    //
    // Use lower spot price so contribution is smaller than |interest|:
    //   spot @ price 5: TV contrib = 5 - 5*0.5 = 2.5 → 2 (truncation).
    //   With interest -10: net change = 2 - 10 = -8. TV=9992 < TR=10000 → Liquidatable. ✓
    state.facade.price_tick(asset_info: @spot_info, price: 5);

    let deposit_info_2 = state
        .facade
        .deposit_spot(
            depositor: user.account, :asset_id, position_id: user.position_id, quantized_amount: 1,
        );
    state.facade.process_deposit_with_interest(deposit_info: deposit_info_2, interest_amount: -10);
}

#[test]
fn test_multi_trade_with_mixed_interest() {
    let risk_factor_data = RiskFactorTiers {
        tiers: array![10].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let synthetic_info = AssetInfoTrait::new(
        asset_name: 'BTC_1', :risk_factor_data, oracles_len: 1,
    );
    let asset_id = synthetic_info.asset_id;
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    state.facade.add_active_synthetic(synthetic_info: @synthetic_info, initial_price: 100);

    let user_a = state.new_user_with_position();
    let user_b = state.new_user_with_position();

    let deposit_a = state
        .facade
        .deposit(
            depositor: user_a.account, position_id: user_a.position_id, quantized_amount: 100_000,
        );
    state.facade.process_deposit(deposit_info: deposit_a);
    let deposit_b = state
        .facade
        .deposit(
            depositor: user_b.account, position_id: user_b.position_id, quantized_amount: 100_000,
        );
    state.facade.process_deposit(deposit_info: deposit_b);

    state.facade.advance_time(seconds: HOUR);

    // PnL for both = 100000 (collateral only, no synthetics yet). max_allowed for an hour ~ 100.
    // Both users have positive collateral → both receive positive interest (different
    // magnitudes).
    let interest_a: i64 = 50_i64;
    let interest_b: i64 = 75_i64;

    let order_a = state
        .facade
        .create_order(
            user: user_a,
            base_amount: 10,
            base_asset_id: asset_id,
            quote_amount: -1000,
            fee_amount: 5,
        );
    let order_b = state
        .facade
        .create_order(
            user: user_b,
            base_amount: -15,
            base_asset_id: asset_id,
            quote_amount: 1500,
            fee_amount: 8,
        );

    let settlement = state
        .facade
        .create_settlement_with_interest(
            :order_a,
            :order_b,
            base: 10,
            quote: -1000,
            fee_a: 5,
            fee_b: 5,
            interest_amount_a: interest_a,
            interest_amount_b: interest_b,
        );

    // Facade validates: user_a collateral = 100000 - 1000 - 5 + interest_a,
    // user_b collateral = 100000 + 1000 - 5 + interest_b, and synthetic balances.
    state.facade.multi_trade(trades: array![settlement].span());
}

#[test]
fn test_multi_trade_positive_interest_enables_unhealthy_trade() {
    // With risk_factor 50%, user_a opens a short that would make them unhealthy
    // without positive interest. Interest tips the position back to exactly healthy.
    let risk_factor_data = RiskFactorTiers {
        tiers: array![500].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let synthetic_info = AssetInfoTrait::new(
        asset_name: 'BTC_1', :risk_factor_data, oracles_len: 1,
    );
    let asset_id = synthetic_info.asset_id;
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    state.facade.add_active_synthetic(synthetic_info: @synthetic_info, initial_price: 100);

    let user_a = state.new_user_with_position();
    let user_b = state.new_user_with_position();

    let deposit_a = state
        .facade
        .deposit(
            depositor: user_a.account, position_id: user_a.position_id, quantized_amount: 5_000,
        );
    state.facade.process_deposit(deposit_info: deposit_a);
    let deposit_b = state
        .facade
        .deposit(
            depositor: user_b.account, position_id: user_b.position_id, quantized_amount: 100_000,
        );
    state.facade.process_deposit(deposit_info: deposit_b);

    state.facade.advance_time(seconds: HOUR);

    // user_a PnL = 5000. max_allowed = floor(5000 * 3600 * 1200 / 2^32) = 5.
    // Without interest: user_a sells 100 BTC, gets 10000 quote, pays fee 1.
    //   collateral = 5000 + 10000 - 1 = 14999, BTC = -100
    //   TV = 14999 - 10000 = 4999, TR = 10000 * 0.5 = 5000 -> UNHEALTHY
    // With interest_a = +1:
    //   collateral = 5000 + 10000 - 1 + 1 = 15000, BTC = -100
    //   TV = 15000 - 10000 = 5000, TR = 5000 -> HEALTHY (barely)
    let order_a = state
        .facade
        .create_order(
            user: user_a,
            base_amount: -100,
            base_asset_id: asset_id,
            quote_amount: 10000,
            fee_amount: 1,
        );
    let order_b = state
        .facade
        .create_order(
            user: user_b,
            base_amount: 100,
            base_asset_id: asset_id,
            quote_amount: -10000,
            fee_amount: 0,
        );

    let settlement = state
        .facade
        .create_settlement_with_interest(
            :order_a,
            :order_b,
            base: -100,
            quote: 10000,
            fee_a: 1,
            fee_b: 0,
            interest_amount_a: 1,
            interest_amount_b: 0,
        );

    state.facade.multi_trade(trades: array![settlement].span());
}

#[test]
#[should_panic(expected: "POSITION_NOT_HEALTHY_NOR_HEALTHIER")]
fn test_multi_trade_negative_interest_makes_trade_unhealthy() {
    // Sign-rule-friendly reframe: scale the helper-style setup 10x so |PnL|=100k, allowing
    // interest magnitudes up to ~100 within the HOUR cap. Pre-trade user_a sits exactly at
    // TV=TR=100k. A small sell + interest -51 pushes TV below the (slightly-reduced) TR.
    let risk_factor_data = RiskFactorTiers {
        tiers: array![500].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let synthetic_info = AssetInfoTrait::new(
        asset_name: 'BTC_1', :risk_factor_data, oracles_len: 1,
    );
    let asset_id = synthetic_info.asset_id;
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    state.facade.add_active_synthetic(synthetic_info: @synthetic_info, initial_price: 100);

    let user_a = state.new_user_with_position();
    let user_b = state.new_user_with_position();

    state
        .facade
        .process_deposit(state.facade.deposit(user_a.account, user_a.position_id, 100_000_u64));
    state
        .facade
        .process_deposit(state.facade.deposit(user_b.account, user_b.position_id, 1_000_000_u64));

    // Setup trade: user_a buys 2000 BTC at price 100 → collateral = -100_000, BTC = 2000.
    // TV = -100_000 + 2000*100 = 100_000. TR = 2000*100*0.5 = 100_000. Just healthy.
    let setup_a = state
        .facade
        .create_order(
            user: user_a,
            base_amount: 3000,
            base_asset_id: asset_id,
            quote_amount: -300_000,
            fee_amount: 0,
        );
    let setup_b = state
        .facade
        .create_order(
            user: user_b,
            base_amount: -2000,
            base_asset_id: asset_id,
            quote_amount: 100_000,
            fee_amount: 0,
        );
    state
        .facade
        .trade(
            order_info_a: setup_a,
            order_info_b: setup_b,
            base: 2000,
            quote: -200_000,
            fee_a: 0,
            fee_b: 0,
        );

    state.facade.advance_time(seconds: HOUR);

    // |PnL_a| = 100_000. max_allowed for HOUR ≈ 100.
    // Sell 1 BTC at quote 100 (price-perfect): TV stays 100_000, TR = 1999*100*0.5 = 99_950.
    // Interest_a = -51: TV = 99_949 < TR = 99_950 → Liquidatable.
    let order_a = state
        .facade
        .create_order(
            user: user_a,
            base_amount: -1,
            base_asset_id: asset_id,
            quote_amount: 100,
            fee_amount: 0,
        );
    let order_b = state
        .facade
        .create_order(
            user: user_b,
            base_amount: 1,
            base_asset_id: asset_id,
            quote_amount: -100,
            fee_amount: 0,
        );

    let settlement = state
        .facade
        .create_settlement_with_interest(
            :order_a,
            :order_b,
            base: -1,
            quote: 100,
            fee_a: 0,
            fee_b: 0,
            interest_amount_a: -51,
            interest_amount_b: 0,
        );

    state.facade.multi_trade(trades: array![settlement].span());
}

#[test]
#[should_panic(expected: "INVALID_INTEREST_RATE position_id: PositionId { value: 101 }")]
fn test_multi_trade_non_zero_interest_on_fresh_position() {
    // No time has advanced since position creation, so time_diff = 0 and any non-zero
    // interest exceeds max_allowed (which is 0).
    let risk_factor_data = RiskFactorTiers {
        tiers: array![10].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let synthetic_info = AssetInfoTrait::new(
        asset_name: 'BTC_1', :risk_factor_data, oracles_len: 1,
    );
    let asset_id = synthetic_info.asset_id;
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    state.facade.add_active_synthetic(synthetic_info: @synthetic_info, initial_price: 100);

    let user_a = state.new_user_with_position();
    let user_b = state.new_user_with_position();

    let deposit_a = state
        .facade
        .deposit(
            depositor: user_a.account, position_id: user_a.position_id, quantized_amount: 10_000,
        );
    state.facade.process_deposit(deposit_info: deposit_a);
    let deposit_b = state
        .facade
        .deposit(
            depositor: user_b.account, position_id: user_b.position_id, quantized_amount: 100_000,
        );
    state.facade.process_deposit(deposit_info: deposit_b);

    let order_a = state
        .facade
        .create_order(
            user: user_a,
            base_amount: 10,
            base_asset_id: asset_id,
            quote_amount: -1000,
            fee_amount: 0,
        );
    let order_b = state
        .facade
        .create_order(
            user: user_b,
            base_amount: -10,
            base_asset_id: asset_id,
            quote_amount: 1000,
            fee_amount: 0,
        );

    let settlement = state
        .facade
        .create_settlement_with_interest(
            :order_a,
            :order_b,
            base: 10,
            quote: -1000,
            fee_a: 0,
            fee_b: 0,
            interest_amount_a: 1,
            interest_amount_b: 0,
        );

    state.facade.multi_trade(trades: array![settlement].span());
}

#[test]
fn test_multi_trade_interest_with_synthetic_pnl() {
    // A position with synthetics has PnL = collateral + synthetic_value, allowing more
    // interest than a collateral-only position. We apply interest that would be invalid
    // for the collateral alone but is valid thanks to the synthetic exposure.
    let risk_factor_data = RiskFactorTiers {
        tiers: array![10].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let synthetic_info = AssetInfoTrait::new(
        asset_name: 'BTC_1', :risk_factor_data, oracles_len: 1,
    );
    let asset_id = synthetic_info.asset_id;
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    state.facade.add_active_synthetic(synthetic_info: @synthetic_info, initial_price: 100);

    let user_a = state.new_user_with_position();
    let user_b = state.new_user_with_position();

    let deposit_a = state
        .facade
        .deposit(
            depositor: user_a.account, position_id: user_a.position_id, quantized_amount: 10_000,
        );
    state.facade.process_deposit(deposit_info: deposit_a);
    let deposit_b = state
        .facade
        .deposit(
            depositor: user_b.account, position_id: user_b.position_id, quantized_amount: 100_000,
        );
    state.facade.process_deposit(deposit_info: deposit_b);

    // First trade: user_a buys 100 BTC at 80 quote each (below oracle price of 100).
    // After trade: user_a collateral = 10000 - 8000 = 2000, BTC = 100
    // PnL = 2000 + 100*100 = 12000
    let order_a_1 = state
        .facade
        .create_order(
            user: user_a,
            base_amount: 100,
            base_asset_id: asset_id,
            quote_amount: -8000,
            fee_amount: 0,
        );
    let order_b_1 = state
        .facade
        .create_order(
            user: user_b,
            base_amount: -100,
            base_asset_id: asset_id,
            quote_amount: 8000,
            fee_amount: 0,
        );

    let settlement_1 = state
        .facade
        .create_settlement(
            order_a: order_a_1, order_b: order_b_1, base: 100, quote: -8000, fee_a: 0, fee_b: 0,
        );
    state.facade.multi_trade(trades: array![settlement_1].span());

    state.facade.advance_time(seconds: HOUR);

    // user_a PnL = 12000 (collateral 2000 + synthetic 10000).
    // max_allowed = floor(12000 * 3600 * 1200 / 2^32) = 12.
    // With collateral alone (2000): max would be floor(2000 * 3600 * 1200 / 2^32) = 2.
    // We apply interest_a = 5, which exceeds the collateral-only max (2) but is valid
    // because the synthetic PnL pushes the limit to 12.
    let order_a_2 = state
        .facade
        .create_order(
            user: user_a,
            base_amount: 1,
            base_asset_id: asset_id,
            quote_amount: -100,
            fee_amount: 0,
        );
    let order_b_2 = state
        .facade
        .create_order(
            user: user_b,
            base_amount: -1,
            base_asset_id: asset_id,
            quote_amount: 100,
            fee_amount: 0,
        );

    let settlement_2 = state
        .facade
        .create_settlement_with_interest(
            order_a: order_a_2,
            order_b: order_b_2,
            base: 1,
            quote: -100,
            fee_a: 0,
            fee_b: 0,
            interest_amount_a: 5,
            interest_amount_b: 0,
        );

    // After: user_a collateral = 2000 - 100 + 5 = 1905, BTC = 101
    // TV = 1905 + 10100 = 12005, TR = 10100 * 0.01 = 101 -> healthy
    state.facade.multi_trade(trades: array![settlement_2].span());
}

#[test]
fn test_multi_trade_multiple_settlements_with_interest() {
    // 3 positions, 3 settlements in a single multi_trade call.
    // Tests that non-zero interest appears only in each position's last settlement,
    // and that the TVTR cache correctly accumulates across settlements.
    let risk_factor_data = RiskFactorTiers {
        tiers: array![10].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let synthetic_info = AssetInfoTrait::new(
        asset_name: 'BTC_1', :risk_factor_data, oracles_len: 1,
    );
    let asset_id = synthetic_info.asset_id;
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    state.facade.add_active_synthetic(synthetic_info: @synthetic_info, initial_price: 100);

    let user_a = state.new_user_with_position();
    let user_b = state.new_user_with_position();
    let user_c = state.new_user_with_position();

    let deposit_a = state
        .facade
        .deposit(
            depositor: user_a.account, position_id: user_a.position_id, quantized_amount: 100_000,
        );
    state.facade.process_deposit(deposit_info: deposit_a);
    let deposit_b = state
        .facade
        .deposit(
            depositor: user_b.account, position_id: user_b.position_id, quantized_amount: 100_000,
        );
    state.facade.process_deposit(deposit_info: deposit_b);
    let deposit_c = state
        .facade
        .deposit(
            depositor: user_c.account, position_id: user_c.position_id, quantized_amount: 100_000,
        );
    state.facade.process_deposit(deposit_info: deposit_c);

    state.facade.advance_time(seconds: HOUR);

    // All positions PnL = 100000. max_allowed = floor(100000 * 3600 * 1200 / 2^32) = 100.

    // Settlement 1: A buys 10 BTC from B. No interest (both participate later).
    let order_a_1 = state
        .facade
        .create_order(
            user: user_a,
            base_amount: 10,
            base_asset_id: asset_id,
            quote_amount: -1000,
            fee_amount: 0,
        );
    let order_b_1 = state
        .facade
        .create_order(
            user: user_b,
            base_amount: -10,
            base_asset_id: asset_id,
            quote_amount: 1000,
            fee_amount: 0,
        );
    let settlement_1 = state
        .facade
        .create_settlement_with_interest(
            order_a: order_a_1,
            order_b: order_b_1,
            base: 10,
            quote: -1000,
            fee_a: 0,
            fee_b: 0,
            interest_amount_a: 0,
            interest_amount_b: 0,
        );

    // Settlement 2: A sells 5 BTC to C. Non-zero interest for A (A's last settlement).
    let order_a_2 = state
        .facade
        .create_order(
            user: user_a,
            base_amount: -5,
            base_asset_id: asset_id,
            quote_amount: 500,
            fee_amount: 0,
        );
    let order_c_2 = state
        .facade
        .create_order(
            user: user_c,
            base_amount: 5,
            base_asset_id: asset_id,
            quote_amount: -500,
            fee_amount: 0,
        );
    let settlement_2 = state
        .facade
        .create_settlement_with_interest(
            order_a: order_a_2,
            order_b: order_c_2,
            base: -5,
            quote: 500,
            fee_a: 0,
            fee_b: 0,
            interest_amount_a: 50,
            interest_amount_b: 0,
        );

    // Settlement 3: B buys 5 BTC from C. Non-zero interest for both (last for B and C).
    let order_b_3 = state
        .facade
        .create_order(
            user: user_b,
            base_amount: 5,
            base_asset_id: asset_id,
            quote_amount: -500,
            fee_amount: 0,
        );
    let order_c_3 = state
        .facade
        .create_order(
            user: user_c,
            base_amount: -5,
            base_asset_id: asset_id,
            quote_amount: 500,
            fee_amount: 0,
        );
    let settlement_3 = state
        .facade
        .create_settlement_with_interest(
            order_a: order_b_3,
            order_b: order_c_3,
            base: 5,
            quote: -500,
            fee_a: 0,
            fee_b: 0,
            interest_amount_a: 50,
            interest_amount_b: 50,
        );

    // Execute all 3 settlements in one multi_trade call.
    // Expected final balances:
    //   A: collateral = 100000 - 1000 + 500 + 50 = 99550, BTC = 10 - 5 = 5
    //   B: collateral = 100000 + 1000 - 500 + 50 = 100550, BTC = -10 + 5 = -5
    //   C: collateral = 100000 - 500 + 500 + 0 + 50 = 100050, BTC = 5 - 5 = 0
    //   Fee: 0
    state.facade.multi_trade(trades: array![settlement_1, settlement_2, settlement_3].span());
}

#[test]
fn test_redeem_from_vault_with_mixed_interest_same_position() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let vault_user = state.new_user_with_position();
    let redeeming_user = state.new_user_with_position();

    state
        .facade
        .process_deposit(
            state.facade.deposit(vault_user.account, vault_user.position_id, 5000_u64),
        );
    let vault_config = state.facade.register_vault_share_spot_asset(vault_user, asset_name: 'VS_1');
    state.facade.price_tick(@vault_config.asset_info, 1);

    // Set vault protection limit high to allow redemptions in this test
    state.facade.update_vault_protection_limit(vault_user.position_id, 100);

    state
        .facade
        .process_deposit(
            state.facade.deposit(redeeming_user.account, redeeming_user.position_id, 10_000_u64),
        );
    state
        .facade
        .process_deposit(
            state
                .facade
                .deposit_into_vault(
                    vault: vault_config,
                    amount_to_invest: 1000,
                    min_shares_to_receive: 500,
                    depositing_user: redeeming_user,
                    receiving_user: redeeming_user,
                ),
        );

    // Set treasury protection to 100% for vault share token after deposits fund the treasury.
    state
        .facade
        .set_treasury_protection_percent_for_token(
            vault_config.deployed_vault.contract_address, 100,
        );

    state.facade.advance_time(seconds: HOUR);

    let redeeming_collateral_before = state
        .facade
        .get_position_collateral_balance(redeeming_user.position_id);
    let vault_collateral_before = state
        .facade
        .get_position_collateral_balance(vault_config.position_id);

    // Vault PnL = 6000, sender PnL = 9000 (both positive collateral → positive interest).
    let interest_sender: i64 = 3;
    let interest_vault: i64 = 2;
    let value_of_shares: u64 = 399;

    state
        .facade
        .redeem_from_vault_with_interest(
            vault: vault_config,
            withdrawing_user: redeeming_user,
            receiving_user: redeeming_user,
            shares_to_burn_user: 400,
            value_of_shares_user: value_of_shares,
            shares_to_burn_vault: 400,
            value_of_shares_vault: value_of_shares,
            actual_shares_user: 400,
            actual_collateral_user: value_of_shares,
            interest_amount_vault_position: interest_vault,
            interest_amount_sender: interest_sender,
            interest_amount_receiver: 0,
            other_collaterals: array![].span(),
        );

    state
        .facade
        .validate_collateral_balance(
            position_id: redeeming_user.position_id,
            expected_balance: redeeming_collateral_before
                + value_of_shares.into()
                + interest_sender.into(),
        );
    state
        .facade
        .validate_collateral_balance(
            position_id: vault_config.position_id,
            expected_balance: vault_collateral_before
                - value_of_shares.into()
                + interest_vault.into(),
        );
}

#[test]
fn test_redeem_from_vault_with_positive_interest_enables_otherwise_unhealthy_redeem() {
    // Sign-rule-friendly inversion: redeeming_user goes SHORT 190 BTC instead of long, keeping
    // collateral positive so the operator-supplied positive interest is allowed.
    //
    // Deposit 10000, invest 1000 => collateral = 9000. Sell 190 BTC@100 => collateral = +28000,
    // BTC = -190.
    // PnL = 28000 + (-190)*100 = 9000. max_allowed = floor(9000*3600*1200/2^32) = 9.
    // TV = 28000 + 1000(shares) - 19000(BTC short) = 10000, TR = 190*100*0.5 = 9500. Healthy.
    //
    // Redeem all 1000 shares for $499, interest = 0:
    //   TV = 28000 + 499 + 0 - 19000 = 9499, TR = 9500. Unhealthy by 1!
    // Redeem all 1000 shares for $499, interest = +1:
    //   TV = 28000 + 499 + 1 - 19000 = 9500 = TR. Just healthy!
    let risk_factor_data = RiskFactorTiers {
        tiers: array![500].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let synthetic_info = AssetInfoTrait::new(
        asset_name: 'BTC_1', :risk_factor_data, oracles_len: 1,
    );
    let asset_id = synthetic_info.asset_id;
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    state.facade.add_active_synthetic(synthetic_info: @synthetic_info, initial_price: 100);

    let vault_user = state.new_user_with_position();
    let trade_user = state.new_user_with_position();
    let redeeming_user = state.new_user_with_position();

    state
        .facade
        .process_deposit(
            state.facade.deposit(vault_user.account, vault_user.position_id, 50_000_u64),
        );
    let vault_config = state.facade.register_vault_share_spot_asset(vault_user, asset_name: 'VS_1');
    state.facade.price_tick(@vault_config.asset_info, 1);

    state
        .facade
        .process_deposit(
            state.facade.deposit(redeeming_user.account, redeeming_user.position_id, 10_000_u64),
        );
    state
        .facade
        .process_deposit(
            state.facade.deposit(trade_user.account, trade_user.position_id, 100_000_u64),
        );
    state
        .facade
        .process_deposit(
            state
                .facade
                .deposit_into_vault(
                    vault: vault_config,
                    amount_to_invest: 1000,
                    min_shares_to_receive: 500,
                    depositing_user: redeeming_user,
                    receiving_user: redeeming_user,
                ),
        );

    // Set treasury protection to 100% for vault share token after deposits fund the treasury.
    state
        .facade
        .set_treasury_protection_percent_for_token(
            vault_config.deployed_vault.contract_address, 100,
        );

    let user_order = state
        .facade
        .create_order(
            user: redeeming_user,
            base_amount: -190,
            base_asset_id: asset_id,
            quote_amount: 19000,
            fee_amount: 0,
        );
    let other_side_order = state
        .facade
        .create_order(
            user: trade_user,
            base_amount: 190,
            base_asset_id: asset_id,
            quote_amount: -19000,
            fee_amount: 0,
        );
    state
        .facade
        .trade(
            order_info_a: user_order,
            order_info_b: other_side_order,
            base: -190,
            quote: 19000,
            fee_a: 0,
            fee_b: 0,
        );

    state.facade.advance_time(seconds: HOUR);

    state
        .facade
        .redeem_from_vault_with_interest(
            vault: vault_config,
            withdrawing_user: redeeming_user,
            receiving_user: redeeming_user,
            shares_to_burn_user: 1000,
            value_of_shares_user: 499,
            shares_to_burn_vault: 1000,
            value_of_shares_vault: 499,
            actual_shares_user: 1000,
            actual_collateral_user: 499,
            interest_amount_vault_position: 0,
            interest_amount_sender: 1,
            interest_amount_receiver: 0,
            other_collaterals: array![].span(),
        );
}

#[test]
#[should_panic(expected: "POSITION_NOT_HEALTHY_NOR_HEALTHIER")]
fn test_redeem_from_vault_with_negative_interest_makes_redeem_unhealthy() {
    // Same setup as the enables-unhealthy test.
    // Redeem all 1000 shares for $500, interest = 0:
    //   TV = -10000 + 500 + 0 + 19000 = 9500 = TR. Just healthy.
    // Redeem all 1000 shares for $500, interest = -1:
    //   TV = -10000 + 500 - 1 + 19000 = 9499 < TR = 9500. Unhealthy!
    let risk_factor_data = RiskFactorTiers {
        tiers: array![500].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let synthetic_info = AssetInfoTrait::new(
        asset_name: 'BTC_1', :risk_factor_data, oracles_len: 1,
    );
    let asset_id = synthetic_info.asset_id;
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    state.facade.add_active_synthetic(synthetic_info: @synthetic_info, initial_price: 100);

    let vault_user = state.new_user_with_position();
    let trade_user = state.new_user_with_position();
    let redeeming_user = state.new_user_with_position();

    state
        .facade
        .process_deposit(
            state.facade.deposit(vault_user.account, vault_user.position_id, 50_000_u64),
        );
    let vault_config = state.facade.register_vault_share_spot_asset(vault_user, asset_name: 'VS_1');
    state.facade.price_tick(@vault_config.asset_info, 1);

    state
        .facade
        .process_deposit(
            state.facade.deposit(redeeming_user.account, redeeming_user.position_id, 10_000_u64),
        );
    state
        .facade
        .process_deposit(
            state.facade.deposit(trade_user.account, trade_user.position_id, 100_000_u64),
        );
    state
        .facade
        .process_deposit(
            state
                .facade
                .deposit_into_vault(
                    vault: vault_config,
                    amount_to_invest: 1000,
                    min_shares_to_receive: 500,
                    depositing_user: redeeming_user,
                    receiving_user: redeeming_user,
                ),
        );

    // Set treasury protection to 100% for vault share token after deposits fund the treasury.
    state
        .facade
        .set_treasury_protection_percent_for_token(
            vault_config.deployed_vault.contract_address, 100,
        );

    let user_order = state
        .facade
        .create_order(
            user: redeeming_user,
            base_amount: 190,
            base_asset_id: asset_id,
            quote_amount: -19000,
            fee_amount: 0,
        );
    let other_side_order = state
        .facade
        .create_order(
            user: trade_user,
            base_amount: -190,
            base_asset_id: asset_id,
            quote_amount: 19000,
            fee_amount: 0,
        );
    state
        .facade
        .trade(
            order_info_a: user_order,
            order_info_b: other_side_order,
            base: 190,
            quote: -19000,
            fee_a: 0,
            fee_b: 0,
        );

    state.facade.advance_time(seconds: HOUR);

    state
        .facade
        .redeem_from_vault_with_interest(
            vault: vault_config,
            withdrawing_user: redeeming_user,
            receiving_user: redeeming_user,
            shares_to_burn_user: 1000,
            value_of_shares_user: 500,
            shares_to_burn_vault: 1000,
            value_of_shares_vault: 500,
            actual_shares_user: 1000,
            actual_collateral_user: 500,
            interest_amount_vault_position: 0,
            interest_amount_sender: -1,
            interest_amount_receiver: 0,
            other_collaterals: array![].span(),
        );
}

#[test]
#[should_panic(expected: "INVALID_INTEREST_RATE")]
fn test_redeem_from_vault_non_zero_interest_without_time_advance() {
    // No advance_time => last_interest_applied_time is zero (first interest calc).
    // Any non-zero interest must fail with INVALID_INTEREST_RATE.
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let vault_user = state.new_user_with_position();
    let redeeming_user = state.new_user_with_position();

    state
        .facade
        .process_deposit(
            state.facade.deposit(vault_user.account, vault_user.position_id, 5000_u64),
        );
    let vault_config = state.facade.register_vault_share_spot_asset(vault_user, asset_name: 'VS_1');
    state.facade.price_tick(@vault_config.asset_info, 1);

    state
        .facade
        .process_deposit(
            state.facade.deposit(redeeming_user.account, redeeming_user.position_id, 10_000_u64),
        );
    state
        .facade
        .process_deposit(
            state
                .facade
                .deposit_into_vault(
                    vault: vault_config,
                    amount_to_invest: 1000,
                    min_shares_to_receive: 500,
                    depositing_user: redeeming_user,
                    receiving_user: redeeming_user,
                ),
        );

    state
        .facade
        .redeem_from_vault_with_interest(
            vault: vault_config,
            withdrawing_user: redeeming_user,
            receiving_user: redeeming_user,
            shares_to_burn_user: 400,
            value_of_shares_user: 399,
            shares_to_burn_vault: 400,
            value_of_shares_vault: 399,
            actual_shares_user: 400,
            actual_collateral_user: 399,
            interest_amount_vault_position: 0,
            interest_amount_sender: 1,
            interest_amount_receiver: 0,
            other_collaterals: array![].span(),
        );
}

#[test]
fn test_redeem_from_vault_with_interest_different_receiver() {
    // 3-position scenario: sender != receiver.
    // When sender != receiver:
    //   sender collateral_diff = interest_amount_sender (no redeem collateral)
    //   receiver collateral_diff = value_to_receive + interest_amount_receiver
    //   vault collateral_diff = -value_to_receive + interest_amount_vault_position
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let vault_user = state.new_user_with_position();
    let withdrawing_user = state.new_user_with_position();
    // Receiver is a second position under the same owner, so the redeem is allowed.
    let receiving_user = state.new_sibling_position(withdrawing_user);

    state
        .facade
        .process_deposit(
            state.facade.deposit(vault_user.account, vault_user.position_id, 5000_u64),
        );
    let vault_config = state.facade.register_vault_share_spot_asset(vault_user, asset_name: 'VS_1');
    state.facade.price_tick(@vault_config.asset_info, 1);

    // Set vault protection limit high to allow redemptions in this test
    state.facade.update_vault_protection_limit(vault_user.position_id, 100);

    state
        .facade
        .process_deposit(
            state
                .facade
                .deposit(withdrawing_user.account, withdrawing_user.position_id, 10_000_u64),
        );
    state
        .facade
        .process_deposit(
            state.facade.deposit(receiving_user.account, receiving_user.position_id, 10_000_u64),
        );
    state
        .facade
        .process_deposit(
            state
                .facade
                .deposit_into_vault(
                    vault: vault_config,
                    amount_to_invest: 1000,
                    min_shares_to_receive: 500,
                    depositing_user: withdrawing_user,
                    receiving_user: withdrawing_user,
                ),
        );

    // Set treasury protection to 100% for vault share token after deposits fund the treasury.
    state
        .facade
        .set_treasury_protection_percent_for_token(
            vault_config.deployed_vault.contract_address, 100,
        );

    state.facade.advance_time(seconds: HOUR);

    let sender_collateral_before = state
        .facade
        .get_position_collateral_balance(withdrawing_user.position_id);
    let receiver_collateral_before = state
        .facade
        .get_position_collateral_balance(receiving_user.position_id);
    let vault_collateral_before = state
        .facade
        .get_position_collateral_balance(vault_config.position_id);

    // All three positions have positive collateral → all receive (positive) interest.
    // Vault PnL = 6000, max_allowed ~ 6. Sender PnL = 9000, max ~ 9.
    // Receiver PnL = 10000, max ~ 10.
    let interest_vault: i64 = 3;
    let interest_sender: i64 = 2;
    let interest_receiver: i64 = 4;
    let value_of_shares: u64 = 399;

    state
        .facade
        .redeem_from_vault_with_interest(
            vault: vault_config,
            withdrawing_user: withdrawing_user,
            receiving_user: receiving_user,
            shares_to_burn_user: 400,
            value_of_shares_user: value_of_shares,
            shares_to_burn_vault: 400,
            value_of_shares_vault: value_of_shares,
            actual_shares_user: 400,
            actual_collateral_user: value_of_shares,
            interest_amount_vault_position: interest_vault,
            interest_amount_sender: interest_sender,
            interest_amount_receiver: interest_receiver,
            other_collaterals: array![].span(),
        );

    // Sender gets only interest (shares burned, no collateral from redeem)
    state
        .facade
        .validate_collateral_balance(
            position_id: withdrawing_user.position_id,
            expected_balance: sender_collateral_before + interest_sender.into(),
        );
    println!("Sender verified")
    // Receiver gets collateral from redeem + interest
    state
        .facade
        .validate_collateral_balance(
            position_id: receiving_user.position_id,
            expected_balance: receiver_collateral_before
                + value_of_shares.into()
                + interest_receiver.into(),
        );
    println!("Receiver verified")
    // Vault loses collateral, gains interest
    state
        .facade
        .validate_collateral_balance(
            position_id: vault_config.position_id,
            expected_balance: vault_collateral_before
                - value_of_shares.into()
                + interest_vault.into(),
        );
    println!("Vault verified")
}

// ============================================================================
// owner-account protection for value-exit flows
//
// Any position with an `owner_account` is protected: a compromised Stark key must not be able to
// route value out of it. Transfers and vault invest/redeem may only move value to a position
// under the SAME owner_account, and withdrawals may only target the owner_account address.
// Operator-driven liquidation / forced redeem are exempt. Positions created via the flow-test
// helpers always have an owner_account, so the protection is active by default.
// ============================================================================

#[test]
#[should_panic(expected: 'TRANSFER_NOT_TO_SAME_OWNER')]
fn test_transfer_to_different_owner_fails() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let user_1 = state.new_user_with_position();
    // A genuinely different owner (its own owner_account), not a sibling.
    let attacker = state.new_user_with_position();

    state
        .facade
        .process_deposit(state.facade.deposit(user_1.account, user_1.position_id, 10_000_u64));

    // user_1 has an owner_account, so a transfer to a different owner's position must revert.
    let transfer_info = state
        .facade
        .transfer_request(sender: user_1, recipient: attacker, amount: 1000);
    state.facade.transfer(:transfer_info);
}

#[test]
#[should_panic(expected: 'WITHDRAWAL_RECIPIENT_NOT_OWNER')]
fn test_withdraw_to_non_owner_fails() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let user = state.new_user_with_position();
    let attacker = state.new_user_with_position();

    state.facade.process_deposit(state.facade.deposit(user.account, user.position_id, 10_000_u64));

    // user has an owner_account, so withdrawals may only target the owner_account address.
    state.facade.withdraw_to_recipient(user, 1000, attacker.account.address);
}

#[test]
#[should_panic(expected: 'INVEST_NOT_TO_SAME_OWNER')]
fn test_invest_in_vault_owner_only_blocks_different_owner_receiver() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let vault_user = state.new_user_with_position();
    let investing_user = state.new_user_with_position();
    let attacker = state.new_user_with_position();

    state
        .facade
        .process_deposit(
            state.facade.deposit(vault_user.account, vault_user.position_id, 100_000_u64),
        );
    let vault_config = state.facade.register_vault_share_spot_asset(vault_user, asset_name: 'VS_1');
    state.facade.price_tick(@vault_config.asset_info, 1);

    state
        .facade
        .process_deposit(
            state.facade.deposit(investing_user.account, investing_user.position_id, 100_000_u64),
        );

    // investing_user has an owner_account, so the protection is active by default.
    // Routing the minted shares into a position owned by a different account must revert.
    state
        .facade
        .deposit_into_vault(
            vault: vault_config,
            amount_to_invest: 1000,
            min_shares_to_receive: 500,
            depositing_user: investing_user,
            receiving_user: attacker,
        );
}

#[test]
fn test_invest_in_vault_owner_only_allows_same_owner_receiver() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let vault_user = state.new_user_with_position();
    let investing_user = state.new_user_with_position();
    // A second position controlled by the same owner_account as `investing_user`.
    let sibling = state.new_sibling_position(investing_user);

    state
        .facade
        .process_deposit(
            state.facade.deposit(vault_user.account, vault_user.position_id, 100_000_u64),
        );
    let vault_config = state.facade.register_vault_share_spot_asset(vault_user, asset_name: 'VS_1');
    state.facade.price_tick(@vault_config.asset_info, 1);

    state
        .facade
        .process_deposit(
            state.facade.deposit(investing_user.account, investing_user.position_id, 100_000_u64),
        );

    // investing_user has an owner_account, so the protection is active by default.
    // Shares may still be credited to a different position under the same owner.
    state
        .facade
        .process_deposit(
            state
                .facade
                .deposit_into_vault(
                    vault: vault_config,
                    amount_to_invest: 1000,
                    min_shares_to_receive: 500,
                    depositing_user: investing_user,
                    receiving_user: sibling,
                ),
        );
}

#[test]
#[should_panic(expected: 'REDEEM_NOT_TO_SAME_OWNER')]
fn test_redeem_from_vault_owner_only_blocks_different_owner_receiver() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let vault_user = state.new_user_with_position();
    let withdrawing_user = state.new_user_with_position();
    let attacker = state.new_user_with_position();

    state
        .facade
        .process_deposit(
            state.facade.deposit(vault_user.account, vault_user.position_id, 5000_u64),
        );
    let vault_config = state.facade.register_vault_share_spot_asset(vault_user, asset_name: 'VS_1');
    state.facade.price_tick(@vault_config.asset_info, 1);
    state.facade.update_vault_protection_limit(vault_user.position_id, 100);

    state
        .facade
        .process_deposit(
            state
                .facade
                .deposit(withdrawing_user.account, withdrawing_user.position_id, 10_000_u64),
        );
    state
        .facade
        .process_deposit(
            state
                .facade
                .deposit_into_vault(
                    vault: vault_config,
                    amount_to_invest: 1000,
                    min_shares_to_receive: 500,
                    depositing_user: withdrawing_user,
                    receiving_user: withdrawing_user,
                ),
        );

    state
        .facade
        .set_treasury_protection_percent_for_token(
            vault_config.deployed_vault.contract_address, 100,
        );

    // withdrawing_user has an owner_account, so the protection is active by default.
    // Redeeming into a different owner's position must revert.
    state
        .facade
        .redeem_from_vault(
            vault: vault_config,
            withdrawing_user: withdrawing_user,
            receiving_user: attacker,
            shares_to_burn_user: 400,
            value_of_shares_user: 399,
            shares_to_burn_vault: 400,
            value_of_shares_vault: 399,
            actual_shares_user: 400,
            actual_collateral_user: 399,
            other_collaterals: array![].span(),
        );
}

#[test]
fn test_redeem_from_vault_owner_only_allows_same_owner_receiver() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let vault_user = state.new_user_with_position();
    let withdrawing_user = state.new_user_with_position();
    // A second position controlled by the same owner_account as `withdrawing_user`.
    let sibling = state.new_sibling_position(withdrawing_user);

    state
        .facade
        .process_deposit(
            state.facade.deposit(vault_user.account, vault_user.position_id, 5000_u64),
        );
    let vault_config = state.facade.register_vault_share_spot_asset(vault_user, asset_name: 'VS_1');
    state.facade.price_tick(@vault_config.asset_info, 1);
    state.facade.update_vault_protection_limit(vault_user.position_id, 100);

    state
        .facade
        .process_deposit(
            state
                .facade
                .deposit(withdrawing_user.account, withdrawing_user.position_id, 10_000_u64),
        );
    state
        .facade
        .process_deposit(
            state
                .facade
                .deposit_into_vault(
                    vault: vault_config,
                    amount_to_invest: 1000,
                    min_shares_to_receive: 500,
                    depositing_user: withdrawing_user,
                    receiving_user: withdrawing_user,
                ),
        );

    state
        .facade
        .set_treasury_protection_percent_for_token(
            vault_config.deployed_vault.contract_address, 100,
        );

    // withdrawing_user has an owner_account, so the protection is active by default.
    let receiver_collateral_before = state
        .facade
        .get_position_collateral_balance(sibling.position_id);

    // Collateral may still be redeemed into a different position under the same owner.
    state
        .facade
        .redeem_from_vault(
            vault: vault_config,
            withdrawing_user: withdrawing_user,
            receiving_user: sibling,
            shares_to_burn_user: 400,
            value_of_shares_user: 399,
            shares_to_burn_vault: 400,
            value_of_shares_vault: 399,
            actual_shares_user: 400,
            actual_collateral_user: 399,
            other_collaterals: array![].span(),
        );

    state
        .facade
        .validate_collateral_balance(
            position_id: sibling.position_id,
            expected_balance: receiver_collateral_before + 399_u64.into(),
        );
}

// Removed `test_redeem_from_vault_negative_interest_on_vault_makes_vault_unhealthy`: its
// scenario (operator passes negative interest to a vault position) is now rejected upstream
// by the sign rule (vault positions always hold positive collateral, so interest must be
// non-negative). The analogous sender/receiver-leg variants below cover the
// "negative interest tips an unhealthy redeem" semantic on user positions.

#[test]
#[should_panic(expected: "POSITION_NOT_HEALTHY_NOR_HEALTHIER")]
fn test_redeem_from_vault_negative_interest_makes_receiver_unhealthy() {
    // Receiver buys 200 BTC@100 => collateral = -10000, TV = 10000, TR = 10000. Borderline.
    // Redeem 400 shares for $9 to receiver: collateral_diff = 9 + interest_receiver.
    // interest_receiver = -10: TV = 10000 + 9 - 10 = 9999 < TR = 10000. Unhealthy!
    // Receiver PnL = 10000. max_allowed = floor(10000*3600*1200/2^32) = 10. Within bounds.
    let risk_factor_data = RiskFactorTiers {
        tiers: array![500].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let synthetic_info = AssetInfoTrait::new(
        asset_name: 'BTC_1', :risk_factor_data, oracles_len: 1,
    );
    let asset_id = synthetic_info.asset_id;
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    state.facade.add_active_synthetic(synthetic_info: @synthetic_info, initial_price: 100);

    let vault_user = state.new_user_with_position();
    let withdrawing_user = state.new_user_with_position();
    // Receiver is a second position under the same owner, so the redeem is allowed.
    let receiving_user = state.new_sibling_position(withdrawing_user);
    let trade_user = state.new_user_with_position();

    state
        .facade
        .process_deposit(
            state.facade.deposit(vault_user.account, vault_user.position_id, 5000_u64),
        );
    let vault_config = state.facade.register_vault_share_spot_asset(vault_user, asset_name: 'VS_1');
    state.facade.price_tick(@vault_config.asset_info, 1);

    state
        .facade
        .process_deposit(
            state
                .facade
                .deposit(withdrawing_user.account, withdrawing_user.position_id, 10_000_u64),
        );
    state
        .facade
        .process_deposit(
            state.facade.deposit(receiving_user.account, receiving_user.position_id, 10_000_u64),
        );
    state
        .facade
        .process_deposit(
            state.facade.deposit(trade_user.account, trade_user.position_id, 100_000_u64),
        );
    state
        .facade
        .process_deposit(
            state
                .facade
                .deposit_into_vault(
                    vault: vault_config,
                    amount_to_invest: 1000,
                    min_shares_to_receive: 500,
                    depositing_user: withdrawing_user,
                    receiving_user: withdrawing_user,
                ),
        );

    // Set treasury protection to 100% for vault share token after deposits fund the treasury.
    state
        .facade
        .set_treasury_protection_percent_for_token(
            vault_config.deployed_vault.contract_address, 100,
        );

    // Receiver buys 200 BTC@100 => collateral = -10000, TV = 10000, TR = 10000.
    let recv_order = state
        .facade
        .create_order(
            user: receiving_user,
            base_amount: 200,
            base_asset_id: asset_id,
            quote_amount: -20000,
            fee_amount: 0,
        );
    let counter_order = state
        .facade
        .create_order(
            user: trade_user,
            base_amount: -200,
            base_asset_id: asset_id,
            quote_amount: 20000,
            fee_amount: 0,
        );
    state
        .facade
        .trade(
            order_info_a: recv_order,
            order_info_b: counter_order,
            base: 200,
            quote: -20000,
            fee_a: 0,
            fee_b: 0,
        );

    state.facade.advance_time(seconds: HOUR);

    state
        .facade
        .redeem_from_vault_with_interest(
            vault: vault_config,
            withdrawing_user: withdrawing_user,
            receiving_user: receiving_user,
            shares_to_burn_user: 400,
            value_of_shares_user: 9,
            shares_to_burn_vault: 400,
            value_of_shares_vault: 9,
            actual_shares_user: 400,
            actual_collateral_user: 9,
            interest_amount_vault_position: 0,
            interest_amount_sender: 0,
            interest_amount_receiver: -10,
            other_collaterals: array![].span(),
        );
}

#[test]
#[should_panic(expected: "INVALID_INTEREST_RATE")]
fn test_redeem_from_vault_receiver_interest_exceeds_max_allowed() {
    // Receiver deposits 10000, no synthetics. PnL = 10000.
    // max_allowed = floor(10000*3600*1200/2^32) = 10.
    // interest_amount_receiver = 11 exceeds max_allowed => INVALID_INTEREST_RATE.
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let vault_user = state.new_user_with_position();
    let withdrawing_user = state.new_user_with_position();
    // Receiver is a second position under the same owner, so the redeem is allowed.
    let receiving_user = state.new_sibling_position(withdrawing_user);

    state
        .facade
        .process_deposit(
            state.facade.deposit(vault_user.account, vault_user.position_id, 5000_u64),
        );
    let vault_config = state.facade.register_vault_share_spot_asset(vault_user, asset_name: 'VS_1');
    state.facade.price_tick(@vault_config.asset_info, 1);

    state
        .facade
        .process_deposit(
            state
                .facade
                .deposit(withdrawing_user.account, withdrawing_user.position_id, 10_000_u64),
        );
    state
        .facade
        .process_deposit(
            state.facade.deposit(receiving_user.account, receiving_user.position_id, 10_000_u64),
        );
    state
        .facade
        .process_deposit(
            state
                .facade
                .deposit_into_vault(
                    vault: vault_config,
                    amount_to_invest: 1000,
                    min_shares_to_receive: 500,
                    depositing_user: withdrawing_user,
                    receiving_user: withdrawing_user,
                ),
        );

    state.facade.advance_time(seconds: HOUR);

    state
        .facade
        .redeem_from_vault_with_interest(
            vault: vault_config,
            withdrawing_user: withdrawing_user,
            receiving_user: receiving_user,
            shares_to_burn_user: 400,
            value_of_shares_user: 399,
            shares_to_burn_vault: 400,
            value_of_shares_vault: 399,
            actual_shares_user: 400,
            actual_collateral_user: 399,
            interest_amount_vault_position: 0,
            interest_amount_sender: 0,
            interest_amount_receiver: 11,
            other_collaterals: array![].span(),
        );
}


#[test]
fn test_liquidate_spot_with_synthetics_tr_nonzero() {
    // Position has both spot collateral AND a synthetic, so TR != 0.
    // Spot price drops making the combined position liquidatable.
    let spot_risk_factor_data = RiskFactorTiers {
        tiers: array![100].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let synthetic_risk_factor_data = RiskFactorTiers {
        tiers: array![500].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    // Create a spot collateral asset.
    let token = snforge_std::Token::STRK;
    let erc20_contract_address = token.contract_address();
    let spot_info = AssetInfoTrait::new_collateral(
        asset_name: 'SPOT',
        risk_factor_data: spot_risk_factor_data,
        oracles_len: 1,
        :erc20_contract_address,
    );
    let spot_id = spot_info.asset_id;
    state.facade.add_active_collateral(asset_info: @spot_info, initial_price: 100);

    // Create a synthetic asset.
    let synthetic_info = AssetInfoTrait::new(
        asset_name: 'BTC_1', risk_factor_data: synthetic_risk_factor_data, oracles_len: 1,
    );
    let synthetic_id = synthetic_info.asset_id;
    state.facade.add_active_synthetic(synthetic_info: @synthetic_info, initial_price: 100);

    let liquidated_user = state.new_user_with_position();
    let liquidator_user = state.new_user_with_position();
    let trade_counterparty = state.new_user_with_position();
    snforge_std::set_balance(target: liquidated_user.account.address, new_balance: 5000000, :token);

    // Deposit spot collateral to liquidated user.
    let deposit_spot = state
        .facade
        .deposit_spot(
            depositor: liquidated_user.account,
            asset_id: spot_id,
            position_id: liquidated_user.position_id,
            quantized_amount: 5000,
        );
    state.facade.process_deposit(deposit_info: deposit_spot);

    // Deposit base collateral to liquidator and counterparty.
    let deposit_liquidator = state
        .facade
        .deposit(
            depositor: liquidator_user.account,
            position_id: liquidator_user.position_id,
            quantized_amount: 200000,
        );
    state.facade.process_deposit(deposit_info: deposit_liquidator);
    let deposit_counterparty = state
        .facade
        .deposit(
            depositor: trade_counterparty.account,
            position_id: trade_counterparty.position_id,
            quantized_amount: 200000,
        );
    state.facade.process_deposit(deposit_info: deposit_counterparty);

    // Give liquidated user a BTC long (2 BTC @ 100 => value 200, risk 100).
    let order_liquidated = state
        .facade
        .create_order(
            user: liquidated_user,
            base_amount: 2,
            base_asset_id: synthetic_id,
            quote_amount: -200,
            fee_amount: 0,
        );
    let order_counter = state
        .facade
        .create_order(
            user: trade_counterparty,
            base_amount: -2,
            base_asset_id: synthetic_id,
            quote_amount: 200,
            fee_amount: 0,
        );
    state
        .facade
        .trade(
            order_info_a: order_liquidated,
            order_info_b: order_counter,
            base: 2,
            quote: -200,
            fee_a: 0,
            fee_b: 0,
        );

    // Create negative base collateral via transfer.
    state.drain_collateral(liquidated_user, 4900);

    // At spot price 100:
    //   Collateral: -200 (trade) - 4900 (transfer) = -5100
    //   Spot: 5000 * 100 = 500000, spot_risk = 5000 * 100 * 0.1 = 50000
    //   Synthetic: 2 * 100 = 200, synthetic_risk = 2 * 100 * 0.5 = 100
    //   TV = -5100 + 500000 - 50000 + 200 = 445100, TR = 100 => healthy
    state
        .facade
        .validate_total_risk(position_id: liquidated_user.position_id, expected_total_risk: 100);
    assert(state.facade.is_healthy(position_id: liquidated_user.position_id), 'should be healthy');

    // Drop spot price to 1 to make position liquidatable.
    state.facade.price_tick(asset_info: @spot_info, price: 1);

    // At spot price 1:
    //   Collateral: -5100
    //   Spot: 5000 * 1 = 5000, spot_risk = 5000 * 1 * 0.1 = 500
    //   Synthetic: 2 * 100 = 200, synthetic_risk = 100
    //   TV = -5100 + 5000 - 500 + 200 = -400, TR = 100
    //   TV < TR => liquidatable
    state
        .facade
        .validate_total_value(position_id: liquidated_user.position_id, expected_total_value: -400);
    state
        .facade
        .validate_total_risk(position_id: liquidated_user.position_id, expected_total_risk: 100);
    assert(
        state.facade.is_liquidatable(position_id: liquidated_user.position_id),
        'user is not liquidatable',
    );

    // Liquidate spot: sell 4800 spot units to liquidator for 4900 base collateral.
    let liquidator_order_info = state
        .facade
        .create_limit_order(
            user: liquidator_user,
            base_asset_id: spot_id,
            base_amount: 4800,
            quote_amount: -4900,
            fee_amount: 50,
            receive_position_id: Option::None,
        );

    state
        .facade
        .liquidate_spot_asset(
            :liquidated_user,
            :liquidator_order_info,
            actual_amount_spot_collateral: -4800,
            actual_amount_base_collateral: 4900,
            actual_liquidator_fee: 50,
            liquidated_fee_amount: 50,
        );

    // After liquidation at spot price 1:
    //   Collateral: -5100 + 4900 - 50 = -250
    //   Spot: (5000 - 4800) * 1 = 200, spot_risk = 200 * 1 * 0.1 = 20
    //   Synthetic: 2 * 100 = 200, synthetic_risk = 100
    //   TV = -250 + 200 - 20 + 200 = 130, TR = 100
    //   TV > TR => healthy
    state
        .facade
        .validate_total_value(position_id: liquidated_user.position_id, expected_total_value: 130);
    state
        .facade
        .validate_total_risk(position_id: liquidated_user.position_id, expected_total_risk: 100);
    assert(state.facade.is_healthy(position_id: liquidated_user.position_id), 'should be healthy');
}

#[test]
fn test_liquidate_synthetic_with_spot_in_position() {
    // Position holds spot collateral + a synthetic. Synthetic price moves against the position
    // making it liquidatable. Use the regular liquidate (synthetic) to liquidate.
    let spot_risk_factor_data = RiskFactorTiers {
        tiers: array![100].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let synthetic_risk_factor_data = RiskFactorTiers {
        tiers: array![500].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    let token = snforge_std::Token::STRK;
    let erc20_contract_address = token.contract_address();
    let spot_info = AssetInfoTrait::new_collateral(
        asset_name: 'SPOT',
        risk_factor_data: spot_risk_factor_data,
        oracles_len: 1,
        :erc20_contract_address,
    );
    let spot_id = spot_info.asset_id;
    state.facade.add_active_collateral(asset_info: @spot_info, initial_price: 10);

    let synthetic_info = AssetInfoTrait::new(
        asset_name: 'BTC_1', risk_factor_data: synthetic_risk_factor_data, oracles_len: 1,
    );
    let synthetic_id = synthetic_info.asset_id;
    state.facade.add_active_synthetic(synthetic_info: @synthetic_info, initial_price: 100);

    let liquidated_user = state.new_user_with_position();
    let liquidator_user = state.new_user_with_position();
    snforge_std::set_balance(target: liquidated_user.account.address, new_balance: 5000000, :token);

    // Deposit spot collateral to liquidated user.
    let deposit_spot = state
        .facade
        .deposit_spot(
            depositor: liquidated_user.account,
            asset_id: spot_id,
            position_id: liquidated_user.position_id,
            quantized_amount: 1000,
        );
    state.facade.process_deposit(deposit_info: deposit_spot);

    // Deposit base collateral to liquidator.
    let deposit_liquidator = state
        .facade
        .deposit(
            depositor: liquidator_user.account,
            position_id: liquidator_user.position_id,
            quantized_amount: 200000,
        );
    state.facade.process_deposit(deposit_info: deposit_liquidator);

    // Give liquidated user a BTC long (100 BTC @ 100).
    let order_liq = state
        .facade
        .create_order(
            user: liquidated_user,
            base_amount: 100,
            base_asset_id: synthetic_id,
            quote_amount: -10000,
            fee_amount: 0,
        );
    let order_counter = state
        .facade
        .create_order(
            user: liquidator_user,
            base_amount: -100,
            base_asset_id: synthetic_id,
            quote_amount: 10000,
            fee_amount: 0,
        );
    state
        .facade
        .trade(
            order_info_a: order_liq,
            order_info_b: order_counter,
            base: 100,
            quote: -10000,
            fee_a: 0,
            fee_b: 0,
        );

    // At BTC price 100, spot price 10:
    //   Collateral: -10000
    //   Spot: 1000 * 10 = 10000, spot_risk = 1000 * 10 * 0.1 = 1000
    //   Synthetic: 100 * 100 = 10000, synthetic_risk = 100 * 100 * 0.5 = 5000
    //   TV = -10000 + 10000 - 1000 + 10000 = 9000, TR = 5000 => healthy
    assert(state.facade.is_healthy(position_id: liquidated_user.position_id), 'should be healthy');

    // Drop synthetic price to make position liquidatable.
    state.facade.price_tick(asset_info: @synthetic_info, price: 11);

    // At BTC price 11, spot price 10:
    //   Collateral: -10000
    //   Spot: 10000, spot_risk = 1000
    //   Synthetic: 100 * 11 = 1100, synthetic_risk = 100 * 11 * 0.5 = 550
    //   TV = -10000 + 10000 - 1000 + 1100 = 100, TR = 550 => liquidatable
    state
        .facade
        .validate_total_value(position_id: liquidated_user.position_id, expected_total_value: 100);
    state
        .facade
        .validate_total_risk(position_id: liquidated_user.position_id, expected_total_risk: 550);
    assert(
        state.facade.is_liquidatable(position_id: liquidated_user.position_id),
        'user is not liquidatable',
    );

    // Liquidate the synthetic (not spot) using regular liquidate.
    let liquidator_order = state
        .facade
        .create_order(
            user: liquidator_user,
            base_amount: 50,
            base_asset_id: synthetic_id,
            quote_amount: -600,
            fee_amount: 10,
        );
    state
        .facade
        .liquidate(
            :liquidated_user,
            :liquidator_order,
            liquidated_base: -50,
            liquidated_quote: 600,
            liquidated_insurance_fee: 10,
            liquidator_fee: 10,
        );

    // After liquidation at BTC price 11, spot price 10:
    //   Collateral: -10000 + 600 - 10 = -9410
    //   Spot: 10000, spot_risk = 1000
    //   Synthetic: 50 * 11 = 550, synthetic_risk = 50 * 11 * 0.5 = 275
    //   TV = -9410 + 10000 - 1000 + 550 = 140, TR = 275
    //   Spot collateral remains intact.
    state
        .facade
        .validate_asset_balance(
            position_id: liquidated_user.position_id,
            asset_id: spot_id,
            expected_balance: 1000_i64.into(),
        );
    state
        .facade
        .validate_total_value(position_id: liquidated_user.position_id, expected_total_value: 140);
    state
        .facade
        .validate_total_risk(position_id: liquidated_user.position_id, expected_total_risk: 275);
}

#[test]
fn test_spot_deleverage() {
    // Setup: position with only spot collateral, negative base collateral, TV < 0.
    let risk_factor_data = RiskFactorTiers {
        tiers: array![100].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    let token = snforge_std::Token::STRK;
    let erc20_contract_address = token.contract_address();
    let asset_info = AssetInfoTrait::new_collateral(
        asset_name: 'SPOT', :risk_factor_data, oracles_len: 1, :erc20_contract_address,
    );
    let asset_id = asset_info.asset_id;
    state.facade.add_active_collateral(asset_info: @asset_info, initial_price: 100);

    let deleveraged_user = state.new_user_with_position();
    let deleverager_user = state.new_user_with_position();
    snforge_std::set_balance(
        target: deleveraged_user.account.address, new_balance: 5000000, :token,
    );
    snforge_std::set_balance(
        target: deleverager_user.account.address, new_balance: 5000000, :token,
    );

    // Deposit spot collateral to deleveraged user.
    let deposit_spot = state
        .facade
        .deposit_spot(
            depositor: deleveraged_user.account,
            asset_id: asset_id,
            position_id: deleveraged_user.position_id,
            quantized_amount: 10000,
        );
    state.facade.process_deposit(deposit_info: deposit_spot);

    // Deposit base collateral to deleverager.
    let deposit_deleverager = state
        .facade
        .deposit(
            depositor: deleverager_user.account,
            position_id: deleverager_user.position_id,
            quantized_amount: 200000,
        );
    state.facade.process_deposit(deposit_info: deposit_deleverager);

    // Transfer out base collateral to make the deleveraged user's collateral negative.
    state.drain_collateral(deleveraged_user, 10100);

    // At spot price 100:
    //   Collateral: -10100
    //   Spot: 10000 * 100 = 1000000, spot_risk = 10000 * 100 * 0.1 = 100000
    //   spot_tv = 1000000 - 100000 = 900000
    //   TV = -10100 + 900000 = 889900, TR = 0 => healthy
    state
        .facade
        .validate_total_value(
            position_id: deleveraged_user.position_id, expected_total_value: 889900,
        );
    state
        .facade
        .validate_total_risk(position_id: deleveraged_user.position_id, expected_total_risk: 0);
    assert(state.facade.is_healthy(position_id: deleveraged_user.position_id), 'should be healthy');

    // Massive price drop to make position deleveragable (TV < 0).
    state.facade.price_tick(asset_info: @asset_info, price: 1);

    // At spot price 1:
    //   Collateral: -10100
    //   Spot: 10000 * 1 = 10000, spot_risk = 10000 * 1 * 0.1 = 1000
    //   spot_tv = 10000 - 1000 = 9000 (the only spot, so total_spot_tv = 9000)
    //   TV = -10100 + 9000 = -1100, TR = 0
    //   TV < 0 => deleveragable
    state
        .facade
        .validate_total_value(
            position_id: deleveraged_user.position_id, expected_total_value: -1100,
        );
    state
        .facade
        .validate_total_risk(position_id: deleveraged_user.position_id, expected_total_risk: 0);
    assert(
        state.facade.is_deleveragable(position_id: deleveraged_user.position_id),
        'should be deleveragable',
    );

    // Fair spot deleverage: sell all 10000 spot units.
    // Formula: collateral_diff / |debt| == asset_tv / total_spot_tv
    // Only one spot asset, so asset_tv == total_spot_tv => ratio = 1.
    // Therefore collateral_diff / |debt| must == 1, i.e. collateral_diff == |debt| = 10100.
    // After: collateral = -10100 + 10100 = 0, spot = 0, TV = 0, TR = 0.
    state
        .facade
        .deleverage(
            :deleveraged_user,
            :deleverager_user,
            base_asset_id: asset_id,
            deleveraged_base: -10000,
            deleveraged_quote: 10100,
        );

    // Position fully closed.
    state
        .facade
        .validate_total_value(position_id: deleveraged_user.position_id, expected_total_value: 0);
    state
        .facade
        .validate_total_risk(position_id: deleveraged_user.position_id, expected_total_risk: 0);
}

#[test]
#[should_panic(expected: "POSITION_IS_NOT_FAIR_SPOT_DELEVERAGE")]
fn test_unfair_spot_deleverage() {
    // Two spot assets: deleverage one with wrong proportional split.
    // The position becomes healthier overall, but the ratio is unfair.
    let risk_factor_data = RiskFactorTiers {
        tiers: array![100].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    let strk_token = snforge_std::Token::STRK;
    let strk_erc20 = strk_token.contract_address();
    let spot_info_1 = AssetInfoTrait::new_collateral(
        asset_name: 'SPOT_A', :risk_factor_data, oracles_len: 1, erc20_contract_address: strk_erc20,
    );
    let spot_id_1 = spot_info_1.asset_id;
    state.facade.add_active_collateral(asset_info: @spot_info_1, initial_price: 10);

    let eth_token = snforge_std::Token::ETH;
    let eth_erc20 = eth_token.contract_address();
    let spot_info_2 = AssetInfoTrait::new_collateral(
        asset_name: 'SPOT_B', :risk_factor_data, oracles_len: 1, erc20_contract_address: eth_erc20,
    );
    let spot_id_2 = spot_info_2.asset_id;
    state.facade.add_active_collateral(asset_info: @spot_info_2, initial_price: 10);

    let deleveraged_user = state.new_user_with_position();
    let deleverager_user = state.new_user_with_position();
    snforge_std::set_balance(
        target: deleveraged_user.account.address, new_balance: 50000000, token: strk_token,
    );
    snforge_std::set_balance(
        target: deleveraged_user.account.address, new_balance: 50000000, token: eth_token,
    );
    snforge_std::set_balance(
        target: deleverager_user.account.address, new_balance: 50000000, token: strk_token,
    );
    snforge_std::set_balance(
        target: deleverager_user.account.address, new_balance: 50000000, token: eth_token,
    );

    // Deposit 1000 SPOT_A and 3000 SPOT_B.
    let dep_a = state
        .facade
        .deposit_spot(
            depositor: deleveraged_user.account,
            asset_id: spot_id_1,
            position_id: deleveraged_user.position_id,
            quantized_amount: 1000,
        );
    state.facade.process_deposit(deposit_info: dep_a);

    let dep_b = state
        .facade
        .deposit_spot(
            depositor: deleveraged_user.account,
            asset_id: spot_id_2,
            position_id: deleveraged_user.position_id,
            quantized_amount: 3000,
        );
    state.facade.process_deposit(deposit_info: dep_b);

    let deposit_deleverager = state
        .facade
        .deposit(
            depositor: deleverager_user.account,
            position_id: deleverager_user.position_id,
            quantized_amount: 200000,
        );
    state.facade.process_deposit(deposit_info: deposit_deleverager);

    state.drain_collateral(deleveraged_user, 10000);

    // Price drop: both spots at price 1.
    // SPOT_A TV = 900, SPOT_B TV = 2700, total_spot_tv = 3600.
    // Collateral = -10000, TV = -6400, TR = 0 => deleveragable.
    state.facade.price_tick(asset_info: @spot_info_1, price: 1);
    state.facade.price_tick(asset_info: @spot_info_2, price: 1);

    assert(
        state.facade.is_deleveragable(position_id: deleveraged_user.position_id),
        'should be deleveragable',
    );

    // Fair collateral_diff for SPOT_A = 10000 * 900 / 3600 = 2500.
    // Give 5000 instead (too much) — position is healthier but unfair ratio.
    state
        .facade
        .deleverage(
            :deleveraged_user,
            :deleverager_user,
            base_asset_id: spot_id_1,
            deleveraged_base: -1000,
            deleveraged_quote: 5000,
        );
}

#[test]
fn test_partial_spot_deleverage() {
    // Partial deleverage: sell half the spot, position stays deleveragable.
    let risk_factor_data = RiskFactorTiers {
        tiers: array![100].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    let token = snforge_std::Token::STRK;
    let erc20_contract_address = token.contract_address();
    let asset_info = AssetInfoTrait::new_collateral(
        asset_name: 'SPOT', :risk_factor_data, oracles_len: 1, :erc20_contract_address,
    );
    let asset_id = asset_info.asset_id;
    state.facade.add_active_collateral(asset_info: @asset_info, initial_price: 100);

    let deleveraged_user = state.new_user_with_position();
    let deleverager_user = state.new_user_with_position();
    snforge_std::set_balance(
        target: deleveraged_user.account.address, new_balance: 5000000, :token,
    );
    snforge_std::set_balance(
        target: deleverager_user.account.address, new_balance: 5000000, :token,
    );

    let deposit_spot = state
        .facade
        .deposit_spot(
            depositor: deleveraged_user.account,
            asset_id: asset_id,
            position_id: deleveraged_user.position_id,
            quantized_amount: 10000,
        );
    state.facade.process_deposit(deposit_info: deposit_spot);

    let deposit_deleverager = state
        .facade
        .deposit(
            depositor: deleverager_user.account,
            position_id: deleverager_user.position_id,
            quantized_amount: 200000,
        );
    state.facade.process_deposit(deposit_info: deposit_deleverager);

    state.drain_collateral(deleveraged_user, 10100);

    state.facade.price_tick(asset_info: @asset_info, price: 1);

    // At spot price 1:
    //   Collateral: -10100, Spot TV = 9000, TV = -1100, TR = 0
    assert(
        state.facade.is_deleveragable(position_id: deleveraged_user.position_id),
        'should be deleveragable',
    );

    // Partial deleverage: sell 5000 out of 10000 spot units.
    // Single spot asset so asset_tv / total_spot_tv = 1.
    // collateral_diff must == |debt| * 1 = 10100. But we're only selling half...
    // The asset_tv before the deleverage is 9000, total_spot_tv is 9000.
    // asset_tv/total_spot_tv = 1, so collateral_diff = |debt| = 10100.
    // After: collateral = -10100 + 10100 = 0, spot = 5000, TV = 0 + 4500 = 4500.
    state
        .facade
        .deleverage(
            :deleveraged_user,
            :deleverager_user,
            base_asset_id: asset_id,
            deleveraged_base: -5000,
            deleveraged_quote: 10100,
        );

    // Position should now be healthy with remaining spot.
    // Collateral: 0, Spot: 5000 * 1 = 5000, spot_risk = 500, TV = 4500, TR = 0
    state
        .facade
        .validate_total_value(
            position_id: deleveraged_user.position_id, expected_total_value: 4500,
        );
    state
        .facade
        .validate_total_risk(position_id: deleveraged_user.position_id, expected_total_risk: 0);
    assert(state.facade.is_healthy(position_id: deleveraged_user.position_id), 'should be healthy');
}

#[test]
fn test_spot_deleverage_two_spot_assets() {
    // Two spot assets: deleverage one, fairness check uses proportional ratio.
    let risk_factor_data = RiskFactorTiers {
        tiers: array![100].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    let strk_token = snforge_std::Token::STRK;
    let strk_erc20 = strk_token.contract_address();
    let spot_info_1 = AssetInfoTrait::new_collateral(
        asset_name: 'SPOT_A', :risk_factor_data, oracles_len: 1, erc20_contract_address: strk_erc20,
    );
    let spot_id_1 = spot_info_1.asset_id;
    state.facade.add_active_collateral(asset_info: @spot_info_1, initial_price: 10);

    let eth_token = snforge_std::Token::ETH;
    let eth_erc20 = eth_token.contract_address();
    let spot_info_2 = AssetInfoTrait::new_collateral(
        asset_name: 'SPOT_B', :risk_factor_data, oracles_len: 1, erc20_contract_address: eth_erc20,
    );
    let spot_id_2 = spot_info_2.asset_id;
    state.facade.add_active_collateral(asset_info: @spot_info_2, initial_price: 10);

    let deleveraged_user = state.new_user_with_position();
    let deleverager_user = state.new_user_with_position();
    snforge_std::set_balance(
        target: deleveraged_user.account.address, new_balance: 50000000, token: strk_token,
    );
    snforge_std::set_balance(
        target: deleveraged_user.account.address, new_balance: 50000000, token: eth_token,
    );
    snforge_std::set_balance(
        target: deleverager_user.account.address, new_balance: 50000000, token: strk_token,
    );
    snforge_std::set_balance(
        target: deleverager_user.account.address, new_balance: 50000000, token: eth_token,
    );

    // Deposit 1000 of SPOT_A and 3000 of SPOT_B to deleveraged user.
    let dep_a = state
        .facade
        .deposit_spot(
            depositor: deleveraged_user.account,
            asset_id: spot_id_1,
            position_id: deleveraged_user.position_id,
            quantized_amount: 1000,
        );
    state.facade.process_deposit(deposit_info: dep_a);

    let dep_b = state
        .facade
        .deposit_spot(
            depositor: deleveraged_user.account,
            asset_id: spot_id_2,
            position_id: deleveraged_user.position_id,
            quantized_amount: 3000,
        );
    state.facade.process_deposit(deposit_info: dep_b);

    let deposit_deleverager = state
        .facade
        .deposit(
            depositor: deleverager_user.account,
            position_id: deleverager_user.position_id,
            quantized_amount: 200000,
        );
    state.facade.process_deposit(deposit_info: deposit_deleverager);

    // Transfer out base collateral to create debt (position stays healthy at price 10).
    // At price 10: SPOT_A TV = 1000*10 - 1000*10*0.1 = 9000, SPOT_B TV = 3000*10 - 3000*10*0.1 =
    // 27000 total_spot_tv = 36000. Transfer 10000 so collateral = -10000, TV = 26000 (still
    // healthy).
    state.drain_collateral(deleveraged_user, 10000);

    assert(state.facade.is_healthy(position_id: deleveraged_user.position_id), 'should be healthy');

    // Price drop to make position deleveragable (TV < 0).
    // At price 1: SPOT_A value = 1000, risk = 100, TV_A = 900.
    //             SPOT_B value = 3000, risk = 300, TV_B = 2700.
    //             total_spot_tv = 900 + 2700 = 3600.
    //             Collateral = -10000, TV = -10000 + 3600 = -6400, TR = 0.
    state.facade.price_tick(asset_info: @spot_info_1, price: 1);
    state.facade.price_tick(asset_info: @spot_info_2, price: 1);

    state
        .facade
        .validate_total_value(
            position_id: deleveraged_user.position_id, expected_total_value: -6400,
        );
    state
        .facade
        .validate_total_risk(position_id: deleveraged_user.position_id, expected_total_risk: 0);
    assert(
        state.facade.is_deleveragable(position_id: deleveraged_user.position_id),
        'should be deleveragable',
    );

    // Deleverage SPOT_A (asset_tv = 900, total_spot_tv = 3600).
    // collateral_diff = |debt| * asset_tv / total_spot_tv = 10000 * 900 / 3600 = 2500.
    state
        .facade
        .deleverage(
            :deleveraged_user,
            :deleverager_user,
            base_asset_id: spot_id_1,
            deleveraged_base: -1000,
            deleveraged_quote: 2500,
        );

    // After: Collateral = -10000 + 2500 = -7500, SPOT_A = 0, SPOT_B TV = 2700
    // TV = -7500 + 2700 = -4800, TR = 0
    state
        .facade
        .validate_total_value(
            position_id: deleveraged_user.position_id, expected_total_value: -4800,
        );
    state
        .facade
        .validate_total_risk(position_id: deleveraged_user.position_id, expected_total_risk: 0);
}

#[test]
fn test_liquidate_spot_deleveraged_stays_deleveraged() {
    // Create a deeply underwater position (TV < 0, deleveragable).
    // Liquidate spot to improve it, but keep TV still negative.
    let risk_factor_data = RiskFactorTiers {
        tiers: array![100].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    let token = snforge_std::Token::STRK;
    let erc20_contract_address = token.contract_address();
    let asset_info = AssetInfoTrait::new_collateral(
        asset_name: 'SPOT', :risk_factor_data, oracles_len: 1, :erc20_contract_address,
    );
    let asset_id = asset_info.asset_id;
    state.facade.add_active_collateral(asset_info: @asset_info, initial_price: 100);

    let liquidated_user = state.new_user_with_position();
    let liquidator_user = state.new_user_with_position();
    snforge_std::set_balance(target: liquidated_user.account.address, new_balance: 5000000, :token);
    snforge_std::set_balance(target: liquidator_user.account.address, new_balance: 5000000, :token);

    // Deposit spot collateral.
    let deposit_spot = state
        .facade
        .deposit_spot(
            depositor: liquidated_user.account,
            asset_id: asset_id,
            position_id: liquidated_user.position_id,
            quantized_amount: 10000,
        );
    state.facade.process_deposit(deposit_info: deposit_spot);

    let deposit_liquidator = state
        .facade
        .deposit(
            depositor: liquidator_user.account,
            position_id: liquidator_user.position_id,
            quantized_amount: 200000,
        );
    state.facade.process_deposit(deposit_info: deposit_liquidator);

    // Transfer out a large amount of base collateral.
    state.drain_collateral(liquidated_user, 10100);

    // At spot price 100:
    //   Collateral: -10100
    //   Spot: 10000 * 100 = 1000000, spot_risk = 100000
    //   TV = -10100 + 1000000 - 100000 = 889900, TR = 0 => healthy
    assert(state.facade.is_healthy(position_id: liquidated_user.position_id), 'should be healthy');

    // Massive price drop to make position deleveragable (TV < 0).
    state.facade.price_tick(asset_info: @asset_info, price: 1);

    // At spot price 1:
    //   Collateral: -10100
    //   Spot: 10000 * 1 = 10000, spot_risk = 10000 * 1 * 0.1 = 1000
    //   TV = -10100 + 10000 - 1000 = -1100, TR = 0
    //   TV < 0 => deleveragable
    state
        .facade
        .validate_total_value(
            position_id: liquidated_user.position_id, expected_total_value: -1100,
        );
    assert(
        state.facade.is_deleveragable(position_id: liquidated_user.position_id),
        'should be deleveragable',
    );

    // Partial liquidation: sell 5000 spot units, receive 5050 base collateral.
    let liquidator_order_info = state
        .facade
        .create_limit_order(
            user: liquidator_user,
            base_asset_id: asset_id,
            base_amount: 5000,
            quote_amount: -5050,
            fee_amount: 50,
            receive_position_id: Option::None,
        );

    state
        .facade
        .liquidate_spot_asset(
            :liquidated_user,
            :liquidator_order_info,
            actual_amount_spot_collateral: -5000,
            actual_amount_base_collateral: 5050,
            actual_liquidator_fee: 50,
            liquidated_fee_amount: 0,
        );

    // After liquidation at spot price 1:
    //   Collateral: -10100 + 5050 - 0 = -5050
    //   Spot: 5000 * 1 = 5000, spot_risk = 500
    //   TV = -5050 + 5000 - 500 = -550, TR = 0
    //   TV still < 0 => still deleveragable
    state
        .facade
        .validate_total_value(position_id: liquidated_user.position_id, expected_total_value: -550);
    assert(
        state.facade.is_deleveragable(position_id: liquidated_user.position_id),
        'should still be deleveragable',
    );
}

#[test]
#[should_panic(expected: 'INVALID_SAME_POSITIONS')]
fn test_liquidate_spot_receiver_is_liquidated_position() {
    let risk_factor_data = RiskFactorTiers {
        tiers: array![100].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    let token = snforge_std::Token::STRK;
    let erc20_contract_address = token.contract_address();
    let asset_info = AssetInfoTrait::new_collateral(
        asset_name: 'SPOT', :risk_factor_data, oracles_len: 1, :erc20_contract_address,
    );
    let asset_id = asset_info.asset_id;
    state.facade.add_active_collateral(asset_info: @asset_info, initial_price: 100);

    let liquidated_user = state.new_user_with_position();
    let liquidator_user = state.new_user_with_position();

    // Set receive_position to the liquidated position.
    let liquidator_order_info = state
        .facade
        .create_limit_order(
            user: liquidator_user,
            base_asset_id: asset_id,
            base_amount: 9500,
            quote_amount: -9600,
            fee_amount: 100,
            receive_position_id: Option::Some(liquidated_user.position_id),
        );

    state
        .facade
        .liquidate_spot_asset(
            :liquidated_user,
            :liquidator_order_info,
            actual_amount_spot_collateral: -9500,
            actual_amount_base_collateral: 9600,
            actual_liquidator_fee: 100,
            liquidated_fee_amount: 100,
        );
}

#[test]
#[should_panic(expected: 'CANT_LIQUIDATE_IF_POSITION')]
fn test_liquidate_spot_receiver_is_insurance_fund() {
    let risk_factor_data = RiskFactorTiers {
        tiers: array![100].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    let token = snforge_std::Token::STRK;
    let erc20_contract_address = token.contract_address();
    let asset_info = AssetInfoTrait::new_collateral(
        asset_name: 'SPOT', :risk_factor_data, oracles_len: 1, :erc20_contract_address,
    );
    let asset_id = asset_info.asset_id;
    state.facade.add_active_collateral(asset_info: @asset_info, initial_price: 100);

    let liquidated_user = state.new_user_with_position();
    let liquidator_user = state.new_user_with_position();

    // Set receive_position to INSURANCE_FUND_POSITION.
    let liquidator_order_info = state
        .facade
        .create_limit_order(
            user: liquidator_user,
            base_asset_id: asset_id,
            base_amount: 9500,
            quote_amount: -9600,
            fee_amount: 100,
            receive_position_id: Option::Some(INSURANCE_FUND_POSITION),
        );

    state
        .facade
        .liquidate_spot_asset(
            :liquidated_user,
            :liquidator_order_info,
            actual_amount_spot_collateral: -9500,
            actual_amount_base_collateral: 9600,
            actual_liquidator_fee: 100,
            liquidated_fee_amount: 100,
        );
}

#[test]
#[should_panic(expected: 'CANT_LIQUIDATE_WITH_FP')]
fn test_liquidate_spot_receiver_is_fee_position() {
    let risk_factor_data = RiskFactorTiers {
        tiers: array![100].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    let token = snforge_std::Token::STRK;
    let erc20_contract_address = token.contract_address();
    let asset_info = AssetInfoTrait::new_collateral(
        asset_name: 'SPOT', :risk_factor_data, oracles_len: 1, :erc20_contract_address,
    );
    let asset_id = asset_info.asset_id;
    state.facade.add_active_collateral(asset_info: @asset_info, initial_price: 100);

    let liquidated_user = state.new_user_with_position();
    let liquidator_user = state.new_user_with_position();

    // Set receive_position to FEE_POSITION.
    let liquidator_order_info = state
        .facade
        .create_limit_order(
            user: liquidator_user,
            base_asset_id: asset_id,
            base_amount: 9500,
            quote_amount: -9600,
            fee_amount: 100,
            receive_position_id: Option::Some(FEE_POSITION),
        );

    state
        .facade
        .liquidate_spot_asset(
            :liquidated_user,
            :liquidator_order_info,
            actual_amount_spot_collateral: -9500,
            actual_amount_base_collateral: 9600,
            actual_liquidator_fee: 100,
            liquidated_fee_amount: 100,
        );
}

#[test]
#[should_panic(expected: 'INVALID_SHRINK_TO_NEGATIVE')]
fn test_liquidate_spot_too_many_spots() {
    let risk_factor_data = RiskFactorTiers {
        tiers: array![100].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    let token = snforge_std::Token::STRK;
    let erc20_contract_address = token.contract_address();
    let asset_info = AssetInfoTrait::new_collateral(
        asset_name: 'SPOT', :risk_factor_data, oracles_len: 1, :erc20_contract_address,
    );
    let asset_id = asset_info.asset_id;
    state.facade.add_active_collateral(asset_info: @asset_info, initial_price: 100);

    let liquidated_user = state.new_user_with_position();
    let liquidator_user = state.new_user_with_position();
    snforge_std::set_balance(target: liquidated_user.account.address, new_balance: 5000000, :token);

    // Deposit 5000 spot collateral.
    let deposit_spot = state
        .facade
        .deposit_spot(
            depositor: liquidated_user.account,
            asset_id: asset_id,
            position_id: liquidated_user.position_id,
            quantized_amount: 5000,
        );
    state.facade.process_deposit(deposit_info: deposit_spot);

    let deposit_liquidator = state
        .facade
        .deposit(
            depositor: liquidator_user.account,
            position_id: liquidator_user.position_id,
            quantized_amount: 200000,
        );
    state.facade.process_deposit(deposit_info: deposit_liquidator);

    state.drain_collateral(liquidated_user, 4900);

    state.facade.price_tick(asset_info: @asset_info, price: 1);

    assert(
        state.facade.is_liquidatable(position_id: liquidated_user.position_id),
        'user is not liquidatable',
    );

    // Try to liquidate 6000 spots but position only has 5000.
    let liquidator_order_info = state
        .facade
        .create_limit_order(
            user: liquidator_user,
            base_asset_id: asset_id,
            base_amount: 6000,
            quote_amount: -6100,
            fee_amount: 50,
            receive_position_id: Option::None,
        );

    state
        .facade
        .liquidate_spot_asset(
            :liquidated_user,
            :liquidator_order_info,
            actual_amount_spot_collateral: -6000,
            actual_amount_base_collateral: 6100,
            actual_liquidator_fee: 50,
            liquidated_fee_amount: 50,
        );
}

#[test]
fn test_liquidate_spot_with_interest_different_receiver() {
    // 3-position scenario (source != receiver) with interest on all three positions.
    let risk_factor_data = RiskFactorTiers {
        tiers: array![100].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    let token = snforge_std::Token::STRK;
    let erc20_contract_address = token.contract_address();
    let asset_info = AssetInfoTrait::new_collateral(
        asset_name: 'SPOT', :risk_factor_data, oracles_len: 1, :erc20_contract_address,
    );
    let asset_id = asset_info.asset_id;
    state.facade.add_active_collateral(asset_info: @asset_info, initial_price: 100);

    let liquidated_user = state.new_user_with_position();
    let liquidator_source_user = state.new_user_with_position();
    let liquidator_receive_user = state.new_user_with_position();
    snforge_std::set_balance(target: liquidated_user.account.address, new_balance: 5000000, :token);

    // Deposit spot collateral to liquidated user.
    let deposit_spot = state
        .facade
        .deposit_spot(
            depositor: liquidated_user.account,
            asset_id: asset_id,
            position_id: liquidated_user.position_id,
            quantized_amount: 9800,
        );
    state.facade.process_deposit(deposit_info: deposit_spot);

    // Deposit base collateral to liquidator source and receive positions.
    let deposit_source = state
        .facade
        .deposit(
            depositor: liquidator_source_user.account,
            position_id: liquidator_source_user.position_id,
            quantized_amount: 200000,
        );
    state.facade.process_deposit(deposit_info: deposit_source);

    let deposit_receive = state
        .facade
        .deposit(
            depositor: liquidator_receive_user.account,
            position_id: liquidator_receive_user.position_id,
            quantized_amount: 200000,
        );
    state.facade.process_deposit(deposit_info: deposit_receive);

    // Create negative base collateral for liquidated user.
    state.drain_collateral(liquidated_user, 9500);

    state.facade.price_tick(asset_info: @asset_info, price: 1);

    assert(
        state.facade.is_liquidatable(position_id: liquidated_user.position_id),
        'user is not liquidatable',
    );

    // Advance time to allow interest calculation.
    state.facade.advance_time(seconds: HOUR);

    let liquidator_order_info = state
        .facade
        .create_limit_order(
            user: liquidator_source_user,
            base_asset_id: asset_id,
            base_amount: 9500,
            quote_amount: -9600,
            fee_amount: 100,
            receive_position_id: Option::Some(liquidator_receive_user.position_id),
        );

    // Sign rule per pre-liquidation collateral:
    //   liquidated has -9500 (negative) → pays interest;
    //   liquidator_source has +209500 (positive) → receives interest;
    //   liquidator_receiver has +200000 (positive) → receives interest.
    state
        .facade
        .liquidate_spot_asset_with_interest(
            liquidated_user: liquidated_user,
            :liquidator_order_info,
            actual_amount_spot_collateral: -9500,
            actual_amount_base_collateral: 9600,
            actual_liquidator_fee: 100,
            liquidated_fee_amount: 100,
            interest_amount_liquidated: -3,
            interest_amount_liquidator: 2,
            interest_amount_liquidator_receiver: 1,
        );

    assert(state.facade.is_healthy(position_id: liquidated_user.position_id), 'should be healthy');
}

#[test]
fn test_transfer_with_interest() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    let user_1 = state.new_user_with_position();
    // Same owner as user_1 so the transfer is allowed; interest still applies to both.
    let user_2 = state.new_sibling_position(user_1);

    let deposit_info = state
        .facade
        .deposit(
            depositor: user_1.account, position_id: user_1.position_id, quantized_amount: 100_000,
        );
    state.facade.process_deposit(deposit_info: deposit_info);

    let deposit_info_2 = state
        .facade
        .deposit(
            depositor: user_2.account, position_id: user_2.position_id, quantized_amount: 50_000,
        );
    state.facade.process_deposit(deposit_info: deposit_info_2);

    state.facade.advance_time(seconds: HOUR);

    let transfer_info = state
        .facade
        .transfer_request(sender: user_1, recipient: user_2, amount: 40_000);
    // Both have positive collateral → both receive (positive) interest.
    state
        .facade
        .transfer_with_interest(
            :transfer_info, interest_amount_sender: 50, interest_amount_recipient: 30,
        );
}

#[test]
fn test_liquidate_with_interest() {
    let risk_factor_data = RiskFactorTiers {
        tiers: array![10].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let synthetic_info = AssetInfoTrait::new(
        asset_name: 'BTC_1', :risk_factor_data, oracles_len: 1,
    );
    let asset_id = synthetic_info.asset_id;

    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    state.facade.add_active_synthetic(synthetic_info: @synthetic_info, initial_price: 100);

    let liquidated_user = state.new_user_with_position();
    let liquidator_user = state.new_user_with_position();

    state
        .facade
        .process_deposit(
            state
                .facade
                .deposit(
                    depositor: liquidated_user.account,
                    position_id: liquidated_user.position_id,
                    quantized_amount: 100_000,
                ),
        );
    state
        .facade
        .process_deposit(
            state
                .facade
                .deposit(
                    depositor: liquidator_user.account,
                    position_id: liquidator_user.position_id,
                    quantized_amount: 100_000,
                ),
        );

    // Buy 30,000 BTC at 100. collateral = -2,900,000, synth_value = 3,000,000.
    // PnL = 100,000. TR = 30,000.
    let order_liquidated = state
        .facade
        .create_order(
            user: liquidated_user,
            base_amount: 30_000,
            base_asset_id: asset_id,
            quote_amount: -3_000_000,
            fee_amount: 0,
        );
    let order_liquidator = state
        .facade
        .create_order(
            user: liquidator_user,
            base_amount: -30_000,
            base_asset_id: asset_id,
            quote_amount: 3_000_000,
            fee_amount: 0,
        );
    state
        .facade
        .trade(
            order_info_a: order_liquidated,
            order_info_b: order_liquidator,
            base: 30_000,
            quote: -3_000_000,
            fee_a: 0,
            fee_b: 0,
        );

    // New Funding index is 3, delta = (old - new) * balance = (0 -3) * 30,000 = -90,000.
    // TV = 100,000 - 90,000 = 10,000 < TR = 30,000 → liquidatable.
    // PnL ≈ 10,000.
    state.facade.advance_time(10000);
    let new_funding_index = FundingIndex { value: 3 * FUNDING_SCALE };
    state
        .facade
        .funding_tick(
            funding_ticks: array![
                FundingTick { asset_id: asset_id, funding_index: new_funding_index },
            ]
                .span(),
        );

    assert(
        state.facade.is_liquidatable(position_id: liquidated_user.position_id),
        'user is not liquidatable',
    );

    // max_allowed ≈ 10,000 * 36,000 * 1,200 / 2^32 ≈ 100.
    state.facade.advance_time(seconds: 10 * HOUR);

    let liquidator_order = state
        .facade
        .create_order(
            user: liquidator_user,
            base_amount: 30_000,
            base_asset_id: asset_id,
            quote_amount: -3_000_000,
            fee_amount: 1,
        );

    state
        .facade
        .liquidate_with_interest(
            :liquidated_user,
            :liquidator_order,
            liquidated_base: -30_000,
            liquidated_quote: 3_000_000,
            liquidated_insurance_fee: 3,
            liquidator_fee: 1,
            interest_amount_liquidated: -20,
            interest_amount_liquidator: 50,
        );
}

#[test]
fn test_deleverage_with_interest() {
    let risk_factor_data = RiskFactorTiers {
        tiers: array![10].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let synthetic_info = AssetInfoTrait::new(
        asset_name: 'BTC_1', :risk_factor_data, oracles_len: 1,
    );
    let asset_id = synthetic_info.asset_id;

    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    state.facade.add_active_synthetic(synthetic_info: @synthetic_info, initial_price: 100);

    let deleveraged_user = state.new_user_with_position();
    let deleverager_user = state.new_user_with_position();

    state
        .facade
        .process_deposit(
            state
                .facade
                .deposit(
                    depositor: deleveraged_user.account,
                    position_id: deleveraged_user.position_id,
                    quantized_amount: 100_000,
                ),
        );
    state
        .facade
        .process_deposit(
            state
                .facade
                .deposit(
                    depositor: deleverager_user.account,
                    position_id: deleverager_user.position_id,
                    quantized_amount: 100_000,
                ),
        );

    // Buy 30,000 BTC at 100. collateral = -2,900,000, synth_value = 3,000,000.
    // PnL = 100,000.
    let order_deleveraged = state
        .facade
        .create_order(
            user: deleveraged_user,
            base_amount: 30_000,
            base_asset_id: asset_id,
            quote_amount: -3_000_000,
            fee_amount: 0,
        );
    let order_deleverager = state
        .facade
        .create_order(
            user: deleverager_user,
            base_amount: -30_000,
            base_asset_id: asset_id,
            quote_amount: 3_000_000,
            fee_amount: 0,
        );
    state
        .facade
        .trade(
            order_info_a: order_deleveraged,
            order_info_b: order_deleverager,
            base: 30_000,
            quote: -3_000_000,
            fee_a: 0,
            fee_b: 0,
        );

    // New Funding index is 4, delta = (old - new) * balance = (0 - 4) * 30,000 = -120,000.
    // TV = 100,000 - 120,000 = -20,000 < 0 → deleveragable.
    // |PnL| ≈ 20,000.
    state.facade.advance_time(10000);
    let new_funding_index = FundingIndex { value: 4 * FUNDING_SCALE };
    state
        .facade
        .funding_tick(
            funding_ticks: array![
                FundingTick { asset_id: asset_id, funding_index: new_funding_index },
            ]
                .span(),
        );

    assert(
        state.facade.is_deleveragable(position_id: deleveraged_user.position_id),
        'user is not deleveragable',
    );

    // max_allowed ≈ 20,000 * 36,000 * 1,200 / 2^32 ≈ 200.
    state.facade.advance_time(seconds: 10 * HOUR);

    // Full close. Collateral balance: -2,900,000 - 120,000 = -3,020,000.
    // Sign rule: deleveraged has negative balance → pays interest (negative); deleverager has
    // positive balance → receives interest (positive).
    // For fair deleverage (TR=0 requires TV=0): quote_amount = 3,020,000 + |interest| = 3,020,010.
    state
        .facade
        .deleverage_with_interest(
            :deleveraged_user,
            :deleverager_user,
            base_asset_id: asset_id,
            deleveraged_base: -30_000,
            deleveraged_quote: 3_020_010,
            interest_amount_deleveraged: -10,
            interest_amount_deleverager: 50,
        );
}

#[test]
fn test_invest_in_vault_with_interest() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let vault_user = state.new_user_with_position();
    let investing_user = state.new_user_with_position();

    let vault_init_deposit = state
        .facade
        .deposit(vault_user.account, vault_user.position_id, 100_000_u64);
    state.facade.process_deposit(vault_init_deposit);
    let vault_config = state.facade.register_vault_share_spot_asset(vault_user, asset_name: 'VS_1');
    state.facade.price_tick(@vault_config.asset_info, 1);

    state
        .facade
        .process_deposit(
            state.facade.deposit(investing_user.account, investing_user.position_id, 100_000_u64),
        );

    state.facade.advance_time(seconds: HOUR);

    state
        .facade
        .process_deposit(
            state
                .facade
                .deposit_into_vault_with_interest(
                    vault: vault_config,
                    amount_to_invest: 1000,
                    min_shares_to_receive: 500,
                    depositing_user: investing_user,
                    receiving_user: investing_user,
                    // Both positions have positive collateral → both receive (positive) interest.
                    interest_amount_vault_position: 50,
                    interest_amount_sender: 30,
                ),
        );
}

#[test]
fn test_liquidate_vault_shares_with_interest() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let vault_user = state.new_user_with_position_id(333_u32.into());
    let trade_user = state.new_user_with_position();
    let liquidated_user = state.new_user_with_position_id(555_u32.into());

    // Large vault deposit so vault position PnL supports interest amount.
    let vault_init_deposit = state
        .facade
        .deposit(vault_user.account, vault_user.position_id, 100_000_u64);
    state.facade.process_deposit(vault_init_deposit);
    let vault_config = state.facade.register_vault_share_spot_asset(vault_user, asset_name: 'VS_1');
    state.facade.price_tick(@vault_config.asset_info, 1);

    state
        .facade
        .process_deposit(
            state.facade.deposit(liquidated_user.account, liquidated_user.position_id, 1000_u64),
        );
    state
        .facade
        .process_deposit(
            state.facade.deposit(trade_user.account, trade_user.position_id, 1000_u64),
        );

    state
        .facade
        .process_deposit(
            state
                .facade
                .deposit_into_vault(
                    vault: vault_config,
                    amount_to_invest: 1000,
                    min_shares_to_receive: 500,
                    depositing_user: liquidated_user,
                    receiving_user: liquidated_user,
                ),
        );

    // Set treasury protection to 100% for vault share token after deposits fund the treasury.
    state
        .facade
        .set_treasury_protection_percent_for_token(
            vault_config.deployed_vault.contract_address, 100,
        );

    let risk_factor_data = RiskFactorTiers {
        tiers: array![300].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let synthetic_info = AssetInfoTrait::new(
        asset_name: 'BTC_1', :risk_factor_data, oracles_len: 1,
    );
    let asset_id = synthetic_info.asset_id;
    state.facade.add_active_synthetic(synthetic_info: @synthetic_info, initial_price: 1000);

    let user_order = state
        .facade
        .create_order(
            user: liquidated_user,
            base_amount: 2,
            base_asset_id: asset_id,
            quote_amount: -2000,
            fee_amount: 0,
        );
    let other_side_order = state
        .facade
        .create_order(
            user: trade_user,
            base_amount: -2,
            base_asset_id: asset_id,
            quote_amount: 2000,
            fee_amount: 0,
        );
    state
        .facade
        .trade(
            order_info_a: user_order,
            order_info_b: other_side_order,
            base: 2,
            quote: -2000,
            fee_a: 0,
            fee_b: 0,
        );

    state.facade.price_tick(@synthetic_info, 600);

    assert(
        state.facade.is_liquidatable(position_id: liquidated_user.position_id),
        'user is not liquidatable',
    );

    // Advance time then refresh prices + funding for validity.
    // Liquidated PnL (synth only) ≈ -800. Vault PnL ≈ 100,000.
    // max_allowed (100 hours): liquidated ≈ 80, vault ≈ 10,000.
    state.facade.advance_time(seconds: 100 * HOUR);
    state.facade.price_tick(@synthetic_info, 600);
    state.facade.price_tick(@vault_config.asset_info, 1);
    state
        .facade
        .funding_tick(
            funding_ticks: array![
                FundingTick {
                    asset_id: synthetic_info.asset_id, funding_index: FundingIndex { value: 0 },
                },
            ]
                .span(),
        );

    state
        .facade
        .liquidate_shares_with_interest(
            vault: vault_config,
            :liquidated_user,
            shares_to_burn_vault: 400,
            value_of_shares_vault: 400,
            actual_shares_user: 400,
            actual_collateral_user: 400,
            interest_amount_vault_position: 50,
            interest_amount_liquidated: -20,
            other_collaterals: array![].span(),
        );
}
