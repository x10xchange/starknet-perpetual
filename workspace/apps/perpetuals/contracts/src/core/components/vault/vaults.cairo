use perpetuals::core::types::asset::AssetId;
use perpetuals::core::types::position::PositionId;
use perpetuals::core::types::vault::{ConvertPositionToVault, InvestInVault};

const STORAGE_VERSION: u8 = 1;

#[derive(Copy, Debug, Default, Drop, Hash, PartialEq, Serde, starknet::Store)]
pub struct VaultConfig {
    version: u8,
    pub asset_id: AssetId,
    pub position_id: u32,
}

#[starknet::interface]
pub trait IVaults<TContractState> {
    fn activate_vault(ref self: TContractState, operator_nonce: u64, order: ConvertPositionToVault);

    fn is_vault(ref self: TContractState, vault_position: PositionId) -> bool;
}

#[starknet::component]
pub(crate) mod Vaults {
    use core::num::traits::Zero;
    use core::panic_with_felt252;
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::interfaces::erc4626::{IERC4626Dispatcher, IERC4626DispatcherTrait};
    use openzeppelin::introspection::src5::SRC5Component;
    use perpetuals::core::components::assets::AssetsComponent;
    use perpetuals::core::components::assets::interface::IAssets;
    use perpetuals::core::components::deposit::Deposit as DepositComponent;
    use perpetuals::core::components::operator_nonce::OperatorNonceComponent;
    use perpetuals::core::components::operator_nonce::OperatorNonceComponent::InternalTrait as NonceInternal;
    use perpetuals::core::components::positions::Positions as PositionsComponent;
    use perpetuals::core::components::positions::Positions::InternalTrait as PositionsInternal;
    use perpetuals::core::components::vault::events;
    use perpetuals::core::components::vault::protocol_vault::{
        IProtocolVaultDispatcher, IProtocolVaultDispatcherTrait,
    };
    use perpetuals::core::types::asset::AssetId;
    use perpetuals::core::types::asset::synthetic::AssetType;
    use perpetuals::core::types::position::PositionId;
    use starknet::storage::{Map, StorageMapReadAccess, StorageMapWriteAccess};
    use starkware_utils::components::pausable::PausableComponent;
    use starkware_utils::components::pausable::PausableComponent::InternalTrait as PausableInternal;
    use starkware_utils::components::request_approvals::RequestApprovalsComponent;
    use starkware_utils::components::roles::RolesComponent;
    use starkware_utils::storage::iterable_map::{
        IterableMapIntoIterImpl, IterableMapReadAccessImpl, IterableMapWriteAccessImpl,
    };
    use crate::core::components::positions;
    use super::{ConvertPositionToVault, IVaults, STORAGE_VERSION, VaultConfig};

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
        // impl Deposit: Deposit::HasComponent<TContractState>,
    > of IVaults<ComponentState<TContractState>> {
        fn activate_vault(
            ref self: ComponentState<TContractState>,
            operator_nonce: u64,
            order: ConvertPositionToVault,
        ) {
            let vault_asset_id = order.vault_asset_id;
            let vault_position = order.position_to_convert;
            let expiration = order.expiration;

            /// Validations:
            get_dep_component!(@self, Pausable).assert_not_paused();
            let mut nonce = get_dep_component_mut!(ref self, OperatorNonce);
            nonce.use_checked_nonce(operator_nonce);

            let existing_entry = self.registered_vaults_by_asset.read(vault_asset_id);
            assert(existing_entry.version == 0, 'VAULT_ALREADY_ACTIVATED');

            let existing_position_entry = self.registered_vaults_by_position.read(vault_position);
            assert(existing_position_entry.version == 0, 'VAULT_ALREADY_ACTIVATED');

            let positions = get_dep_component!(@self, Positions);
            let position_info = positions.get_position_snapshot(vault_position);
            let assets = get_dep_component!(@self, Assets);

            let asset_config = assets.get_asset_config(vault_asset_id);

            let erc4626_dispatcher = IERC4626Dispatcher {
                contract_address: asset_config.token_contract.expect('NOT_ERC4626'),
            };

            let vault_dispatcher = IProtocolVaultDispatcher {
                contract_address: asset_config.token_contract.expect('NOT_ERC4626'),
            };
            assert(
                vault_dispatcher.get_owning_position_id() == vault_position.value,
                'VAULT_OWNERSHIP_MISMATCH',
            );

            assert(
                erc4626_dispatcher
                    .asset() == assets
                    .get_collateral_token_contract()
                    .contract_address,
                'VAULT_ASSET_MISMATCH',
            );

            for (asset_id, balance_info) in position_info.asset_balances {
                if balance_info.balance.is_zero() {
                    continue;
                }
                let asset_config = assets.get_asset_config(asset_id);

                if (asset_config.asset_type == AssetType::VAULT_SHARE_COLLATERAL) {
                    panic_with_felt252('VAULT_CANNOT_HOLD_VAULT');
                }
            }

            self
                .registered_vaults_by_asset
                .write(
                    vault_asset_id,
                    VaultConfig {
                        version: STORAGE_VERSION,
                        asset_id: vault_asset_id,
                        position_id: vault_position.value,
                    },
                );

            self
                .registered_vaults_by_position
                .write(
                    vault_position,
                    VaultConfig {
                        version: STORAGE_VERSION,
                        asset_id: vault_asset_id,
                        position_id: vault_position.value,
                    },
                );

            self
                .emit(
                    Event::VaultOpened(
                        events::VaultOpened {
                            position_id: vault_position, asset_id: vault_asset_id,
                        },
                    ),
                )
        }

        fn is_vault(ref self: ComponentState<TContractState>, vault_position: PositionId) -> bool {
            let vault_config = self.registered_vaults_by_position.read(vault_position);
            vault_config.version != 0
        }
    }

    #[generate_trait]
    pub impl InternalImpl<
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
        impl Deposit: DepositComponent::HasComponent<TContractState>,
    > of InternalTrait<TContractState> {
        fn initialize(ref self: ComponentState<TContractState>) {}

        fn get_vault_config_for_position(
            ref self: ComponentState<TContractState>, vault_position: PositionId,
        ) -> VaultConfig {
            let vault_config = self.registered_vaults_by_position.read(vault_position);
            assert(vault_config.version != 0, 'UNKNOWN_VAULT');
            vault_config
        }

        fn get_vault_config_for_asset(
            ref self: ComponentState<TContractState>, vault_asset_id: AssetId,
        ) -> VaultConfig {
            let vault_config = self.registered_vaults_by_asset.read(vault_asset_id);
            assert(vault_config.version != 0, 'UNKNOWN_VAULT');
            vault_config
        }
    }
}
