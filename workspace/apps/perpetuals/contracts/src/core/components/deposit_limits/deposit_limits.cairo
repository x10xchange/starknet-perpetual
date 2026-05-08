#[starknet::component]
pub mod DepositLimits {
    use core::num::traits::{Pow, Zero};
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::interfaces::erc20::{
        IERC20Dispatcher, IERC20DispatcherTrait, IERC20MetadataDispatcher,
        IERC20MetadataDispatcherTrait,
    };
    use openzeppelin::introspection::src5::SRC5Component;
    use starknet::storage::{Map, StorageMapReadAccess, StorageMapWriteAccess};
    use starknet::{ContractAddress, get_contract_address};
    use starkware_utils::components::roles::RolesComponent;
    use starkware_utils::components::roles::RolesComponent::InternalTrait as RolesInternalTrait;
    use crate::core::components::deposit_limits::interface::IDepositLimits;
    use crate::core::components::deposit_limits::{errors, events};

    #[storage]
    pub struct Storage {
        pub max_deposits: Map<ContractAddress, Option<u256>>,
    }

    #[event]
    #[derive(Drop, PartialEq, starknet::Event)]
    pub enum Event {
        MaxDepositUpdated: events::MaxDepositUpdated,
    }

    #[embeddable_as(DepositLimitsImpl)]
    impl DepositLimitsComponent<
        TContractState,
        +HasComponent<TContractState>,
        +Drop<TContractState>,
        +AccessControlComponent::HasComponent<TContractState>,
        +SRC5Component::HasComponent<TContractState>,
        impl Roles: RolesComponent::HasComponent<TContractState>,
    > of IDepositLimits<ComponentState<TContractState>> {
        fn set_max_deposit(
            ref self: ComponentState<TContractState>,
            token_address: ContractAddress,
            whole_amount: u256,
        ) {
            get_dep_component!(@self, Roles).only_app_governor();
            assert(token_address.is_non_zero(), errors::ZERO_TOKEN_ADDRESS);
            let decimals = IERC20MetadataDispatcher { contract_address: token_address }.decimals();
            let raw_amount = whole_amount * 10_u256.pow(decimals.into());
            let old_max = self.max_deposits.read(token_address);
            self.max_deposits.write(token_address, Option::Some(raw_amount));
            self
                .emit(
                    events::MaxDepositUpdated {
                        token_address, old_max, new_max: Option::Some(raw_amount),
                    },
                );
        }

        fn get_max_deposit(
            self: @ComponentState<TContractState>, token_address: ContractAddress,
        ) -> Option<u256> {
            self.max_deposits.read(token_address)
        }
    }

    #[generate_trait]
    pub impl InternalImpl<
        TContractState, +HasComponent<TContractState>, +Drop<TContractState>,
    > of InternalTrait<TContractState> {
        /// Reverts if the new deposit would push the in-flight total past the configured cap.
        /// In-flight = `balance_of(treasury) + balance_of(perps)` — pending deposits sit on the
        /// perps contract until processed, so balances alone reflect the full picture without
        /// extra bookkeeping. `None` cap = unlimited; the treasury is only read when a cap is
        /// set so deposits aren't blocked while treasury is unwired.
        fn validate_deposit_within_limit(
            self: @ComponentState<TContractState>,
            token_address: ContractAddress,
            treasury_address: ContractAddress,
            amount: u256,
        ) {
            if let Option::Some(max_deposit) = self.max_deposits.read(token_address) {
                assert(treasury_address.is_non_zero(), errors::TREASURY_NOT_SET);
                let token = IERC20Dispatcher { contract_address: token_address };
                let in_flight = token.balance_of(treasury_address)
                    + token.balance_of(get_contract_address());
                assert(in_flight + amount <= max_deposit, errors::DEPOSIT_LIMIT_EXCEEDED);
            }
        }
    }
}
