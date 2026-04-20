use starkware_utils::constants::DAY;
use starkware_utils::time::time::TimeDelta;
use treasury::interface::ITreasury;
use treasury::types::{ProtectionState, ProtectionStateTrait, compute_max_withdrawal};

const CHECK_FREQUENCY: TimeDelta = TimeDelta { seconds: DAY };
const DEFAULT_PROTECTION_PERCENT: u64 = 5;

#[starknet::contract]
pub mod ProtocolTreasury {
    use core::panics::panic_with_byte_array;
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use openzeppelin::introspection::src5::SRC5Component;
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starknet::event::EventEmitter;
    use starknet::{ContractAddress, get_caller_address};
    use starkware_utils::components::pausable::PausableComponent;
    use starkware_utils::components::pausable::PausableComponent::InternalTrait as PausableInternal;
    use starkware_utils::components::replaceability::ReplaceabilityComponent;
    use starkware_utils::components::replaceability::ReplaceabilityComponent::InternalReplaceabilityTrait;
    use starkware_utils::components::roles::RolesComponent;
    use starkware_utils::components::roles::RolesComponent::InternalTrait as RolesInternal;
    use starkware_utils::time::time::Time;
    use super::{
        CHECK_FREQUENCY, DEFAULT_PROTECTION_PERCENT, ITreasury, ProtectionState,
        ProtectionStateTrait, compute_max_withdrawal,
    };


    component!(path: AccessControlComponent, storage: accesscontrol, event: AccessControlEvent);
    component!(path: PausableComponent, storage: pausable, event: PausableEvent);
    component!(path: ReplaceabilityComponent, storage: replaceability, event: ReplaceabilityEvent);
    component!(path: RolesComponent, storage: roles, event: RolesEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);


    #[abi(embed_v0)]
    impl PausableImpl = PausableComponent::PausableImpl<ContractState>;

    #[abi(embed_v0)]
    impl ReplaceabilityImpl =
        ReplaceabilityComponent::ReplaceabilityImpl<ContractState>;

    #[abi(embed_v0)]
    impl RolesImpl = RolesComponent::RolesImpl<ContractState>;

    #[derive(Drop, PartialEq, starknet::Event)]
    pub struct Withdrawal {
        #[key]
        pub contract_address: ContractAddress,
        pub amount: u256,
        pub timestamp: u64,
    }

    #[derive(Drop, PartialEq, starknet::Event)]
    pub struct Deposit {
        #[key]
        pub collateral_address: ContractAddress,
        pub amount: u256,
        pub timestamp: u64,
    }

    #[derive(Drop, PartialEq, starknet::Event)]
    pub struct AdminLimitChanged {
        #[key]
        pub collateral_address: ContractAddress,
        pub percent: u64,
    }

    #[derive(Drop, PartialEq, starknet::Event)]
    pub struct AdminLimitReset {
        #[key]
        pub collateral_address: ContractAddress,
    }

    #[storage]
    pub struct Storage {
        #[substorage(v0)]
        accesscontrol: AccessControlComponent::Storage,
        #[substorage(v0)]
        pausable: PausableComponent::Storage,
        #[substorage(v0)]
        pub replaceability: ReplaceabilityComponent::Storage,
        #[substorage(v0)]
        pub roles: RolesComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        perps_contract: ContractAddress,
        protection_percent_override: Map<ContractAddress, u64>,
        protection: Map<ContractAddress, ProtectionState>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        AccessControlEvent: AccessControlComponent::Event,
        #[flat]
        PausableEvent: PausableComponent::Event,
        #[flat]
        ReplaceabilityEvent: ReplaceabilityComponent::Event,
        #[flat]
        RolesEvent: RolesComponent::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
        Withdrawal: Withdrawal,
        Deposit: Deposit,
        AdminLimitChanged: AdminLimitChanged,
        AdminLimitReset: AdminLimitReset,
    }

    #[constructor]
    pub fn constructor(
        ref self: ContractState,
        governance_admin: ContractAddress,
        upgrade_delay: u64,
        perps_contract: ContractAddress,
    ) {
        self.roles.initialize(:governance_admin);
        self.replaceability.initialize(:upgrade_delay);
        self.perps_contract.write(perps_contract);
    }

    #[abi(embed_v0)]
    pub impl Impl of ITreasury<ContractState> {
        fn get_perps_contract(self: @ContractState) -> ContractAddress {
            self.perps_contract.read()
        }

        fn deposit_into(
            ref self: ContractState, collateral_address: ContractAddress, amount: u256,
        ) {
            self.pausable.assert_not_paused();
            assert(get_caller_address() == self.perps_contract.read(), 'ONLY_PERPS_CAN_DEPOSIT');
            let this = starknet::get_contract_address();
            let caller = get_caller_address();
            let collateral_dispatcher = IERC20Dispatcher { contract_address: collateral_address };
            assert(collateral_dispatcher.transfer_from(caller, this, amount), 'TRANSFER_FAILED');
            self.emit(Deposit { collateral_address, amount, timestamp: Time::now().seconds });
        }

        fn withdraw_from(
            ref self: ContractState, collateral_address: ContractAddress, amount: u256,
        ) {
            self.pausable.assert_not_paused();
            assert(get_caller_address() == self.perps_contract.read(), 'ONLY_PERPS_CAN_WITHDRAW');
            self
                .update_withdrawn_and_verify(
                    collateral_address, amount.try_into().expect('AMOUNT_OVERFLOW'),
                );
            let collateral_dispatcher = IERC20Dispatcher { contract_address: collateral_address };
            assert(
                collateral_dispatcher.transfer(self.perps_contract.read(), amount),
                'TRANSFER_FAILED',
            );
            self
                .emit(
                    Withdrawal {
                        contract_address: collateral_address,
                        amount,
                        timestamp: Time::now().seconds,
                    },
                );
        }

        fn reset_protection_limit(ref self: ContractState, collateral_address: ContractAddress) {
            self.pausable.assert_not_paused();
            self.roles.only_app_governor();
            let balance: u128 = IERC20Dispatcher { contract_address: collateral_address }
                .balance_of(starknet::get_contract_address())
                .try_into()
                .expect('BALANCE_OVERFLOW');
            let percent = self.get_protection_percent(collateral_address);
            let state = ProtectionStateTrait::new(balance, percent);
            self.protection.write(collateral_address, state);
            self.emit(AdminLimitReset { collateral_address });
        }

        fn change_protection_limit_percent(
            ref self: ContractState, collateral_address: ContractAddress, percent: u64,
        ) {
            self.pausable.assert_not_paused();
            self.roles.only_app_governor();
            self.protection_percent_override.write(collateral_address, percent);
            let mut state = self.protection.read(collateral_address);
            state
                .max_allowed_withdrawal =
                    compute_max_withdrawal(state.balance_at_last_reset, percent);
            self.protection.write(collateral_address, state);
            self.emit(AdminLimitChanged { collateral_address, percent });
        }
    }

    #[generate_trait]
    impl PrivateImpl of PrivateTrait {
        fn get_protection_percent(
            self: @ContractState, collateral_address: ContractAddress,
        ) -> u64 {
            let override_percent = self.protection_percent_override.read(collateral_address);
            if override_percent != 0 {
                override_percent
            } else {
                DEFAULT_PROTECTION_PERCENT
            }
        }

        fn update_and_get_protection_limit(
            ref self: ContractState, collateral_address: ContractAddress,
        ) -> ProtectionState {
            let mut state = self.protection.read(collateral_address);
            let now = Time::now();
            let time_elapsed = now.sub(state.time_of_last_reset);
            if time_elapsed > CHECK_FREQUENCY {
                let balance: u128 = IERC20Dispatcher { contract_address: collateral_address }
                    .balance_of(starknet::get_contract_address())
                    .try_into()
                    .expect('BALANCE_OVERFLOW');
                let percent = self.get_protection_percent(collateral_address);
                state = ProtectionStateTrait::new(balance, percent);
                self.protection.write(collateral_address, state);
            }
            state
        }

        fn update_withdrawn_and_verify(
            ref self: ContractState, collateral_address: ContractAddress, amount: u128,
        ) {
            let mut state = self.update_and_get_protection_limit(collateral_address);
            let new_withdrawn = state.amount_withdrawn_since_reset + amount;
            if new_withdrawn > state.max_allowed_withdrawal {
                panic_with_byte_array(
                    err: @format!(
                        "Treasury Protection Limit Exceeded, balance_at_reset: {}, withdrawn: {}, max_allowed: {}",
                        state.balance_at_last_reset,
                        new_withdrawn,
                        state.max_allowed_withdrawal,
                    ),
                );
            }
            state.amount_withdrawn_since_reset = new_withdrawn;
            self.protection.write(collateral_address, state);
        }
    }
}
