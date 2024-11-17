use contracts_commons::test_utils::cheat_caller_address_once;
use perpetuals::core::core::Core::InternalCoreFunctionsTrait;
use perpetuals::core::core::Core;
use perpetuals::tests::commons::constants::ASSET_ID;
use perpetuals::tests::commons::constants::VALUE_RISK_CALCULATOR_CONTRACT_ADDRESS;
use snforge_std::test_address;

fn CONTRACT_STATE() -> Core::ContractState {
    Core::contract_state_for_testing()
}

#[test]
fn test_constructor() {
    let mut state = CONTRACT_STATE();
    cheat_caller_address_once(contract_address: test_address(), caller_address: test_address());
    Core::constructor(ref state, value_risk_calculator: VALUE_RISK_CALCULATOR_CONTRACT_ADDRESS());
    assert_eq!(
        state.value_risk_calculator_dispatcher.read().contract_address,
        VALUE_RISK_CALCULATOR_CONTRACT_ADDRESS()
    );
}

#[test]
fn test_validate_assets() { // TODO: implement
}

#[test]
#[should_panic(expected: "Asset does not exist")]
fn test_validate_assets_doesnt_exist() {
    let mut state = CONTRACT_STATE();
    state._validate_assets(array![ASSET_ID()]);
}
