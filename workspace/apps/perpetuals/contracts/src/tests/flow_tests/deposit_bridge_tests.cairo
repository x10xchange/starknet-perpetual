use openzeppelin::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
use perpetuals::core::components::deposit::deposit_manager::deposit_hash;
use perpetuals::core::components::deposit::interface::{
    DepositStatus, IDepositDispatcher, IDepositDispatcherTrait, IDepositSafeDispatcher,
    IDepositSafeDispatcherTrait,
};
use perpetuals::core::components::external_components::interface::{
    EXTERNAL_COMPONENT_DEPOSITS, IExternalComponentsDispatcher, IExternalComponentsDispatcherTrait,
};
use perpetuals::core::components::operator_nonce::interface::{
    IOperatorNonceDispatcher, IOperatorNonceDispatcherTrait,
};
use perpetuals::core::components::positions::interface::IPositionsDispatcherTrait;
use perpetuals::tests::flow_tests::infra::*;
use perpetuals::tests::flow_tests::perps_tests_facade::*;
use snforge_std::{ContractClassTrait, DeclareResultTrait, EventSpyAssertionsTrait};
use starknet::ContractAddress;
use starkware_utils::components::pausable::interface::{
    IPausableDispatcher, IPausableDispatcherTrait,
};
use starkware_utils::components::roles::interface::{IRolesDispatcher, IRolesDispatcherTrait};
use starkware_utils_testing::test_utils::{TokenTrait, cheat_caller_address_once};

#[starknet::contract]
mod RhinoBridgeMock {
    use openzeppelin::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use perpetuals::core::components::deposit::interface::IRhinoBridge;
    use starknet::{ContractAddress, get_caller_address, get_contract_address};
    #[storage]
    struct Storage {}
    #[abi(embed_v0)]
    impl Bridge of IRhinoBridge<ContractState> {
        fn deposit_with_id(
            ref self: ContractState, token: ContractAddress, amount: u256, commitment_id: felt252,
        ) {
            // Exercise both a reverting bridge and one that returns without taking the funds.
            assert(commitment_id != 999, 'RHINO_FAILURE');
            if commitment_id != 998 {
                assert(
                    IERC20Dispatcher { contract_address: token }
                        .transfer_from(get_caller_address(), get_contract_address(), amount),
                    'TRANSFER_FAILED',
                );
            }
        }
    }
}

fn setup_bridge() -> ContractAddress {
    let bridge: ContractAddress = perpetuals::core::constants::RHINO_BRIDGE.try_into().unwrap();
    snforge_std::declare("RhinoBridgeMock")
        .unwrap()
        .contract_class()
        .deploy_at(@array![], bridge)
        .unwrap();
    bridge
}

fn deposit(ref state: FlowTestBase, user: User) -> u256 {
    let core = state.facade.perpetuals_contract;
    let amount: u256 = 10000_u256 * state.facade.collateral_quantum.into();
    state.facade.token_state.approve(user.account.address, core, amount.try_into().unwrap());
    user.account.set_as_caller(core);
    let mut spy = snforge_std::spy_events();
    IDepositDispatcher { contract_address: core }.deposit(user.position_id, 10000, 42);
    let hash = deposit_hash(
        state.facade.token_state.address, user.account.address, user.position_id, 10000, 42,
    );
    spy
        .assert_emitted(
            @array![
                (
                    core,
                    perpetuals::core::components::deposit::deposit_manager::DepositManager::Event::Deposit(
                        perpetuals::core::components::deposit::events::Deposit {
                            position_id: user.position_id,
                            depositing_address: user.account.address,
                            collateral_id: state.facade.collateral_id,
                            token_address: state.facade.token_state.address,
                            quantized_amount: 10000,
                            unquantized_amount: amount.try_into().unwrap(),
                            deposit_request_hash: hash,
                            salt: 42,
                        },
                    ),
                ),
            ],
        );
    assert!(
        IDepositDispatcher { contract_address: core }
            .get_deposit_status(hash) == DepositStatus::NOT_REGISTERED,
    );
    amount
}

#[test]
#[feature("safe_dispatcher")]
fn test_deposit_bridge_direct_transfer_without_tracking() {
    let mut state = post_migration_state();
    let user = state.new_user_with_position();
    let bridge = setup_bridge();
    let token = IERC20Dispatcher { contract_address: state.facade.token_state.address };
    let core = state.facade.perpetuals_contract;
    let positions = perpetuals::core::components::positions::interface::IPositionsDispatcher {
        contract_address: core,
    };
    let position_before = positions.get_position_assets(user.position_id);
    let treasury_before = token.balance_of(state.facade.treasury_address);
    let core_before = token.balance_of(core);
    let amount = deposit(ref state, user);
    assert!(token.balance_of(core) == core_before + amount);
    let nonce = IOperatorNonceDispatcher { contract_address: core }.get_operator_nonce();
    cheat_caller_address_once(core, state.facade.operator.address);
    let mut spy = snforge_std::spy_events();
    IDepositDispatcher { contract_address: core }.bridge_funds(amount, 123);
    spy
        .assert_emitted(
            @array![
                (
                    core,
                    perpetuals::core::components::deposit::Deposit::Event::FundsBridged(
                        perpetuals::core::components::deposit::events::FundsBridged {
                            token_address: state.facade.token_state.address,
                            amount,
                            commitment_id: 123,
                        },
                    ),
                ),
            ],
        );
    let position_after = positions.get_position_assets(user.position_id);
    assert!(position_after.collateral_balance == position_before.collateral_balance);
    assert!(position_after.assets == position_before.assets);
    assert!(token.balance_of(core) == core_before);
    assert!(token.balance_of(bridge) == amount);
    assert!(token.balance_of(state.facade.treasury_address) == treasury_before);
    assert!(token.allowance(core, bridge) == 0);

    assert!(IOperatorNonceDispatcher { contract_address: core }.get_operator_nonce() == nonce);
    cheat_caller_address_once(core, state.facade.operator.address);
    assert!(IDepositSafeDispatcher { contract_address: core }.bridge_funds(amount, 124).is_err());
}

#[test]
#[should_panic(expected: 'RHINO_FAILURE')]
fn test_deposit_bridge_propagates_rhino_failure() {
    let mut state = post_migration_state();
    let user = state.new_user_with_position();
    setup_bridge();
    let amount = deposit(ref state, user);
    let core = state.facade.perpetuals_contract;
    cheat_caller_address_once(core, state.facade.operator.address);
    IDepositDispatcher { contract_address: core }.bridge_funds(amount, 999);
}

#[test]
#[should_panic(expected: 'BRIDGE_AMOUNT_MISMATCH')]
fn test_deposit_bridge_rejects_missing_transfer() {
    let mut state = post_migration_state();
    let user = state.new_user_with_position();
    setup_bridge();
    let amount = deposit(ref state, user);
    let core = state.facade.perpetuals_contract;
    cheat_caller_address_once(core, state.facade.operator.address);
    IDepositDispatcher { contract_address: core }.bridge_funds(amount, 998);
}

#[test]
#[should_panic(expected: 'LEGACY_DEPOSITS_DISABLED')]
fn test_deposit_bridge_blocks_legacy_processing() {
    let mut state = post_migration_state();
    let user = state.new_user_with_position();
    setup_bridge();
    deposit(ref state, user);
    let core = state.facade.perpetuals_contract;
    let nonce = IOperatorNonceDispatcher { contract_address: core }.get_operator_nonce();
    state.facade.operator.set_as_caller(core);
    IDepositDispatcher { contract_address: core }
        .process_deposit(
            nonce, user.account.address, state.facade.collateral_id, user.position_id, 10000, 42, 0,
        );
}

#[test]
#[should_panic(expected: "ONLY_OPERATOR")]
fn test_deposit_bridge_rejects_unauthorized_execution() {
    let mut state = post_migration_state();
    let user = state.new_user_with_position();
    setup_bridge();
    let amount = deposit(ref state, user);
    user.account.set_as_caller(state.facade.perpetuals_contract);
    IDepositDispatcher { contract_address: state.facade.perpetuals_contract }
        .bridge_funds(amount, 123);
}

#[test]
#[feature("safe_dispatcher")]
fn test_deposit_bridge_uses_existing_operator_role_and_revocation() {
    let mut state = post_migration_state();
    let user = state.new_user_with_position();
    let core = state.facade.perpetuals_contract;
    let safe = IDepositSafeDispatcher { contract_address: core };
    setup_bridge();
    let amount = deposit(ref state, user);
    let roles = IRolesDispatcher { contract_address: core };
    cheat_caller_address_once(core, state.facade.role_admin);
    roles.remove_operator(state.facade.operator.address);
    cheat_caller_address_once(core, state.facade.role_admin);
    roles.register_operator(user.account.address);
    state.facade.operator.set_as_caller(core);
    assert!(safe.bridge_funds(amount, 123).is_err());
    user.account.set_as_caller(core);
    IDepositDispatcher { contract_address: core }.bridge_funds(amount, 123);
}

#[test]
#[feature("safe_dispatcher")]
fn test_deposit_bridge_respects_pause() {
    let mut state = post_migration_state();
    let user = state.new_user_with_position();
    setup_bridge();
    let amount = deposit(ref state, user);
    let core = state.facade.perpetuals_contract;
    cheat_caller_address_once(core, state.facade.governance_admin);
    IRolesDispatcher { contract_address: core }
        .register_security_agent(state.facade.operator.address);
    cheat_caller_address_once(core, state.facade.operator.address);
    IPausableDispatcher { contract_address: core }.pause();
    let token = IERC20Dispatcher { contract_address: state.facade.token_state.address };
    let before = token.balance_of(core);
    cheat_caller_address_once(core, state.facade.operator.address);
    assert!(IDepositSafeDispatcher { contract_address: core }.bridge_funds(amount, 123).is_err());
    assert!(token.balance_of(core) == before);
}

#[test]
#[should_panic(expected: 'LEGACY_DEPOSITS_DISABLED')]
fn test_deposit_bridge_deposit_without_rhino_setup() {
    let mut state = post_migration_state();
    let user = state.new_user_with_position();
    deposit(ref state, user);
    let core = state.facade.perpetuals_contract;
    let nonce = IOperatorNonceDispatcher { contract_address: core }.get_operator_nonce();
    state.facade.operator.set_as_caller(core);
    IDepositDispatcher { contract_address: core }
        .process_deposit(
            nonce, user.account.address, state.facade.collateral_id, user.position_id, 10000, 42, 0,
        );
}

// Historical settlement fixtures use a test-only legacy manager. Every test in this module
// installs the production manager before accepting any post-migration deposits.
fn post_migration_state() -> FlowTestBase {
    let state = FlowTestBaseTrait::new();
    let manager = snforge_std::declare("DepositManager").unwrap().contract_class();
    let core = state.facade.perpetuals_contract;
    let dispatcher = IExternalComponentsDispatcher { contract_address: core };
    cheat_caller_address_once(core, state.facade.governance_admin);
    dispatcher.register_external_component(EXTERNAL_COMPONENT_DEPOSITS, *manager.class_hash);
    cheat_caller_address_once(core, state.facade.governance_admin);
    dispatcher.activate_external_component(EXTERNAL_COMPONENT_DEPOSITS, *manager.class_hash);
    state
}

#[test]
#[feature("safe_dispatcher")]
fn test_deposit_bridge_accepts_partial_amount_and_repeated_deposit() {
    let mut state = post_migration_state();
    let user = state.new_user_with_position();
    let bridge = setup_bridge();
    let amount = deposit(ref state, user);
    // Identical deposit arguments are allowed: the service identifies individual event logs.
    deposit(ref state, user);
    let core = state.facade.perpetuals_contract;
    let dispatcher = IDepositDispatcher { contract_address: core };
    cheat_caller_address_once(core, state.facade.operator.address);
    dispatcher.bridge_funds(amount / 2, 123);
    cheat_caller_address_once(core, state.facade.operator.address);
    dispatcher.bridge_funds(amount + amount / 2, 124);
    let token = IERC20Dispatcher { contract_address: state.facade.token_state.address };
    assert!(token.balance_of(bridge) == amount * 2);
    assert!(token.allowance(core, bridge) == 0);
}

#[test]
#[should_panic(expected: 'UNSUPPORTED_DEPOSIT_ASSET')]
fn test_deposit_bridge_blocks_other_assets() {
    let mut state = post_migration_state();
    let user = state.new_user_with_position();
    user.account.set_as_caller(state.facade.perpetuals_contract);
    IDepositDispatcher { contract_address: state.facade.perpetuals_contract }
        .deposit_asset('UNSUPPORTED'.into(), user.position_id, 10000, 42);
}

#[test]
#[should_panic(expected: 'LEGACY_DEPOSITS_DISABLED')]
fn test_deposit_bridge_blocks_cancel() {
    let mut state = post_migration_state();
    let user = state.new_user_with_position();
    deposit(ref state, user);
    user.account.set_as_caller(state.facade.perpetuals_contract);
    IDepositDispatcher { contract_address: state.facade.perpetuals_contract }
        .cancel_deposit(state.facade.collateral_id, user.position_id, 10000, 42);
}

#[test]
#[should_panic(expected: 'LEGACY_DEPOSITS_DISABLED')]
fn test_deposit_bridge_blocks_reject() {
    let mut state = post_migration_state();
    let user = state.new_user_with_position();
    deposit(ref state, user);
    let core = state.facade.perpetuals_contract;
    let nonce = IOperatorNonceDispatcher { contract_address: core }.get_operator_nonce();
    state.facade.operator.set_as_caller(core);
    IDepositDispatcher { contract_address: core }
        .reject_deposit(
            nonce, user.account.address, state.facade.collateral_id, user.position_id, 10000, 42,
        );
}

#[test]
#[should_panic(expected: 'ZERO_AMOUNT')]
fn test_deposit_bridge_blocks_zero_amount() {
    let state = post_migration_state();
    setup_bridge();
    cheat_caller_address_once(state.facade.perpetuals_contract, state.facade.operator.address);
    IDepositDispatcher { contract_address: state.facade.perpetuals_contract }.bridge_funds(0, 123);
}

#[test]
#[should_panic(expected: 'INVALID_COMMITMENT')]
fn test_deposit_bridge_blocks_zero_commitment() {
    let state = post_migration_state();
    setup_bridge();
    cheat_caller_address_once(state.facade.perpetuals_contract, state.facade.operator.address);
    IDepositDispatcher { contract_address: state.facade.perpetuals_contract }.bridge_funds(1, 0);
}
