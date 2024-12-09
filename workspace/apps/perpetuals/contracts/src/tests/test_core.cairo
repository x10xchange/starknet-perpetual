use contracts_commons::test_utils::cheat_caller_address_once;
use perpetuals::core::core::Core;
use perpetuals::tests::commons::constants::*;
use snforge_std::test_address;

fn CONTRACT_STATE() -> Core::ContractState {
    Core::contract_state_for_testing()
}

#[test]
fn test_constructor() {
    let mut state = CONTRACT_STATE();
    cheat_caller_address_once(contract_address: test_address(), caller_address: test_address());
    Core::constructor(
        ref state,
        value_risk_calculator: VALUE_RISK_CALCULATOR_CONTRACT_ADDRESS(),
        price_validation_interval: PRICE_VALIDATION_INTERVAL(),
        funding_validation_interval: FUNDING_VALIDATION_INTERVAL(),
        max_funding_rate: MAX_FUNDING_RATE,
    );
    assert_eq!(
        state.value_risk_calculator_dispatcher.read().contract_address,
        VALUE_RISK_CALCULATOR_CONTRACT_ADDRESS(),
    );
    assert_eq!(state.price_validation_interval.read(), PRICE_VALIDATION_INTERVAL());
    assert_eq!(state.funding_validation_interval.read(), FUNDING_VALIDATION_INTERVAL());
    assert_eq!(state.max_funding_rate.read(), MAX_FUNDING_RATE);
}
