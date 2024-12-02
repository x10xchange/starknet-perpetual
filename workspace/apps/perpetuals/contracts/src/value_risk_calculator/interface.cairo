use perpetuals::core::types::{PositionData, PositionDiff};


#[derive(Drop, Serde)]
pub struct PositionTVTR {
    pub total_value: i128,
    pub total_risk: u128,
}

#[derive(Drop, Serde)]
pub struct PositionTVTRChange {
    pub before: PositionTVTR,
    pub after: PositionTVTR,
}

#[starknet::interface]
pub trait IValueRiskCalculator<TContractState> {
    fn calculate_position_tvtr_change(
        self: @TContractState, position: PositionData, position_diff: PositionDiff,
    ) -> PositionTVTRChange;
}
