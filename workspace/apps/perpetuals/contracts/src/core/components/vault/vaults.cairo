use perpetuals::core::types::asset::AssetId;
use perpetuals::core::types::position::PositionId;

const STORAGE_VERSION: u8 = 1;

#[derive(Copy, Debug, Default, Drop, Hash, PartialEq, Serde, starknet::Store)]
pub struct VaultConfig {
    version: u8,
    must_return_funds: bool,
}

#[starknet::interface]
pub trait IVaults<TContractState> {
    fn activate_vault(
        ref self: TContractState,
        vault_asset_id: AssetId,
        vault_position: PositionId,
        must_return_funds: bool,
    );
    fn vault_must_return_funds(ref self: TContractState, vault_asset_id: AssetId) -> bool;

    fn is_vault(ref self: TContractState, vault_position: PositionId) -> bool;
}

#[starknet::component]
pub(crate) mod Vaults {
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::introspection::src5::SRC5Component;
    use perpetuals::core::components::assets::AssetsComponent;
    use perpetuals::core::components::operator_nonce::OperatorNonceComponent;
    use perpetuals::core::components::positions::Positions as PositionsComponent;
    use perpetuals::core::components::vault::events;
    use perpetuals::core::types::asset::AssetId;
    use perpetuals::core::types::position::PositionId;
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starkware_utils::components::pausable::PausableComponent;
    use starkware_utils::components::request_approvals::RequestApprovalsComponent;
    use starkware_utils::components::roles::RolesComponent;
    use super::{IVaults, STORAGE_VERSION, VaultConfig};

    #[event]
    #[derive(Drop, PartialEq, starknet::Event)]
    pub enum Event {
        VaultOpened: events::VaultOpened,
    }

    #[storage]
    pub struct Storage {
        registered_vaults_by_asset: Map<AssetId, VaultConfig>,
        registered_vaults_by_position: Map<PositionId, VaultConfig>,
    }

    #[embeddable_as(VaultsImpl)]
    impl Vaults<
        TContractState,
        +HasComponent<TContractState>,
        +Drop<TContractState>,
        +AccessControlComponent::HasComponent<TContractState>,
        +SRC5Component::HasComponent<TContractState>,
        impl Assets: AssetsComponent::HasComponent<TContractState>,
        impl OperatorNonce: OperatorNonceComponent::HasComponent<TContractState>,
        impl Pausable: PausableComponent::HasComponent<TContractState>,
        impl Positions: PositionsComponent::HasComponent<TContractState>,
        impl Roles: RolesComponent::HasComponent<TContractState>,
        impl RequestApprovals: RequestApprovalsComponent::HasComponent<TContractState>,
    > of IVaults<ComponentState<TContractState>> {
        fn activate_vault(
            ref self: ComponentState<TContractState>,
            vault_asset_id: AssetId,
            vault_position: PositionId,
            must_return_funds: bool,
        ) {
            let existing_entry = self.registered_vaults_by_asset.read(vault_asset_id);
            assert(existing_entry.version == 0, 'VAULT_ALREADY_ACTIVATED');

            let existing_position_entry = self.registered_vaults_by_position.read(vault_position);
            assert(existing_position_entry.version == 0, 'VAULT_ALREADY_ACTIVATED');

            self
                .registered_vaults_by_asset
                .write(vault_asset_id, VaultConfig { must_return_funds, version: STORAGE_VERSION });

            self
                .registered_vaults_by_position
                .write(vault_position, VaultConfig { must_return_funds, version: STORAGE_VERSION });

            self
                .emit(
                    Event::VaultOpened(
                        events::VaultOpened {
                            position_id: vault_position, asset_id: vault_asset_id,
                        },
                    ),
                )
        }
        fn vault_must_return_funds(
            ref self: ComponentState<TContractState>, vault_asset_id: AssetId,
        ) -> bool {
            let existing_entry = self.registered_vaults_by_asset.read(vault_asset_id);
            assert(existing_entry.version != 0, 'UNKNOWN_VAULT');
            existing_entry.must_return_funds
        }
        fn is_vault(ref self: ComponentState<TContractState>, vault_position: PositionId) -> bool {
            let vault_config = self.registered_vaults_by_position.read(vault_position);
            vault_config.version != 0
        }
    }

    #[generate_trait]
    pub impl InternalImpl<
        TContractState, +HasComponent<TContractState>, +Drop<TContractState>,
    > of InternalTrait<TContractState> {
        fn initialize(ref self: ComponentState<TContractState>) {}
    }
}
