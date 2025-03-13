use perpetuals::core::components::deposit::interface::{
    DepositStatus, IDepositDispatcher, IDepositDispatcherTrait,
};
use perpetuals::tests::constants;
use perpetuals::tests::event_test_utils::assert_deposit_event_with_expected;
use perpetuals::tests::test_utils::validate_balance;
use snforge_std::cheatcodes::events::Event;
use starknet::ContractAddress;
use starkware_utils::test_utils::TokenState;
use starkware_utils::types::time::time::Timestamp;
use super::flow_tests_infra::User;

pub fn event_check_deposit(
    user: User, amount: u64, deposit_hash: felt252, event: @(ContractAddress, Event),
) {
    assert_deposit_event_with_expected(
        spied_event: event,
        position_id: user.position_id,
        depositing_address: user.account.address,
        collateral_id: constants::COLLATERAL_ASSET_ID(),
        quantized_amount: amount,
        unquantized_amount: amount * constants::COLLATERAL_QUANTUM.into(),
        deposit_request_hash: deposit_hash,
    );
}

pub fn validate_balance_deposit(
    token_state: TokenState,
    user_address: ContractAddress,
    contract_address: ContractAddress,
    expected_user_balance: u128,
    expected_contract_balance: u128,
) {
    validate_balance(:token_state, address: user_address, expected_balance: expected_user_balance);
    validate_balance(
        :token_state, address: contract_address, expected_balance: expected_contract_balance,
    );
}

pub fn check_status_deposit(
    contract_address: ContractAddress, deposit_hash: felt252, expected_time: Timestamp,
) {
    let status = IDepositDispatcher { contract_address: contract_address }
        .get_deposit_status(:deposit_hash);
    if let DepositStatus::PENDING(timestamp) = status {
        assert!(timestamp == expected_time);
    } else {
        panic!("Deposit not found");
    }
}
