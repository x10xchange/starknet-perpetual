use contracts_commons::test_utils::cheat_caller_address_once;
use perpetuals::direct_interaction::direct_interaction::DirectInteraction;
use snforge_std::test_address;

fn CONTRACT_STATE() -> DirectInteraction::ContractState {
    DirectInteraction::contract_state_for_testing()
}

#[test]
fn test_constructor() {
    let mut state = CONTRACT_STATE();
    cheat_caller_address_once(contract_address: test_address(), caller_address: test_address());
    DirectInteraction::constructor(ref state);
}
