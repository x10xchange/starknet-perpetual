use perpetuals::tests::constants::*;
use perpetuals::tests::flow_tests::infra::*;
use perpetuals::tests::flow_tests::perps_tests_facade::*;
use perpetuals::tests::test_utils::assert_with_error;
use starkware_utils_testing::test_utils::TokenTrait;


#[test]
fn test_redeem_from_protocol_vault_redeem_to_same_position() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let vault_user = state.new_user_with_position();
    let redeeming_user = state.new_user_with_position();
    let vault_init_deposit = state
        .facade
        .deposit(vault_user.account, vault_user.position_id, 5000_u64);
    state.facade.process_deposit(vault_init_deposit);
    let vault_config = state.facade.register_vault_share_spot_asset(vault_user.position_id);

    state
        .facade
        .process_deposit(
            state.facade.deposit(redeeming_user.account, redeeming_user.position_id, 1000_u64),
        );

    let perps_usdc_balance_before_vault_interaction = state
        .facade
        .token_state
        .balance_of(state.facade.perpetuals_contract);

    state
        .facade
        .process_deposit(
            state
                .facade
                .deposit_into_vault(
                    vault: vault_config,
                    amount: 1000,
                    depositing_user: redeeming_user,
                    receiving_user: redeeming_user,
                ),
        );

    let redeeming_user_usdc_balance_before_redeem = state
        .facade
        .get_position_collateral_balance(redeeming_user.position_id);

    let redeeming_user_vault_share_balance_before_redeem = state
        .facade
        .get_position_asset_balance(redeeming_user.position_id, vault_config.asset_id);

    let vault_usdc_balance_before_redeem = state
        .facade
        .get_position_collateral_balance(vault_config.position_id);

    let value_of_shares: u64 = 399;

    state
        .facade
        .redeem_from_vault(
            vault: vault_config,
            amount: 1000,
            withdrawing_user: redeeming_user,
            receiving_user: redeeming_user,
            shares_to_burn_user: 400,
            value_of_shares_user: value_of_shares,
            shares_to_burn_vault: 400,
            value_of_shares_vault: value_of_shares,
        );
    //     explicity check invariants
    // 1. perps USDC balance must not change

    let perps_usdc_balance_after_vault_interaction = state
        .facade
        .token_state
        .balance_of(state.facade.perpetuals_contract);

    assert_with_error(
        perps_usdc_balance_before_vault_interaction == perps_usdc_balance_after_vault_interaction,
        format!(
            "perps usdc balance changed after vault interaction, before: {}, after: {}",
            perps_usdc_balance_before_vault_interaction,
            perps_usdc_balance_after_vault_interaction,
        ),
    );
    // 2. redeeming user position balance must increase by 399 USDC
    let redeeming_user_usdc_balance_after_vault_interaction = state
        .facade
        .get_position_collateral_balance(redeeming_user.position_id);

    assert_with_error(
        redeeming_user_usdc_balance_after_vault_interaction == redeeming_user_usdc_balance_before_redeem
            + value_of_shares.into(),
        format!(
            "redeeming user collateral balance did not increase by {:?}, before: {:?}, after: {:?}",
            value_of_shares,
            redeeming_user_usdc_balance_before_redeem,
            redeeming_user_usdc_balance_after_vault_interaction,
        ),
    );

    let redeeming_user_vault_share_balance_after_redeem = state
        .facade
        .get_position_asset_balance(redeeming_user.position_id, vault_config.asset_id);
    // 3. redeeming user vault share balance must decrease by redeemed amount
    assert_with_error(
        redeeming_user_vault_share_balance_before_redeem
            - 400_i64.into() == redeeming_user_vault_share_balance_after_redeem,
        format!(
            "depositing user vault share balance did not decrease, before: {:?}, after: {:?}",
            redeeming_user_vault_share_balance_before_redeem,
            redeeming_user_vault_share_balance_after_redeem,
        ),
    );
    //4. vault usdc balance must decrease by 399
    let vault_usdc_balance_after_redeem = state
        .facade
        .get_position_collateral_balance(vault_user.position_id);

    assert_with_error(
        vault_usdc_balance_after_redeem == vault_usdc_balance_before_redeem - 399_i64.into(),
        format!(
            "vault usdc balance did not decrease by 399, before: {:?}, after: {:?}",
            vault_usdc_balance_before_redeem,
            vault_usdc_balance_after_redeem,
        ),
    );
}

