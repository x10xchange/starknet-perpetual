use contracts_commons::types::fixed_two_decimal::FixedTwoDecimal;
use perpetuals::core::types::asset::AssetId;
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

    fn set_risk_factor_for_asset(
        ref self: TContractState, asset_id: AssetId, risk_factor: FixedTwoDecimal,
    );
}
