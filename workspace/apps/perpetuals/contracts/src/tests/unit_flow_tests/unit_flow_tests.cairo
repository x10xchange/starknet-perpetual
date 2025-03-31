use perpetuals::core::types::funding::{FUNDING_SCALE, FundingIndex, FundingTick};
use perpetuals::tests::constants::*;
use perpetuals::tests::perps_tests_facade::*;
use perpetuals::tests::unit_flow_infra::*;
use starkware_utils::constants::MAX_U128;
use super::unit_flow_infra::{TestDataState, TestDataStateTrait};

#[test]
fn test_deleverage_after_funding_tick() {
    // Setup.
    let risk_factor_data = RiskFactorTiers {
        tiers: array![1].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    // Create a custom asset configuration to test interesting risk factor scenarios.
    let synthetic_info = SyntheticInfoTrait::new(
        asset_name: 'BTC_1', :risk_factor_data, oracles_len: 1,
    );
    let asset_id = synthetic_info.asset_id;

    let mut test_data_state: TestDataState = TestDataStateTrait::new();

    test_data_state
        .perpetual_contract_data
        .add_active_synthetic(synthetic_info: @synthetic_info, initial_price: 100);

    // Create users.
    let delevereged_user = test_data_state.new_user_with_position();
    let delevereger_user_1 = test_data_state.new_user_with_position();
    let delevereger_user_2 = test_data_state.new_user_with_position();

    // Deposit to users.
    let deposit_info_user_1 = test_data_state
        .perpetual_contract_data
        .deposit(
            depositor: delevereger_user_1.account,
            position_id: delevereger_user_1.position_id,
            quantized_amount: 100000,
        );
    test_data_state.perpetual_contract_data.process_deposit(deposit_info: deposit_info_user_1);

    let deposit_info_user_2 = test_data_state
        .perpetual_contract_data
        .deposit(
            depositor: delevereger_user_2.account,
            position_id: delevereger_user_2.position_id,
            quantized_amount: 100000,
        );
    test_data_state.perpetual_contract_data.process_deposit(deposit_info: deposit_info_user_2);

    // Create orders.
    let order_delevereged_user = test_data_state
        .perpetual_contract_data
        .create_order(
            user: delevereged_user,
            base_amount: 2,
            base_asset_id: asset_id,
            quote_amount: -168,
            fee_amount: 20,
        );

    let order_delevereger_user_1 = test_data_state
        .perpetual_contract_data
        .create_order(
            user: delevereger_user_1,
            base_amount: -1,
            base_asset_id: asset_id,
            quote_amount: 50,
            fee_amount: 2,
        );

    let order_delevereger_user_2 = test_data_state
        .perpetual_contract_data
        .create_order(
            user: delevereger_user_2,
            base_amount: -1,
            base_asset_id: asset_id,
            quote_amount: 84,
            fee_amount: 2,
        );

    // Make trades.
    test_data_state
        .perpetual_contract_data
        .trade(
            order_info_a: order_delevereged_user,
            order_info_b: order_delevereger_user_1,
            base: 1,
            quote: -84,
            fee_a: 10,
            fee_b: 3,
        );

    test_data_state
        .perpetual_contract_data
        .trade(
            order_info_a: order_delevereged_user,
            order_info_b: order_delevereger_user_2,
            base: 1,
            quote: -84,
            fee_a: 10,
            fee_b: 1,
        );

    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // Delevereged User:   -188 + 2 * 100 = 12                 2 * 100 * 0.01 = 2           6
    test_data_state
        .perpetual_contract_data
        .validate_total_value(position_id: delevereged_user.position_id, expected_total_value: 12);
    test_data_state
        .perpetual_contract_data
        .validate_total_risk(position_id: delevereged_user.position_id, expected_total_risk: 2);

    advance_time(10000);
    let mut new_funding_index = FundingIndex { value: 7 * FUNDING_SCALE };
    test_data_state
        .perpetual_contract_data
        .funding_tick(
            funding_ticks: array![
                FundingTick { asset_id: asset_id, funding_index: new_funding_index },
            ]
                .span(),
        );

    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // Delevereged User:   -202 + 2 * 100 = -2                 2 * 100 * 0.01 = 2          - 1
    test_data_state
        .perpetual_contract_data
        .validate_total_value(position_id: delevereged_user.position_id, expected_total_value: -2);
    test_data_state
        .perpetual_contract_data
        .validate_total_risk(position_id: delevereged_user.position_id, expected_total_risk: 2);

    test_data_state
        .perpetual_contract_data
        .deleverage(
            deleveraged_user: delevereged_user,
            deleverager_user: delevereger_user_1,
            base_asset_id: asset_id,
            deleveraged_base: -1,
            deleveraged_quote: 101,
        );

    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // Delevereged User:   -101 + 1 * 100 = -1                 1 * 100 * 0.01 = 1          - 1
    test_data_state
        .perpetual_contract_data
        .validate_total_value(position_id: delevereged_user.position_id, expected_total_value: -1);
    test_data_state
        .perpetual_contract_data
        .validate_total_risk(position_id: delevereged_user.position_id, expected_total_risk: 1);
    // TODO(Tomer-StarkWare): add the following assertion.
// test_data_state
//     .perpetual_contract_data
//      .deleverage(
//         deleveraged_user: delevereged_user,
//         deleverager_user: delevereger_user_2,
//         base_asset_id: asset_id,
//         deleveraged_base: -1,
//         deleveraged_quote: 101,
//     );
}

#[test]
fn test_deleverage_after_price_tick() {
    // Setup.
    let risk_factor_data = RiskFactorTiers {
        tiers: array![10].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    // Create a custom asset configuration to test interesting risk factor scenarios.
    let synthetic_info = SyntheticInfoTrait::new(
        asset_name: 'BTC_1', :risk_factor_data, oracles_len: 1,
    );
    let asset_id = synthetic_info.asset_id;

    let mut test_data_state: TestDataState = TestDataStateTrait::new();

    test_data_state
        .perpetual_contract_data
        .add_active_synthetic(synthetic_info: @synthetic_info, initial_price: 20);

    // Create users.
    let delevereged_user = test_data_state.new_user_with_position();
    let delevereger_user = test_data_state.new_user_with_position();

    // Deposit to users.
    let deposit_info_user = test_data_state
        .perpetual_contract_data
        .deposit(
            depositor: delevereger_user.account,
            position_id: delevereger_user.position_id,
            quantized_amount: 100000,
        );
    test_data_state.perpetual_contract_data.process_deposit(deposit_info: deposit_info_user);

    // Create orders.
    let order_delevereged_user = test_data_state
        .perpetual_contract_data
        .create_order(
            user: delevereged_user,
            base_amount: 2,
            base_asset_id: asset_id,
            quote_amount: -33,
            fee_amount: 3,
        );
    let order_delevereger_user = test_data_state
        .perpetual_contract_data
        .create_order(
            user: delevereger_user,
            base_amount: -2,
            base_asset_id: asset_id,
            quote_amount: 30,
            fee_amount: 4,
        );

    // Make trades.
    test_data_state
        .perpetual_contract_data
        .trade(
            order_info_a: order_delevereged_user,
            order_info_b: order_delevereger_user,
            base: 2,
            quote: -33,
            fee_a: 3,
            fee_b: 4,
        );

    //                            TV                                  TR                    TV/TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // Delevereged User:   -36 + 2 * 20 = 4                    2 * 20 * 0.1 = 4               1
    test_data_state
        .perpetual_contract_data
        .validate_total_value(position_id: delevereged_user.position_id, expected_total_value: 4);
    test_data_state
        .perpetual_contract_data
        .validate_total_risk(position_id: delevereged_user.position_id, expected_total_risk: 4);

    test_data_state.perpetual_contract_data.price_tick(synthetic_info: @synthetic_info, price: 10);

    //                            TV                                  TR                    TV/TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // Delevereged User:   -36 + 2 * 10 = -16                  2 * 10 * 0.1 = 2               -8
    test_data_state
        .perpetual_contract_data
        .validate_total_value(position_id: delevereged_user.position_id, expected_total_value: -16);
    test_data_state
        .perpetual_contract_data
        .validate_total_risk(position_id: delevereged_user.position_id, expected_total_risk: 2);

    test_data_state
        .perpetual_contract_data
        .deleverage(
            deleveraged_user: delevereged_user,
            deleverager_user: delevereger_user,
            base_asset_id: asset_id,
            deleveraged_base: -1,
            deleveraged_quote: 18,
        );

    //                            TV                                  TR                    TV/TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // Delevereged User:    -18 + 1 * 10 = -8                 1 * 10 * 0.1 = 1               -8
    test_data_state
        .perpetual_contract_data
        .validate_total_value(position_id: delevereged_user.position_id, expected_total_value: -8);
    test_data_state
        .perpetual_contract_data
        .validate_total_risk(position_id: delevereged_user.position_id, expected_total_risk: 1);
    // TODO(Tomer-StarkWare): add the following assertion.
// test_data_state
// .perpetual_contract_data
// .deleverage(
//     deleveraged_user: delevereged_user,
//     deleverager_user: delevereger_user,
//     base_asset_id: asset_id,
//     deleveraged_base: -1,
//     deleveraged_quote: 18,
// );
}

#[test]
fn test_liquidate_after_funding_tick() {
    // Setup.
    let risk_factor_data = RiskFactorTiers {
        tiers: array![1].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    // Create a custom asset configuration to test interesting risk factor scenarios.
    let synthetic_info = SyntheticInfoTrait::new(
        asset_name: 'BTC_1', :risk_factor_data, oracles_len: 1,
    );
    let asset_id = synthetic_info.asset_id;

    let mut test_data_state: TestDataState = TestDataStateTrait::new();

    test_data_state
        .perpetual_contract_data
        .add_active_synthetic(synthetic_info: @synthetic_info, initial_price: 100);

    // Create users.
    let liquidated_user = test_data_state.new_user_with_position();
    let liquidator_user_1 = test_data_state.new_user_with_position();
    let liquidator_user_2 = test_data_state.new_user_with_position();

    // Deposit to users.
    let deposit_info_user_1 = test_data_state
        .perpetual_contract_data
        .deposit(
            depositor: liquidator_user_1.account,
            position_id: liquidator_user_1.position_id,
            quantized_amount: 100000,
        );
    test_data_state.perpetual_contract_data.process_deposit(deposit_info: deposit_info_user_1);

    let deposit_info_user_2 = test_data_state
        .perpetual_contract_data
        .deposit(
            depositor: liquidator_user_2.account,
            position_id: liquidator_user_2.position_id,
            quantized_amount: 100000,
        );
    test_data_state.perpetual_contract_data.process_deposit(deposit_info: deposit_info_user_2);

    // Create orders.
    let order_liquidated_user = test_data_state
        .perpetual_contract_data
        .create_order(
            user: liquidated_user,
            base_amount: 3,
            base_asset_id: asset_id,
            quote_amount: -285,
            fee_amount: 3,
        );

    let mut order_liquidator_user_1 = test_data_state
        .perpetual_contract_data
        .create_order(
            user: liquidator_user_1,
            base_amount: -2,
            base_asset_id: asset_id,
            quote_amount: 100,
            fee_amount: 0,
        );

    let mut order_liquidator_user_2 = test_data_state
        .perpetual_contract_data
        .create_order(
            user: liquidator_user_2,
            base_amount: -1,
            base_asset_id: asset_id,
            quote_amount: 50,
            fee_amount: 0,
        );

    // Make trade.
    test_data_state
        .perpetual_contract_data
        .trade(
            order_info_a: order_liquidated_user,
            order_info_b: order_liquidator_user_1,
            base: 2,
            quote: -190,
            fee_a: 2,
            fee_b: 0,
        );

    test_data_state
        .perpetual_contract_data
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
    test_data_state
        .perpetual_contract_data
        .validate_total_value(position_id: liquidated_user.position_id, expected_total_value: 13);
    test_data_state
        .perpetual_contract_data
        .validate_total_risk(position_id: liquidated_user.position_id, expected_total_risk: 3);

    advance_time(10000);
    let mut new_funding_index = FundingIndex { value: 4 * FUNDING_SCALE };
    test_data_state
        .perpetual_contract_data
        .funding_tick(
            funding_ticks: array![
                FundingTick { asset_id: asset_id, funding_index: new_funding_index },
            ]
                .span(),
        );

    //                            TV                                  TR                 TV / TR
    //                COLLATERAL*1 + SYNTHETIC*PRICE        |SYNTHETIC*PRICE*RISK|
    // liquidated User:    -299 + 3 * 100 = 1                 3 * 100 * 0.01 = 3           0.3
    test_data_state
        .perpetual_contract_data
        .validate_total_value(position_id: liquidated_user.position_id, expected_total_value: 1);
    test_data_state
        .perpetual_contract_data
        .validate_total_risk(position_id: liquidated_user.position_id, expected_total_risk: 3);

    order_liquidator_user_1 = test_data_state
        .perpetual_contract_data
        .create_order(
            user: liquidator_user_1,
            base_amount: 1,
            base_asset_id: asset_id,
            quote_amount: -101,
            fee_amount: 1,
        );
    test_data_state
        .perpetual_contract_data
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
    // Delevereged User:   -199 + 2 * 10 = 1                  2 * 100 * 0.01 = 2           0.5
    test_data_state
        .perpetual_contract_data
        .validate_total_value(position_id: liquidated_user.position_id, expected_total_value: 1);
    test_data_state
        .perpetual_contract_data
        .validate_total_risk(position_id: liquidated_user.position_id, expected_total_risk: 2);

    order_liquidator_user_2 = test_data_state
        .perpetual_contract_data
        .create_order(
            user: liquidator_user_2,
            base_amount: 2,
            base_asset_id: asset_id,
            quote_amount: -201,
            fee_amount: 1,
        );
    test_data_state
        .perpetual_contract_data
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
    // Delevereged User:        0 + 0 = 0                     0 * 100 * 0.01 = 0            0
    test_data_state
        .perpetual_contract_data
        .validate_total_value(position_id: liquidated_user.position_id, expected_total_value: 0);
    test_data_state
        .perpetual_contract_data
        .validate_total_risk(position_id: liquidated_user.position_id, expected_total_risk: 0);
}
