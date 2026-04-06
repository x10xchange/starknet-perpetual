use perpetuals::tests::constants::*;
use perpetuals::tests::flow_tests::infra::*;
use perpetuals::tests::flow_tests::perps_tests_facade::*;
use starkware_utils_testing::test_utils::cheat_caller_address_once;
use treasury::interface::{ITreasuryDispatcher, ITreasuryDispatcherTrait};

/// Helper: set a specific treasury protection percent and reset the limit so it takes effect.
fn set_treasury_protection_percent(facade: @PerpsTestsFacade, percent: u64) {
    let treasury = ITreasuryDispatcher { contract_address: *facade.treasury_address };

    cheat_caller_address_once(
        contract_address: *facade.treasury_address, caller_address: *facade.app_governor,
    );
    treasury.change_protection_limit_percent(*facade.token_state.address, percent);

    cheat_caller_address_once(
        contract_address: *facade.treasury_address, caller_address: *facade.app_governor,
    );
    treasury.reset_protection_limit(*facade.token_state.address);
}

#[test]
fn test_treasury_withdrawal_within_limit_succeeds() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let user = state.new_user_with_position();

    let deposit = state.facade.deposit(user.account, user.position_id, 10000_u64);
    state.facade.process_deposit(deposit);

    // 5% of ~1B treasury ≈ 50M. Withdrawing 400 is well within limit.
    set_treasury_protection_percent(@state.facade, 5);

    let withdraw_request = state.facade.withdraw_request(user, 400_u64);
    state.facade.withdraw(withdraw_request);
}

#[test]
#[should_panic(expected: "Treasury Protection Limit Exceeded")]
fn test_treasury_withdrawal_exceeding_limit_fails() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let user = state.new_user_with_position();

    let deposit = state.facade.deposit(user.account, user.position_id, 10000_u64);
    state.facade.process_deposit(deposit);

    // 0% — no withdrawals allowed.
    set_treasury_protection_percent(@state.facade, 0);

    let withdraw_request = state.facade.withdraw_request(user, 1_u64);
    state.facade.withdraw(withdraw_request);
}

// TODO: Vault deposit/redeem round-trips currently double-count against the treasury protection
// limit because withdraw_from is used for temporary token movements. This needs a flash_withdraw
// mechanism (callback-based) that bypasses the limit and asserts balance is restored after the
// callback completes.
#[test]
#[should_panic(expected: "Treasury Protection Limit Exceeded")]
fn test_vault_round_trip_does_not_exhaust_treasury_limit() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let vault_user = state.new_user_with_position();
    let user = state.new_user_with_position();

    // Vault owner deposits 50k, user deposits 10k.
    state
        .facade
        .process_deposit(
            state.facade.deposit(vault_user.account, vault_user.position_id, 50000_u64),
        );
    let vault_config = state.facade.register_vault_share_spot_asset(vault_user);
    state.facade.price_tick(@vault_config.asset_info, 1);

    state
        .facade
        .process_deposit(
            state.facade.deposit(user.account, user.position_id, 10000_u64),
        );

    // Invest 5k into vault.
    state
        .facade
        .process_deposit(
            state
                .facade
                .deposit_into_vault(
                    vault: vault_config,
                    amount_to_invest: 5000,
                    min_shares_to_receive: 2500,
                    depositing_user: user,
                    receiving_user: user,
                ),
        );

    // Set a tight 5% limit. Treasury has ~1B, so max withdrawal ≈ 50M.
    // But with double-counting, each vault round-trip eats into that budget.
    set_treasury_protection_percent(@state.facade, 5);

    // Redeem 4000 from vault — tokens round-trip through treasury but should NOT
    // count against the protection limit.
    state
        .facade
        .redeem_from_vault(
            vault: vault_config,
            withdrawing_user: user,
            receiving_user: user,
            shares_to_burn_user: 4000,
            value_of_shares_user: 4000,
            shares_to_burn_vault: 4000,
            value_of_shares_vault: 4000,
            actual_shares_user: 4000,
            actual_collateral_user: 4000,
        );

    // Real user withdrawal of 5k should succeed — treasury is fully funded.
    let withdraw_request = state.facade.withdraw_request(user, 5000_u64);
    state.facade.withdraw(withdraw_request);
}
