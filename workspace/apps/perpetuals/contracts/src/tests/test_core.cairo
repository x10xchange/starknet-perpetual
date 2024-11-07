use contracts_commons::test_utils::cheat_caller_address_once;
use perpetuals::core::core::Core;
use perpetuals::tests::commons::constants::{TOKEN_ADDRESS, VALUE_RISK_CALCULATOR_CONTRACT_ADDRESS};
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
        token_address: TOKEN_ADDRESS(),
        value_risk_calculator: VALUE_RISK_CALCULATOR_CONTRACT_ADDRESS()
    );
    assert_eq!(state.erc20_dispatcher.read().contract_address, TOKEN_ADDRESS());
    assert_eq!(
        state.value_risk_calculator_dispatcher.read().contract_address,
        VALUE_RISK_CALCULATOR_CONTRACT_ADDRESS()
    );
}
