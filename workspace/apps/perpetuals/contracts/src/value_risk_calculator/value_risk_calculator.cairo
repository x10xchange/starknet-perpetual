#[starknet::contract]
pub mod ValueRiskCalculator {
    use perpetuals::core::types::{PositionData, PositionDiff};
    use perpetuals::value_risk_calculator::interface::IValueRiskCalculator;

    use perpetuals::value_risk_calculator::interface::{PositionTVTR, PositionTVTRChange};

    #[storage]
    struct Storage {}

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {}

    #[constructor]
    pub fn constructor(ref self: ContractState) {}

    #[abi(embed_v0)]
    impl ValueRiskCalculatorImpl of IValueRiskCalculator<ContractState> {
        fn calculate_position_tvtr(
            self: @ContractState, Position: PositionData, Position_diff: PositionDiff
        ) -> PositionTVTRChange {
            PositionTVTRChange {
                before: PositionTVTR { total_value: 0, total_risk: 0, },
                after: PositionTVTR { total_value: 0, total_risk: 0, },
            }
        }
    }
}
