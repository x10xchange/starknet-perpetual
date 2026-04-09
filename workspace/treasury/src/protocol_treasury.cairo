use starkware_utils::constants::DAY;
use starkware_utils::time::time::{TimeDelta, Timestamp};
use treasury::interface::ITreasury;

const PERCENT_SCALE: u128 = 1000;
const CHECK_FREQUENCY: TimeDelta = TimeDelta { seconds: DAY };

#[derive(Copy, Drop, Serde, starknet::Store)]
struct ProtectionState {
    time_of_last_reset: Timestamp,
    amount_withdrawn_since_reset: u128,
    balance_at_last_reset: u128,
    max_allowed_withdrawal: u128,
}

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
    use starknet::{ContractAddress, get_caller_address};
    use starkware_utils::components::replaceability::ReplaceabilityComponent;
    use starkware_utils::components::replaceability::ReplaceabilityComponent::InternalReplaceabilityTrait;
    use starkware_utils::components::roles::RolesComponent;
    use starkware_utils::components::roles::RolesComponent::InternalTrait as RolesInternal;
    use starkware_utils::math::utils::mul_wide_and_floor_div;
    use starkware_utils::time::time::Time;
    use super::{CHECK_FREQUENCY, ITreasury, PERCENT_SCALE, ProtectionState};


    component!(path: AccessControlComponent, storage: accesscontrol, event: AccessControlEvent);
    component!(path: ReplaceabilityComponent, storage: replaceability, event: ReplaceabilityEvent);
    component!(path: RolesComponent, storage: roles, event: RolesEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);


    #[abi(embed_v0)]
    impl ReplaceabilityImpl =
        ReplaceabilityComponent::ReplaceabilityImpl<ContractState>;

    #[abi(embed_v0)]
    impl RolesImpl = RolesComponent::RolesImpl<ContractState>;


    #[storage]
    pub struct Storage {
        #[substorage(v0)]
        accesscontrol: AccessControlComponent::Storage,
        #[substorage(v0)]
        pub replaceability: ReplaceabilityComponent::Storage,
        #[substorage(v0)]
        pub roles: RolesComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        perps_contract: ContractAddress,
        initial_protection_percent: u64,
        protection: Map<ContractAddress, ProtectionState>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        AccessControlEvent: AccessControlComponent::Event,
        #[flat]
        ReplaceabilityEvent: ReplaceabilityComponent::Event,
        #[flat]
        RolesEvent: RolesComponent::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
    }

    #[constructor]
    pub fn constructor(
        ref self: ContractState,
        governance_admin: ContractAddress,
        upgrade_delay: u64,
        perps_contract: ContractAddress,
        initial_protection_percent: u64,
    ) {
        self.roles.initialize(:governance_admin);
        self.replaceability.initialize(:upgrade_delay);
        self.perps_contract.write(perps_contract);
        self.initial_protection_percent.write(initial_protection_percent);
    }

    fn compute_max_withdrawal(balance: u128, percent: u64) -> u128 {
        mul_wide_and_floor_div(balance, percent.into() * 10, PERCENT_SCALE)
            .expect('MUL_DIV_OVERFLOW')
    }

    fn snapshot_protection(balance: u128, percent: u64) -> ProtectionState {
        ProtectionState {
            time_of_last_reset: Time::now(),
            amount_withdrawn_since_reset: 0,
            balance_at_last_reset: balance,
            max_allowed_withdrawal: compute_max_withdrawal(balance, percent),
        }
    }

    #[abi(embed_v0)]
    pub impl Impl of ITreasury<ContractState> {
        fn get_perps_contract(self: @ContractState) -> ContractAddress {
            self.perps_contract.read()
        }

        fn deposit_into(
            ref self: ContractState, collateral_address: ContractAddress, amount: u256,
        ) {
            let this = starknet::get_contract_address();
            let caller = get_caller_address();
            let collateral_dispatcher = IERC20Dispatcher { contract_address: collateral_address };
            assert(collateral_dispatcher.transfer_from(caller, this, amount), 'TRANSFER_FAILED');
        }

        fn withdraw_from(
            ref self: ContractState, collateral_address: ContractAddress, amount: u256,
        ) {
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
        }

        fn reset_protection_limit(ref self: ContractState, collateral_address: ContractAddress) {
            self.roles.only_app_governor();
            let balance: u128 = IERC20Dispatcher { contract_address: collateral_address }
                .balance_of(starknet::get_contract_address())
                .try_into()
                .expect('BALANCE_OVERFLOW');
            let state = snapshot_protection(balance, self.initial_protection_percent.read());
            self.protection.write(collateral_address, state);
        }

        fn change_protection_limit_percent(
            ref self: ContractState, collateral_address: ContractAddress, percent: u64,
        ) {
            self.roles.only_app_governor();
            self.initial_protection_percent.write(percent);
            let mut state = self.protection.read(collateral_address);
            state
                .max_allowed_withdrawal =
                    compute_max_withdrawal(state.balance_at_last_reset, percent);
            self.protection.write(collateral_address, state);
        }
    }

    #[generate_trait]
    impl PrivateImpl of PrivateTrait {
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
                state = snapshot_protection(balance, self.initial_protection_percent.read());
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
