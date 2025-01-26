use contracts_commons::math::{Abs, FractionTrait};
use perpetuals::core::types::price::PriceMulTrait;
use perpetuals::core::types::{PositionData, PositionDiff};


#[derive(Drop, Debug, PartialEq, Serde)]
pub enum PositionState {
    Healthy,
    Liquidatable,
    Deleveragable,
}

#[derive(Copy, Debug, Drop, Serde)]
pub struct PositionTVTR {
    pub total_value: i128,
    pub total_risk: u128,
}


#[derive(Copy, Debug, Drop, Serde)]
pub struct PositionTVTRChange {
    pub before: PositionTVTR,
    pub after: PositionTVTR,
}

#[generate_trait]
pub impl PositionStateImpl of PositionStateTrait {
    fn new(position_tvtr: PositionTVTR) -> PositionState {
        if position_tvtr.total_value < 0 {
            PositionState::Deleveragable
        } else if position_tvtr.total_value.abs() < position_tvtr.total_risk {
            PositionState::Liquidatable
        } else {
            PositionState::Healthy
        }
    }
}

/// A struct representing the assessment of a position after a change.
/// It contains answers to key questions about the position's state.
///
/// # Fields:
/// - `is_healthier`:
///     The position is healthier if the risk has decreased.
/// - `is_fair_deleverage`:
///     Indicates whether the deleveraging process is fair.
#[derive(Debug, Drop, Serde)]
pub struct ChangeEffects {
    pub is_healthier: bool,
    pub is_fair_deleverage: bool,
}

/// Representing the evaluation of position's state and the effects of a proposed change.
#[derive(Debug, Drop, Serde)]
pub struct PositionChangeResult {
    pub position_state_before_change: PositionState,
    pub position_state_after_change: PositionState,
    pub change_effects: Option<ChangeEffects>,
}


/// The position is fair if the total_value divided by the total_risk is the same
/// before and after the change.
fn is_fair_deleverage(before: PositionTVTR, after: PositionTVTR) -> bool {
    let before_ratio = FractionTrait::new(before.total_value, before.total_risk);
    let after_ratio = FractionTrait::new(after.total_value, after.total_risk);
    before_ratio == after_ratio
}

/// The position is healthier if the total_value divided by the total_risk
/// is higher after the change and the total_risk is lower.
/// Formal definition:
/// total_value_after / total_risk_after > total_value_before / total_risk_before
/// AND total_risk_after < total_risk_before.
fn is_healthier(before: PositionTVTR, after: PositionTVTR) -> bool {
    let before_ratio = FractionTrait::new(before.total_value, before.total_risk);
    let after_ratio = FractionTrait::new(after.total_value, after.total_risk);
    after_ratio >= before_ratio && after.total_risk < before.total_risk
}


pub fn evaluate_position_change(
    position: PositionData, position_diff: PositionDiff,
) -> PositionChangeResult {
    let tvtr = calculate_position_tvtr_change(position, position_diff);

    let change_effects = if tvtr.before.total_risk != 0 && tvtr.after.total_risk != 0 {
        Option::Some(
            ChangeEffects {
                is_healthier: is_healthier(tvtr.before, tvtr.after),
                is_fair_deleverage: is_fair_deleverage(tvtr.before, tvtr.after),
            },
        )
    } else {
        Option::None
    };
    PositionChangeResult {
        position_state_before_change: PositionStateTrait::new(tvtr.before),
        position_state_after_change: PositionStateTrait::new(tvtr.after),
        change_effects,
    }
}


fn calculate_position_tvtr_change(
    position: PositionData, position_diff: PositionDiff,
) -> PositionTVTRChange {
    // Calculate the total value and total risk before the diff.
    let mut total_value_before = 0_i128;
    let mut total_risk_before = 0_u128;
    let asset_entries = position.asset_entries;
    for asset_entry in asset_entries {
        let balance = *asset_entry.balance;
        let price = *asset_entry.price;
        let risk_factor = *asset_entry.risk_factor;
        let asset_value: i128 = price.mul(rhs: balance);

        // Update the total value and total risk.
        total_value_before += asset_value;
        total_risk_before += risk_factor.mul(asset_value.abs());
    };

    // Calculate the total value and total risk after the diff.
    let mut total_value_after = total_value_before;
    let mut total_risk_after: u128 = total_risk_before;
    for asset_diff_entry in position_diff {
        let risk_factor = *asset_diff_entry.risk_factor;
        let price = *asset_diff_entry.price;
        let balance_before = *asset_diff_entry.before;
        let balance_after = *asset_diff_entry.after;
        let asset_value_before = price.mul(rhs: balance_before);
        let asset_value_after = price.mul(rhs: balance_after);

        /// Update the total value.
        total_value_after += asset_value_after;
        total_value_after -= asset_value_before;

        /// Update the total risk.
        total_risk_after += risk_factor.mul(asset_value_after.abs());
        total_risk_after -= risk_factor.mul(asset_value_before.abs());
    };

    // Return the total value and total risk before and after the diff.
    PositionTVTRChange {
        before: PositionTVTR { total_value: total_value_before, total_risk: total_risk_before },
        after: PositionTVTR { total_value: total_value_after, total_risk: total_risk_after },
    }
}

/// --------------------------------- Test ---------------------------------
use contracts_commons::types::fixed_two_decimal::{FixedTwoDecimal, FixedTwoDecimalTrait};
use perpetuals::core::types::asset::{AssetId, AssetIdTrait};
use perpetuals::core::types::balance::BalanceTrait;
use perpetuals::core::types::price::{Price, PriceTrait, TWO_POW_28};
use perpetuals::core::types::{AssetDiffEntry, AssetEntry};


/// Prices
fn PRICE_1() -> Price {
    PriceTrait::new(900 * TWO_POW_28)
}
fn PRICE_2() -> Price {
    PriceTrait::new(900 * TWO_POW_28)
}
fn PRICE_3() -> Price {
    PriceTrait::new(900 * TWO_POW_28)
}
fn PRICE_4() -> Price {
    PriceTrait::new(900 * TWO_POW_28)
}
fn PRICE_5() -> Price {
    PriceTrait::new(900 * TWO_POW_28)
}

/// Risk factors
fn RISK_FACTOR_1() -> FixedTwoDecimal {
    FixedTwoDecimalTrait::new(50)
}
fn RISK_FACTOR_2() -> FixedTwoDecimal {
    FixedTwoDecimalTrait::new(50)
}
fn RISK_FACTOR_3() -> FixedTwoDecimal {
    FixedTwoDecimalTrait::new(50)
}
fn RISK_FACTOR_4() -> FixedTwoDecimal {
    FixedTwoDecimalTrait::new(50)
}
fn RISK_FACTOR_5() -> FixedTwoDecimal {
    FixedTwoDecimalTrait::new(50)
}

/// Assets IDs
fn SYNTHETIC_ASSET_ID_1() -> AssetId {
    AssetIdTrait::new(value: selector!("SYNTHETIC_ASSET_ID_1"))
}
fn SYNTHETIC_ASSET_ID_2() -> AssetId {
    AssetIdTrait::new(value: selector!("SYNTHETIC_ASSET_ID_2"))
}
fn SYNTHETIC_ASSET_ID_3() -> AssetId {
    AssetIdTrait::new(value: selector!("SYNTHETIC_ASSET_ID_3"))
}
fn SYNTHETIC_ASSET_ID_4() -> AssetId {
    AssetIdTrait::new(value: selector!("SYNTHETIC_ASSET_ID_4"))
}
fn SYNTHETIC_ASSET_ID_5() -> AssetId {
    AssetIdTrait::new(value: selector!("SYNTHETIC_ASSET_ID_5"))
}

#[test]
fn test_calculate_position_tvtr_change_basic_case() {
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

    let position_tvtr_change = calculate_position_tvtr_change(position_data, position_diff);

    /// Ensures `total_value` before the change is `54,000`, calculated as `balance_before *
    /// price`
    /// (`60 * 900`).
    assert_eq!(position_tvtr_change.before.total_value, 54_000);

    /// Ensures `total_risk` before the change is `27,000`, calculated as `abs(balance_before) *
    /// price * risk_factor` (`abs(60) * 900 * 0.5`).
    assert_eq!(position_tvtr_change.before.total_risk, 27_000);

    /// Ensures `total_value` after the change is `72,000`, calculated as `balance_after *
    /// price`
    /// (`80 * 900`).
    assert_eq!(position_tvtr_change.after.total_value, 72_000);

    /// Ensures `total_risk` after the change is `36,000`, calculated as `abs(balance_after) *
    /// price * risk_factor` (`abs(80) * 900 * 0.5`).
    assert_eq!(position_tvtr_change.after.total_risk, 36_000);
}

/// Test the `calculate_position_tvtr_change` function for the case where the balance is
/// negative.
///
/// This test verifies the correctness of total value and total risk calculations before and
/// after a position change in a scenario with one asset entry and one asset diff, where the
/// balance is negative.
#[test]
fn test_calculate_position_tvtr_change_negative_balance() {
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

    let position_tvtr_change = calculate_position_tvtr_change(position_data, position_diff);

    /// Ensures `total_value` before the change is `-54,000`, calculated as `balance_before *
    /// price`
    /// (`-60 * 900`).
    assert_eq!(position_tvtr_change.before.total_value, -54_000);

    /// Ensures `total_risk` before the change is `27,000`, calculated as `abs(balance_before) *
    /// price * risk_factor` (`abs(-60) * 900 * 0.5`).
    assert_eq!(position_tvtr_change.before.total_risk, 27_000);

    /// Ensures `total_value` after the change is `-18,000`, calculated as `balance_after *
    /// price`
    /// (`20 * 900`).
    assert_eq!(position_tvtr_change.after.total_value, 18_000);

    /// Ensures `total_risk` after the change is `9,000`, calculated as `abs(balance_after) *
    /// price * risk_factor` (`abs(20) * 900 * 0.5`).
    assert_eq!(position_tvtr_change.after.total_risk, 9_000);
}

/// Test the `calculate_position_tvtr_change` function for the case where there are multiple
/// asset
///
/// This test verifies the correctness of total value and total risk calculations before and
/// after a position change in a scenario with multiple asset entries and multiple asset diffs.
#[test]
fn test_calculate_position_tvtr_change_multiple_assets() {
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

    let position_tvtr_change = calculate_position_tvtr_change(position_data, position_diff);

    /// Ensures `total_value` before the change is `121,500`, calculated as `balance_1_before *
    /// price + balance_2_before * price + balance_3_before * price + balance_4_before * price +
    /// balance_5_before * price` (`60 * 900 + 40 * 900 + 20 * 900 + 10 * 900 + 5 * 900`).
    assert_eq!(position_tvtr_change.before.total_value, 121_500);

    /// Ensures `total_risk` before the change is `60,750`, calculated as `abs(balance_1_before)
    /// *
    /// price * risk_factor_1 + abs(balance_2_before) * price * risk_factor_2 +
    /// abs(balance_3_before) *
    /// price * risk_factor_3 + abs(balance_4_before) * price * risk_factor_4 +
    /// abs(balance_5_before) *
    /// price * risk_factor_5` (`abs(60) * 900 * 0.5 + abs(40) * 900 * 0.5 + abs(20) * 900 * 0.5
    /// +
    /// abs(10) * 900 * 0.5 + abs(5) * 900 * 0.5`).
    assert_eq!(position_tvtr_change.before.total_risk, 60_750);

    /// Ensures `total_value` after the change is `157,500`, calculated as `balance_1_after *
    /// price + balance_2_after * price` + balance_3_after * price + balance_4_after * price +
    /// balance_5_after * price` (`80 * 900 + 60 * 900 + 20 * 900 + 10 * 900 + 5 * 900`).
    /// The balance of the other assets remains the same, so balance_3_after = 20,
    /// balance_4_after = 10, balance_5_after = 5.
    assert_eq!(position_tvtr_change.after.total_value, 157_500);

    /// Ensures `total_risk` after the change is `78,750`, calculated as `abs(balance_1_after) *
    /// price * risk_factor_1 + abs(balance_2_after) * price * risk_factor_2 +
    /// abs(balance_3_after) * price * risk_factor_3 + abs(balance_4_after) * price *
    /// risk_factor_4 + abs(balance_5_after) * price * risk_factor_5` (`abs(80) * 900 * 0.5 +
    /// abs(60) * 900 * 0.5 + abs(20) * 900 * 0.5 + abs(10) * 900 * 0.5 + abs(5) * 900 * 0.5`).
    /// The balance of the other assets remains the same, so balance_3_after = 20,
    /// balance_4_after = 10, balance_5_after = 5.
    assert_eq!(position_tvtr_change.after.total_risk, 78_750);
}

/// Test the `calculate_position_tvtr_change` function for the case where the diff is empty.
#[test]
fn test_calculate_position_tvtr_empty_diff() {
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

    let position_tvtr_change = calculate_position_tvtr_change(position_data, position_diff);

    /// Ensures `total_value` before the change is `54,000`, calculated as `balance_before *
    /// price`
    /// (`60 * 900`).
    assert_eq!(position_tvtr_change.before.total_value, 54_000);

    /// Ensures `total_risk` before the change is `27,000`, calculated as `abs(balance_before) *
    /// price * risk_factor` (`abs(60) * 900 * 0.5`).
    assert_eq!(position_tvtr_change.before.total_risk, 27_000);

    /// Ensures `total_value` after the change is `54,000`, calculated as `balance_before *
    /// price`
    /// (`60 * 900`).
    assert_eq!(position_tvtr_change.after.total_value, 54_000);

    /// Ensures `total_risk` after the change is `27,000`, calculated as `abs(balance_before) *
    /// price * risk_factor` (`abs(60) * 900 * 0.5`).
    assert_eq!(position_tvtr_change.after.total_risk, 27_000);
}


/// Test the `calculate_position_tvtr_change` function for the case where the position is empty,
/// and no diff is provided.
#[test]
fn test_calculate_position_tvtr_empty_position_and_diff() {
    // Create an empty position.
    let position_data = PositionData { asset_entries: array![].span() };

    // Create an empty position diff.
    let position_diff = array![].span();

    let position_tvtr_change = calculate_position_tvtr_change(position_data, position_diff);

    /// Ensures `total_value` before the change is `0`.
    assert_eq!(position_tvtr_change.before.total_value, 0);

    /// Ensures `total_risk` before the change is `0`.
    assert_eq!(position_tvtr_change.before.total_risk, 0);

    /// Ensures `total_value` after the change is `0`.
    assert_eq!(position_tvtr_change.after.total_value, 0);

    /// Ensures `total_risk` after the change is `0`.
    assert_eq!(position_tvtr_change.after.total_risk, 0);
}


/// Test the `evaluate_position_change` function for the case where the position is empty, and
/// no diff is provided.
#[test]
fn test_evaluate_position_change_empty_position_and_empty_diff() {
    // Create an empty position.
    let position_data = PositionData { asset_entries: array![].span() };

    // Create an empty position diff.
    let position_diff = array![].span();

    let evaluated_position_change = evaluate_position_change(position_data, position_diff);

    /// Ensures `position_state_before_change` is `Healthy`.
    assert!(
        evaluated_position_change.change_effects.is_none(),
        "Expected position_state_before_change to be Healthy",
    );
}
