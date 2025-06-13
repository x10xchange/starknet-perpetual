use perpetuals::core::types::position::PositionId;
use starknet::ContractAddress;
use starkware_utils::types::HashType;
use starkware_utils::types::time::time::{TimeDelta, Timestamp};

#[starknet::interface]
pub trait IDeposit<TContractState> {
    fn deposit(
        ref self: TContractState, position_id: PositionId, quantized_amount: u64, salt: felt252,
    );
    fn cancel_deposit(
        ref self: TContractState, position_id: PositionId, quantized_amount: u64, salt: felt252,
    );
    fn reject_deposit(
        ref self: TContractState, operator_nonce: u64, depositor: ContractAddress, position_id: PositionId, quantized_amount: u64, salt: felt252,
    );
    fn process_deposit(
        ref self: TContractState,
        operator_nonce: u64,
        depositor: ContractAddress,
        position_id: PositionId,
        quantized_amount: u64,
        salt: felt252,
    );
    fn get_deposit_status(self: @TContractState, deposit_hash: HashType) -> DepositStatus;
    fn get_cancel_delay(self: @TContractState) -> TimeDelta;
}

#[derive(Debug, Drop, PartialEq, Serde, starknet::Store)]
pub enum DepositStatus {
    #[default]
    NOT_REGISTERED,
    PROCESSED,
    CANCELED,
    PENDING: Timestamp,
}
