use contracts_commons::test_utils::cheat_caller_address_once;
use perpetuals::value_risk_calculator::value_risk_calculator::ValueRiskCalculator;
use snforge_std::test_address;

fn CONTRACT_STATE() -> ValueRiskCalculator::ContractState {
    ValueRiskCalculator::contract_state_for_testing()
}

#[test]
fn test_constructor() {
    let mut state = CONTRACT_STATE();
    cheat_caller_address_once(contract_address: test_address(), caller_address: test_address());
    ValueRiskCalculator::constructor(ref state);
}
