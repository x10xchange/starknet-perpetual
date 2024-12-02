#[starknet::contract]
pub mod ValueRiskCalculator {
    use contracts_commons::math::Abs;
    use contracts_commons::types::fixed_two_decimal::FixedTwoDecimalTrait;
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
        fn calculate_position_tvtr_change(
            self: @ContractState, position: PositionData, position_diff: PositionDiff
        ) -> PositionTVTRChange {
            // Calculate the total value and total risk before the diff.
            let mut total_value_before = 0_i128;
            let mut total_risk_before = 0_u128;
            let asset_entries = position.asset_entries;
            for asset_entry in asset_entries {
                let balance = *asset_entry.value.value;
                let price = *asset_entry.price;
                let risk_factor = *asset_entry.risk_factor;

                let asset_value = balance * price.into();

                // Update the total value and total risk.
                total_value_before += asset_value;
                total_risk_before += risk_factor.mul(asset_value.abs());
            };

            // Calculate the total value and total risk after the diff.
            let mut total_value_after = total_value_before;
            let mut total_risk_after: i128 = total_risk_before.try_into().unwrap();
            for asset_diff_entry in position_diff {
                let risk_factor = *asset_diff_entry.risk_factor;
                let price = *asset_diff_entry.price;
                let balance_before = *asset_diff_entry.before.value;
                let balance_after = *asset_diff_entry.after.value;
                let asset_value_before = balance_before * price.into();
                let asset_value_after = balance_after * price.into();

                /// Update the total value.
                total_value_after += asset_value_after;
                total_value_after -= asset_value_before;

                /// Update the total risk.
                total_risk_after += risk_factor.mul(asset_value_after.abs()).try_into().unwrap();
                total_risk_after -= risk_factor.mul(asset_value_before.abs()).try_into().unwrap();
            };

            // Return the total value and total risk before and after the diff.
            PositionTVTRChange {
                before: PositionTVTR {
                    total_value: total_value_before, total_risk: total_risk_before,
                },
                after: PositionTVTR {
                    total_value: total_value_after,
                    total_risk: total_risk_after.try_into().unwrap(),
                },
            }
        }
    }
}
