use perpetuals::tests::constants::*;
use perpetuals::tests::flow_tests::infra::*;
use perpetuals::tests::flow_tests::perps_tests_facade::*;
use starkware_utils_testing::test_utils::cheat_caller_address_once;
use treasury::interface::{ITreasuryDispatcher, ITreasuryDispatcherTrait};

/// Helper: set a specific treasury protection percent and reset the limit so it takes effect.
/// The percent change is timelocked, but the flow-test treasury is deployed with a zero timelock,
/// so the request can be applied in the same block.
fn set_treasury_protection_percent(facade: @PerpsTestsFacade, percent: u64) {
    let treasury = ITreasuryDispatcher { contract_address: *facade.treasury_address };

    // The treasury rejects no-op percent requests, so only request/apply when the percent actually
    // changes; the reset below re-snapshots the limit either way.
    if treasury.get_protection_limit_percent(*facade.token_state.address) != percent {
        cheat_caller_address_once(
            contract_address: *facade.treasury_address, caller_address: *facade.app_governor,
        );
        treasury.request_protection_limit_percent_change(*facade.token_state.address, percent);

        cheat_caller_address_once(
            contract_address: *facade.treasury_address, caller_address: *facade.app_governor,
        );
        treasury.apply_protection_limit_percent_change(*facade.token_state.address);
    }

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
    // Request/apply the 0% change directly (without reset_protection_limit) because an override of
    // 0 is treated as "no override" by get_protection_percent, so a subsequent reset would revert
    // to the default 5%. The flow-test treasury has a zero timelock, so apply succeeds immediately.
    let treasury = ITreasuryDispatcher { contract_address: state.facade.treasury_address };
    cheat_caller_address_once(
        contract_address: state.facade.treasury_address, caller_address: state.facade.app_governor,
    );
    treasury.request_protection_limit_percent_change(state.facade.token_state.address, 0);
    cheat_caller_address_once(
        contract_address: state.facade.treasury_address, caller_address: state.facade.app_governor,
    );
    treasury.apply_protection_limit_percent_change(state.facade.token_state.address);

    let withdraw_request = state.facade.withdraw_request(user, 1_u64);
    state.facade.withdraw(withdraw_request);
}

// Vault deposit/redeem no longer round-trip collateral through the treasury, so there is no
// double-counting against the protection limit.
#[test]
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
    let vault_config = state.facade.register_vault_share_spot_asset(vault_user, 'VAULT');
    state.facade.price_tick(@vault_config.asset_info, 1);
    state.facade.update_vault_protection_limit(vault_config.position_id, 100);

    state.facade.process_deposit(state.facade.deposit(user.account, user.position_id, 10000_u64));

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

    // Allow full withdrawal of vault share tokens from treasury.
    state
        .facade
        .set_treasury_protection_percent_for_token(
            vault_config.deployed_vault.contract_address, 100,
        );

    // Redeem 4000 from vault — only vault shares are withdrawn from treasury,
    // no USDC round-trip occurs.
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
            other_collaterals: array![].span(),
        );

    // Set a tight 5% limit AFTER vault operations. Treasury has 60k USDC,
    // so max withdrawal ≈ 3000. A 2000 withdrawal should succeed because
    // vault operations did not eat into the USDC protection budget.
    set_treasury_protection_percent(@state.facade, 5);

    let withdraw_request = state.facade.withdraw_request(user, 2000_u64);
    state.facade.withdraw(withdraw_request);
}
