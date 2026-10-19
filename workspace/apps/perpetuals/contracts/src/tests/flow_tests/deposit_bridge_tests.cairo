use openzeppelin::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
use perpetuals::core::components::deposit::deposit_manager::deposit_hash;
use perpetuals::core::components::deposit::interface::{
    DepositStatus, IDepositDispatcher, IDepositDispatcherTrait, IDepositSafeDispatcher,
    IDepositSafeDispatcherTrait,
};
use perpetuals::core::components::operator_nonce::interface::{
    IOperatorNonceDispatcher, IOperatorNonceDispatcherTrait,
};
use perpetuals::core::components::positions::interface::IPositionsDispatcherTrait;
use perpetuals::tests::flow_tests::infra::*;
use perpetuals::tests::flow_tests::perps_tests_facade::*;
use snforge_std::{ContractClassTrait, DeclareResultTrait};
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

fn operator() -> ContractAddress {
    0x123456.try_into().unwrap()
}

fn setup_bridge(state: @FlowTestBase) -> ContractAddress {
    let bridge: ContractAddress = perpetuals::core::constants::RHINO_BRIDGE.try_into().unwrap();
    snforge_std::declare("RhinoBridgeMock")
        .unwrap()
        .contract_class()
        .deploy_at(@array![], bridge)
        .unwrap();
    cheat_caller_address_once(*state.facade.perpetuals_contract, *state.facade.app_governor);
    IDepositDispatcher { contract_address: *state.facade.perpetuals_contract }
        .set_deposit_bridge_operator(operator());
    bridge
}

fn deposit(ref state: FlowTestBase, user: User) -> felt252 {
    let core = state.facade.perpetuals_contract;
    let amount: u256 = 10000_u256 * state.facade.collateral_quantum.into();
    state.facade.token_state.approve(user.account.address, core, amount.try_into().unwrap());
    user.account.set_as_caller(core);
    IDepositDispatcher { contract_address: core }.deposit(user.position_id, 10000, 42);
    deposit_hash(
        state.facade.token_state.address, user.account.address, user.position_id, 10000, 42,
    )
}

#[test]
#[feature("safe_dispatcher")]
fn test_deposit_bridge_direct_transfer_and_replay_protection() {
    let mut state = FlowTestBaseTrait::new();
    let user = state.new_user_with_position();
    let bridge = setup_bridge(@state);
    let token = IERC20Dispatcher { contract_address: state.facade.token_state.address };
    let core = state.facade.perpetuals_contract;
    let positions = perpetuals::core::components::positions::interface::IPositionsDispatcher {
        contract_address: core,
    };
    let position_before = positions.get_position_assets(user.position_id);
    let treasury_before = token.balance_of(state.facade.treasury_address);
    let core_before = token.balance_of(core);
    let hash = deposit(ref state, user);
    let amount: u256 = 10000_u256 * state.facade.collateral_quantum.into();
    assert!(token.balance_of(core) == core_before + amount);
    let nonce = IOperatorNonceDispatcher { contract_address: core }.get_operator_nonce();
    cheat_caller_address_once(core, operator());
    IDepositDispatcher { contract_address: core }.bridge_deposit(hash, 123);
    let position_after = positions.get_position_assets(user.position_id);
    assert!(position_after.collateral_balance == position_before.collateral_balance);
    assert!(position_after.assets == position_before.assets);
    assert!(token.balance_of(core) == core_before);
    assert!(token.balance_of(bridge) == amount);
    assert!(token.balance_of(state.facade.treasury_address) == treasury_before);
    assert!(token.allowance(core, bridge) == 0);
    assert!(
        IDepositDispatcher { contract_address: core }
            .get_deposit_status(hash) == DepositStatus::PROCESSED,
    );
    assert!(IOperatorNonceDispatcher { contract_address: core }.get_operator_nonce() == nonce);
    cheat_caller_address_once(core, operator());
    assert!(IDepositSafeDispatcher { contract_address: core }.bridge_deposit(hash, 124).is_err());
}

#[test]
#[should_panic(expected: 'RHINO_FAILURE')]
fn test_deposit_bridge_propagates_rhino_failure() {
    let mut state = FlowTestBaseTrait::new();
    let user = state.new_user_with_position();
    setup_bridge(@state);
    let hash = deposit(ref state, user);
    let core = state.facade.perpetuals_contract;
    cheat_caller_address_once(core, operator());
    IDepositDispatcher { contract_address: core }.bridge_deposit(hash, 999);
}

#[test]
#[should_panic(expected: 'BRIDGE_AMOUNT_MISMATCH')]
fn test_deposit_bridge_rejects_missing_transfer() {
    let mut state = FlowTestBaseTrait::new();
    let user = state.new_user_with_position();
    setup_bridge(@state);
    let hash = deposit(ref state, user);
    let core = state.facade.perpetuals_contract;
    cheat_caller_address_once(core, operator());
    IDepositDispatcher { contract_address: core }.bridge_deposit(hash, 998);
}

#[test]
#[should_panic(expected: 'DEPOSIT_REQUIRES_BRIDGE')]
fn test_deposit_bridge_blocks_legacy_processing() {
    let mut state = FlowTestBaseTrait::new();
    let user = state.new_user_with_position();
    setup_bridge(@state);
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
fn test_deposit_bridge_preserves_pre_upgrade_pending_deposits() {
    let mut state = FlowTestBaseTrait::new();
    let user = state.new_user_with_position();
    let info = state.facade.deposit(user.account, user.position_id, 10000);
    setup_bridge(@state);
    state.facade.process_deposit(info);
}

#[test]
#[should_panic(expected: 'NOT_BRIDGE_DEPOSIT')]
fn test_deposit_bridge_cannot_sweep_pre_upgrade_deposits() {
    let mut state = FlowTestBaseTrait::new();
    let user = state.new_user_with_position();
    let hash = deposit(ref state, user);
    crate::tests::test_utils::mark_pre_upgrade_deposit(state.facade.perpetuals_contract, hash);
    setup_bridge(@state);
    cheat_caller_address_once(state.facade.perpetuals_contract, operator());
    IDepositDispatcher { contract_address: state.facade.perpetuals_contract }
        .bridge_deposit(hash, 123);
}

#[test]
#[should_panic(expected: 'ONLY_BRIDGE_OPERATOR')]
fn test_deposit_bridge_rejects_unauthorized_execution() {
    let mut state = FlowTestBaseTrait::new();
    let user = state.new_user_with_position();
    setup_bridge(@state);
    let hash = deposit(ref state, user);
    user.account.set_as_caller(state.facade.perpetuals_contract);
    IDepositDispatcher { contract_address: state.facade.perpetuals_contract }
        .bridge_deposit(hash, 123);
}

#[test]
#[feature("safe_dispatcher")]
fn test_deposit_bridge_cancel_and_bridge_are_mutually_exclusive() {
    let mut state = FlowTestBaseTrait::new();
    let user = state.new_user_with_position();
    setup_bridge(@state);
    let hash = deposit(ref state, user);
    let core = state.facade.perpetuals_contract;
    let dispatcher = IDepositDispatcher { contract_address: core };
    let token = IERC20Dispatcher { contract_address: state.facade.token_state.address };
    let user_before = token.balance_of(user.account.address);
    let now = starkware_utils::time::time::Time::now();
    let later = now.seconds + dispatcher.get_cancel_delay().seconds;
    snforge_std::start_cheat_block_timestamp_global(later + 1);
    user.account.set_as_caller(core);
    dispatcher.cancel_deposit(state.facade.collateral_id, user.position_id, 10000, 42);
    assert!(dispatcher.get_deposit_status(hash) == DepositStatus::CANCELED);
    assert!(token.balance_of(user.account.address) > user_before);
    cheat_caller_address_once(core, operator());
    assert!(IDepositSafeDispatcher { contract_address: core }.bridge_deposit(hash, 123).is_err());
}

#[test]
#[feature("safe_dispatcher")]
fn test_deposit_bridge_operator_rotation_and_governor_authorization() {
    let mut state = FlowTestBaseTrait::new();
    let user = state.new_user_with_position();
    let core = state.facade.perpetuals_contract;
    let safe = IDepositSafeDispatcher { contract_address: core };
    setup_bridge(@state);
    let hash = deposit(ref state, user);
    user.account.set_as_caller(core);
    assert!(safe.set_deposit_bridge_operator(user.account.address).is_err());
    cheat_caller_address_once(core, state.facade.app_governor);
    IDepositDispatcher { contract_address: core }.set_deposit_bridge_operator(user.account.address);
    cheat_caller_address_once(core, operator());
    assert!(safe.bridge_deposit(hash, 123).is_err());
    user.account.set_as_caller(core);
    IDepositDispatcher { contract_address: core }.bridge_deposit(hash, 123);
}

#[test]
#[feature("safe_dispatcher")]
fn test_deposit_bridge_respects_pause() {
    let mut state = FlowTestBaseTrait::new();
    let user = state.new_user_with_position();
    setup_bridge(@state);
    let hash = deposit(ref state, user);
    let core = state.facade.perpetuals_contract;
    cheat_caller_address_once(core, state.facade.governance_admin);
    IRolesDispatcher { contract_address: core }.register_security_agent(operator());
    cheat_caller_address_once(core, operator());
    IPausableDispatcher { contract_address: core }.pause();
    let before = IDepositDispatcher { contract_address: core }.get_deposit_status(hash);
    cheat_caller_address_once(core, operator());
    assert!(IDepositSafeDispatcher { contract_address: core }.bridge_deposit(hash, 123).is_err());
    assert!(IDepositDispatcher { contract_address: core }.get_deposit_status(hash) == before);
}

#[test]
#[should_panic(expected: 'DEPOSIT_REQUIRES_BRIDGE')]
fn test_deposit_bridge_registration_does_not_require_operator_setup() {
    let mut state = FlowTestBaseTrait::new();
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
