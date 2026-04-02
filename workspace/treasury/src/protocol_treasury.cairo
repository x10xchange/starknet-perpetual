use treasury::interface::ITreasury;

const SCALE: u64 = 1000000_u64;

#[starknet::contract]
pub mod ProtocolTreasury {
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::introspection::src5::SRC5Component;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::{ContractAddress, get_caller_address};
    use starkware_utils::components::replaceability::ReplaceabilityComponent;
    use starkware_utils::components::replaceability::ReplaceabilityComponent::InternalReplaceabilityTrait;
    use starkware_utils::components::roles::RolesComponent;
    use starkware_utils::components::roles::RolesComponent::InternalTrait as RolesInternal;
    use starkware_utils::math::abs::Abs;
    use super::{ITreasury, SCALE};

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
            panic!("not implemented")
        }

        fn withdraw_from(
            ref self: ContractState, collateral_address: ContractAddress, amount: u256,
        ) {
            panic!("not implemented")
        }

        fn reset_protection_limit(
            ref self: ContractState, collateral_address: ContractAddress,
        ) {
            panic!("not implemented")
        }

        fn change_protection_limit_percent(
            ref self: ContractState, collateral_address: ContractAddress,
        ) {
            panic!("not implemented")
        }
    }
}
