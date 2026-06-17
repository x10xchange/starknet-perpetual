use perpetuals::tests::constants::{APP_GOVERNOR, GOVERNANCE_ADMIN};
use perpetuals::tests::test_utils::deploy_treasury;
use snforge_std::{ContractClassTrait, DeclareResultTrait, start_cheat_block_timestamp_global};
use starknet::ContractAddress;
use starkware_utils::components::replaceability::interface::{
    EICData, IReplaceableDispatcher, IReplaceableDispatcherTrait, ImplementationData,
};
use starkware_utils::components::roles::interface::{IRolesDispatcher, IRolesDispatcherTrait};
use starkware_utils::constants::{DAY, HOUR};
use starkware_utils_testing::test_utils::cheat_caller_address_once;
use treasury::interface::{ITreasuryDispatcher, ITreasuryDispatcherTrait};

// Non-zero so the upgraded implementation's activation time is non-zero.
const TS: u64 = 1_000_000_000;

fn dummy_address(value: felt252) -> ContractAddress {
    value.try_into().unwrap()
}

/// Deploys a treasury with the timelocks disabled, then upgrades it via the `TreasuryTimelockEIC`.
fn deploy_treasury_and_upgrade_with_eic() -> ITreasuryDispatcher {
    start_cheat_block_timestamp_global(TS);
    let treasury_address = deploy_treasury(
        governance_admin: GOVERNANCE_ADMIN(),
        upgrade_delay: 0,
        perps_contract: dummy_address('PERPS'),
    );

    let roles = IRolesDispatcher { contract_address: treasury_address };
    cheat_caller_address_once(
        contract_address: treasury_address, caller_address: GOVERNANCE_ADMIN(),
    );
    roles.register_upgrade_governor(GOVERNANCE_ADMIN());

    let impl_hash = *snforge_std::declare("ProtocolTreasury").unwrap().contract_class().class_hash;
    let eic_hash = *snforge_std::declare("TreasuryTimelockEIC")
        .unwrap()
        .contract_class()
        .class_hash;
    let eic_data = EICData { eic_hash, eic_init_data: array![].span() };
    let implementation_data = ImplementationData {
        impl_hash, eic_data: Option::Some(eic_data), final: false,
    };

    let replaceable = IReplaceableDispatcher { contract_address: treasury_address };
    cheat_caller_address_once(
        contract_address: treasury_address, caller_address: GOVERNANCE_ADMIN(),
    );
    replaceable.add_new_implementation(implementation_data);
    cheat_caller_address_once(
        contract_address: treasury_address, caller_address: GOVERNANCE_ADMIN(),
    );
    replaceable.replace_to(implementation_data);

    ITreasuryDispatcher { contract_address: treasury_address }
}

#[test]
fn test_treasury_timelock_eic_configures_params_on_upgrade() {
    start_cheat_block_timestamp_global(TS);
    let treasury_address = deploy_treasury(
        governance_admin: GOVERNANCE_ADMIN(),
        upgrade_delay: 0,
        perps_contract: dummy_address('PERPS'),
    );
    let treasury = ITreasuryDispatcher { contract_address: treasury_address };
    assert!(treasury.get_reset_cooldown().seconds == 0, "reset cooldown should start at 0");
    assert!(
        treasury.get_protection_limit_timelock().seconds == 0, "change timelock should start at 0",
    );

    let treasury = deploy_treasury_and_upgrade_with_eic();

    assert!(treasury.get_reset_cooldown().seconds == DAY, "EIC did not configure reset cooldown");
    assert!(
        treasury.get_protection_limit_timelock().seconds == 12 * HOUR,
        "EIC did not configure change timelock to 12 hours",
    );
}

#[test]
#[should_panic(expected: 'TIMELOCK_NOT_PASSED')]
fn test_treasury_timelock_eic_enables_change_timelock_enforcement() {
    let treasury = deploy_treasury_and_upgrade_with_eic();
    let collateral = dummy_address('COLLATERAL');

    cheat_caller_address_once(
        contract_address: treasury.contract_address, caller_address: APP_GOVERNOR(),
    );
    treasury.request_protection_limit_percent_change(collateral, 10);
    cheat_caller_address_once(
        contract_address: treasury.contract_address, caller_address: APP_GOVERNOR(),
    );
    treasury.apply_protection_limit_percent_change(collateral);
}
