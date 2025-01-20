#[starknet::component]
pub(crate) mod RequestApprovalsComponent {
    use contracts_commons::types::time::time::Time;
    use core::num::traits::Zero;
    use perpetuals::core::components::request_approvals::errors;
    use perpetuals::core::components::request_approvals::interface::{
        IRequestApprovals, RequestStatus,
    };
    use perpetuals::core::types::Signature;
    use perpetuals::core::utils::validate_stark_signature;
    use starknet::storage::{Map, StorageMapReadAccess, StorageMapWriteAccess};
    use starknet::{ContractAddress, get_caller_address};

    #[storage]
    pub struct Storage {
        pub approved_requests: Map<felt252, RequestStatus>,
    }

    #[event]
    #[derive(Drop, PartialEq, starknet::Event)]
    pub enum Event {}

    #[embeddable_as(RequestApprovalsImpl)]
    impl RequestApprovals<
        TContractState, +HasComponent<TContractState>, +Drop<TContractState>,
    > of IRequestApprovals<ComponentState<TContractState>> {
        fn register_approval(
            ref self: ComponentState<TContractState>,
            owner_account: ContractAddress,
            public_key: felt252,
            signature: Signature,
            hash: felt252,
        ) {
            if owner_account.is_non_zero() {
                assert(owner_account == get_caller_address(), errors::CALLER_IS_NOT_OWNER_ACCOUNT);
            }
            validate_stark_signature(:public_key, msg_hash: hash, :signature);
            self.approved_requests.write(key: hash, value: RequestStatus::PENDING(Time::now()));
        }

        fn consume_approved_request(ref self: ComponentState<TContractState>, hash: felt252) {
            let request_status = self.approved_requests.read(hash);
            assert(request_status != RequestStatus::NON_EXIST, errors::APPROVAL_NOT_REGISTERED);
            assert(request_status != RequestStatus::DONE, errors::ALREADY_DONE);
            self.approved_requests.write(hash, RequestStatus::DONE);
        }

        fn get_request_status(
            self: @ComponentState<TContractState>, hash: felt252,
        ) -> RequestStatus {
            self.approved_requests.read(hash)
        }
    }
}
