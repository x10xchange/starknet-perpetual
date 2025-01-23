use core::panic_with_felt252;
use core::starknet::storage_access::StorePacking;
use perpetuals::core::components::request_approvals::errors;


#[starknet::interface]
pub trait IRequestApprovals<TContractState> {
    /// Returns the status of a request.
    fn get_request_status(self: @TContractState, hash: felt252) -> RequestStatus;
}

#[derive(Debug, Drop, PartialEq, Serde)]
pub(crate) enum RequestStatus {
    NON_EXIST,
    DONE,
    PENDING,
}

const STATUS_MASK: u8 = 0x3;

impl RequestStatusPacking of StorePacking<RequestStatus, u8> {
    fn pack(value: RequestStatus) -> u8 {
        match value {
            RequestStatus::NON_EXIST => 0,
            RequestStatus::DONE => 1,
            RequestStatus::PENDING => 2,
        }
    }

    fn unpack(value: u8) -> RequestStatus {
        let status = value & STATUS_MASK;
        if status == 0 {
            RequestStatus::NON_EXIST
        } else if status == 1 {
            RequestStatus::DONE
        } else if status == 2 {
            RequestStatus::PENDING
        } else {
            panic_with_felt252(errors::INVALID_STATUS)
        }
    }
}
