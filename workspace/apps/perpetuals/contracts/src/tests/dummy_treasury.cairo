use starkware_utils::constants::DAY;
use starkware_utils::time::time::TimeDelta;
use treasury::interface::ITreasury;

const PERCENT_SCALE: u128 = 1000;
const CHECK_FREQUENCY: TimeDelta = TimeDelta { seconds: DAY };

#[starknet::contract]
pub mod DummyTreasury {
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::introspection::src5::SRC5Component;
    use starknet::ContractAddress;
    use starknet::storage::StoragePointerReadAccess;
    use starkware_utils::components::replaceability::ReplaceabilityComponent;
    use starkware_utils::components::roles::RolesComponent;
    use super::ITreasury;


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
    ) {}

    #[abi(embed_v0)]
    pub impl Impl of ITreasury<ContractState> {
        fn get_perps_contract(self: @ContractState) -> ContractAddress {
            self.perps_contract.read()
        }

        fn deposit_into(
            ref self: ContractState, collateral_address: ContractAddress, amount: u256,
        ) {}

        fn withdraw_from(
            ref self: ContractState, collateral_address: ContractAddress, amount: u256,
        ) {}

        fn reset_protection_limit(ref self: ContractState, collateral_address: ContractAddress) {}

        fn change_protection_limit_percent(
            ref self: ContractState, collateral_address: ContractAddress, percent: u64,
        ) {}
    }

    #[generate_trait]
    impl PrivateImpl of PrivateTrait {
        fn update_and_get_protection_limit(
            ref self: ContractState, collateral_address: ContractAddress,
        ) -> u128 {
            0_u128
        }

        fn update_withdrawn_and_verify(
            ref self: ContractState, collateral_address: ContractAddress, amount: u128,
        ) {}
    }
}
