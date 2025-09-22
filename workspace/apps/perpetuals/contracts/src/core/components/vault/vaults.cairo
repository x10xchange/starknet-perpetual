use perpetuals::core::types::asset::AssetId;
use perpetuals::core::types::position::PositionId;
use starkware_utils::time::time::Timestamp;

const STORAGE_VERSION: u8 = 1;

#[derive(Copy, Drop, Hash, Serde)]
/// An order to convert a position into a vault.
pub struct ConvertPositionToVault {
    pub position_to_convert: PositionId,
    pub vault_asset_id: AssetId,
    pub is_protocol_vault: bool,
    pub expiration: Timestamp,
}

#[derive(Copy, Drop, Hash, Serde)]
pub struct InvestInVault {
    pub from_position_id: PositionId,
    pub vault_id: PositionId,
    pub amount: u64,
    pub expiration: Timestamp,
    pub salt: felt252,
}

#[derive(Copy, Debug, Default, Drop, Hash, PartialEq, Serde, starknet::Store)]
pub struct VaultConfig {
    version: u8,
    is_protocol_vault: bool,
    asset_id: AssetId,
    position_id: u32,
}

#[starknet::interface]
pub trait IVaults<TContractState> {
    fn activate_vault(ref self: TContractState, operator_nonce: u64, order: ConvertPositionToVault);
    fn vault_is_protocol_vault(ref self: TContractState, vault_asset_id: AssetId) -> bool;

    fn is_vault(ref self: TContractState, vault_position: PositionId) -> bool;
}

#[starknet::component]
pub(crate) mod Vaults {
    use core::num::traits::Zero;
    use core::panic_with_felt252;
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use openzeppelin::interfaces::erc4626::{IERC4626Dispatcher, IERC4626DispatcherTrait};
    use openzeppelin::introspection::src5::SRC5Component;
    use perpetuals::core::components::assets::AssetsComponent;
    use perpetuals::core::components::assets::interface::IAssets;
    use perpetuals::core::components::deposit::Deposit as DepositComponent;
    use perpetuals::core::components::deposit::interface::{
        IDepositDispatcher, IDepositDispatcherTrait,
    };
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
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starkware_utils::components::pausable::PausableComponent;
    use starkware_utils::components::pausable::PausableComponent::InternalTrait as PausableInternal;
    use starkware_utils::components::request_approvals::RequestApprovalsComponent;
    use starkware_utils::components::roles::RolesComponent;
    use starkware_utils::storage::iterable_map::{
        IterableMapIntoIterImpl, IterableMapReadAccessImpl, IterableMapWriteAccessImpl,
    };
    use super::{ConvertPositionToVault, IVaults, InvestInVault, STORAGE_VERSION, VaultConfig};

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
            let is_protocol_vault = order.is_protocol_vault;
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

            if (is_protocol_vault) {
                let vault_dispatcher = IProtocolVaultDispatcher {
                    contract_address: asset_config.token_contract.expect('NOT_ERC4626'),
                };
                assert(
                    vault_dispatcher.get_owning_position_id() == vault_position.value,
                    'VAULT_OWNERSHIP_MISMATCH',
                );
            }

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
                        is_protocol_vault,
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
                        is_protocol_vault,
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
        fn vault_is_protocol_vault(
            ref self: ComponentState<TContractState>, vault_asset_id: AssetId,
        ) -> bool {
            let existing_entry = self.registered_vaults_by_asset.read(vault_asset_id);
            assert(existing_entry.version != 0, 'UNKNOWN_VAULT');
            existing_entry.is_protocol_vault
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


        fn _invest_in_vault(ref self: ComponentState<TContractState>, order: InvestInVault) {
            let from_position_id = order.from_position_id;
            let vault_id = order.vault_id;
            let amount = order.amount;
            let expiration = order.expiration;
            let salt = order.salt;

            get_dep_component!(@self, Pausable).assert_not_paused();
            assert(self.is_vault(vault_id), 'NOT_A_VAULT');
            let positions = get_dep_component!(@self, Positions);
            let from_position_info = positions.get_position_snapshot(from_position_id);
            let vault_position_info = positions.get_position_snapshot(vault_id);
            let assets = get_dep_component!(@self, Assets);

            let vault_asset = self.registered_vaults_by_position.read(vault_id);
            assert(vault_asset.version != 0, 'UNKNOWN_VAULT');

            let asset_config = assets.get_asset_config(vault_asset.asset_id);

            let vault_dispatcher = IERC4626Dispatcher {
                contract_address: asset_config.token_contract.expect('NOT_ERC4626'),
            };

            let collateral_token_dispatcher = assets.get_collateral_token_contract();

            let current_collateral_balance = collateral_token_dispatcher
                .balance_of(starknet::get_contract_address());

            let minted_shares = vault_dispatcher
                .deposit(amount.into(), starknet::get_contract_address());

            let deposits_dispatcher = IDepositDispatcher {
                contract_address: starknet::get_contract_address(),
            };

            deposits_dispatcher
                .deposit(
                    asset_id: vault_asset.asset_id,
                    position_id: from_position_id,
                    quantized_amount: minted_shares.into(),
                    salt: salt,
                )
        }
    }
}
