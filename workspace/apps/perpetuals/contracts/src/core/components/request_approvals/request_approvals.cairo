#[starknet::component]
pub(crate) mod RequestApprovalsComponent {
    use contracts_commons::utils::validate_stark_signature;
    use core::num::traits::Zero;
    use perpetuals::core::components::request_approvals::errors;
    use perpetuals::core::components::request_approvals::interface::{
        IRequestApprovals, RequestStatus,
    };
    use perpetuals::core::types::Signature;
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
        fn get_request_status(
            self: @ComponentState<TContractState>, hash: felt252,
        ) -> RequestStatus {
            self.get_request_status_internal(:hash)
        }
    }


    #[generate_trait]
    pub impl InternalImpl<
        TContractState, +HasComponent<TContractState>,
    > of InternalTrait<TContractState> {
        /// Registers an approval for a request.
        /// If the owner_account is non-zero, the caller must be the owner_account.
        /// The approval is signed with the public key.
        /// The signature is verified with the hash of the request.
        /// The request is stored with a status of PENDING.
        fn register_approval(
            ref self: ComponentState<TContractState>,
            owner_account: ContractAddress,
            public_key: felt252,
            signature: Signature,
            hash: felt252,
        ) {
            assert(
                self.get_request_status_internal(:hash) == RequestStatus::NON_EXIST,
                errors::APPROVAL_ALREADY_REGISTERED,
            );
            if owner_account.is_non_zero() {
                assert(owner_account == get_caller_address(), errors::CALLER_IS_NOT_OWNER_ACCOUNT);
            }
            validate_stark_signature(:public_key, msg_hash: hash, :signature);
            self.approved_requests.write(key: hash, value: RequestStatus::PENDING);
        }

        /// Consumes an approved request.
        /// The request marked with a status of DONE.
        ///
        /// Validations:
        /// The request must be registered with PENDING state.
        /// The request must not be in the DONE state.
        fn consume_approved_request(ref self: ComponentState<TContractState>, hash: felt252) {
            let request_status = self.get_request_status_internal(:hash);
            assert(request_status == RequestStatus::PENDING, errors::APPROVAL_NOT_REGISTERED);
            self.approved_requests.write(hash, RequestStatus::DONE);
        }


        fn get_request_status_internal(
            self: @ComponentState<TContractState>, hash: felt252,
        ) -> RequestStatus {
            self.approved_requests.read(hash)
        }
    }
}
