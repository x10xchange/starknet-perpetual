#[starknet::contract]
pub mod ValueRiskCalculator {
    use perpetuals::value_risk_calculator::interface::IValueRiskCalculator;

    #[storage]
    struct Storage {}

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {}

    #[constructor]
    pub fn constructor(ref self: ContractState) {}

    #[abi(embed_v0)]
    impl ValueRiskCalculatorImpl of IValueRiskCalculator<ContractState> {}
}
