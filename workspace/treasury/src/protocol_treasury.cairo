use starkware_utils::constants::DAY;
use starkware_utils::time::time::TimeDelta;
use treasury::interface::ITreasury;
use treasury::types::{
    PendingPercentChange, ProtectionAdminState, ProtectionState, ProtectionStateTrait,
    compute_max_withdrawal,
};

const CHECK_FREQUENCY: TimeDelta = TimeDelta { seconds: DAY };
const DEFAULT_PROTECTION_PERCENT: u64 = 5;

#[starknet::contract]
pub mod ProtocolTreasury {
    use core::num::traits::Zero;
    use core::panics::panic_with_byte_array;
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use openzeppelin::introspection::src5::SRC5Component;
    use starknet::event::EventEmitter;
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_caller_address};
    use starkware_utils::components::pausable::PausableComponent;
    use starkware_utils::components::pausable::PausableComponent::InternalTrait as PausableInternal;
    use starkware_utils::components::replaceability::ReplaceabilityComponent;
    use starkware_utils::components::replaceability::ReplaceabilityComponent::InternalReplaceabilityTrait;
    use starkware_utils::components::roles::RolesComponent;
    use starkware_utils::components::roles::RolesComponent::InternalTrait as RolesInternal;
    use starkware_utils::time::time::{Time, TimeDelta, Timestamp};
    use super::{
        CHECK_FREQUENCY, DEFAULT_PROTECTION_PERCENT, ITreasury, PendingPercentChange,
        ProtectionAdminState, ProtectionState, ProtectionStateTrait, compute_max_withdrawal,
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

    #[derive(Drop, PartialEq, starknet::Event)]
    pub struct AdminLimitChangeRequested {
        #[key]
        pub collateral_address: ContractAddress,
        pub percent: u64,
        pub applicable_at: Timestamp,
    }

    #[derive(Drop, PartialEq, starknet::Event)]
    pub struct AdminLimitChangeCancelled {
        #[key]
        pub collateral_address: ContractAddress,
        pub percent: u64,
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
        // Pre-existing (deployed) storage — names and types kept unchanged for upgrade safety.
        protection_percent_override: Map<ContractAddress, u64>,
        protection: Map<ContractAddress, ProtectionState>,
        // New cold-path state: manual-reset cooldown tracker + pending timelocked change, in one
        // entry per collateral.
        protection_admin: Map<ContractAddress, ProtectionAdminState>,
        // Minimum cooldown between manual `reset_protection_limit` calls (set at construction).
        reset_cooldown: TimeDelta,
        // Timelock between requesting and applying a percent change (set at construction).
        change_timelock: TimeDelta,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
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
        AdminLimitChangeRequested: AdminLimitChangeRequested,
        AdminLimitChangeCancelled: AdminLimitChangeCancelled,
    }

    #[constructor]
    pub fn constructor(
        ref self: ContractState,
        governance_admin: ContractAddress,
        upgrade_delay: u64,
        perps_contract: ContractAddress,
        reset_cooldown_seconds: u64,
        change_timelock_seconds: u64,
    ) {
        self.roles.initialize(:governance_admin);
        self.replaceability.initialize(:upgrade_delay);
        self.perps_contract.write(perps_contract);
        self.reset_cooldown.write(TimeDelta { seconds: reset_cooldown_seconds });
        self.change_timelock.write(TimeDelta { seconds: change_timelock_seconds });
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
            let mut admin = self.protection_admin.read(collateral_address);
            if admin.last_manual_reset_at.is_non_zero() {
                let elapsed = Time::now().sub(admin.last_manual_reset_at);
                assert(elapsed >= self.reset_cooldown.read(), 'RESET_COOLDOWN_ACTIVE');
            }
            let balance: u128 = IERC20Dispatcher { contract_address: collateral_address }
                .balance_of(starknet::get_contract_address())
                .try_into()
                .expect('BALANCE_OVERFLOW');
            let percent = self.get_protection_percent(collateral_address);
            let state = ProtectionStateTrait::new(balance, percent);
            self.protection.write(collateral_address, state);
            admin.last_manual_reset_at = Time::now();
            self.protection_admin.write(collateral_address, admin);
            self.emit(AdminLimitReset { collateral_address });
        }

        fn request_protection_limit_percent_change(
            ref self: ContractState, collateral_address: ContractAddress, percent: u64,
        ) {
            self.pausable.assert_not_paused();
            self.roles.only_app_governor();
            assert(percent <= 100, 'PERCENT_TOO_HIGH');
            let applicable_at = Time::now().add(self.change_timelock.read());
            let mut admin = self.protection_admin.read(collateral_address);
            admin.pending = PendingPercentChange { percent, applicable_at };
            self.protection_admin.write(collateral_address, admin);
            self.emit(AdminLimitChangeRequested { collateral_address, percent, applicable_at });
        }

        fn apply_protection_limit_percent_change(
            ref self: ContractState, collateral_address: ContractAddress,
        ) {
            self.pausable.assert_not_paused();
            self.roles.only_app_governor();
            let mut admin = self.protection_admin.read(collateral_address);
            assert(admin.pending.applicable_at.is_non_zero(), 'NO_PENDING_CHANGE');
            assert(Time::now() >= admin.pending.applicable_at, 'TIMELOCK_NOT_PASSED');
            let percent = admin.pending.percent;
            self.protection_percent_override.write(collateral_address, percent);
            admin.pending = PendingPercentChange { percent: 0, applicable_at: Zero::zero() };
            self.protection_admin.write(collateral_address, admin);
            let mut state = self.protection.read(collateral_address);
            state
                .max_allowed_withdrawal =
                    compute_max_withdrawal(state.balance_at_last_reset, percent);
            self.protection.write(collateral_address, state);
            self.emit(AdminLimitChanged { collateral_address, percent });
        }

        fn cancel_protection_limit_percent_change(
            ref self: ContractState, collateral_address: ContractAddress,
        ) {
            self.pausable.assert_not_paused();
            self.roles.only_app_governor();
            let mut admin = self.protection_admin.read(collateral_address);
            assert(admin.pending.applicable_at.is_non_zero(), 'NO_PENDING_CHANGE');
            let percent = admin.pending.percent;
            admin.pending = PendingPercentChange { percent: 0, applicable_at: Zero::zero() };
            self.protection_admin.write(collateral_address, admin);
            self.emit(AdminLimitChangeCancelled { collateral_address, percent });
        }

        fn get_pending_protection_limit_change(
            self: @ContractState, collateral_address: ContractAddress,
        ) -> PendingPercentChange {
            self.protection_admin.read(collateral_address).pending
        }

        fn get_last_protection_reset_at(
            self: @ContractState, collateral_address: ContractAddress,
        ) -> Timestamp {
            self.protection_admin.read(collateral_address).last_manual_reset_at
        }

        fn get_reset_cooldown(self: @ContractState) -> TimeDelta {
            self.reset_cooldown.read()
        }

        fn get_protection_limit_timelock(self: @ContractState) -> TimeDelta {
            self.change_timelock.read()
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
