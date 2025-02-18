use contracts_commons::errors::assert_with_byte_array;

use contracts_commons::math::abs::Abs;
use contracts_commons::math::fraction::FractionTrait;
use contracts_commons::types::fixed_two_decimal::FixedTwoDecimalTrait;
use perpetuals::core::errors::{
    POSITION_IS_NOT_DELEVERAGABLE, POSITION_IS_NOT_FAIR_DELEVERAGE, POSITION_IS_NOT_HEALTHIER,
    POSITION_IS_NOT_LIQUIDATABLE, position_not_healthy_nor_healthier,
};
use perpetuals::core::types::AssetDiff;
use perpetuals::core::types::price::PriceMulTrait;
use perpetuals::core::types::{PositionData, PositionDiff, PositionId};


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
    let after_minus_one_ratio = FractionTrait::new(after.total_value - 1, after.total_risk);
    after_minus_one_ratio < before_ratio && before_ratio <= after_ratio
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

pub fn validate_position_is_healthy_or_healthier(
    position_id: PositionId, position_data: PositionData, position_diff: Span<AssetDiff>,
) {
    let position_change_result = evaluate_position_change(position_data, position_diff);

    let position_is_healthier = if let Option::Some(change_effects) = position_change_result
        .change_effects {
        change_effects.is_healthier
    } else {
        false
    };
    let position_is_healthy = position_change_result
        .position_state_after_change == PositionState::Healthy;
    assert_with_byte_array(
        position_is_healthier || position_is_healthy,
        position_not_healthy_nor_healthier(position_id),
    );
}

pub fn validate_liquidated_position(
    position_id: PositionId, position_data: PositionData, position_diff: Span<AssetDiff>,
) {
    let position_change_result = evaluate_position_change(position_data, position_diff);

    assert(
        position_change_result.position_state_before_change == PositionState::Liquidatable,
        POSITION_IS_NOT_LIQUIDATABLE,
    );

    // None means the position is empty; transitioning from liquidatable to empty is
    // allowed.
    if let Option::Some(change_effects) = position_change_result.change_effects {
        assert(change_effects.is_healthier, POSITION_IS_NOT_HEALTHIER);
    }
}

pub fn validate_deleveraged_position(
    position_id: PositionId, position_data: PositionData, position_diff: Span<AssetDiff>,
) {
    let position_change_result = evaluate_position_change(position_data, position_diff);

    assert(
        position_change_result.position_state_before_change == PositionState::Deleveragable,
        POSITION_IS_NOT_DELEVERAGABLE,
    );

    // None means the position is empty; transitioning from deleveragable to empty is
    // allowed.
    if let Option::Some(change_effects) = position_change_result.change_effects {
        assert(change_effects.is_fair_deleverage, POSITION_IS_NOT_FAIR_DELEVERAGE);
        assert(change_effects.is_healthier, POSITION_IS_NOT_HEALTHIER);
    }
}


fn calculate_position_tvtr_change(
    position_data: PositionData, position_diff: PositionDiff,
) -> PositionTVTRChange {
    // Calculate the total value and total risk before the diff.
    let mut total_value_before = 0_i128;
    let mut total_risk_before = 0_u128;
    for asset in position_data {
        let balance = *asset.balance;
        let price = *asset.price;
        let risk_factor = *asset.risk_factor;
        let asset_value: i128 = price.mul(rhs: balance);

        // Update the total value and total risk.
        total_value_before += asset_value;
        total_risk_before += risk_factor.mul(asset_value.abs());
    };

    // Calculate the total value and total risk - after (i.e. counting diff as applied).
    let mut total_value_after = total_value_before;
    let mut total_risk_after: u128 = total_risk_before;
    for asset_diff in position_diff {
        let risk_factor_before = *asset_diff.risk_factor_before;
        let risk_factor_after = *asset_diff.risk_factor_after;
        let price = *asset_diff.price;
        let balance_before = *asset_diff.balance_before;
        let balance_after = *asset_diff.balance_after;
        let asset_value_before = price.mul(rhs: balance_before);
        let asset_value_after = price.mul(rhs: balance_after);

        /// Update the total value.
        total_value_after += asset_value_after;
        total_value_after -= asset_value_before;

        /// Update the total risk.
        total_risk_after += risk_factor_after.mul(asset_value_after.abs());
        total_risk_after -= risk_factor_before.mul(asset_value_before.abs());
    };

    // Return the total value and total risk before and after the diff.
    PositionTVTRChange {
        before: PositionTVTR { total_value: total_value_before, total_risk: total_risk_before },
        after: PositionTVTR { total_value: total_value_after, total_risk: total_risk_after },
    }
}

#[cfg(test)]
mod tests {
    use contracts_commons::types::fixed_two_decimal::FixedTwoDecimal;
    use perpetuals::core::types::asset::{AssetId, AssetIdTrait};
    use perpetuals::core::types::balance::BalanceTrait;
    use perpetuals::core::types::price::{Price, PriceTrait, TWO_POW_28};
    use perpetuals::core::types::{Asset, AssetDiff};
    use super::*;


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
        let asset = Asset {
            id: SYNTHETIC_ASSET_ID_1(),
            balance: BalanceTrait::new(value: 60),
            price: PRICE_1(),
            risk_factor: RISK_FACTOR_1(),
        };
        let position_data = array![asset].span();

        // Create a position diff with a single asset diff entry.
        let asset_diff = AssetDiff {
            id: asset.id,
            balance_before: asset.balance,
            balance_after: BalanceTrait::new(value: 80),
            price: asset.price,
            risk_factor_before: RISK_FACTOR_1(),
            risk_factor_after: RISK_FACTOR_1(),
        };
        let position_diff = array![asset_diff].span();

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
        let asset = Asset {
            id: SYNTHETIC_ASSET_ID_1(),
            balance: BalanceTrait::new(value: -60),
            price: PRICE_1(),
            risk_factor: RISK_FACTOR_1(),
        };
        let position_data = array![asset].span();

        // Create a position diff with a single asset diff entry.
        let asset_diff = AssetDiff {
            id: asset.id,
            balance_before: asset.balance,
            balance_after: BalanceTrait::new(value: 20),
            price: asset.price,
            risk_factor_before: RISK_FACTOR_1(),
            risk_factor_after: RISK_FACTOR_1(),
        };
        let position_diff = array![asset_diff].span();

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
    /// after a position change in a scenario with multiple assets and multiple assets diff.
    #[test]
    fn test_calculate_position_tvtr_change_multiple_assets() {
        // Create a position with multiple assets.
        let asset_1 = Asset {
            id: SYNTHETIC_ASSET_ID_1(),
            balance: BalanceTrait::new(value: 60),
            price: PRICE_1(),
            risk_factor: RISK_FACTOR_1(),
        };
        let asset_2 = Asset {
            id: SYNTHETIC_ASSET_ID_2(),
            balance: BalanceTrait::new(value: 40),
            price: PRICE_2(),
            risk_factor: RISK_FACTOR_2(),
        };
        let asset_3 = Asset {
            id: SYNTHETIC_ASSET_ID_3(),
            balance: BalanceTrait::new(value: 20),
            price: PRICE_3(),
            risk_factor: RISK_FACTOR_3(),
        };
        let asset_4 = Asset {
            id: SYNTHETIC_ASSET_ID_4(),
            balance: BalanceTrait::new(value: 10),
            price: PRICE_4(),
            risk_factor: RISK_FACTOR_4(),
        };
        let asset_5 = Asset {
            id: SYNTHETIC_ASSET_ID_5(),
            balance: BalanceTrait::new(value: 5),
            price: PRICE_5(),
            risk_factor: RISK_FACTOR_5(),
        };
        let position_data = array![asset_1, asset_2, asset_3, asset_4, asset_5].span();

        // Create a position diff with two assets diff.
        let asset_diff_1 = AssetDiff {
            id: asset_1.id,
            balance_before: asset_1.balance,
            balance_after: BalanceTrait::new(value: 80),
            price: asset_1.price,
            risk_factor_before: RISK_FACTOR_1(),
            risk_factor_after: RISK_FACTOR_1(),
        };
        let asset_diff_2 = AssetDiff {
            id: asset_2.id,
            balance_before: asset_2.balance,
            balance_after: BalanceTrait::new(value: 60),
            price: asset_2.price,
            risk_factor_before: RISK_FACTOR_2(),
            risk_factor_after: RISK_FACTOR_2(),
        };
        let position_diff = array![asset_diff_1, asset_diff_2].span();

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
        let asset = Asset {
            id: SYNTHETIC_ASSET_ID_1(),
            balance: BalanceTrait::new(value: 60),
            price: PRICE_1(),
            risk_factor: RISK_FACTOR_1(),
        };
        let position_data = array![asset].span();

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
        let position_data = array![].span();

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
        let position_data = array![].span();

        // Create an empty position diff.
        let position_diff = array![].span();

        let evaluated_position_change = evaluate_position_change(position_data, position_diff);

        /// Ensures `position_state_before_change` is `Healthy`.
        assert!(
            evaluated_position_change.change_effects.is_none(),
            "Expected position_state_before_change to be Healthy",
        );
    }
}
