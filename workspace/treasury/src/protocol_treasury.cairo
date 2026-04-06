use starkware_utils::constants::DAY;
use starkware_utils::time::time::TimeDelta;
use treasury::interface::ITreasury;

const PERCENT_SCALE: u128 = 1000;
const CHECK_FREQUENCY: TimeDelta = TimeDelta { seconds: DAY };

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
    use starkware_utils::time::time::{Time, Timestamp};
    use super::{CHECK_FREQUENCY, ITreasury, PERCENT_SCALE};


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
        time_of_last_reset: Map<ContractAddress, Timestamp>,
        amount_withdrawn_since_reset: Map<ContractAddress, u128>,
        balance_at_last_reset: Map<ContractAddress, u128>,
        max_allowed_withdrawal: Map<ContractAddress, u128>,
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
            self.amount_withdrawn_since_reset.write(collateral_address, 0);
            self.time_of_last_reset.write(collateral_address, Time::now());
            let balance: u128 = IERC20Dispatcher { contract_address: collateral_address }
                .balance_of(starknet::get_contract_address())
                .try_into()
                .expect('BALANCE_OVERFLOW');
            self.balance_at_last_reset.write(collateral_address, balance);
            let limit = self.initial_protection_percent.read();
            let max_withdrawal = mul_wide_and_floor_div(balance, limit.into() * 10, PERCENT_SCALE)
                .expect('MUL_DIV_OVERFLOW');
            self.max_allowed_withdrawal.write(collateral_address, max_withdrawal);
        }

        fn change_protection_limit_percent(
            ref self: ContractState, collateral_address: ContractAddress, percent: u64,
        ) {
            self.roles.only_app_governor();
            self.initial_protection_percent.write(percent);
            let balance = self.balance_at_last_reset.read(collateral_address);
            let max_withdrawal = mul_wide_and_floor_div(balance, percent.into() * 10, PERCENT_SCALE)
                .expect('MUL_DIV_OVERFLOW');
            self.max_allowed_withdrawal.write(collateral_address, max_withdrawal);
        }
    }

    #[generate_trait]
    impl PrivateImpl of PrivateTrait {
        fn update_and_get_protection_limit(
            ref self: ContractState, collateral_address: ContractAddress,
        ) -> u128 {
            let now = Time::now();
            let time_of_last_reset = self.time_of_last_reset.read(collateral_address);
            let time_elapsed = now.sub(time_of_last_reset);
            if time_elapsed > CHECK_FREQUENCY {
                self.time_of_last_reset.write(collateral_address, now);
                self.amount_withdrawn_since_reset.write(collateral_address, 0);
                let balance: u128 = IERC20Dispatcher { contract_address: collateral_address }
                    .balance_of(starknet::get_contract_address())
                    .try_into()
                    .expect('BALANCE_OVERFLOW');
                self.balance_at_last_reset.write(collateral_address, balance);
                let limit = self.initial_protection_percent.read();
                let max_withdrawal = mul_wide_and_floor_div(
                    balance, limit.into() * 10, PERCENT_SCALE,
                )
                    .expect('MUL_DIV_OVERFLOW');
                self.max_allowed_withdrawal.write(collateral_address, max_withdrawal);
            }
            self.amount_withdrawn_since_reset.read(collateral_address)
        }

        fn update_withdrawn_and_verify(
            ref self: ContractState, collateral_address: ContractAddress, amount: u128,
        ) {
            let current_withdrawn = self.update_and_get_protection_limit(collateral_address);
            let new_withdrawn = current_withdrawn + amount;
            let max_allowed = self.max_allowed_withdrawal.read(collateral_address);
            if new_withdrawn >= max_allowed {
                panic_with_byte_array(
                    err: @format!(
                        "Treasury Protection Limit Exceeded, balance_at_reset: {}, withdrawn: {}, max_allowed: {}",
                        self.balance_at_last_reset.read(collateral_address),
                        new_withdrawn,
                        max_allowed,
                    ),
                );
            }
            self.amount_withdrawn_since_reset.write(collateral_address, new_withdrawn);
        }
    }
}
