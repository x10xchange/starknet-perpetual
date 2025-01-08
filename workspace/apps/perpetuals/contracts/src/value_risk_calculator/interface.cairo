use contracts_commons::math::Abs;
use contracts_commons::types::fixed_two_decimal::FixedTwoDecimal;
use perpetuals::core::types::asset::AssetId;
use perpetuals::core::types::{PositionData, PositionDiff};


#[derive(Copy, Drop, Serde)]
pub struct PositionTVTR {
    pub total_value: i128,
    pub total_risk: u128,
}

#[derive(Copy, Drop, Serde)]
pub struct PositionTVTRChange {
    pub before: PositionTVTR,
    pub after: PositionTVTR,
}

#[derive(Drop, Serde, PartialEq)]
pub enum PositionState {
    Healthy,
    Liquidatable,
    Deleveragable,
}


#[generate_trait]
pub impl PositionStateImpl of PositionStateTrait {
    fn new(position_tvtr: PositionTVTR) -> PositionState {
        if position_tvtr.total_value < 0 {
            return PositionState::Deleveragable;
        }
        if position_tvtr.total_risk > position_tvtr.total_value.abs() {
            return PositionState::Liquidatable;
        }
        PositionState::Healthy
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
#[derive(Drop, Serde)]
pub struct ChangeEffects {
    pub is_healthier: bool,
    pub is_fair_deleverage: bool,
}

/// Representing the evaluation of position's state and the effects of a proposed change.
#[derive(Drop, Serde)]
pub struct PositionChangeResult {
    pub position_state_before_change: PositionState,
    pub position_state_after_change: PositionState,
    pub change_effects: Option<ChangeEffects>,
}


#[starknet::interface]
pub trait IValueRiskCalculator<TContractState> {
    /// Evaluates the state of a position before and after applying a change, and assesses the
    /// impact of the change.
    ///
    /// # Parameters:
    /// - `self`: The contract state.
    /// - `position`: The current state of the position, represented by `PositionData`.
    /// - `position_diff`: The proposed changes to the position, represented by `PositionDiff`.
    ///
    /// # Returns:
    /// - `PositionChangeResult`: A struct containing:
    ///     - `position_state_before_change`: The state of the position before applying the change.
    ///     - `position_state_after_change`: The state of the position after applying the change.
    ///     - `change_assessment`: An evaluation of the impact of the change, including health
    ///     improvement, fairness, and health preservation.
    fn evaluate_position_change(
        self: @TContractState, position: PositionData, position_diff: PositionDiff,
    ) -> PositionChangeResult;

    fn set_risk_factor_for_asset(
        ref self: TContractState, asset_id: AssetId, risk_factor: FixedTwoDecimal,
    );
}
