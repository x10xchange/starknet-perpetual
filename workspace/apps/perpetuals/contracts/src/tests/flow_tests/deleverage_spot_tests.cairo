use core::num::traits::{Pow, Zero};
use perpetuals::core::types::asset::synthetic::SpotAssetBalanceDiff;
use perpetuals::tests::constants::*;
use perpetuals::tests::flow_tests::infra::*;
use perpetuals::tests::flow_tests::perps_tests_facade::*;
use snforge_std::TokenTrait;
use starknet::storage::{StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess};
use starkware_utils::constants::{HOUR, MAX_U128, WEEK};
use starkware_utils::time::time::Timestamp;
use starkware_utils_testing::test_utils::TokenTrait as StarknetTokenTrait;

#[test]
fn test_deleverage_spot_asset() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    // 1. Setup spot assets
    let token_1 = snforge_std::Token::STRK;
    let erc20_1 = token_1.contract_address();
    let test_asset_1_info = AssetInfoTrait::new_collateral(
        asset_name: 'STRK',
        risk_factor_data: RiskFactorTiers {
            tiers: array![500].span(), first_tier_boundary: MAX_U128, tier_size: 1,
        },
        oracles_len: 1,
        erc20_contract_address: erc20_1,
    );
    let asset_id_1 = test_asset_1_info.asset_id;
    state.facade.add_active_collateral(asset_info: @test_asset_1_info, initial_price: 100);

    let token_2 = snforge_std::Token::ETH;
    let erc20_2 = token_2.contract_address();
    let test_asset_2_info = AssetInfoTrait::new_collateral(
        asset_name: 'ETH',
        risk_factor_data: RiskFactorTiers {
            tiers: array![250].span(), first_tier_boundary: MAX_U128, tier_size: 1,
        },
        oracles_len: 1,
        erc20_contract_address: erc20_2,
    );
    let asset_id_2 = test_asset_2_info.asset_id;
    state.facade.add_active_collateral(asset_info: @test_asset_2_info, initial_price: 100);

    // 2. Setup users
    let deleveraged_user = state.new_user_with_position();
    let deleverager_user = state.new_user_with_position();

    // Mint tokens
    snforge_std::set_balance(
        target: deleveraged_user.account.address, new_balance: 5000000, token: token_1,
    );
    snforge_std::set_balance(
        target: deleveraged_user.account.address, new_balance: 5000000, token: token_2,
    );

    // 3. Deposit Base Collateral (USDC)
    // Deleverager needs a large amount of USDC to take over the spot assets.
    let deposit_info_deleverager = state
        .facade
        .deposit(deleverager_user.account, deleverager_user.position_id, 100000);
    state.facade.process_deposit(deposit_info_deleverager);

    // 4. Deposit Spot Assets for deleveraged user
    // The user has STRK and ETH as spot collateral.
    let deposit_spo_1 = state
        .facade
        .deposit_spot(deleveraged_user.account, asset_id_1, deleveraged_user.position_id, 100);
    state.facade.process_deposit(deposit_spo_1);

    let deposit_spo_2 = state
        .facade
        .deposit_spot(deleveraged_user.account, asset_id_2, deleveraged_user.position_id, 50);
    state.facade.process_deposit(deposit_spo_2);

    // Initial Risk Adjusted Value:
    // STRK: 100 * 100 * 0.5 = 5000
    // ETH: 50 * 100 * 0.75 = 3750
    // Total Value = 8750

    // 5. Open Synthetic Position to take a loss
    let risk_factor_data_synth = RiskFactorTiers {
        tiers: array![1].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let synthetic_info = AssetInfoTrait::new(
        asset_name: 'BTC_PERP', risk_factor_data: risk_factor_data_synth, oracles_len: 1,
    );
    state.facade.add_active_synthetic(synthetic_info: @synthetic_info, initial_price: 20000);

    let order_deleveraged_user = state
        .facade
        .create_order(
            user: deleveraged_user,
            base_amount: 10, // Long 10 BTC
            base_asset_id: synthetic_info.asset_id,
            quote_amount: -200000,
            fee_amount: 0,
        );

    // Deleverager user will take the short side just to match the trade
    let order_deleverager_user = state
        .facade
        .create_order(
            user: deleverager_user,
            base_amount: -10, // Short 10 BTC
            base_asset_id: synthetic_info.asset_id,
            quote_amount: 200000,
            fee_amount: 0,
        );

    state
        .facade
        .trade(
            order_info_a: order_deleveraged_user,
            order_info_b: order_deleverager_user,
            base: 10,
            quote: -200000,
            fee_a: 0,
            fee_b: 0,
        );

    // 6. Reverse the trade at a worse price to realize a massive USD loss
    // Deleveraged user sells 10 BTC at 19130 = 191300 USDC total.
    // Realized loss = 191300 - 200000 = -8700 USDC.
    let order_deleveraged_user_close = state
        .facade
        .create_order(
            user: deleveraged_user,
            base_amount: -10,
            base_asset_id: synthetic_info.asset_id,
            quote_amount: 191300,
            fee_amount: 0,
        );

    let order_deleverager_user_close = state
        .facade
        .create_order(
            user: deleverager_user,
            base_amount: 10,
            base_asset_id: synthetic_info.asset_id,
            quote_amount: -191300,
            fee_amount: 0,
        );

    state
        .facade
        .trade(
            order_info_a: order_deleveraged_user_close,
            order_info_b: order_deleverager_user_close,
            base: -10,
            quote: 191300,
            fee_a: 0,
            fee_b: 0,
        );

    // Total Value after trade = 8750 - 8700 = 50. Still strictly positive.

    // Now tick down the STRK spot price.
    state.facade.price_tick(asset_info: @test_asset_1_info, price: 50);

    // New Risk adjusted value:
    // STRK: 100 * 50 * 0.5 = 2500
    // ETH: 50 * 100 * 0.75 = 3750
    // Total value = 2500 + 3750 - 8700 = -2450 < 0 (Insolvent).

    // Total physical spot value (D):
    // STRK: 100 * 50 = 5000
    // ETH: 50 * 100 = 5000
    // D = 10000.

    // Check deleveragability
    assert(
        state.facade.is_deleveragable(position_id: deleveraged_user.position_id),
        'user is not deleveragable',
    );

    // Calculate proportions:
    // d = 400.
    // d * S_i / D:
    // STRK proportion = (100 / 8700) * 400 = floor(4.59) = 4
    // ETH proportion = (50 / 8700) * 400 = floor(2.29) = 2

    let debt_to_clear = 400; // Debt in terms of USDC
    let expected_strk_diff = -4;
    let expected_eth_diff = -2;

    let mut expected_transfers = array![];
    expected_transfers
        .append(SpotAssetBalanceDiff { asset_id: asset_id_1, diff: expected_strk_diff });
    expected_transfers
        .append(SpotAssetBalanceDiff { asset_id: asset_id_2, diff: expected_eth_diff });

    state
        .facade
        .deleverage_spot_asset(
            :deleveraged_user,
            :deleverager_user,
            spot_amounts: expected_transfers.span(),
            deleveraged_base_collateral_amount: debt_to_clear,
        );
}

#[test]
#[should_panic(expected: ('DUPLICATE_SPOT_ASSET',))]
fn test_deleverage_spot_asset_duplicate_exploit() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    // 1. Setup spot assets
    let token_1 = snforge_std::Token::STRK;
    let erc20_1 = token_1.contract_address();
    let test_asset_1_info = AssetInfoTrait::new_collateral(
        asset_name: 'STRK',
        risk_factor_data: RiskFactorTiers {
            tiers: array![500].span(), first_tier_boundary: MAX_U128, tier_size: 1,
        },
        oracles_len: 1,
        erc20_contract_address: erc20_1,
    );
    let asset_id_1 = test_asset_1_info.asset_id;
    state.facade.add_active_collateral(asset_info: @test_asset_1_info, initial_price: 100);

    let token_2 = snforge_std::Token::ETH;
    let erc20_2 = token_2.contract_address();
    let test_asset_2_info = AssetInfoTrait::new_collateral(
        asset_name: 'ETH',
        risk_factor_data: RiskFactorTiers {
            tiers: array![250].span(), first_tier_boundary: MAX_U128, tier_size: 1,
        },
        oracles_len: 1,
        erc20_contract_address: erc20_2,
    );
    let asset_id_2 = test_asset_2_info.asset_id;
    state.facade.add_active_collateral(asset_info: @test_asset_2_info, initial_price: 100);

    // 2. Setup users
    let deleveraged_user = state.new_user_with_position();
    let deleverager_user = state.new_user_with_position();

    // Mint tokens
    snforge_std::set_balance(
        target: deleveraged_user.account.address, new_balance: 5000000, token: token_1,
    );
    snforge_std::set_balance(
        target: deleveraged_user.account.address, new_balance: 5000000, token: token_2,
    );

    // 3. Deposit Base Collateral (USDC)
    // Deleverager needs a large amount of USDC to take over the spot assets.
    let deposit_info_deleverager = state
        .facade
        .deposit(deleverager_user.account, deleverager_user.position_id, 100000);
    state.facade.process_deposit(deposit_info_deleverager);

    // 4. Deposit Spot Assets for deleveraged user
    // The user has STRK and ETH as spot collateral.
    let deposit_spo_1 = state
        .facade
        .deposit_spot(deleveraged_user.account, asset_id_1, deleveraged_user.position_id, 100);
    state.facade.process_deposit(deposit_spo_1);

    let deposit_spo_2 = state
        .facade
        .deposit_spot(deleveraged_user.account, asset_id_2, deleveraged_user.position_id, 50);
    state.facade.process_deposit(deposit_spo_2);

    // Initial Risk Adjusted Value:
    // STRK: 100 * 100 * 0.5 = 5000
    // ETH: 50 * 100 * 0.75 = 3750
    // Total Value = 8750

    // 5. Open Synthetic Position to take a loss
    let risk_factor_data_synth = RiskFactorTiers {
        tiers: array![1].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let synthetic_info = AssetInfoTrait::new(
        asset_name: 'BTC_PERP', risk_factor_data: risk_factor_data_synth, oracles_len: 1,
    );
    state.facade.add_active_synthetic(synthetic_info: @synthetic_info, initial_price: 20000);

    let order_deleveraged_user = state
        .facade
        .create_order(
            user: deleveraged_user,
            base_amount: 10, // Long 10 BTC
            base_asset_id: synthetic_info.asset_id,
            quote_amount: -200000,
            fee_amount: 0,
        );

    // Deleverager user will take the short side just to match the trade
    let order_deleverager_user = state
        .facade
        .create_order(
            user: deleverager_user,
            base_amount: -10, // Short 10 BTC
            base_asset_id: synthetic_info.asset_id,
            quote_amount: 200000,
            fee_amount: 0,
        );

    state
        .facade
        .trade(
            order_info_a: order_deleveraged_user,
            order_info_b: order_deleverager_user,
            base: 10,
            quote: -200000,
            fee_a: 0,
            fee_b: 0,
        );

    // 6. Reverse the trade at a worse price to realize a massive USD loss
    // Deleveraged user sells 10 BTC at 19130 = 191300 USDC total.
    // Realized loss = 191300 - 200000 = -8700 USDC.
    let order_deleveraged_user_close = state
        .facade
        .create_order(
            user: deleveraged_user,
            base_amount: -10,
            base_asset_id: synthetic_info.asset_id,
            quote_amount: 191300,
            fee_amount: 0,
        );

    let order_deleverager_user_close = state
        .facade
        .create_order(
            user: deleverager_user,
            base_amount: 10,
            base_asset_id: synthetic_info.asset_id,
            quote_amount: -191300,
            fee_amount: 0,
        );

    state
        .facade
        .trade(
            order_info_a: order_deleveraged_user_close,
            order_info_b: order_deleverager_user_close,
            base: -10,
            quote: 191300,
            fee_a: 0,
            fee_b: 0,
        );

    // Total Value after trade = 8750 - 8700 = 50. Still strictly positive.

    // Now tick down the STRK spot price.
    state.facade.price_tick(asset_info: @test_asset_1_info, price: 50);

    // New Risk adjusted value:
    // STRK: 100 * 50 * 0.5 = 2500
    // ETH: 50 * 100 * 0.75 = 3750
    // Total value = 2500 + 3750 - 8700 = -2450 < 0 (Insolvent).

    // Total physical spot value (D):
    // STRK: 100 * 50 = 5000
    // ETH: 50 * 100 = 5000
    // D = 10000.

    // Check deleveragability
    assert(
        state.facade.is_deleveragable(position_id: deleveraged_user.position_id),
        'user is not deleveragable',
    );

    // Calculate proportions:
    // d = 400.
    // d * S_i / D:
    // STRK proportion = (100 / 8700) * 400 = floor(4.59) = 4
    // ETH proportion = (50 / 8700) * 400 = floor(2.29) = 2

    let debt_to_clear = 400; // Debt in terms of USDC

    let expected_strk_diff = -4;
    let expected_eth_diff = -2;

    let exploit_strk_diff = -50;

    let mut expected_transfers = array![];
    // EXPLOIT: Liquidator inserts a massively negative diff for STRK
    expected_transfers
        .append(SpotAssetBalanceDiff { asset_id: asset_id_1, diff: exploit_strk_diff });
    // And then follows it up with the "expected" one. The dictionary overwrites the exploit diff,
    // causing the validation loop to pass, but `apply_multi_spot_diff` will process BOTH.
    expected_transfers
        .append(SpotAssetBalanceDiff { asset_id: asset_id_1, diff: expected_strk_diff });
    expected_transfers
        .append(SpotAssetBalanceDiff { asset_id: asset_id_2, diff: expected_eth_diff });

    state
        .facade
        .deleverage_spot_asset(
            :deleveraged_user,
            :deleverager_user,
            spot_amounts: expected_transfers.span(),
            deleveraged_base_collateral_amount: debt_to_clear,
        );
}

#[test]
#[should_panic(expected: "Missing spot asset")]
fn test_deleverage_spot_asset_missing_asset() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    // 1. Setup spot assets
    let token_1 = snforge_std::Token::STRK;
    let erc20_1 = token_1.contract_address();
    let test_asset_1_info = AssetInfoTrait::new_collateral(
        asset_name: 'STRK',
        risk_factor_data: RiskFactorTiers {
            tiers: array![500].span(), first_tier_boundary: MAX_U128, tier_size: 1,
        },
        oracles_len: 1,
        erc20_contract_address: erc20_1,
    );
    let asset_id_1 = test_asset_1_info.asset_id;
    state.facade.add_active_collateral(asset_info: @test_asset_1_info, initial_price: 100);

    let token_2 = snforge_std::Token::ETH;
    let erc20_2 = token_2.contract_address();
    let test_asset_2_info = AssetInfoTrait::new_collateral(
        asset_name: 'ETH',
        risk_factor_data: RiskFactorTiers {
            tiers: array![250].span(), first_tier_boundary: MAX_U128, tier_size: 1,
        },
        oracles_len: 1,
        erc20_contract_address: erc20_2,
    );
    let asset_id_2 = test_asset_2_info.asset_id;
    state.facade.add_active_collateral(asset_info: @test_asset_2_info, initial_price: 100);

    // 2. Setup users
    let deleveraged_user = state.new_user_with_position();
    let deleverager_user = state.new_user_with_position();

    // Mint tokens
    snforge_std::set_balance(
        target: deleveraged_user.account.address, new_balance: 5000000, token: token_1,
    );
    snforge_std::set_balance(
        target: deleveraged_user.account.address, new_balance: 5000000, token: token_2,
    );

    // 3. Deposit Base Collateral (USDC)
    let deposit_info_deleverager = state
        .facade
        .deposit(deleverager_user.account, deleverager_user.position_id, 100000);
    state.facade.process_deposit(deposit_info_deleverager);

    // 4. Deposit Spot Assets for deleveraged user
    let deposit_spo_1 = state
        .facade
        .deposit_spot(deleveraged_user.account, asset_id_1, deleveraged_user.position_id, 100);
    state.facade.process_deposit(deposit_spo_1);

    let deposit_spo_2 = state
        .facade
        .deposit_spot(deleveraged_user.account, asset_id_2, deleveraged_user.position_id, 50);
    state.facade.process_deposit(deposit_spo_2);

    // 5. Open Synthetic Position to take a loss
    let risk_factor_data_synth = RiskFactorTiers {
        tiers: array![1].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let synthetic_info = AssetInfoTrait::new(
        asset_name: 'BTC_PERP', risk_factor_data: risk_factor_data_synth, oracles_len: 1,
    );
    state.facade.add_active_synthetic(synthetic_info: @synthetic_info, initial_price: 20000);

    let order_deleveraged_user = state
        .facade
        .create_order(
            user: deleveraged_user,
            base_amount: 10,
            base_asset_id: synthetic_info.asset_id,
            quote_amount: -200000,
            fee_amount: 0,
        );

    let order_deleverager_user = state
        .facade
        .create_order(
            user: deleverager_user,
            base_amount: -10,
            base_asset_id: synthetic_info.asset_id,
            quote_amount: 200000,
            fee_amount: 0,
        );

    state
        .facade
        .trade(
            order_info_a: order_deleveraged_user,
            order_info_b: order_deleverager_user,
            base: 10,
            quote: -200000,
            fee_a: 0,
            fee_b: 0,
        );

    // 6. Reverse the trade at a worse price to realize a massive USD loss
    // (Realized loss = -8700 USDC)
    let order_deleveraged_user_close = state
        .facade
        .create_order(
            user: deleveraged_user,
            base_amount: -10,
            base_asset_id: synthetic_info.asset_id,
            quote_amount: 191300,
            fee_amount: 0,
        );

    let order_deleverager_user_close = state
        .facade
        .create_order(
            user: deleverager_user,
            base_amount: 10,
            base_asset_id: synthetic_info.asset_id,
            quote_amount: -191300,
            fee_amount: 0,
        );

    state
        .facade
        .trade(
            order_info_a: order_deleveraged_user_close,
            order_info_b: order_deleverager_user_close,
            base: -10,
            quote: 191300,
            fee_a: 0,
            fee_b: 0,
        );

    // Now tick down the STRK spot price.
    state.facade.price_tick(asset_info: @test_asset_1_info, price: 50);

    // Check deleveragability
    assert(
        state.facade.is_deleveragable(position_id: deleveraged_user.position_id),
        'user is not deleveragable',
    );

    let debt_to_clear = 400; // Debt in terms of USDC
    let expected_strk_diff = -4;
    // We explicitly omit the expected ETH transfer to test the dictionary verification

    let mut expected_transfers = array![];
    expected_transfers
        .append(SpotAssetBalanceDiff { asset_id: asset_id_1, diff: expected_strk_diff });

    // Missing asset_id_2 in spot_amounts!
    state
        .facade
        .deleverage_spot_asset(
            :deleveraged_user,
            :deleverager_user,
            spot_amounts: expected_transfers.span(),
            deleveraged_base_collateral_amount: debt_to_clear,
        );
}

#[test]
#[should_panic(expected: "Invalid spot proportion")]
fn test_deleverage_spot_asset_invalid_proportion() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    // 1. Setup spot assets
    let token_1 = snforge_std::Token::STRK;
    let erc20_1 = token_1.contract_address();
    let test_asset_1_info = AssetInfoTrait::new_collateral(
        asset_name: 'STRK',
        risk_factor_data: RiskFactorTiers {
            tiers: array![500].span(), first_tier_boundary: MAX_U128, tier_size: 1,
        },
        oracles_len: 1,
        erc20_contract_address: erc20_1,
    );
    let asset_id_1 = test_asset_1_info.asset_id;
    state.facade.add_active_collateral(asset_info: @test_asset_1_info, initial_price: 100);

    let token_2 = snforge_std::Token::ETH;
    let erc20_2 = token_2.contract_address();
    let test_asset_2_info = AssetInfoTrait::new_collateral(
        asset_name: 'ETH',
        risk_factor_data: RiskFactorTiers {
            tiers: array![250].span(), first_tier_boundary: MAX_U128, tier_size: 1,
        },
        oracles_len: 1,
        erc20_contract_address: erc20_2,
    );
    let asset_id_2 = test_asset_2_info.asset_id;
    state.facade.add_active_collateral(asset_info: @test_asset_2_info, initial_price: 100);

    // 2. Setup users
    let deleveraged_user = state.new_user_with_position();
    let deleverager_user = state.new_user_with_position();

    // Mint tokens
    snforge_std::set_balance(
        target: deleveraged_user.account.address, new_balance: 5000000, token: token_1,
    );
    snforge_std::set_balance(
        target: deleveraged_user.account.address, new_balance: 5000000, token: token_2,
    );

    // 3. Deposit Base Collateral (USDC)
    let deposit_info_deleverager = state
        .facade
        .deposit(deleverager_user.account, deleverager_user.position_id, 100000);
    state.facade.process_deposit(deposit_info_deleverager);

    // 4. Deposit Spot Assets for deleveraged user
    let deposit_spo_1 = state
        .facade
        .deposit_spot(deleveraged_user.account, asset_id_1, deleveraged_user.position_id, 100);
    state.facade.process_deposit(deposit_spo_1);

    let deposit_spo_2 = state
        .facade
        .deposit_spot(deleveraged_user.account, asset_id_2, deleveraged_user.position_id, 50);
    state.facade.process_deposit(deposit_spo_2);

    // 5. Open Synthetic Position to take a loss
    let risk_factor_data_synth = RiskFactorTiers {
        tiers: array![1].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let synthetic_info = AssetInfoTrait::new(
        asset_name: 'BTC_PERP', risk_factor_data: risk_factor_data_synth, oracles_len: 1,
    );
    state.facade.add_active_synthetic(synthetic_info: @synthetic_info, initial_price: 20000);

    let order_deleveraged_user = state
        .facade
        .create_order(
            user: deleveraged_user,
            base_amount: 10,
            base_asset_id: synthetic_info.asset_id,
            quote_amount: -200000,
            fee_amount: 0,
        );

    let order_deleverager_user = state
        .facade
        .create_order(
            user: deleverager_user,
            base_amount: -10,
            base_asset_id: synthetic_info.asset_id,
            quote_amount: 200000,
            fee_amount: 0,
        );

    state
        .facade
        .trade(
            order_info_a: order_deleveraged_user,
            order_info_b: order_deleverager_user,
            base: 10,
            quote: -200000,
            fee_a: 0,
            fee_b: 0,
        );

    // 6. Reverse the trade at a worse price to realize a massive USD loss
    // (Realized loss = -8700 USDC)
    let order_deleveraged_user_close = state
        .facade
        .create_order(
            user: deleveraged_user,
            base_amount: -10,
            base_asset_id: synthetic_info.asset_id,
            quote_amount: 191300,
            fee_amount: 0,
        );

    let order_deleverager_user_close = state
        .facade
        .create_order(
            user: deleverager_user,
            base_amount: 10,
            base_asset_id: synthetic_info.asset_id,
            quote_amount: -191300,
            fee_amount: 0,
        );

    state
        .facade
        .trade(
            order_info_a: order_deleveraged_user_close,
            order_info_b: order_deleverager_user_close,
            base: -10,
            quote: 191300,
            fee_a: 0,
            fee_b: 0,
        );

    // Now tick down the STRK spot price.
    state.facade.price_tick(asset_info: @test_asset_1_info, price: 50);

    // Check deleveragability
    assert(
        state.facade.is_deleveragable(position_id: deleveraged_user.position_id),
        'user is not deleveragable',
    );

    let debt_to_clear = 400; // Debt in terms of USDC
    // Intentional bad proportion to trigger "Invalid spot proportion"
    // Valid values are -4 and -2 respectively. We swap them.
    let expected_strk_diff = -2;
    let expected_eth_diff = -4;

    let mut expected_transfers = array![];
    expected_transfers
        .append(SpotAssetBalanceDiff { asset_id: asset_id_1, diff: expected_strk_diff });
    expected_transfers
        .append(SpotAssetBalanceDiff { asset_id: asset_id_2, diff: expected_eth_diff });

    state
        .facade
        .deleverage_spot_asset(
            :deleveraged_user,
            :deleverager_user,
            spot_amounts: expected_transfers.span(),
            deleveraged_base_collateral_amount: debt_to_clear,
        );
}

#[test]
fn test_deleverage_spot_asset_full_amount() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();

    // 1. Setup spot assets
    let token_1 = snforge_std::Token::STRK;
    let erc20_1 = token_1.contract_address();
    let test_asset_1_info = AssetInfoTrait::new_collateral(
        asset_name: 'STRK',
        risk_factor_data: RiskFactorTiers {
            tiers: array![500].span(), first_tier_boundary: MAX_U128, tier_size: 1,
        },
        oracles_len: 1,
        erc20_contract_address: erc20_1,
    );
    let asset_id_1 = test_asset_1_info.asset_id;
    state.facade.add_active_collateral(asset_info: @test_asset_1_info, initial_price: 100);

    let token_2 = snforge_std::Token::ETH;
    let erc20_2 = token_2.contract_address();
    let test_asset_2_info = AssetInfoTrait::new_collateral(
        asset_name: 'ETH',
        risk_factor_data: RiskFactorTiers {
            tiers: array![250].span(), first_tier_boundary: MAX_U128, tier_size: 1,
        },
        oracles_len: 1,
        erc20_contract_address: erc20_2,
    );
    let asset_id_2 = test_asset_2_info.asset_id;
    state.facade.add_active_collateral(asset_info: @test_asset_2_info, initial_price: 100);

    // 2. Setup users
    let deleveraged_user = state.new_user_with_position();
    let deleverager_user = state.new_user_with_position();

    // Mint tokens
    snforge_std::set_balance(
        target: deleveraged_user.account.address, new_balance: 5000000, token: token_1,
    );
    snforge_std::set_balance(
        target: deleveraged_user.account.address, new_balance: 5000000, token: token_2,
    );

    // 3. Deposit Base Collateral (USDC)
    let deposit_info_deleverager = state
        .facade
        .deposit(deleverager_user.account, deleverager_user.position_id, 100000);
    state.facade.process_deposit(deposit_info_deleverager);

    // 4. Deposit Spot Assets for deleveraged user
    let deposit_spo_1 = state
        .facade
        .deposit_spot(deleveraged_user.account, asset_id_1, deleveraged_user.position_id, 100);
    state.facade.process_deposit(deposit_spo_1);

    let deposit_spo_2 = state
        .facade
        .deposit_spot(deleveraged_user.account, asset_id_2, deleveraged_user.position_id, 50);
    state.facade.process_deposit(deposit_spo_2);

    // 5. Open Synthetic Position to take a loss
    let risk_factor_data_synth = RiskFactorTiers {
        tiers: array![1].span(), first_tier_boundary: MAX_U128, tier_size: 1,
    };
    let synthetic_info = AssetInfoTrait::new(
        asset_name: 'BTC_PERP', risk_factor_data: risk_factor_data_synth, oracles_len: 1,
    );
    state.facade.add_active_synthetic(synthetic_info: @synthetic_info, initial_price: 20000);

    let order_deleveraged_user = state
        .facade
        .create_order(
            user: deleveraged_user,
            base_amount: 10,
            base_asset_id: synthetic_info.asset_id,
            quote_amount: -200000,
            fee_amount: 0,
        );

    let order_deleverager_user = state
        .facade
        .create_order(
            user: deleverager_user,
            base_amount: -10,
            base_asset_id: synthetic_info.asset_id,
            quote_amount: 200000,
            fee_amount: 0,
        );

    state
        .facade
        .trade(
            order_info_a: order_deleveraged_user,
            order_info_b: order_deleverager_user,
            base: 10,
            quote: -200000,
            fee_a: 0,
            fee_b: 0,
        );

    // 6. Reverse the trade at a worse price to realize a massive USD loss
    // (Realized loss = -8700 USDC)
    let order_deleveraged_user_close = state
        .facade
        .create_order(
            user: deleveraged_user,
            base_amount: -10,
            base_asset_id: synthetic_info.asset_id,
            quote_amount: 191300,
            fee_amount: 0,
        );

    let order_deleverager_user_close = state
        .facade
        .create_order(
            user: deleverager_user,
            base_amount: 10,
            base_asset_id: synthetic_info.asset_id,
            quote_amount: -191300,
            fee_amount: 0,
        );

    state
        .facade
        .trade(
            order_info_a: order_deleveraged_user_close,
            order_info_b: order_deleverager_user_close,
            base: -10,
            quote: 191300,
            fee_a: 0,
            fee_b: 0,
        );

    // Now tick down the STRK spot price.
    state.facade.price_tick(asset_info: @test_asset_1_info, price: 50);

    // Check deleveragability
    assert(
        state.facade.is_deleveragable(position_id: deleveraged_user.position_id),
        'user is not deleveragable',
    );

    let debt_to_clear = 8700; // Account's full debt in terms of USDC
    let expected_strk_diff = -100;
    let expected_eth_diff = -50;

    let mut expected_transfers = array![];
    expected_transfers
        .append(SpotAssetBalanceDiff { asset_id: asset_id_1, diff: expected_strk_diff });
    expected_transfers
        .append(SpotAssetBalanceDiff { asset_id: asset_id_2, diff: expected_eth_diff });

    state
        .facade
        .deleverage_spot_asset(
            :deleveraged_user,
            :deleverager_user,
            spot_amounts: expected_transfers.span(),
            deleveraged_base_collateral_amount: debt_to_clear,
        );

    // Validate final spot balances are 0
    let deleveraged_strk_after = state
        .facade
        .get_position_asset_balance(deleveraged_user.position_id, asset_id_1);
    let deleveraged_eth_after = state
        .facade
        .get_position_asset_balance(deleveraged_user.position_id, asset_id_2);

    assert(deleveraged_strk_after == 0_i64.into(), 'STRK balance should be 0');
    assert(deleveraged_eth_after == 0_i64.into(), 'ETH balance should be 0');
}

