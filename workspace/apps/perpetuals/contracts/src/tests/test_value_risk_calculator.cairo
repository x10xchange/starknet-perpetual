use contracts_commons::test_utils::cheat_caller_address_once;
use perpetuals::core::types::balance::BalanceTrait;
use perpetuals::core::types::{AssetDiffEntry, AssetEntry, PositionData};
use perpetuals::tests::constants::{
    PRICE_1, PRICE_2, PRICE_3, PRICE_4, PRICE_5, RISK_FACTOR_1, RISK_FACTOR_2, RISK_FACTOR_3,
    RISK_FACTOR_4, RISK_FACTOR_5, SYNTHETIC_ASSET_ID_1, SYNTHETIC_ASSET_ID_2, SYNTHETIC_ASSET_ID_3,
    SYNTHETIC_ASSET_ID_4, SYNTHETIC_ASSET_ID_5,
};
use perpetuals::value_risk_calculator::value_risk_calculator::ValueRiskCalculator;
use perpetuals::value_risk_calculator::value_risk_calculator::ValueRiskCalculator::{
    InternalValueRiskCalculatorFunctionsTrait, ValueRiskCalculatorImpl,
};
use snforge_std::test_address;

fn CONTRACT_STATE() -> ValueRiskCalculator::ContractState {
    ValueRiskCalculator::contract_state_for_testing()
}

fn INITIALIZED_CONTRACT_STATE() -> ValueRiskCalculator::ContractState {
    let mut state = CONTRACT_STATE();
    ValueRiskCalculator::constructor(ref state);
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
    let asset_entry = AssetEntry {
        id: SYNTHETIC_ASSET_ID_1(),
        balance: BalanceTrait::new(value: 60),
        price: PRICE_1(),
        risk_factor: RISK_FACTOR_1(),
    };
    let position_data = PositionData { asset_entries: array![asset_entry].span() };

    // Create a position diff with a single asset diff entry.
    let asset_diff_entry = AssetDiffEntry {
        id: asset_entry.id,
        before: asset_entry.balance,
        after: BalanceTrait::new(value: 80),
        price: asset_entry.price,
        risk_factor: RISK_FACTOR_1(),
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
    let asset_entry = AssetEntry {
        id: SYNTHETIC_ASSET_ID_1(),
        balance: BalanceTrait::new(value: -60),
        price: PRICE_1(),
        risk_factor: RISK_FACTOR_1(),
    };
    let position_data = PositionData { asset_entries: array![asset_entry].span() };

    // Create a position diff with a single asset diff entry.
    let asset_diff_entry = AssetDiffEntry {
        id: asset_entry.id,
        before: asset_entry.balance,
        after: BalanceTrait::new(value: 20),
        price: asset_entry.price,
        risk_factor: RISK_FACTOR_1(),
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

/// Test the `calculate_position_tvtr_change` function for the case where there are multiple asset
///
/// This test verifies the correctness of total value and total risk calculations before and after a
/// position change in a scenario with multiple asset entries and multiple asset diffs.
#[test]
fn test_calculate_position_tvtr_change_multiple_assets() {
    let mut state = INITIALIZED_CONTRACT_STATE();

    // Create a position with multiple asset entries.
    let asset_entry_1 = AssetEntry {
        id: SYNTHETIC_ASSET_ID_1(),
        balance: BalanceTrait::new(value: 60),
        price: PRICE_1(),
        risk_factor: RISK_FACTOR_1(),
    };
    let asset_entry_2 = AssetEntry {
        id: SYNTHETIC_ASSET_ID_2(),
        balance: BalanceTrait::new(value: 40),
        price: PRICE_2(),
        risk_factor: RISK_FACTOR_2(),
    };
    let asset_entry_3 = AssetEntry {
        id: SYNTHETIC_ASSET_ID_3(),
        balance: BalanceTrait::new(value: 20),
        price: PRICE_3(),
        risk_factor: RISK_FACTOR_3(),
    };
    let asset_entry_4 = AssetEntry {
        id: SYNTHETIC_ASSET_ID_4(),
        balance: BalanceTrait::new(value: 10),
        price: PRICE_4(),
        risk_factor: RISK_FACTOR_4(),
    };
    let asset_entry_5 = AssetEntry {
        id: SYNTHETIC_ASSET_ID_5(),
        balance: BalanceTrait::new(value: 5),
        price: PRICE_5(),
        risk_factor: RISK_FACTOR_5(),
    };
    let position_data = PositionData {
        asset_entries: array![
            asset_entry_1, asset_entry_2, asset_entry_3, asset_entry_4, asset_entry_5,
        ]
            .span(),
    };

    // Create a position diff with two asset diff entries.
    let asset_diff_entry_1 = AssetDiffEntry {
        id: asset_entry_1.id,
        before: asset_entry_1.balance,
        after: BalanceTrait::new(value: 80),
        price: asset_entry_1.price,
        risk_factor: RISK_FACTOR_1(),
    };
    let asset_diff_entry_2 = AssetDiffEntry {
        id: asset_entry_2.id,
        before: asset_entry_2.balance,
        after: BalanceTrait::new(value: 60),
        price: asset_entry_2.price,
        risk_factor: RISK_FACTOR_2(),
    };
    let position_diff = array![asset_diff_entry_1, asset_diff_entry_2].span();

    let position_tvtr_change = state.calculate_position_tvtr_change(position_data, position_diff);

    /// Ensures `total_value` before the change is `121,500`, calculated as `balance_1_before *
    /// price + balance_2_before * price + balance_3_before * price + balance_4_before * price +
    /// balance_5_before * price` (`60 * 900 + 40 * 900 + 20 * 900 + 10 * 900 + 5 * 900`).
    assert_eq!(position_tvtr_change.before.total_value, 121_500);

    /// Ensures `total_risk` before the change is `60,750`, calculated as `abs(balance_1_before) *
    /// price * risk_factor_1 + abs(balance_2_before) * price * risk_factor_2 +
    /// abs(balance_3_before) *
    /// price * risk_factor_3 + abs(balance_4_before) * price * risk_factor_4 +
    /// abs(balance_5_before) *
    /// price * risk_factor_5` (`abs(60) * 900 * 0.5 + abs(40) * 900 * 0.5 + abs(20) * 900 * 0.5 +
    /// abs(10) * 900 * 0.5 + abs(5) * 900 * 0.5`).
    assert_eq!(position_tvtr_change.before.total_risk, 60_750);

    /// Ensures `total_value` after the change is `157,500`, calculated as `balance_1_after * price
    /// + balance_2_after * price` + balance_3_after * price + balance_4_after * price +
    /// balance_5_after * price` (`80 * 900 + 60 * 900 + 20 * 900 + 10 * 900 + 5 * 900`).
    /// The balance of the other assets remains the same, so balance_3_after = 20, balance_4_after
    /// = 10, balance_5_after = 5.
    assert_eq!(position_tvtr_change.after.total_value, 157_500);

    /// Ensures `total_risk` after the change is `78,750`, calculated as `abs(balance_1_after) *
    /// price * risk_factor_1 + abs(balance_2_after) * price * risk_factor_2 +
    /// abs(balance_3_after) * price * risk_factor_3 + abs(balance_4_after) * price * risk_factor_4
    /// + abs(balance_5_after) * price * risk_factor_5` (`abs(80) * 900 * 0.5 + abs(60) * 900 * 0.5
    /// + abs(20) * 900 * 0.5 + abs(10) * 900 * 0.5 + abs(5) * 900 * 0.5`).
    /// The balance of the other assets remains the same, so balance_3_after = 20, balance_4_after
    /// = 10, balance_5_after = 5.
    assert_eq!(position_tvtr_change.after.total_risk, 78_750);
}

/// Test the `calculate_position_tvtr_change` function for the case where the diff is empty.
#[test]
fn test_calculate_position_tvtr_empty_diff() {
    let mut state = INITIALIZED_CONTRACT_STATE();

    // Create a position with a single asset entry.
    let asset_entry = AssetEntry {
        id: SYNTHETIC_ASSET_ID_1(),
        balance: BalanceTrait::new(value: 60),
        price: PRICE_1(),
        risk_factor: RISK_FACTOR_1(),
    };
    let position_data = PositionData { asset_entries: array![asset_entry].span() };

    // Create an empty position diff.
    let position_diff = array![].span();

    let position_tvtr_change = state.calculate_position_tvtr_change(position_data, position_diff);

    /// Ensures `total_value` before the change is `54,000`, calculated as `balance_before * price`
    /// (`60 * 900`).
    assert_eq!(position_tvtr_change.before.total_value, 54_000);

    /// Ensures `total_risk` before the change is `27,000`, calculated as `abs(balance_before) *
    /// price * risk_factor` (`abs(60) * 900 * 0.5`).
    assert_eq!(position_tvtr_change.before.total_risk, 27_000);

    /// Ensures `total_value` after the change is `54,000`, calculated as `balance_before * price`
    /// (`60 * 900`).
    assert_eq!(position_tvtr_change.after.total_value, 54_000);

    /// Ensures `total_risk` after the change is `27,000`, calculated as `abs(balance_before) *
    /// price * risk_factor` (`abs(60) * 900 * 0.5`).
    assert_eq!(position_tvtr_change.after.total_risk, 27_000);
}


/// Test the `calculate_position_tvtr_change` function for the case where the position is empty, and
/// no diff is provided.
#[test]
fn test_calculate_position_tvtr_empty_position_and_diff() {
    let mut state = INITIALIZED_CONTRACT_STATE();

    // Create an empty position.
    let position_data = PositionData { asset_entries: array![].span() };

    // Create an empty position diff.
    let position_diff = array![].span();

    let position_tvtr_change = state.calculate_position_tvtr_change(position_data, position_diff);

    /// Ensures `total_value` before the change is `0`.
    assert_eq!(position_tvtr_change.before.total_value, 0);

    /// Ensures `total_risk` before the change is `0`.
    assert_eq!(position_tvtr_change.before.total_risk, 0);

    /// Ensures `total_value` after the change is `0`.
    assert_eq!(position_tvtr_change.after.total_value, 0);

    /// Ensures `total_risk` after the change is `0`.
    assert_eq!(position_tvtr_change.after.total_risk, 0);
}


/// Test the `evaluate_position_change` function for the case where the position is empty, and no
/// diff is provided.
#[test]
fn test_evaluate_position_change_empty_position_and_empty_diff() {
    let mut state = INITIALIZED_CONTRACT_STATE();

    // Create an empty position.
    let position_data = PositionData { asset_entries: array![].span() };

    // Create an empty position diff.
    let position_diff = array![].span();

    let evaluated_position_change = state.evaluate_position_change(position_data, position_diff);

    /// Ensures `position_state_before_change` is `Healthy`.
    assert!(
        evaluated_position_change.change_effects.is_none(),
        "Expected position_state_before_change to be Healthy",
    );
}
