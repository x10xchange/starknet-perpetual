use core::num::traits::{One, Zero};
use core::panics::panic_with_byte_array;
use perpetuals::core::errors::{
    position_not_deleveragable, position_not_fair_deleverage, position_not_healthy_nor_healthier,
    position_not_liquidatable,
};
use perpetuals::core::types::position::PositionId;
use perpetuals::core::types::price::{Price, PriceMulTrait};
use perpetuals::core::types::{PositionData, PositionDiffEnriched, UnchangedAssets};
use starkware_utils::errors::assert_with_byte_array;
use starkware_utils::math::abs::Abs;
use starkware_utils::math::fraction::FractionTraitI128U128 as FractionTrait;
use starkware_utils::types::fixed_two_decimal::FixedTwoDecimalTrait;

// This is the result of Price::One().mul(balance: 1)
// which is actually 1e-6 USDC * 2^28 / 2^28 = 1
const EPSILON: i128 = 1_i128;


/// Represents the state of a position based on its total value and total risk.
/// - A position is **Deleveragable** (and also **Liquidatable**) if its total value is negative.
/// - A position is **Liquidatable** if its total value is less than its total risk.
/// - Otherwise, the position is considered **Healthy**.
#[derive(Copy, Drop, Debug, PartialEq, Serde)]
pub enum PositionState {
    Healthy,
    Liquidatable,
    Deleveragable,
}

/// The total value and total risk of a position.
#[derive(Copy, Debug, Drop, Serde)]
pub struct PositionTVTR {
    pub total_value: i128,
    pub total_risk: u128,
}

/// The change in terms of total value and total risk of a position.
#[derive(Copy, Debug, Drop, Serde)]
pub struct PositionTVTRChange {
    pub before: PositionTVTR,
    pub after: PositionTVTR,
}


/// Returns the state of a position based on its total value and total risk.
fn get_position_state(position_tvtr: PositionTVTR) -> PositionState {
    if position_tvtr.total_value < 0 {
        PositionState::Deleveragable
    } else if position_tvtr.total_value.abs() < position_tvtr.total_risk {
        PositionState::Liquidatable
    } else {
        PositionState::Healthy
    }
}

/// The position is fair if the total_value divided by the total_risk is the almost before and after
/// the change - the before_ratio needs to be between after_ratio-epsilon and after ratio.
fn is_fair_deleverage(before: PositionTVTR, after: PositionTVTR) -> bool {
    let before_ratio = FractionTrait::new(
        numerator: before.total_value, denominator: before.total_risk,
    );
    let after_ratio = FractionTrait::new(
        numerator: after.total_value, denominator: after.total_risk,
    );
    let after_minus_epsilon_ratio = FractionTrait::new(
        numerator: after.total_value - EPSILON, denominator: after.total_risk,
    );
    after_minus_epsilon_ratio < before_ratio && before_ratio <= after_ratio
}

/// This is checked only when the before is not healthy:
/// The position is healthier if the total_value divided by the total_risk
/// is equal or higher after the change and the total_risk is lower.
/// Formal definition:
/// total_value_after / total_risk_after >= total_value_before / total_risk_before
/// AND total_risk_after < total_risk_before.
fn is_healthier(before: PositionTVTR, after: PositionTVTR) -> bool {
    if after.total_risk >= before.total_risk {
        return false;
    }
    let before_ratio = FractionTrait::new(before.total_value, before.total_risk);
    let after_ratio = FractionTrait::new(after.total_value, after.total_risk);
    after_ratio >= before_ratio
}

/// Returns the state of a position.
pub fn evaluate_position(position_data: PositionData) -> PositionState {
    let tvtr = calculate_position_tvtr_change(
        unchanged_assets: position_data, position_diff_enriched: Default::default(),
    );
    get_position_state(position_tvtr: tvtr.before)
}


pub fn validate_position_is_healthy_or_healthier(
    position_id: PositionId,
    unchanged_assets: UnchangedAssets,
    position_diff_enriched: PositionDiffEnriched,
) {
    let tvtr = calculate_position_tvtr_change(:unchanged_assets, :position_diff_enriched);
    assert_healthy_or_healthier(:position_id, :tvtr);
}

pub fn assert_healthy_or_healthier(position_id: PositionId, tvtr: PositionTVTRChange) {
    let position_state_after_change = get_position_state(position_tvtr: tvtr.after);
    if position_state_after_change == PositionState::Healthy {
        // If the position is healthy we can return.
        return;
    }

    if tvtr.before.total_risk.is_zero() || tvtr.after.total_risk.is_zero() {
        panic_with_byte_array(@position_not_healthy_nor_healthier(:position_id));
    }

    assert_with_byte_array(
        is_healthier(before: tvtr.before, after: tvtr.after),
        position_not_healthy_nor_healthier(:position_id),
    );
}

pub fn liquidated_position_validations(
    position_id: PositionId,
    unchanged_assets: UnchangedAssets,
    position_diff_enriched: PositionDiffEnriched,
) {
    let tvtr = calculate_position_tvtr_change(:unchanged_assets, :position_diff_enriched);
    let position_state_before_change = get_position_state(position_tvtr: tvtr.before);

    // Validate that the position isn't healthy before the change.
    assert_with_byte_array(
        position_state_before_change == PositionState::Liquidatable
            || position_state_before_change == PositionState::Deleveragable,
        position_not_liquidatable(:position_id),
    );
    assert_healthy_or_healthier(:position_id, :tvtr);
}

pub fn deleveraged_position_validations(
    position_id: PositionId,
    unchanged_assets: UnchangedAssets,
    position_diff_enriched: PositionDiffEnriched,
    is_active_asset: bool,
) {
    let tvtr = calculate_position_tvtr_change(:unchanged_assets, :position_diff_enriched);
    let position_state_before_change = get_position_state(position_tvtr: tvtr.before);

    if is_active_asset {
        assert_with_byte_array(
            position_state_before_change == PositionState::Deleveragable,
            position_not_deleveragable(:position_id),
        );
    }

    assert_healthy_or_healthier(:position_id, :tvtr);
    assert_with_byte_array(
        is_fair_deleverage(before: tvtr.before, after: tvtr.after),
        position_not_fair_deleverage(:position_id),
    );
}

pub fn calculate_position_tvtr(position_data: UnchangedAssets) -> PositionTVTR {
    let position_diff_enriched = Default::default();
    calculate_position_tvtr_change(unchanged_assets: position_data, :position_diff_enriched).before
}

/// Calculates the total value and total risk change for a position, taking into account both
/// unchanged assets and position changes (collateral and synthetic assets).
///
/// # Arguments
///
/// * `unchanged_assets` - Assets in the position that have not changed
/// * `position_diff_enriched` - Changes in collateral and synthetic assets for the position
///
/// # Returns
///
/// * `PositionTVTRChange` - Contains the total value and total risk before and after the changes
///
/// # Logic Flow
/// 1. Calculates value and risk for unchanged assets
/// 2. Calculates value and risk changes for collateral assets
/// 3. Calculates value and risk changes for synthetic assets
/// 4. Combines all calculations into final before/after totals
fn calculate_position_tvtr_change(
    unchanged_assets: UnchangedAssets, position_diff_enriched: PositionDiffEnriched,
) -> PositionTVTRChange {
    // Calculate the value and risk of the position data.
    let mut unchanged_assets_value = 0_i128;
    let mut unchanged_assets_risk = 0_u128;
    for asset in unchanged_assets {
        let asset_value: i128 = (*asset.price).mul(rhs: *asset.balance);
        unchanged_assets_value += asset_value;
        unchanged_assets_risk += (*asset.risk_factor).mul(asset_value.abs());
    }

    let mut total_value_before = unchanged_assets_value;
    let mut total_risk_before = unchanged_assets_risk;
    let mut total_value_after = unchanged_assets_value;
    let mut total_risk_after = unchanged_assets_risk;

    if let Option::Some(asset_diff) = position_diff_enriched.synthetic {
        let asset_value_before = asset_diff.price.mul(rhs: asset_diff.asset.balance.before);
        let asset_value_after = asset_diff.price.mul(rhs: asset_diff.asset.balance.after);

        total_value_before += asset_value_before;
        total_value_after += asset_value_after;

        total_risk_before += asset_diff.risk_factor_before.mul(asset_value_before.abs());
        total_risk_after += asset_diff.risk_factor_after.mul(asset_value_after.abs());
    }

    // Collateral price is always 1. We use the Price impl of One to consider PRICE_SCALE in the
    // mul operations.
    let price: Price = One::one();
    let asset_value_before = price.mul(rhs: position_diff_enriched.collateral.before);
    let asset_value_after = price.mul(rhs: position_diff_enriched.collateral.after);

    total_value_before += asset_value_before;
    total_value_after += asset_value_after;

    PositionTVTRChange {
        before: PositionTVTR { total_value: total_value_before, total_risk: total_risk_before },
        after: PositionTVTR { total_value: total_value_after, total_risk: total_risk_after },
    }
}


#[cfg(test)]
mod tests {
    use perpetuals::core::types::asset::{AssetId, AssetIdTrait};
    use perpetuals::core::types::balance::BalanceTrait;
    use perpetuals::core::types::price::{PRICE_SCALE, Price, PriceTrait};
    use perpetuals::core::types::{Asset, AssetDiff, AssetDiffEnriched, BalanceDiff};
    use starkware_utils::types::fixed_two_decimal::FixedTwoDecimal;
    use super::*;


    /// Prices
    fn PRICE_1() -> Price {
        PriceTrait::new(900_u64 * PRICE_SCALE.into())
    }
    fn PRICE_2() -> Price {
        PriceTrait::new(900_u64 * PRICE_SCALE.into())
    }
    fn PRICE_3() -> Price {
        PriceTrait::new(900_u64 * PRICE_SCALE.into())
    }
    fn PRICE_4() -> Price {
        PriceTrait::new(900_u64 * PRICE_SCALE.into())
    }
    fn PRICE_5() -> Price {
        PriceTrait::new(900_u64 * PRICE_SCALE.into())
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
        let position_data = array![].span();
        let asset_diff = AssetDiffEnriched {
            asset: AssetDiff {
                id: asset.id,
                balance: BalanceDiff { before: asset.balance, after: BalanceTrait::new(value: 80) },
            },
            price: asset.price,
            risk_factor_before: RISK_FACTOR_1(),
            risk_factor_after: RISK_FACTOR_1(),
        };
        let position_diff_enriched = PositionDiffEnriched {
            collateral: Default::default(), synthetic: Option::Some(asset_diff),
        };

        let position_tvtr_change = calculate_position_tvtr_change(
            position_data, :position_diff_enriched,
        );

        /// Ensures `total_value` before the change is `54,000`, calculated as `balance_before *
        /// price`
        /// (`60 * 900`).
        assert!(position_tvtr_change.before.total_value == 54_000);

        /// Ensures `total_risk` before the change is `27,000`, calculated as `abs(balance_before) *
        /// price * risk_factor` (`abs(60) * 900 * 0.5`).
        assert!(position_tvtr_change.before.total_risk == 27_000);

        /// Ensures `total_value` after the change is `72,000`, calculated as `balance_after *
        /// price`
        /// (`80 * 900`).
        assert!(position_tvtr_change.after.total_value == 72_000);

        /// Ensures `total_risk` after the change is `36,000`, calculated as `abs(balance_after) *
        /// price * risk_factor` (`abs(80) * 900 * 0.5`).
        assert!(position_tvtr_change.after.total_risk == 36_000);
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
        let position_data = array![].span();
        let asset_diff = AssetDiffEnriched {
            asset: AssetDiff {
                id: asset.id,
                balance: BalanceDiff { before: asset.balance, after: BalanceTrait::new(value: 20) },
            },
            price: asset.price,
            risk_factor_before: RISK_FACTOR_1(),
            risk_factor_after: RISK_FACTOR_1(),
        };
        let position_diff_enriched = PositionDiffEnriched {
            collateral: Default::default(), synthetic: Option::Some(asset_diff),
        };

        let position_tvtr_change = calculate_position_tvtr_change(
            position_data, :position_diff_enriched,
        );

        /// Ensures `total_value` before the change is `-54,000`, calculated as `balance_before *
        /// price`
        /// (`-60 * 900`).
        assert!(position_tvtr_change.before.total_value == -54_000);

        /// Ensures `total_risk` before the change is `27,000`, calculated as `abs(balance_before) *
        /// price * risk_factor` (`abs(-60) * 900 * 0.5`).
        assert!(position_tvtr_change.before.total_risk == 27_000);

        /// Ensures `total_value` after the change is `-18,000`, calculated as `balance_after *
        /// price`
        /// (`20 * 900`).
        assert!(position_tvtr_change.after.total_value == 18_000);

        /// Ensures `total_risk` after the change is `9,000`, calculated as `abs(balance_after) *
        /// price * risk_factor` (`abs(20) * 900 * 0.5`).
        assert!(position_tvtr_change.after.total_risk == 9_000);
    }

    /// Test the `calculate_position_tvtr_change` function for the case where there are multiple
    /// assets
    ///
    /// This test verifies the correctness of total value and total risk calculations before and
    /// after a position change in a scenario with multiple assets and a single asset diff.
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
        let position_data = array![asset_2, asset_3, asset_4, asset_5].span();

        // Create a position diff with two assets diff.
        let asset_diff_1 = AssetDiffEnriched {
            asset: AssetDiff {
                id: asset_1.id,
                balance: BalanceDiff {
                    before: asset_1.balance, after: BalanceTrait::new(value: 80),
                },
            },
            price: asset_1.price,
            risk_factor_before: RISK_FACTOR_1(),
            risk_factor_after: RISK_FACTOR_1(),
        };

        let position_diff_enriched = PositionDiffEnriched {
            collateral: Default::default(), synthetic: Option::Some(asset_diff_1),
        };

        let position_tvtr_change = calculate_position_tvtr_change(
            position_data, :position_diff_enriched,
        );

        /// Ensures `total_value` before the change is `121,500`, calculated as `balance_1_before *
        /// price + balance_2_before * price + balance_3_before * price + balance_4_before * price +
        /// balance_5_before * price` (`60 * 900 + 40 * 900 + 20 * 900 + 10 * 900 + 5 * 900`).
        assert!(position_tvtr_change.before.total_value == 121_500);

        /// Ensures `total_risk` before the change is `60,750`, calculated as `abs(balance_1_before)
        /// *
        /// price * risk_factor_1 + abs(balance_2_before) * price * risk_factor_2 +
        /// abs(balance_3_before) *
        /// price * risk_factor_3 + abs(balance_4_before) * price * risk_factor_4 +
        /// abs(balance_5_before) *
        /// price * risk_factor_5` (`abs(60) * 900 * 0.5 + abs(40) * 900 * 0.5 + abs(20) * 900 * 0.5
        /// +
        /// abs(10) * 900 * 0.5 + abs(5) * 900 * 0.5`).
        assert!(position_tvtr_change.before.total_risk == 60_750);

        /// Ensures `total_value` after the change is `139,500`, calculated as `balance_1_after *
        /// price + balance_2_after * price` + balance_3_after * price + balance_4_after * price +
        /// balance_5_after * price` (`80 * 900 + 40 * 900 + 20 * 900 + 10 * 900 + 5 * 900`).
        /// The balance of the other assets remains the same, so balance_2_after = 40,
        /// balance_3_after = 20, balance_4_after = 10, balance_5_after = 5.
        assert!(position_tvtr_change.after.total_value == 139_500);

        /// Ensures `total_risk` after the change is `69,750`, calculated as `abs(balance_1_after) *
        /// price * risk_factor_1 + abs(balance_2_after) * price * risk_factor_2 +
        /// abs(balance_3_after) * price * risk_factor_3 + abs(balance_4_after) * price *
        /// risk_factor_4 + abs(balance_5_after) * price * risk_factor_5` (`abs(80) * 900 * 0.5 +
        /// abs(40) * 900 * 0.5 + abs(20) * 900 * 0.5 + abs(10) * 900 * 0.5 + abs(5) * 900 * 0.5`).
        /// The balance of the other assets remains the same, so balance_2_after = 40,
        /// balance_3_after = 20, balance_4_after = 10, balance_5_after = 5.
        assert!(position_tvtr_change.after.total_risk == 69_750);
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
        let position_diff_enriched = Default::default();

        let position_tvtr_change = calculate_position_tvtr_change(
            position_data, :position_diff_enriched,
        );

        /// Ensures `total_value` before the change is `54,000`, calculated as `balance_before *
        /// price`
        /// (`60 * 900`).
        assert!(position_tvtr_change.before.total_value == 54_000);

        /// Ensures `total_risk` before the change is `27,000`, calculated as `abs(balance_before) *
        /// price * risk_factor` (`abs(60) * 900 * 0.5`).
        assert!(position_tvtr_change.before.total_risk == 27_000);

        /// Ensures `total_value` after the change is `54,000`, calculated as `balance_before *
        /// price`
        /// (`60 * 900`).
        assert!(position_tvtr_change.after.total_value == 54_000);

        /// Ensures `total_risk` after the change is `27,000`, calculated as `abs(balance_before) *
        /// price * risk_factor` (`abs(60) * 900 * 0.5`).
        assert!(position_tvtr_change.after.total_risk == 27_000);
    }


    /// Test the `calculate_position_tvtr_change` function for the case where the position is empty,
    /// and no diff is provided.
    #[test]
    fn test_calculate_position_tvtr_empty_position_and_diff() {
        // Create an empty position.
        let position_data = array![].span();

        // Create an empty position diff.
        let position_diff_enriched = Default::default();

        let position_tvtr_change = calculate_position_tvtr_change(
            position_data, :position_diff_enriched,
        );

        /// Ensures `total_value` before the change is `0`.
        assert!(position_tvtr_change.before.total_value == 0);

        /// Ensures `total_risk` before the change is `0`.
        assert!(position_tvtr_change.before.total_risk == 0);

        /// Ensures `total_value` after the change is `0`.
        assert!(position_tvtr_change.after.total_value == 0);

        /// Ensures `total_risk` after the change is `0`.
        assert!(position_tvtr_change.after.total_risk == 0);
    }


    /// Test the `evaluate_position` function for the case where the position is empty.
    #[test]
    fn test_evaluate_position_empty_position_and_empty_diff() {
        // Create an empty position.
        let position_data = array![].span();

        let evaluated_position = evaluate_position(position_data);
        assert!(evaluated_position == PositionState::Healthy);
    }
}
