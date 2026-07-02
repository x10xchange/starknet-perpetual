use snforge_std::EventSpyAssertionsTrait;
use starkware_utils::constants::{DAY, WEEK};
use starkware_utils_testing::test_utils::cheat_caller_address_once;
use treasury::interface::{ITreasuryDispatcher, ITreasuryDispatcherTrait};
use treasury::protocol_treasury::ProtocolTreasury;
use treasury::tests::constants::*;
use treasury::tests::treasury_tests_facade::TreasuryTestsFacadeTrait;

// ===================== Constructor / Getters =====================

#[test]
fn test_get_perps_contract() {
    let facade = TreasuryTestsFacadeTrait::new();
    let perps = facade.treasury_dispatcher.get_perps_contract();
    assert!(perps == PERPS_CONTRACT(), "perps contract mismatch");
}

// ===================== Deposit =====================

#[test]
fn test_deposit_into_transfers_tokens() {
    let mut facade = TreasuryTestsFacadeTrait::new();
    let depositor = NON_PERPS_CALLER();
    let amount: u128 = TREASURY_FUND_AMOUNT;

    facade.fund_account(depositor, amount);
    facade.approve_treasury(depositor, amount);

    let treasury_balance_before = facade.treasury_balance();
    facade.deposit_into(depositor, amount.into());
    let treasury_balance_after = facade.treasury_balance();

    assert!(
        treasury_balance_after == treasury_balance_before + amount.into(),
        "treasury balance should increase by deposit amount",
    );
}

#[test]
fn test_deposit_into_multiple_deposits() {
    let mut facade = TreasuryTestsFacadeTrait::new();
    let depositor = NON_PERPS_CALLER();
    let amount: u128 = 500_000;

    facade.fund_account(depositor, amount * 3);
    facade.approve_treasury(depositor, amount * 3);

    facade.deposit_into(depositor, amount.into());
    facade.deposit_into(depositor, amount.into());
    facade.deposit_into(depositor, amount.into());

    assert!(facade.treasury_balance() == (amount * 3).into(), "should have 3x deposit");
}

// ===================== Withdraw =====================

#[test]
fn test_withdraw_from_as_perps() {
    let mut facade = TreasuryTestsFacadeTrait::new();
    let deposit_amount: u128 = 10_000_000;
    let withdraw_amount: u128 = 100_000;

    facade.fund_treasury(deposit_amount);
    facade.reset_protection_limit();

    let balance_before = facade.treasury_balance();
    facade.withdraw_from_as_perps(withdraw_amount.into());
    let balance_after = facade.treasury_balance();

    assert!(balance_before - balance_after == withdraw_amount.into(), "balance should decrease");
}

#[test]
#[should_panic(expected: 'ONLY_PERPS_CAN_WITHDRAW')]
fn test_withdraw_from_non_perps_fails() {
    let mut facade = TreasuryTestsFacadeTrait::new();
    let deposit_amount: u128 = 10_000_000;

    facade.fund_treasury(deposit_amount);
    facade.reset_protection_limit();

    facade.withdraw_from_as_non_perps(NON_PERPS_CALLER(), 100.into());
}

#[test]
fn test_withdraw_sends_to_perps_contract() {
    let mut facade = TreasuryTestsFacadeTrait::new();
    let deposit_amount: u128 = 10_000_000;
    let withdraw_amount: u128 = 100_000;

    facade.fund_treasury(deposit_amount);
    facade.reset_protection_limit();

    let perps_balance_before = facade.balance_of(facade.perps_contract);
    facade.withdraw_from_as_perps(withdraw_amount.into());
    let perps_balance_after = facade.balance_of(facade.perps_contract);

    assert!(
        perps_balance_after == perps_balance_before + withdraw_amount.into(),
        "perps contract should receive withdrawn tokens",
    );
}

// ===================== Protection Limit =====================

#[test]
#[should_panic(expected: "Treasury Protection Limit Exceeded")]
fn test_protection_limit_blocks_excessive_withdrawal() {
    let mut facade = TreasuryTestsFacadeTrait::new();
    let deposit_amount: u128 = TREASURY_FUND_AMOUNT;

    facade.fund_treasury(deposit_amount);
    facade.reset_protection_limit();

    // With 5% protection limit, max withdrawal = 1_000_000 * 5 * 10 / 1000 = 50_000.
    // Withdrawing more than that should panic.
    facade.withdraw_from_as_perps(50_001_u128.into());
}

#[test]
fn test_protection_limit_allows_withdrawal_under_limit() {
    let mut facade = TreasuryTestsFacadeTrait::new();
    let deposit_amount: u128 = TREASURY_FUND_AMOUNT;

    facade.fund_treasury(deposit_amount);
    facade.reset_protection_limit();

    // With 5% protection limit, max = 50_000. Withdraw less than that.
    facade.withdraw_from_as_perps(49_000_u128.into());

    assert!(facade.treasury_balance() == (deposit_amount - 49_000).into(), "balance mismatch");
}

#[test]
#[should_panic(expected: "Treasury Protection Limit Exceeded")]
fn test_multiple_withdrawals_accumulate() {
    let mut facade = TreasuryTestsFacadeTrait::new();
    let deposit_amount: u128 = TREASURY_FUND_AMOUNT;

    facade.fund_treasury(deposit_amount);
    facade.reset_protection_limit();

    // max = 50_000. Withdraw in two chunks, then a third that exceeds.
    facade.withdraw_from_as_perps(25_000_u128.into());
    facade.withdraw_from_as_perps(24_000_u128.into());
    // Total so far = 49_000. Next one pushes to 51_000 > 50_000.
    facade.withdraw_from_as_perps(2_000_u128.into());
}

// ===================== Reset Protection Limit =====================

#[test]
fn test_reset_protection_limit_resets_withdrawn_counter() {
    let mut facade = TreasuryTestsFacadeTrait::new();
    let deposit_amount: u128 = TREASURY_FUND_AMOUNT;

    facade.fund_treasury(deposit_amount);
    facade.reset_protection_limit();

    // Withdraw almost to the limit.
    facade.withdraw_from_as_perps(49_000_u128.into());

    // Reset is rate-limited to once per day; advance past the cooldown before resetting again.
    facade.advance_time(DAY + 1);

    // Reset and withdraw again — should succeed.
    facade.reset_protection_limit();
    // New balance = 951_000, max = 951_000 * 50 / 1000 = 47_550.
    facade.withdraw_from_as_perps(47_000_u128.into());

    let expected = deposit_amount - 49_000 - 47_000;
    assert!(facade.treasury_balance() == expected.into(), "balance after reset and withdraw");
}

#[test]
#[should_panic(expected: "ONLY_APP_GOVERNOR")]
fn test_reset_protection_limit_non_governor_fails() {
    let mut facade = TreasuryTestsFacadeTrait::new();
    facade.fund_treasury(TREASURY_FUND_AMOUNT);

    // Call as non-governor.
    let dispatcher = ITreasuryDispatcher { contract_address: facade.treasury_address };
    cheat_caller_address_once(
        contract_address: facade.treasury_address, caller_address: NON_PERPS_CALLER(),
    );
    dispatcher.reset_protection_limit(facade.collateral_address);
}

// ===================== Change Protection Limit Percent =====================

#[test]
fn test_change_protection_limit_percent_increases() {
    let mut facade = TreasuryTestsFacadeTrait::new();
    let deposit_amount: u128 = TREASURY_FUND_AMOUNT;

    facade.fund_treasury(deposit_amount);
    facade.reset_protection_limit();

    // Change percent from 5 to 10. New max = 1_000_000 * 10 * 10 / 1000 = 100_000.
    facade.change_protection_limit_percent(10);

    // Should be able to withdraw up to (but not equal to) 100_000.
    facade.withdraw_from_as_perps(99_000_u128.into());
    assert!(facade.treasury_balance() == (deposit_amount - 99_000).into(), "balance mismatch");
}

#[test]
#[should_panic(expected: "Treasury Protection Limit Exceeded")]
fn test_change_protection_limit_percent_reduces_limit() {
    let mut facade = TreasuryTestsFacadeTrait::new();
    let deposit_amount: u128 = TREASURY_FUND_AMOUNT;

    facade.fund_treasury(deposit_amount);
    facade.reset_protection_limit();

    // Change percent from 5 to 1. New max = 1_000_000 * 1 * 10 / 1000 = 10_000.
    facade.change_protection_limit_percent(1);

    // Withdrawing more than 10_000 should fail.
    facade.withdraw_from_as_perps(10_001_u128.into());
}

#[test]
#[should_panic(expected: "ONLY_APP_GOVERNOR")]
fn test_request_protection_limit_percent_change_non_governor_fails() {
    let mut facade = TreasuryTestsFacadeTrait::new();
    facade.fund_treasury(TREASURY_FUND_AMOUNT);
    facade.reset_protection_limit();

    let dispatcher = ITreasuryDispatcher { contract_address: facade.treasury_address };
    cheat_caller_address_once(
        contract_address: facade.treasury_address, caller_address: NON_PERPS_CALLER(),
    );
    dispatcher.request_protection_limit_percent_change(facade.collateral_address, 10);
}

// ===================== Access Control: Only Perps Can Withdraw =====================

#[test]
#[should_panic(expected: 'ONLY_PERPS_CAN_WITHDRAW')]
fn test_withdraw_from_app_governor_fails() {
    let mut facade = TreasuryTestsFacadeTrait::new();
    facade.fund_treasury(TREASURY_FUND_AMOUNT);
    facade.reset_protection_limit();

    facade.withdraw_from_as_non_perps(APP_GOVERNOR(), 100.into());
}

#[test]
#[should_panic(expected: 'ONLY_PERPS_CAN_WITHDRAW')]
fn test_withdraw_from_governance_admin_fails() {
    let mut facade = TreasuryTestsFacadeTrait::new();
    facade.fund_treasury(TREASURY_FUND_AMOUNT);
    facade.reset_protection_limit();

    facade.withdraw_from_as_non_perps(GOVERNANCE_ADMIN(), 100.into());
}

// ===================== Access Control: Only App Governor Can Call Admin Methods
// =====================

#[test]
#[should_panic(expected: "ONLY_APP_GOVERNOR")]
fn test_reset_protection_limit_perps_fails() {
    let mut facade = TreasuryTestsFacadeTrait::new();
    facade.fund_treasury(TREASURY_FUND_AMOUNT);

    let dispatcher = ITreasuryDispatcher { contract_address: facade.treasury_address };
    cheat_caller_address_once(
        contract_address: facade.treasury_address, caller_address: PERPS_CONTRACT(),
    );
    dispatcher.reset_protection_limit(facade.collateral_address);
}

#[test]
#[should_panic(expected: "ONLY_APP_GOVERNOR")]
fn test_reset_protection_limit_governance_admin_fails() {
    let mut facade = TreasuryTestsFacadeTrait::new();
    facade.fund_treasury(TREASURY_FUND_AMOUNT);

    let dispatcher = ITreasuryDispatcher { contract_address: facade.treasury_address };
    cheat_caller_address_once(
        contract_address: facade.treasury_address, caller_address: GOVERNANCE_ADMIN(),
    );
    dispatcher.reset_protection_limit(facade.collateral_address);
}

#[test]
#[should_panic(expected: "ONLY_APP_GOVERNOR")]
fn test_request_protection_limit_percent_change_perps_fails() {
    let mut facade = TreasuryTestsFacadeTrait::new();
    facade.fund_treasury(TREASURY_FUND_AMOUNT);
    facade.reset_protection_limit();

    let dispatcher = ITreasuryDispatcher { contract_address: facade.treasury_address };
    cheat_caller_address_once(
        contract_address: facade.treasury_address, caller_address: PERPS_CONTRACT(),
    );
    dispatcher.request_protection_limit_percent_change(facade.collateral_address, 10);
}

#[test]
#[should_panic(expected: "ONLY_APP_GOVERNOR")]
fn test_request_protection_limit_percent_change_governance_admin_fails() {
    let mut facade = TreasuryTestsFacadeTrait::new();
    facade.fund_treasury(TREASURY_FUND_AMOUNT);
    facade.reset_protection_limit();

    let dispatcher = ITreasuryDispatcher { contract_address: facade.treasury_address };
    cheat_caller_address_once(
        contract_address: facade.treasury_address, caller_address: GOVERNANCE_ADMIN(),
    );
    dispatcher.request_protection_limit_percent_change(facade.collateral_address, 10);
}

// ===================== Protection Limit Is Snapshotted, Not Rolling =====================

#[test]
#[should_panic(expected: "Treasury Protection Limit Exceeded")]
fn test_protection_limit_snapshotted_not_rolling_with_deposits() {
    let mut facade = TreasuryTestsFacadeTrait::new();

    // 1. Deposit a small amount and snapshot the protection limit.
    let small_deposit: u128 = 100_000;
    facade.fund_treasury(small_deposit);
    facade.reset_protection_limit();
    // max_allowed = 100_000 * 5 * 10 / 1000 = 5_000.

    // 2. Withdraw a small amount within the limit.
    facade.withdraw_from_as_perps(4_000_u128.into());

    // 3. Deposit a much larger amount — treasury balance is now high,
    //    but the protection limit is still based on the old snapshot.
    let large_deposit: u128 = 10_000_000;
    let depositor = NON_PERPS_CALLER();
    facade.fund_account(depositor, large_deposit);
    facade.approve_treasury(depositor, large_deposit);
    facade.deposit_into(depositor, large_deposit.into());

    // 4. Try to withdraw an amount that would be fine under the new balance
    //    but exceeds the snapshotted limit. Remaining allowance = 5_000 - 4_000 = 1_000.
    //    Withdrawing 2_000 pushes total to 6_000 >= 5_000 => panic.
    facade.withdraw_from_as_perps(2_000_u128.into());
}

// ===================== Auto-Reset After CHECK_FREQUENCY =====================

#[test]
fn test_auto_reset_after_one_day() {
    let mut facade = TreasuryTestsFacadeTrait::new();
    let deposit_amount: u128 = TREASURY_FUND_AMOUNT;

    facade.fund_treasury(deposit_amount);
    facade.reset_protection_limit();

    // Withdraw close to the limit.
    facade.withdraw_from_as_perps(49_000_u128.into());

    // Advance time past CHECK_FREQUENCY (1 day).
    facade.advance_time(DAY + 1);

    // The protection limit should auto-reset on next withdrawal.
    // New balance = 951_000, new max = 951_000 * 50 / 1000 = 47_550.
    facade.withdraw_from_as_perps(47_000_u128.into());

    let expected = deposit_amount - 49_000 - 47_000;
    assert!(facade.treasury_balance() == expected.into(), "balance after auto-reset");
}

#[test]
#[should_panic(expected: "Treasury Protection Limit Exceeded")]
fn test_no_auto_reset_within_one_day() {
    let mut facade = TreasuryTestsFacadeTrait::new();
    let deposit_amount: u128 = TREASURY_FUND_AMOUNT;

    facade.fund_treasury(deposit_amount);
    facade.reset_protection_limit();

    facade.withdraw_from_as_perps(49_000_u128.into());

    // Advance time but NOT past the CHECK_FREQUENCY.
    facade.advance_time(DAY - 1);

    // Should still be limited by the original protection period.
    // Total withdrawn would be 49_000 + 2_000 = 51_000 > 50_000.
    facade.withdraw_from_as_perps(2_000_u128.into());
}

// ===================== Pre-Reset / Edge Cases =====================

#[test]
fn test_deposit_zero_amount() {
    let mut facade = TreasuryTestsFacadeTrait::new();
    let depositor = NON_PERPS_CALLER();

    facade.fund_account(depositor, TREASURY_FUND_AMOUNT);
    facade.approve_treasury(depositor, 0);

    let balance_before = facade.treasury_balance();
    facade.deposit_into(depositor, 0_u256);
    let balance_after = facade.treasury_balance();

    assert!(balance_before == balance_after, "balance should not change on zero deposit");
}

#[test]
#[should_panic(expected: "Treasury Protection Limit Exceeded")]
fn test_no_auto_reset_at_exact_day() {
    let mut facade = TreasuryTestsFacadeTrait::new();
    let deposit_amount: u128 = TREASURY_FUND_AMOUNT;

    facade.fund_treasury(deposit_amount);
    facade.reset_protection_limit();

    facade.withdraw_from_as_perps(49_000_u128.into());

    // Advance time by exactly DAY (not DAY+1).
    // The check is `time_elapsed > CHECK_FREQUENCY` (strictly greater),
    // so exactly DAY should NOT trigger auto-reset.
    facade.advance_time(DAY);

    // Total withdrawn = 49_000 + 2_000 = 51_000 > 50_000 => panic.
    facade.withdraw_from_as_perps(2_000_u128.into());
}

#[test]
#[should_panic(expected: "Treasury Protection Limit Exceeded")]
fn test_change_protection_limit_to_zero() {
    let mut facade = TreasuryTestsFacadeTrait::new();

    facade.fund_treasury(TREASURY_FUND_AMOUNT);
    facade.reset_protection_limit();

    // Set protection percent to 0. max_allowed = 0.
    facade.change_protection_limit_percent(0);

    // Any withdrawal should fail since max_allowed is 0.
    facade.withdraw_from_as_perps(1_u128.into());
}

// ===================== Pausable =====================

#[test]
#[should_panic(expected: 'PAUSED')]
fn test_deposit_blocked_when_paused() {
    let mut facade = TreasuryTestsFacadeTrait::new();
    let depositor = NON_PERPS_CALLER();
    facade.fund_account(depositor, TREASURY_FUND_AMOUNT);
    facade.approve_treasury(depositor, TREASURY_FUND_AMOUNT);

    facade.pause_treasury();
    facade.deposit_into(depositor, TREASURY_FUND_AMOUNT.into());
}

#[test]
#[should_panic(expected: 'PAUSED')]
fn test_withdraw_blocked_when_paused() {
    let mut facade = TreasuryTestsFacadeTrait::new();
    facade.fund_treasury(TREASURY_FUND_AMOUNT);
    facade.reset_protection_limit();

    facade.pause_treasury();
    facade.withdraw_from_as_perps(100_u128.into());
}

#[test]
fn test_deposit_works_after_unpause() {
    let mut facade = TreasuryTestsFacadeTrait::new();
    let depositor = NON_PERPS_CALLER();
    facade.fund_account(depositor, TREASURY_FUND_AMOUNT);
    facade.approve_treasury(depositor, TREASURY_FUND_AMOUNT);

    facade.pause_treasury();
    facade.unpause_treasury();

    let balance_before = facade.treasury_balance();
    facade.deposit_into(depositor, TREASURY_FUND_AMOUNT.into());
    assert!(
        facade.treasury_balance() == balance_before + TREASURY_FUND_AMOUNT.into(),
        "deposit should work after unpause",
    );
}

#[test]
fn test_withdraw_works_after_unpause() {
    let mut facade = TreasuryTestsFacadeTrait::new();
    facade.fund_treasury(TREASURY_FUND_AMOUNT);
    facade.reset_protection_limit();

    facade.pause_treasury();
    facade.unpause_treasury();

    facade.withdraw_from_as_perps(100_u128.into());
}

// ===================== Reset Cooldown (once per day) =====================

#[test]
#[should_panic(expected: 'RESET_COOLDOWN_ACTIVE')]
fn test_reset_protection_limit_cooldown_blocks_within_day() {
    let mut facade = TreasuryTestsFacadeTrait::new();
    facade.fund_treasury(TREASURY_FUND_AMOUNT);

    // First reset is always allowed; a second reset on the same day is blocked.
    facade.reset_protection_limit();
    facade.reset_protection_limit();
}

#[test]
#[should_panic(expected: 'RESET_COOLDOWN_ACTIVE')]
fn test_reset_protection_limit_cooldown_blocks_just_under_a_day() {
    let mut facade = TreasuryTestsFacadeTrait::new();
    facade.fund_treasury(TREASURY_FUND_AMOUNT);

    facade.reset_protection_limit();
    facade.advance_time(DAY - 1);
    facade.reset_protection_limit();
}

#[test]
fn test_reset_protection_limit_cooldown_allows_at_exactly_one_day() {
    let mut facade = TreasuryTestsFacadeTrait::new();
    facade.fund_treasury(TREASURY_FUND_AMOUNT);

    facade.reset_protection_limit();
    // Cooldown boundary is inclusive: exactly one day later is allowed.
    facade.advance_time(DAY);
    facade.reset_protection_limit();

    assert!(
        facade.treasury_balance() == TREASURY_FUND_AMOUNT.into(), "balance should be unchanged",
    );
}

#[test]
fn test_reset_protection_limit_cooldown_allows_after_a_day() {
    let mut facade = TreasuryTestsFacadeTrait::new();
    facade.fund_treasury(TREASURY_FUND_AMOUNT);

    facade.reset_protection_limit();
    facade.advance_time(DAY + 1);
    facade.reset_protection_limit();

    assert!(
        facade.treasury_balance() == TREASURY_FUND_AMOUNT.into(), "balance should be unchanged",
    );
}

// ===================== Request / Apply / Cancel Percent Change =====================

#[test]
fn test_request_records_pending_change() {
    let mut facade = TreasuryTestsFacadeTrait::new();
    facade.fund_treasury(TREASURY_FUND_AMOUNT);

    facade.request_protection_limit_percent_change(10);

    let pending = facade
        .treasury_dispatcher
        .get_pending_protection_limit_change(facade.collateral_address);
    assert!(pending.percent == 10, "pending percent mismatch");
    assert!(pending.applicable_at.seconds != 0, "pending should have an applicable_at set");
}

#[test]
#[should_panic(expected: "Treasury Protection Limit Exceeded")]
fn test_request_does_not_apply_immediately() {
    let mut facade = TreasuryTestsFacadeTrait::new();
    facade.fund_treasury(TREASURY_FUND_AMOUNT);
    facade.reset_protection_limit();

    // Request an increase to 10% (max would become 100_000), but do NOT apply it.
    facade.request_protection_limit_percent_change(10);

    // The old 5% limit (max 50_000) is still in force, so 50_001 must still fail.
    facade.withdraw_from_as_perps(50_001_u128.into());
}

#[test]
#[should_panic(expected: 'TIMELOCK_NOT_PASSED')]
fn test_apply_before_timelock_fails() {
    let mut facade = TreasuryTestsFacadeTrait::new();
    facade.fund_treasury(TREASURY_FUND_AMOUNT);
    facade.reset_protection_limit();

    facade.request_protection_limit_percent_change(10);
    facade.advance_time(DAY - 1);
    facade.apply_protection_limit_percent_change();
}

#[test]
fn test_apply_after_timelock_succeeds() {
    let mut facade = TreasuryTestsFacadeTrait::new();
    let deposit_amount: u128 = TREASURY_FUND_AMOUNT;
    facade.fund_treasury(deposit_amount);
    facade.reset_protection_limit();

    facade.request_protection_limit_percent_change(10);
    facade.advance_time(DAY);
    facade.apply_protection_limit_percent_change();

    // New max = 1_000_000 * 10 * 10 / 1000 = 100_000.
    facade.withdraw_from_as_perps(99_000_u128.into());
    assert!(facade.treasury_balance() == (deposit_amount - 99_000).into(), "balance mismatch");
}

#[test]
fn test_apply_clears_pending_change() {
    let mut facade = TreasuryTestsFacadeTrait::new();
    facade.fund_treasury(TREASURY_FUND_AMOUNT);
    facade.reset_protection_limit();

    facade.request_protection_limit_percent_change(10);
    facade.advance_time(DAY);
    facade.apply_protection_limit_percent_change();

    let pending = facade
        .treasury_dispatcher
        .get_pending_protection_limit_change(facade.collateral_address);
    assert!(pending.applicable_at.seconds == 0, "pending should be cleared after apply");
}

#[test]
#[should_panic(expected: 'NO_PENDING_CHANGE')]
fn test_apply_with_no_pending_fails() {
    let mut facade = TreasuryTestsFacadeTrait::new();
    facade.fund_treasury(TREASURY_FUND_AMOUNT);

    facade.apply_protection_limit_percent_change();
}

#[test]
fn test_cancel_clears_pending_change() {
    let mut facade = TreasuryTestsFacadeTrait::new();
    facade.fund_treasury(TREASURY_FUND_AMOUNT);

    facade.request_protection_limit_percent_change(10);
    facade.cancel_protection_limit_percent_change();

    let pending = facade
        .treasury_dispatcher
        .get_pending_protection_limit_change(facade.collateral_address);
    assert!(pending.applicable_at.seconds == 0, "pending should be cleared after cancel");
    assert!(pending.percent == 0, "pending percent should be cleared after cancel");
}

#[test]
#[should_panic(expected: 'NO_PENDING_CHANGE')]
fn test_cancel_with_no_pending_fails() {
    let mut facade = TreasuryTestsFacadeTrait::new();
    facade.fund_treasury(TREASURY_FUND_AMOUNT);

    facade.cancel_protection_limit_percent_change();
}

#[test]
#[should_panic(expected: 'NO_PENDING_CHANGE')]
fn test_apply_after_cancel_fails() {
    let mut facade = TreasuryTestsFacadeTrait::new();
    facade.fund_treasury(TREASURY_FUND_AMOUNT);

    facade.request_protection_limit_percent_change(10);
    facade.cancel_protection_limit_percent_change();
    facade.advance_time(DAY);
    facade.apply_protection_limit_percent_change();
}

#[test]
fn test_request_overwrites_pending_change() {
    let mut facade = TreasuryTestsFacadeTrait::new();
    facade.fund_treasury(TREASURY_FUND_AMOUNT);

    facade.request_protection_limit_percent_change(10);
    facade.request_protection_limit_percent_change(20);

    let pending = facade
        .treasury_dispatcher
        .get_pending_protection_limit_change(facade.collateral_address);
    assert!(pending.percent == 20, "re-request should overwrite the pending percent");
}

#[test]
#[should_panic(expected: "ONLY_APP_GOVERNOR")]
fn test_apply_protection_limit_percent_change_non_governor_fails() {
    let mut facade = TreasuryTestsFacadeTrait::new();
    facade.fund_treasury(TREASURY_FUND_AMOUNT);

    let dispatcher = ITreasuryDispatcher { contract_address: facade.treasury_address };
    cheat_caller_address_once(
        contract_address: facade.treasury_address, caller_address: NON_PERPS_CALLER(),
    );
    dispatcher.apply_protection_limit_percent_change(facade.collateral_address);
}

#[test]
#[should_panic(expected: "ONLY_APP_GOVERNOR")]
fn test_cancel_protection_limit_percent_change_non_governor_fails() {
    let mut facade = TreasuryTestsFacadeTrait::new();
    facade.fund_treasury(TREASURY_FUND_AMOUNT);

    let dispatcher = ITreasuryDispatcher { contract_address: facade.treasury_address };
    cheat_caller_address_once(
        contract_address: facade.treasury_address, caller_address: NON_PERPS_CALLER(),
    );
    dispatcher.cancel_protection_limit_percent_change(facade.collateral_address);
}

// ===================== Reset Cooldown / Change Timelock Are Independent =====================

#[test]
fn test_getters_return_configured_delays() {
    let facade = TreasuryTestsFacadeTrait::new_with_delays(
        reset_cooldown_seconds: DAY, change_timelock_seconds: WEEK,
    );
    assert!(
        facade.treasury_dispatcher.get_reset_cooldown().seconds == DAY, "reset cooldown mismatch",
    );
    assert!(
        facade.treasury_dispatcher.get_protection_limit_timelock().seconds == WEEK,
        "change timelock mismatch",
    );
}

#[test]
fn test_reset_cooldown_independent_of_longer_change_timelock() {
    // A long (one week) change timelock must not slow down the once-per-day reset cadence.
    let mut facade = TreasuryTestsFacadeTrait::new_with_delays(
        reset_cooldown_seconds: DAY, change_timelock_seconds: WEEK,
    );
    facade.fund_treasury(TREASURY_FUND_AMOUNT);

    facade.reset_protection_limit();
    facade.advance_time(DAY + 1);
    // Allowed one day later, despite the week-long change timelock.
    facade.reset_protection_limit();

    assert!(
        facade.treasury_balance() == TREASURY_FUND_AMOUNT.into(), "balance should be unchanged",
    );
}

#[test]
#[should_panic(expected: 'TIMELOCK_NOT_PASSED')]
fn test_change_timelock_independent_of_shorter_reset_cooldown() {
    // The change timelock (one week) is enforced independently of the shorter reset cooldown.
    let mut facade = TreasuryTestsFacadeTrait::new_with_delays(
        reset_cooldown_seconds: DAY, change_timelock_seconds: WEEK,
    );
    facade.fund_treasury(TREASURY_FUND_AMOUNT);

    facade.request_protection_limit_percent_change(10);
    // Past the reset cooldown (a day) but not the change timelock (a week).
    facade.advance_time(DAY + 1);
    facade.apply_protection_limit_percent_change();
}

#[test]
fn test_change_timelock_applies_after_full_timelock() {
    let mut facade = TreasuryTestsFacadeTrait::new_with_delays(
        reset_cooldown_seconds: DAY, change_timelock_seconds: WEEK,
    );
    let deposit_amount: u128 = TREASURY_FUND_AMOUNT;
    facade.fund_treasury(deposit_amount);
    facade.reset_protection_limit();

    facade.request_protection_limit_percent_change(10);
    facade.advance_time(WEEK);
    facade.apply_protection_limit_percent_change();

    // New max = 1_000_000 * 10 * 10 / 1000 = 100_000.
    facade.withdraw_from_as_perps(99_000_u128.into());
    assert!(facade.treasury_balance() == (deposit_amount - 99_000).into(), "balance mismatch");
}

// ===================== Percent Bound =====================

#[test]
#[should_panic(expected: 'PERCENT_TOO_HIGH')]
fn test_request_percent_above_100_fails() {
    let mut facade = TreasuryTestsFacadeTrait::new();
    facade.fund_treasury(TREASURY_FUND_AMOUNT);
    facade.request_protection_limit_percent_change(101);
}

#[test]
fn test_request_percent_exactly_100_allowed() {
    let mut facade = TreasuryTestsFacadeTrait::new();
    facade.fund_treasury(TREASURY_FUND_AMOUNT);
    facade.request_protection_limit_percent_change(100);
    let pending = facade
        .treasury_dispatcher
        .get_pending_protection_limit_change(facade.collateral_address);
    assert!(pending.percent == 100, "percent 100 should be accepted");
}

// ===================== Effective Percent Getter =====================

#[test]
fn test_get_protection_limit_percent_defaults_then_reflects_override() {
    let mut facade = TreasuryTestsFacadeTrait::new();
    facade.fund_treasury(TREASURY_FUND_AMOUNT);
    facade.reset_protection_limit();

    // With no override set, the effective percent is the default (5).
    assert!(
        facade.treasury_dispatcher.get_protection_limit_percent(facade.collateral_address) == 5,
        "effective percent should default to 5",
    );

    // After applying an override, the getter reflects it.
    facade.change_protection_limit_percent(10);
    assert!(
        facade.treasury_dispatcher.get_protection_limit_percent(facade.collateral_address) == 10,
        "effective percent should reflect the applied override",
    );
}

// ===================== Reject No-Op Percent Requests =====================

#[test]
#[should_panic(expected: 'PERCENT_UNCHANGED')]
fn test_request_matching_default_effective_percent_fails() {
    let mut facade = TreasuryTestsFacadeTrait::new();
    facade.fund_treasury(TREASURY_FUND_AMOUNT);

    // No override has been set, so the effective percent is the default (5).
    // Requesting it again is a no-op and must be rejected.
    facade.request_protection_limit_percent_change(5);
}

#[test]
#[should_panic(expected: 'PERCENT_UNCHANGED')]
fn test_request_matching_applied_override_fails() {
    let mut facade = TreasuryTestsFacadeTrait::new();
    facade.fund_treasury(TREASURY_FUND_AMOUNT);
    facade.reset_protection_limit();

    // Apply an override of 10, then request 10 again — the effective percent is unchanged.
    facade.change_protection_limit_percent(10);
    facade.request_protection_limit_percent_change(10);
}

#[test]
#[should_panic(expected: 'PENDING_PERCENT_UNCHANGED')]
fn test_request_matching_pending_percent_fails() {
    let mut facade = TreasuryTestsFacadeTrait::new();
    facade.fund_treasury(TREASURY_FUND_AMOUNT);

    // First request records a pending change to 10. Re-requesting the same pending percent
    // would only push the apply window out, so it must be rejected.
    facade.request_protection_limit_percent_change(10);
    facade.request_protection_limit_percent_change(10);
}

#[test]
#[should_panic(expected: 'PERCENT_UNCHANGED')]
fn test_request_matching_effective_percent_with_different_pending_fails() {
    let mut facade = TreasuryTestsFacadeTrait::new();
    facade.fund_treasury(TREASURY_FUND_AMOUNT);

    // A pending change to 10 exists, but the effective percent is still the default (5).
    // Requesting 5 (the effective percent) is a no-op and must be rejected.
    facade.request_protection_limit_percent_change(10);
    facade.request_protection_limit_percent_change(5);
}

#[test]
fn test_request_differing_from_pending_is_allowed() {
    let mut facade = TreasuryTestsFacadeTrait::new();
    facade.fund_treasury(TREASURY_FUND_AMOUNT);

    // Re-requesting a value that differs from both the effective and the pending percent
    // overwrites the pending change as usual.
    facade.request_protection_limit_percent_change(10);
    facade.request_protection_limit_percent_change(20);

    let pending = facade
        .treasury_dispatcher
        .get_pending_protection_limit_change(facade.collateral_address);
    assert!(pending.percent == 20, "differing re-request should overwrite the pending percent");
}

// ===================== Apply Uses The Snapshot, Not Current Balance =====================

#[test]
#[should_panic(expected: "Treasury Protection Limit Exceeded")]
fn test_apply_recomputes_max_on_existing_snapshot_not_current_balance() {
    let mut facade = TreasuryTestsFacadeTrait::new();
    facade.fund_treasury(TREASURY_FUND_AMOUNT); // 1_000_000
    facade.reset_protection_limit(); // snapshot balance = 1_000_000

    // Deposit more AFTER the snapshot; this must not affect the snapshotted limit.
    let depositor = NON_PERPS_CALLER();
    facade.fund_account(depositor, TREASURY_FUND_AMOUNT);
    facade.approve_treasury(depositor, TREASURY_FUND_AMOUNT);
    facade.deposit_into(depositor, TREASURY_FUND_AMOUNT.into()); // balance now 2_000_000

    // Apply 10%. Against the 1_000_000 snapshot, max = 100_000 (not 200_000 of current balance).
    facade.change_protection_limit_percent(10);

    // 150_000 is under a rolling 200_000 limit but over the snapshotted 100_000 — must fail.
    facade.withdraw_from_as_perps(150_000_u128.into());
}

// ===================== New Admin Functions Are Pausable =====================

#[test]
#[should_panic(expected: 'PAUSED')]
fn test_reset_blocked_when_paused() {
    let mut facade = TreasuryTestsFacadeTrait::new();
    facade.fund_treasury(TREASURY_FUND_AMOUNT);
    facade.pause_treasury();
    facade.reset_protection_limit();
}

#[test]
#[should_panic(expected: 'PAUSED')]
fn test_request_blocked_when_paused() {
    let mut facade = TreasuryTestsFacadeTrait::new();
    facade.fund_treasury(TREASURY_FUND_AMOUNT);
    facade.pause_treasury();
    facade.request_protection_limit_percent_change(10);
}

#[test]
#[should_panic(expected: 'PAUSED')]
fn test_apply_blocked_when_paused() {
    let mut facade = TreasuryTestsFacadeTrait::new();
    facade.fund_treasury(TREASURY_FUND_AMOUNT);
    facade.request_protection_limit_percent_change(10);
    facade.advance_time(DAY);
    facade.pause_treasury();
    facade.apply_protection_limit_percent_change();
}

#[test]
#[should_panic(expected: 'PAUSED')]
fn test_cancel_blocked_when_paused() {
    let mut facade = TreasuryTestsFacadeTrait::new();
    facade.fund_treasury(TREASURY_FUND_AMOUNT);
    facade.request_protection_limit_percent_change(10);
    facade.pause_treasury();
    facade.cancel_protection_limit_percent_change();
}

// ===================== Events =====================

#[test]
fn test_request_and_apply_emit_events() {
    let mut facade = TreasuryTestsFacadeTrait::new();
    facade.fund_treasury(TREASURY_FUND_AMOUNT);
    let collateral = facade.collateral_address;
    let treasury_address = facade.treasury_address;

    let mut spy = snforge_std::spy_events();

    facade.request_protection_limit_percent_change(10);
    let pending = facade.treasury_dispatcher.get_pending_protection_limit_change(collateral);
    spy
        .assert_emitted(
            @array![
                (
                    treasury_address,
                    ProtocolTreasury::Event::AdminLimitChangeRequested(
                        ProtocolTreasury::AdminLimitChangeRequested {
                            collateral_address: collateral,
                            percent: 10,
                            applicable_at: pending.applicable_at,
                        },
                    ),
                ),
            ],
        );

    facade.advance_time(DAY);
    facade.apply_protection_limit_percent_change();
    spy
        .assert_emitted(
            @array![
                (
                    treasury_address,
                    ProtocolTreasury::Event::AdminLimitChanged(
                        ProtocolTreasury::AdminLimitChanged {
                            collateral_address: collateral, percent: 10,
                        },
                    ),
                ),
            ],
        );
}

#[test]
fn test_cancel_emits_event() {
    let mut facade = TreasuryTestsFacadeTrait::new();
    facade.fund_treasury(TREASURY_FUND_AMOUNT);
    let collateral = facade.collateral_address;
    let treasury_address = facade.treasury_address;

    facade.request_protection_limit_percent_change(10);
    let mut spy = snforge_std::spy_events();
    facade.cancel_protection_limit_percent_change();
    spy
        .assert_emitted(
            @array![
                (
                    treasury_address,
                    ProtocolTreasury::Event::AdminLimitChangeCancelled(
                        ProtocolTreasury::AdminLimitChangeCancelled {
                            collateral_address: collateral, percent: 10,
                        },
                    ),
                ),
            ],
        );
}

#[test]
fn test_reset_emits_event() {
    let mut facade = TreasuryTestsFacadeTrait::new();
    facade.fund_treasury(TREASURY_FUND_AMOUNT);
    let collateral = facade.collateral_address;
    let treasury_address = facade.treasury_address;

    let mut spy = snforge_std::spy_events();
    facade.reset_protection_limit();
    spy
        .assert_emitted(
            @array![
                (
                    treasury_address,
                    ProtocolTreasury::Event::AdminLimitReset(
                        ProtocolTreasury::AdminLimitReset { collateral_address: collateral },
                    ),
                ),
            ],
        );
}
