use starkware_utils::constants::DAY;
use starkware_utils_testing::test_utils::cheat_caller_address_once;
use treasury::interface::{ITreasuryDispatcher, ITreasuryDispatcherTrait};
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
    // Withdrawing exactly that amount should panic (>= check).
    facade.withdraw_from_as_perps(50_000_u128.into());
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
    // Total so far = 49_000. Next one pushes to 51_000 >= 50_000.
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

    // Withdrawing 10_000 should fail (>= check).
    facade.withdraw_from_as_perps(10_000_u128.into());
}

#[test]
#[should_panic(expected: "ONLY_APP_GOVERNOR")]
fn test_change_protection_limit_percent_non_governor_fails() {
    let mut facade = TreasuryTestsFacadeTrait::new();
    facade.fund_treasury(TREASURY_FUND_AMOUNT);
    facade.reset_protection_limit();

    let dispatcher = ITreasuryDispatcher { contract_address: facade.treasury_address };
    cheat_caller_address_once(
        contract_address: facade.treasury_address, caller_address: NON_PERPS_CALLER(),
    );
    dispatcher.change_protection_limit_percent(facade.collateral_address, 10);
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

// ===================== Access Control: Only App Governor Can Call Admin Methods =====================

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
fn test_change_protection_limit_percent_perps_fails() {
    let mut facade = TreasuryTestsFacadeTrait::new();
    facade.fund_treasury(TREASURY_FUND_AMOUNT);
    facade.reset_protection_limit();

    let dispatcher = ITreasuryDispatcher { contract_address: facade.treasury_address };
    cheat_caller_address_once(
        contract_address: facade.treasury_address, caller_address: PERPS_CONTRACT(),
    );
    dispatcher.change_protection_limit_percent(facade.collateral_address, 10);
}

#[test]
#[should_panic(expected: "ONLY_APP_GOVERNOR")]
fn test_change_protection_limit_percent_governance_admin_fails() {
    let mut facade = TreasuryTestsFacadeTrait::new();
    facade.fund_treasury(TREASURY_FUND_AMOUNT);
    facade.reset_protection_limit();

    let dispatcher = ITreasuryDispatcher { contract_address: facade.treasury_address };
    cheat_caller_address_once(
        contract_address: facade.treasury_address, caller_address: GOVERNANCE_ADMIN(),
    );
    dispatcher.change_protection_limit_percent(facade.collateral_address, 10);
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
    // Total withdrawn would be 49_000 + 2_000 = 51_000 >= 50_000.
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

    // Total withdrawn = 49_000 + 2_000 = 51_000 >= 50_000 => panic.
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
