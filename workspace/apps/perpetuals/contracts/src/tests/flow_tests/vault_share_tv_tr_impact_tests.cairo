use openzeppelin::interfaces::erc20::IERC20DispatcherTrait;
use perpetuals::tests::constants::*;
use perpetuals::tests::flow_tests::infra::*;
use perpetuals::tests::flow_tests::perps_tests_facade::*;
use perpetuals::tests::test_utils::assert_with_error;
use snforge_std::start_cheat_block_timestamp_global;
use starkware_utils::time::time::Time;
use starkware_utils_testing::test_utils::{
    Deployable, TokenState, TokenTrait, cheat_caller_address_once,
};


#[test]
fn test_shares_should_contribute_zero_until_activated() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let vault_user = state.new_user_with_position();
    let depositing_user = state.new_user_with_position();
    let vault_init_deposit = state
        .facade
        .deposit(vault_user.account, vault_user.position_id, 5000_u64);
    state.facade.process_deposit(vault_init_deposit);
    let vault_config = state.facade.register_vault_share_spot_asset(vault_user.position_id);

    state
        .facade
        .process_deposit(
            state.facade.deposit(depositing_user.account, depositing_user.position_id, 1000_u64),
        );

    state
        .facade
        .validate_total_value(position_id: depositing_user.position_id, expected_total_value: 1000);

    state
        .facade
        .process_deposit(
            state
                .facade
                .deposit_into_vault(
                    vault: vault_config,
                    amount_to_invest: 1000,
                    min_shares_to_receive: 500,
                    :depositing_user,
                    receiving_user: depositing_user,
                ),
        );

    state
        .facade
        .validate_total_value(position_id: depositing_user.position_id, expected_total_value: 0);
}

#[test]
fn test_shares_should_contribute_to_tv_tr_after_activation() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let vault_user = state.new_user_with_position();
    let depositing_user = state.new_user_with_position();
    let vault_init_deposit = state
        .facade
        .deposit(vault_user.account, vault_user.position_id, 5000_u64);
    state.facade.process_deposit(vault_init_deposit);
    let vault_config = state.facade.register_vault_share_spot_asset(vault_user.position_id);

    state
        .facade
        .process_deposit(
            state.facade.deposit(depositing_user.account, depositing_user.position_id, 1000_u64),
        );

    state
        .facade
        .validate_total_value(position_id: depositing_user.position_id, expected_total_value: 1000);

    state
        .facade
        .process_deposit(
            state
                .facade
                .deposit_into_vault(
                    vault: vault_config,
                    amount_to_invest: 1000,
                    min_shares_to_receive: 500,
                    :depositing_user,
                    receiving_user: depositing_user,
                ),
        );

    state.facade.price_tick(@vault_config.asset_info, 12);

    state
        .facade
        .validate_total_value(
            position_id: depositing_user.position_id, expected_total_value: 12 * 1000,
        );

    state
        .facade
        .validate_total_risk(
            position_id: depositing_user.position_id, expected_total_risk: 1200 // 10%
        );
}

