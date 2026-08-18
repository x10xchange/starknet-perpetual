//! Dedicated dump host for `Core`'s storage: exposes the COMPLETE
//! batched export surface (`IDump` + `IDumpExtra`), which does not
//! fit inside `Core` next to the trading logic (Core is near Starknet's max
//! class size). A full dump is `export_config()` (one call) +
//! `export_asset_ids()` (one call) + `export_assets` pages + `export_positions` pages +
//! `export_keyed` pages — see dump.cairo. The
//! only state NOT covered is the request-approvals maps (upstream component
//! internals are private): read `approved_requests` per-hash via
//! `get_request_status` on the live Core class, and `forced_action_requests`
//! via raw `starknet_getStorageAt`.
//!
//! Storage-compatible with `Core` by construction: it declares the exact same
//! component substorages (same names), including the shared
//! `CoreFieldsComponent` hosting Core's own contract-level fields, so every
//! storage address coincides and the two classes cannot silently drift on
//! those fields. It has no trading entrypoints and is meant to be used on a
//! disposable fork / staging deployment only: `replace_to` this class, call
//! `export_*`, optionally `replace_to` back to the original Core class.
//!
//! All export entrypoints are read-only views. The class ALSO embeds
//! `RolesImpl` and `ReplaceabilityImpl`, which are external and MUTATING: they
//! are what make the swap reversible (the final `replace_to` back onto the
//! real Core class), and `Core` embeds the identical impls at the same
//! selectors. After `replace_class_syscall` the address and storage tree are
//! unchanged, so writes through those entrypoints land on live `Core` state.
#[starknet::contract]
pub mod DumpCore {
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::introspection::src5::SRC5Component;
    use perpetuals::core::components::assets::AssetsComponent;
    use perpetuals::core::components::assets::AssetsComponent::DumpTrait as AssetsDumpTrait;
    use perpetuals::core::components::assets::interface::AssetDump;
    use perpetuals::core::components::core_fields::CoreFieldsComponent;
    use perpetuals::core::components::deposit::Deposit;
    use perpetuals::core::components::deposit_limits::DepositLimits as DepositLimitsComponent;
    use perpetuals::core::components::exchange_time::ExchangeTimeComponent;
    use perpetuals::core::components::exchange_time::ExchangeTimeComponent::DumpTrait as ExchangeTimeDumpTrait;
    use perpetuals::core::components::external_components::interface::{
        EXTERNAL_COMPONENT_ASSETS, EXTERNAL_COMPONENT_DELEVERAGES, EXTERNAL_COMPONENT_DEPOSITS,
        EXTERNAL_COMPONENT_FORCED_REQUESTS, EXTERNAL_COMPONENT_LIQUIDATIONS,
        EXTERNAL_COMPONENT_TRANSFERS, EXTERNAL_COMPONENT_VAULT, EXTERNAL_COMPONENT_WITHDRAWALS,
    };
    use perpetuals::core::components::operator_nonce::OperatorNonceComponent;
    use perpetuals::core::components::operator_nonce::OperatorNonceComponent::DumpTrait as OperatorNonceDumpTrait;
    use perpetuals::core::components::positions::Positions;
    use perpetuals::core::components::positions::Positions::DumpTrait as PositionsDumpTrait;
    use perpetuals::core::components::positions::interface::PositionDump;
    use perpetuals::core::dump::{
        ConfigDump, CoreDumpScalars, ExternalComponentEntry, IDump, IDumpExtra, KeySets, KeyedDump,
    };
    use perpetuals::core::types::asset::AssetId;
    use perpetuals::core::types::position::PositionId;
    use starknet::storage::{StorageMapReadAccess, StoragePointerReadAccess};
    use starkware_utils::components::pausable::PausableComponent;
    use starkware_utils::components::replaceability::ReplaceabilityComponent;
    use starkware_utils::components::request_approvals::RequestApprovalsComponent;
    use starkware_utils::components::roles::RolesComponent;
    use crate::core::components::external_components::external_component_manager::ExternalComponents as ExternalComponentsComponent;
    use crate::core::components::fulfillment::fulfillment::Fulfillement;
    use crate::core::components::vaults::vaults::Vaults as VaultsComponent;
    use crate::core::components::vaults::vaults::Vaults::DumpTrait as VaultsDumpTrait;

    component!(path: AccessControlComponent, storage: accesscontrol, event: AccessControlEvent);
    component!(path: OperatorNonceComponent, storage: operator_nonce, event: OperatorNonceEvent);
    component!(path: PausableComponent, storage: pausable, event: PausableEvent);
    component!(path: ExchangeTimeComponent, storage: exchange_time, event: ExchangeTimeEvent);
    component!(path: ReplaceabilityComponent, storage: replaceability, event: ReplaceabilityEvent);
    component!(path: RolesComponent, storage: roles, event: RolesEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);
    component!(path: AssetsComponent, storage: assets, event: AssetsEvent);
    component!(path: Deposit, storage: deposits, event: DepositEvent);
    component!(
        path: RequestApprovalsComponent, storage: request_approvals, event: RequestApprovalsEvent,
    );
    component!(path: Positions, storage: positions, event: PositionsEvent);
    component!(path: Fulfillement, storage: fulfillment_tracking, event: FulfillmentEvent);
    component!(
        path: ExternalComponentsComponent,
        storage: external_components,
        event: ExternalComponentsEvent,
    );
    component!(path: VaultsComponent, storage: vaults, event: VaultsEvent);
    component!(path: DepositLimitsComponent, storage: deposit_limits, event: DepositLimitsEvent);
    component!(path: CoreFieldsComponent, storage: core_fields, event: CoreFieldsEvent);

    // Governance + upgradability are the only functional surfaces: the source
    // needs the final replace_to back onto the real Core class; is_paused is
    // exposed for spot checks.
    #[abi(embed_v0)]
    impl RolesImpl = RolesComponent::RolesImpl<ContractState>;

    #[abi(embed_v0)]
    impl ReplaceabilityImpl =
        ReplaceabilityComponent::ReplaceabilityImpl<ContractState>;

    #[abi(embed_v0)]
    impl PausableImpl = PausableComponent::PausableImpl<ContractState>;

    #[storage]
    struct Storage {
        // --- Components (identical names/types to Core -> identical storage
        // addresses) ---
        #[substorage(v0)]
        accesscontrol: AccessControlComponent::Storage,
        #[substorage(v0)]
        operator_nonce: OperatorNonceComponent::Storage,
        #[substorage(v0)]
        pausable: PausableComponent::Storage,
        #[substorage(v0)]
        exchange_time: ExchangeTimeComponent::Storage,
        #[substorage(v0)]
        pub replaceability: ReplaceabilityComponent::Storage,
        #[substorage(v0)]
        pub roles: RolesComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        #[substorage(v0)]
        #[allow(starknet::colliding_storage_paths)]
        pub assets: AssetsComponent::Storage,
        #[substorage(v0)]
        pub deposits: Deposit::Storage,
        #[substorage(v0)]
        pub request_approvals: RequestApprovalsComponent::Storage,
        #[substorage(v0)]
        pub positions: Positions::Storage,
        #[substorage(v0)]
        pub fulfillment_tracking: Fulfillement::Storage,
        #[substorage(v0)]
        pub external_components: ExternalComponentsComponent::Storage,
        #[substorage(v0)]
        pub vaults: VaultsComponent::Storage,
        #[substorage(v0)]
        pub deposit_limits: DepositLimitsComponent::Storage,
        // --- Core's own contract-level fields, via the component shared with
        // `Core` (single definition, so the two classes cannot drift) ---
        #[substorage(v0)]
        pub core_fields: CoreFieldsComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        AccessControlEvent: AccessControlComponent::Event,
        #[flat]
        OperatorNonceEvent: OperatorNonceComponent::Event,
        #[flat]
        PausableEvent: PausableComponent::Event,
        #[flat]
        ExchangeTimeEvent: ExchangeTimeComponent::Event,
        #[flat]
        ReplaceabilityEvent: ReplaceabilityComponent::Event,
        #[flat]
        RolesEvent: RolesComponent::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
        #[flat]
        AssetsEvent: AssetsComponent::Event,
        #[flat]
        DepositEvent: Deposit::Event,
        #[flat]
        RequestApprovalsEvent: RequestApprovalsComponent::Event,
        #[flat]
        PositionsEvent: Positions::Event,
        #[flat]
        FulfillmentEvent: Fulfillement::Event,
        #[flat]
        ExternalComponentsEvent: ExternalComponentsComponent::Event,
        #[flat]
        VaultsEvent: VaultsComponent::Event,
        #[flat]
        DepositLimitsEvent: DepositLimitsComponent::Event,
        #[flat]
        CoreFieldsEvent: CoreFieldsComponent::Event,
    }

    /// The subset shared with `Core` — same declaration, hence the same
    /// selectors and signatures by construction.
    #[abi(embed_v0)]
    pub impl DumpImpl of IDump<ContractState> {
        fn export_positions(
            self: @ContractState, position_ids: Array<PositionId>,
        ) -> Array<PositionDump> {
            self.positions.export_positions(position_ids)
        }

        fn export_core_scalars(self: @ContractState) -> CoreDumpScalars {
            CoreDumpScalars {
                forced_action_timelock: self.core_fields.forced_action_timelock.read(),
                premium_cost: self.core_fields.premium_cost.read(),
                forced_actions_enabled: self.core_fields.forced_actions_enabled.read(),
                interest_divergence: self.positions.interest_divergence.read(),
            }
        }
    }

    #[abi(embed_v0)]
    pub impl DumpExtraImpl of IDumpExtra<ContractState> {
        /// The entire scalar config plane in one constant-cost call.
        fn export_config(self: @ContractState) -> ConfigDump {
            let mut external_components = array![];
            for component_type in array![
                EXTERNAL_COMPONENT_VAULT, EXTERNAL_COMPONENT_WITHDRAWALS,
                EXTERNAL_COMPONENT_TRANSFERS, EXTERNAL_COMPONENT_LIQUIDATIONS,
                EXTERNAL_COMPONENT_DELEVERAGES, EXTERNAL_COMPONENT_DEPOSITS,
                EXTERNAL_COMPONENT_ASSETS, EXTERNAL_COMPONENT_FORCED_REQUESTS,
            ] {
                let (registered_class_hash, registered_at) = self
                    .external_components
                    .registered_external_components
                    .read(component_type);
                external_components
                    .append(
                        ExternalComponentEntry {
                            component_type,
                            registered_class_hash,
                            registered_at,
                            implementation: self
                                .external_components
                                .external_component_implementations
                                .read(component_type),
                        },
                    );
            }
            ConfigDump {
                operator_nonce: self.operator_nonce.export_nonce(),
                exchange_time: self.exchange_time.export_exchange_time(),
                last_time_of_exchange_time_update: self
                    .exchange_time
                    .export_last_time_of_exchange_time_update(),
                paused: self.pausable.paused.read(),
                deposit_cancel_delay: self.deposits.cancel_delay.read(),
                max_interest_rate_per_sec: self.positions.max_interest_rate_per_sec.read(),
                treasury_address: self.core_fields.treasury.contract_address.read(),
                core: self.export_core_scalars(),
                assets: self.assets.export_assets_scalars(),
                external_components,
            }
        }

        fn export_asset_ids(self: @ContractState) -> Array<AssetId> {
            self.assets.export_asset_ids()
        }

        fn export_assets(self: @ContractState, asset_ids: Array<AssetId>) -> Array<AssetDump> {
            self.assets.export_assets(:asset_ids)
        }

        /// Every event-keyed map in one call per page of keys.
        fn export_keyed(self: @ContractState, keys: KeySets) -> KeyedDump {
            let mut deposit_statuses = array![];
            let mut hashes = keys.deposit_hashes;
            while let Option::Some(hash) = hashes.pop_front() {
                deposit_statuses.append(self.deposits.registered_deposits.read(hash));
            }

            let mut fulfillments = array![];
            let mut hashes = keys.fulfillment_hashes;
            while let Option::Some(hash) = hashes.pop_front() {
                fulfillments.append(self.fulfillment_tracking.fulfillment.read(hash));
            }

            let mut vaults_by_asset = array![];
            let mut ids = keys.vault_asset_ids;
            while let Option::Some(asset_id) = ids.pop_front() {
                vaults_by_asset.append(self.vaults.export_vault_by_asset(asset_id));
            }

            let mut vaults_by_position = array![];
            let mut ids = keys.vault_position_ids;
            while let Option::Some(position_id) = ids.pop_front() {
                vaults_by_position.append(self.vaults.export_vault_by_position(position_id));
            }

            let mut vault_limit_overrides = array![];
            let mut ids = keys.vault_limit_override_position_ids;
            while let Option::Some(position_id) = ids.pop_front() {
                vault_limit_overrides
                    .append(self.vaults.export_vault_protection_limit_override(position_id));
            }

            let mut max_deposits = array![];
            let mut tokens = keys.deposit_limit_tokens;
            while let Option::Some(token) = tokens.pop_front() {
                max_deposits.append(self.deposit_limits.max_deposits.read(token));
            }

            KeyedDump {
                deposit_statuses,
                fulfillments,
                oracle_values: self.assets.export_asset_oracle(keys.oracle_entries),
                vaults_by_asset,
                vaults_by_position,
                vault_limit_overrides,
                max_deposits,
            }
        }
    }
}
