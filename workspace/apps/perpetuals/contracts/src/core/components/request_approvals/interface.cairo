use contracts_commons::types::time::time::Timestamp;
use core::panic_with_felt252;
use core::starknet::storage_access::StorePacking;
use perpetuals::core::components::request_approvals::errors;
use perpetuals::core::types::Signature;
use starknet::ContractAddress;


#[starknet::interface]
pub trait IRequestApprovals<TContractState> {
    /// Registers an approval for a request.
    /// If the owner_account is non-zero, the caller must be the owner_account.
    /// The approval is signed with the public key.
    /// The signature is verified with the hash of the request.
    /// The request is stored with a status of PENDING.
    fn register_approval(
        ref self: TContractState,
        owner_account: ContractAddress,
        public_key: felt252,
        signature: Signature,
        hash: felt252,
    );
    /// Consumes an approved request.
    /// The request marked with a status of DONE.
    ///
    /// Validations:
    /// The request must be registered with PENDING state.
    /// The request must not be in the DONE state.
    fn consume_approved_request(ref self: TContractState, hash: felt252);
    /// Returns the status of a request.
    fn get_request_status(self: @TContractState, hash: felt252) -> RequestStatus;
}

#[derive(Debug, Drop, PartialEq, Serde)]
pub(crate) enum RequestStatus {
    NON_EXIST,
    DONE,
    PENDING: Timestamp,
}

const TWO_POW_4: u64 = 0x10;
const STATUS_MASK: u128 = 0x3;

impl RequestStatusPacking of StorePacking<RequestStatus, u128> {
    fn pack(value: RequestStatus) -> u128 {
        match value {
            RequestStatus::NON_EXIST => 0,
            RequestStatus::DONE => 1,
            RequestStatus::PENDING(time) => { 2_u128 + (TWO_POW_4 * time.into()).into() },
        }
    }

    fn unpack(value: u128) -> RequestStatus {
        let status = value & STATUS_MASK;
        if status == 0 {
            RequestStatus::NON_EXIST
        } else if status == 1 {
            RequestStatus::DONE
        } else if status == 2 {
            let time: u64 = ((value - 2) / TWO_POW_4.into()).try_into().unwrap();
            RequestStatus::PENDING(Timestamp { seconds: time })
        } else {
            panic_with_felt252(errors::INVALID_STATUS)
        }
    }
}


pub(crate) impl RequestStatusImpl of TryInto<RequestStatus, Timestamp> {
    fn try_into(self: RequestStatus) -> Option<Timestamp> {
        match self {
            RequestStatus::PENDING(time) => Option::Some(time),
            _ => Option::None,
        }
    }
}
