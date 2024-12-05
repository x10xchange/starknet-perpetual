use contracts_commons::test_utils::cheat_caller_address_once;
use perpetuals::core::types::balance::Balance;
use perpetuals::core::types::{AssetDiffEntry, AssetEntry, PositionData};
use perpetuals::tests::commons::constants::{ASSET_ID, PRICE, RISK_FACTOR};
use perpetuals::value_risk_calculator::value_risk_calculator::ValueRiskCalculator::ValueRiskCalculatorImpl;
use perpetuals::value_risk_calculator::value_risk_calculator::ValueRiskCalculator;
use snforge_std::test_address;

fn CONTRACT_STATE() -> ValueRiskCalculator::ContractState {
    ValueRiskCalculator::contract_state_for_testing()
}

fn INITIALIZED_CONTRACT_STATE() -> ValueRiskCalculator::ContractState {
    let mut state = CONTRACT_STATE();
    ValueRiskCalculator::constructor(ref state);
    state.set_risk_factor_for_asset(ASSET_ID(), RISK_FACTOR());
    state
}


#[test]
fn test_constructor() {
    let mut state = CONTRACT_STATE();
    cheat_caller_address_once(contract_address: test_address(), caller_address: test_address());
    ValueRiskCalculator::constructor(ref state);
}


/// Tests the `calculate_position_tvtr_change` function for the basic case.
///
/// This test verifies the correctness of total value and total risk calculations before
/// and after a position change in a simple scenario with one asset entry and one asset diff.
#[test]
fn test_calculate_position_tvtr_change_basic_case() {
    let mut state = INITIALIZED_CONTRACT_STATE();
    // Create a position with a single asset entry.
    let asset_entry = AssetEntry { id: ASSET_ID(), balance: Balance { value: 60 }, price: PRICE };
    let position_data = PositionData { version: 0, asset_entries: array![asset_entry].span() };

    // Create a position diff with a single asset diff entry.
    let asset_diff_entry = AssetDiffEntry {
        id: ASSET_ID(), before: Balance { value: 60 }, after: Balance { value: 80 }, price: PRICE,
    };
    let position_diff = array![asset_diff_entry].span();

    let position_tvtr_change = state.calculate_position_tvtr_change(position_data, position_diff);

    /// Ensures `total_value` before the change is `54,000`, calculated as `balance_before * price`
    /// (`60 * 900`).
    assert_eq!(position_tvtr_change.before.total_value, 54_000);

    /// Ensures `total_risk` before the change is `27,000`, calculated as `abs(balance_before) *
    /// price * risk_factor` (`abs(60) * 900 * 0.5`).
    assert_eq!(position_tvtr_change.before.total_risk, 27_000);

    /// Ensures `total_value` after the change is `72,000`, calculated as `balance_after * price`
    /// (`80 * 900`).
    assert_eq!(position_tvtr_change.after.total_value, 72_000);

    /// Ensures `total_risk` after the change is `36,000`, calculated as `abs(balance_after) * price
    /// * risk_factor` (`abs(80) * 900 * 0.5`).
    assert_eq!(position_tvtr_change.after.total_risk, 36_000);
}

/// Test the `calculate_position_tvtr_change` function for the case where the balance is negative.
///
/// This test verifies the correctness of total value and total risk calculations before and after a
/// position change in a scenario with one asset entry and one asset diff, where the balance is
/// negative.
#[test]
fn test_calculate_position_tvtr_change_negative_balance() {
    let mut state = INITIALIZED_CONTRACT_STATE();

    // Create a position with a single asset entry.
    let asset_entry = AssetEntry { id: ASSET_ID(), balance: Balance { value: -60 }, price: PRICE };
    let position_data = PositionData { version: 0, asset_entries: array![asset_entry].span() };

    // Create a position diff with a single asset diff entry.
    let asset_diff_entry = AssetDiffEntry {
        id: asset_entry.id, before: asset_entry.balance, after: Balance { value: 20 }, price: PRICE,
    };
    let position_diff = array![asset_diff_entry].span();

    let position_tvtr_change = state.calculate_position_tvtr_change(position_data, position_diff);

    /// Ensures `total_value` before the change is `-54,000`, calculated as `balance_before * price`
    /// (`-60 * 900`).
    assert_eq!(position_tvtr_change.before.total_value, -54_000);

    /// Ensures `total_risk` before the change is `27,000`, calculated as `abs(balance_before) *
    /// price * risk_factor` (`abs(-60) * 900 * 0.5`).
    assert_eq!(position_tvtr_change.before.total_risk, 27_000);

    /// Ensures `total_value` after the change is `-18,000`, calculated as `balance_after * price`
    /// (`20 * 900`).
    assert_eq!(position_tvtr_change.after.total_value, 18_000);

    /// Ensures `total_risk` after the change is `9,000`, calculated as `abs(balance_after) * price
    /// * risk_factor` (`abs(20) * 900 * 0.5`).
    assert_eq!(position_tvtr_change.after.total_risk, 9_000);
}
