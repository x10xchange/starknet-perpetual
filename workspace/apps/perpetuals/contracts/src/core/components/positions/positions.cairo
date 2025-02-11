#[starknet::component]
pub(crate) mod Positions {
    use contracts_commons::components::nonce::NonceComponent;
    use contracts_commons::components::nonce::NonceComponent::InternalTrait as NonceInternal;
    use contracts_commons::components::pausable::PausableComponent;
    use contracts_commons::components::pausable::PausableComponent::InternalTrait as PausableInternal;
    use contracts_commons::components::request_approvals::RequestApprovalsComponent;
    use contracts_commons::components::request_approvals::RequestApprovalsComponent::InternalTrait as RequestApprovalsInternal;
    use contracts_commons::components::roles::RolesComponent;
    use contracts_commons::components::roles::RolesComponent::InternalTrait as RolesInteral;
    use contracts_commons::message_hash::OffchainMessageHash;
    use contracts_commons::types::time::time::Timestamp;
    use contracts_commons::types::{PublicKey, Signature};
    use contracts_commons::utils::{AddToStorage, validate_expiration, validate_stark_signature};
    use core::num::traits::zero::Zero;
    use core::panic_with_felt252;
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::introspection::src5::SRC5Component;
    use perpetuals::core::components::assets::AssetsComponent;
    use perpetuals::core::components::assets::AssetsComponent::InternalTrait as AssetsInternalTrait;
    use perpetuals::core::components::assets::errors::ASSET_NOT_EXISTS;
    use perpetuals::core::components::positions::errors::{
        ALREADY_INITIALIZED, APPLY_DIFF_MISMATCH, CALLER_IS_NOT_OWNER_ACCOUNT, INVALID_POSITION,
        INVALID_PUBLIC_KEY, NO_OWNER_ACCOUNT, POSITION_ALREADY_EXISTS, POSITION_HAS_OWNER_ACCOUNT,
        SET_POSITION_OWNER_EXPIRED, SET_PUBLIC_KEY_EXPIRED,
    };
    use perpetuals::core::components::positions::events;
    use perpetuals::core::components::positions::interface::IPositions;
    use perpetuals::core::core::Core::SNIP12MetadataImpl;
    use perpetuals::core::types::asset::AssetId;
    use perpetuals::core::types::asset::collateral::{
        CollateralAsset, VERSION as COLLATERAL_VERSION,
    };
    use perpetuals::core::types::asset::synthetic::{SyntheticAsset, VERSION as SYNTHETIC_VERSION};
    use perpetuals::core::types::balance::Balance;
    use perpetuals::core::types::funding::{FundingIndex, FundingIndexMulTrait};
    use perpetuals::core::types::set_owner_account::SetOwnerAccountArgs;
    use perpetuals::core::types::set_public_key::SetPublicKeyArgs;
    use perpetuals::core::types::{AssetEntry, PositionData, PositionDiff, PositionId};
    use starknet::storage::{
        Map, Mutable, StorageMapReadAccess, StoragePath, StoragePathEntry, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_caller_address};

    pub const POSITION_VERSION: u8 = 1;

    pub const FEE_POSITION: PositionId = PositionId { value: 0 };
    pub const INSURANCE_FUND_POSITION: PositionId = PositionId { value: 1 };

    #[starknet::storage_node]
    pub struct Position {
        pub version: u8,
        pub owner_account: ContractAddress,
        pub owner_public_key: PublicKey,
        pub collateral_assets_head: Option<AssetId>,
        pub collateral_assets: Map<AssetId, CollateralAsset>,
        pub synthetic_assets_head: Option<AssetId>,
        pub synthetic_assets: Map<AssetId, SyntheticAsset>,
    }


    #[storage]
    pub struct Storage {
        positions: Map<PositionId, Position>,
    }

    #[event]
    #[derive(Drop, PartialEq, starknet::Event)]
    pub enum Event {
        NewPosition: events::NewPosition,
        SetOwnerAccount: events::SetOwnerAccount,
        SetPublicKey: events::SetPublicKey,
        SetPublicKeyRequest: events::SetPublicKeyRequest,
    }

    #[embeddable_as(PositionsImpl)]
    impl Positions<
        TContractState,
        +HasComponent<TContractState>,
        +Drop<TContractState>,
        impl Assets: AssetsComponent::HasComponent<TContractState>,
        impl Pausable: PausableComponent::HasComponent<TContractState>,
        impl Nonce: NonceComponent::HasComponent<TContractState>,
        impl Roles: RolesComponent::HasComponent<TContractState>,
        impl RequestApprovals: RequestApprovalsComponent::HasComponent<TContractState>,
        +AccessControlComponent::HasComponent<TContractState>,
        +SRC5Component::HasComponent<TContractState>,
    > of IPositions<ComponentState<TContractState>> {
        /// Adds a new position to the system.
        ///
        /// Validations:
        /// - The contract must not be paused.
        /// - The operator nonce must be valid.
        /// - The position does not exist.
        /// - The owner public key is non-zero.
        ///
        /// Execution:
        /// - Create a new position with the given `owner_public_key` and `owner_account`.
        /// - Emit a `NewPosition` event.
        ///
        /// The position can be initialized with `owner_account` that is zero (no owner account).
        /// This is to support the case where it doesn't have a L2 account.
        fn new_position(
            ref self: ComponentState<TContractState>,
            operator_nonce: u64,
            position_id: PositionId,
            owner_public_key: PublicKey,
            owner_account: ContractAddress,
        ) {
            get_dep_component!(@self, Pausable).assert_not_paused();
            get_dep_component!(@self, Roles).only_operator();
            let mut nonce = get_dep_component_mut!(ref self, Nonce);
            nonce.use_checked_nonce(nonce: operator_nonce);
            let mut position = self.positions.entry(position_id);
            assert(position.version.read().is_zero(), POSITION_ALREADY_EXISTS);
            assert(owner_public_key.is_non_zero(), INVALID_PUBLIC_KEY);
            position.version.write(POSITION_VERSION);
            position.owner_public_key.write(owner_public_key);
            position.owner_account.write(owner_account);
            self
                .emit(
                    events::NewPosition {
                        position_id: position_id,
                        owner_public_key: owner_public_key,
                        owner_account: owner_account,
                    },
                );
        }
        /// Sets the owner of a position to a new account owner.
        ///
        /// Validations:
        /// - The contract must not be paused.
        /// - The caller must be the operator.
        /// - The operator nonce must be valid.
        /// - The expiration time has not passed.
        /// - The position has no account owner.
        /// - The signature is valid.
        fn set_owner_account(
            ref self: ComponentState<TContractState>,
            operator_nonce: u64,
            signature: Signature,
            position_id: PositionId,
            public_key: PublicKey,
            new_account_owner: ContractAddress,
            expiration: Timestamp,
        ) {
            get_dep_component!(@self, Pausable).assert_not_paused();
            get_dep_component!(@self, Roles).only_operator();
            let mut nonce = get_dep_component_mut!(ref self, Nonce);
            nonce.use_checked_nonce(nonce: operator_nonce);
            validate_expiration(:expiration, err: SET_POSITION_OWNER_EXPIRED);
            let position = self._get_position_mut(:position_id);
            assert(position.owner_account.read().is_zero(), POSITION_HAS_OWNER_ACCOUNT);
            let hash = SetOwnerAccountArgs {
                position_id, public_key, new_account_owner, expiration,
            }
                .get_message_hash(public_key: position.owner_public_key.read());
            validate_stark_signature(
                public_key: position.owner_public_key.read(), msg_hash: hash, signature: signature,
            );
            position.owner_account.write(new_account_owner);
            self
                .emit(
                    events::SetOwnerAccount {
                        position_id: position_id,
                        public_key,
                        new_position_owner: new_account_owner,
                        expiration: expiration,
                        set_owner_account_hash: hash,
                    },
                );
        }

        /// Registers a request to set the position's public key.
        ///
        /// Validations:
        /// - Validates the signature.
        /// - Validates the position exists.
        /// - Validates the called is the owner of the position.
        /// - Validates the request does not exist.
        ///
        /// Execution:
        /// - Registers the set public key request.
        /// - Emits a `SetPublicKeyRequest` event.
        fn set_public_key_request(
            ref self: ComponentState<TContractState>,
            signature: Signature,
            position_id: PositionId,
            new_public_key: PublicKey,
            expiration: Timestamp,
        ) {
            let position = self._get_position_const(:position_id);
            let owner_account = position.owner_account.read();
            assert(owner_account == get_caller_address(), CALLER_IS_NOT_OWNER_ACCOUNT);
            let mut request_approvals = get_dep_component_mut!(ref self, RequestApprovals);
            let hash = request_approvals
                .register_approval(
                    :owner_account,
                    public_key: new_public_key,
                    :signature,
                    args: SetPublicKeyArgs { position_id, expiration, new_public_key },
                );
            self
                .emit(
                    events::SetPublicKeyRequest {
                        position_id,
                        new_public_key,
                        expiration: expiration,
                        set_public_key_request_hash: hash,
                    },
                );
        }

        // TODO: talk about this flow
        /// Sets the position's public key.
        ///
        /// Validations:
        /// - The contract must not be paused.
        /// - The operator nonce must be valid.
        /// - The expiration time has not passed.
        /// - The position has an owner account.
        /// - The request has been registered.
        fn set_public_key(
            ref self: ComponentState<TContractState>,
            operator_nonce: u64,
            position_id: PositionId,
            new_public_key: PublicKey,
            expiration: Timestamp,
        ) {
            get_dep_component!(@self, Pausable).assert_not_paused();
            get_dep_component!(@self, Roles).only_operator();
            let mut nonce = get_dep_component_mut!(ref self, Nonce);
            nonce.use_checked_nonce(nonce: operator_nonce);
            validate_expiration(:expiration, err: SET_PUBLIC_KEY_EXPIRED);
            let position = self._get_position_mut(:position_id);
            let owner_account = position.owner_account.read();
            assert(owner_account.is_non_zero(), NO_OWNER_ACCOUNT);
            let mut request_approvals = get_dep_component_mut!(ref self, RequestApprovals);
            let hash = request_approvals
                .consume_approved_request(
                    args: SetPublicKeyArgs { position_id, expiration, new_public_key },
                    public_key: new_public_key,
                );
            position.owner_public_key.write(new_public_key);
            self
                .emit(
                    events::SetPublicKey {
                        position_id,
                        new_public_key: new_public_key,
                        expiration: expiration,
                        set_public_key_request_hash: hash,
                    },
                );
        }
    }

    #[generate_trait]
    pub impl InternalImpl<
        TContractState,
        +HasComponent<TContractState>,
        +Drop<TContractState>,
        impl Assets: AssetsComponent::HasComponent<TContractState>,
        impl Pausable: PausableComponent::HasComponent<TContractState>,
        impl Nonce: NonceComponent::HasComponent<TContractState>,
        impl Roles: RolesComponent::HasComponent<TContractState>,
        impl RequestApprovals: RequestApprovalsComponent::HasComponent<TContractState>,
        +AccessControlComponent::HasComponent<TContractState>,
        +SRC5Component::HasComponent<TContractState>,
    > of InternalTrait<TContractState> {
        fn initialize(
            ref self: ComponentState<TContractState>,
            fee_position_owner_account: ContractAddress,
            fee_position_owner_public_key: PublicKey,
            insurance_fund_position_owner_account: ContractAddress,
            insurance_fund_position_owner_public_key: PublicKey,
        ) {
            let fee_position = self.positions.entry(FEE_POSITION);
            // Checks that the component has not been initialized yet.
            assert(fee_position.version.read().is_zero(), ALREADY_INITIALIZED);
            // Create fee positions.
            fee_position.version.write(POSITION_VERSION);
            fee_position.owner_account.write(fee_position_owner_account);
            fee_position.owner_public_key.write(fee_position_owner_public_key);

            let insurance_fund_position = self.positions.entry(INSURANCE_FUND_POSITION);
            insurance_fund_position.version.write(POSITION_VERSION);
            insurance_fund_position.owner_account.write(insurance_fund_position_owner_account);
            insurance_fund_position
                .owner_public_key
                .write(insurance_fund_position_owner_public_key);
        }

        fn apply_diff(
            ref self: ComponentState<TContractState>,
            position_id: PositionId,
            asset_diff_entries: PositionDiff,
        ) {
            for diff in asset_diff_entries {
                let asset_id = *diff.id;
                let balance = self.get_provisional_balance(:position_id, :asset_id);
                assert(*diff.before == balance, APPLY_DIFF_MISMATCH);
                self._apply_funding_and_set_balance(:position_id, :asset_id, balance: *diff.after);
            }
        }

        fn get_position_const(
            self: @ComponentState<TContractState>, position_id: PositionId,
        ) -> StoragePath<Position> {
            self._get_position_const(:position_id)
        }

        fn get_position_data(
            self: @ComponentState<TContractState>, position_id: PositionId,
        ) -> PositionData {
            let mut asset_entries = array![];
            self._validate_position_exists(:position_id);
            self._collect_position_collateral(ref :asset_entries, :position_id);
            self._collect_position_synthetics(ref :asset_entries, :position_id);
            PositionData { asset_entries: asset_entries.span() }
        }

        /// Returns the position at the given `position_id`.
        /// The function asserts that the position exists and has a non-zero owner public key.
        fn get_position_mut(
            ref self: ComponentState<TContractState>, position_id: PositionId,
        ) -> StoragePath<Mutable<Position>> {
            self._get_position_mut(:position_id)
        }

        fn get_provisional_balance(
            self: @ComponentState<TContractState>, position_id: PositionId, asset_id: AssetId,
        ) -> Balance {
            let assets = get_dep_component!(self, Assets);
            if assets.is_collateral(:asset_id) {
                self._get_provisional_main_collateral_balance(:position_id)
            } else if assets.is_synthetic(:asset_id) {
                self
                    ._get_position_const(:position_id)
                    .synthetic_assets
                    .entry(asset_id)
                    .balance
                    .read()
            } else {
                panic_with_felt252(ASSET_NOT_EXISTS)
            }
        }


        fn update_collateral_in_position(
            ref self: ComponentState<TContractState>,
            position: StoragePath<Mutable<Position>>,
            collateral_id: AssetId,
        ) {
            let collateral_entry = position.collateral_assets.entry(collateral_id);
            if (collateral_entry.version.read().is_zero()) {
                collateral_entry.version.write(COLLATERAL_VERSION);
                collateral_entry.next.write(position.collateral_assets_head.read());
                position.collateral_assets_head.write(Option::Some(collateral_id));
            }
        }
    }

    #[generate_trait]
    pub impl PrivateImpl<
        TContractState,
        +HasComponent<TContractState>,
        +Drop<TContractState>,
        impl Assets: AssetsComponent::HasComponent<TContractState>,
        impl Pausable: PausableComponent::HasComponent<TContractState>,
        impl Nonce: NonceComponent::HasComponent<TContractState>,
        impl Roles: RolesComponent::HasComponent<TContractState>,
        impl RequestApprovals: RequestApprovalsComponent::HasComponent<TContractState>,
        +AccessControlComponent::HasComponent<TContractState>,
        +SRC5Component::HasComponent<TContractState>,
    > of PrivateTrait<TContractState> {
        fn _calc_funding(
            self: @ComponentState<TContractState>,
            position_id: PositionId,
            synthetic_id: AssetId,
            curr_funding_index: FundingIndex,
        ) -> Balance {
            let position = self._get_position_const(:position_id);
            let synthetic_asset = position.synthetic_assets.entry(synthetic_id);
            let synthetic_balance = synthetic_asset.balance.read();
            let last_funding_index = synthetic_asset.funding_index.read();
            (curr_funding_index - last_funding_index).mul(synthetic_balance)
        }

        /// Returns the position at the given `position_id`.
        /// The function asserts that the position exists and has a non-zero owner public key.
        fn _get_position_mut(
            ref self: ComponentState<TContractState>, position_id: PositionId,
        ) -> StoragePath<Mutable<Position>> {
            let mut position = self.positions.entry(position_id);
            assert(position.owner_public_key.read().is_non_zero(), INVALID_POSITION);
            position
        }

        fn _get_position_const(
            self: @ComponentState<TContractState>, position_id: PositionId,
        ) -> StoragePath<Position> {
            let position = self.positions.entry(position_id);
            assert(position.owner_public_key.read().is_non_zero(), INVALID_POSITION);
            position
        }

        /// Returns the main collateral balance of a position while taking into account the funding
        /// of all synthetic assets in the position.
        fn _get_provisional_main_collateral_balance(
            self: @ComponentState<TContractState>, position_id: PositionId,
        ) -> Balance {
            let assets = get_dep_component!(self, Assets);
            let position = self._get_position_const(:position_id);
            let mut main_collateral_balance = position
                .collateral_assets
                .entry(assets.get_main_collateral_asset_id())
                .balance
                .read();
            let mut asset_id_opt = position.synthetic_assets_head.read();
            while let Option::Some(synthetic_id) = asset_id_opt {
                let curr_funding_index = assets.get_funding_index(:synthetic_id);
                let funding = self._calc_funding(:position_id, :synthetic_id, :curr_funding_index);
                main_collateral_balance += funding;
                asset_id_opt = position.synthetic_assets.entry(synthetic_id).next.read();
            };
            main_collateral_balance
        }

        fn _validate_position_exists(
            self: @ComponentState<TContractState>, position_id: PositionId,
        ) {
            self._get_position_const(:position_id);
        }

        /// We only have one collateral asset.
        fn _collect_position_collateral(
            self: @ComponentState<TContractState>,
            ref asset_entries: Array<AssetEntry>,
            position_id: PositionId,
        ) {
            let assets = get_dep_component!(self, Assets);
            let position = self._get_position_const(:position_id);
            let mut asset_id_opt = position.collateral_assets_head.read();

            if let Option::Some(collateral_id) = asset_id_opt {
                let balance = self._get_provisional_main_collateral_balance(:position_id);
                if balance.is_non_zero() {
                    asset_entries
                        .append(
                            AssetEntry {
                                id: collateral_id,
                                balance,
                                price: assets.get_collateral_price(:collateral_id),
                                risk_factor: assets.get_risk_factor(asset_id: collateral_id),
                            },
                        );
                }
            };
        }

        fn _collect_position_synthetics(
            self: @ComponentState<TContractState>,
            ref asset_entries: Array<AssetEntry>,
            position_id: PositionId,
        ) {
            let assets = get_dep_component!(self, Assets);
            let position = self._get_position_const(:position_id);
            let mut asset_id_opt = position.synthetic_assets_head.read();
            while let Option::Some(synthetic_id) = asset_id_opt {
                let synthetic_asset = position.synthetic_assets.read(synthetic_id);
                let balance = self.get_provisional_balance(:position_id, asset_id: synthetic_id);
                if balance.is_non_zero() {
                    asset_entries
                        .append(
                            AssetEntry {
                                id: synthetic_id,
                                balance,
                                price: assets.get_synthetic_price(:synthetic_id),
                                risk_factor: assets.get_risk_factor(asset_id: synthetic_id),
                            },
                        );
                }
                asset_id_opt = synthetic_asset.next;
            };
        }

        fn _update_synthetic_in_position(
            ref self: ComponentState<TContractState>,
            position: StoragePath<Mutable<Position>>,
            synthetic_id: AssetId,
        ) {
            let synthetic_entry = position.synthetic_assets.entry(synthetic_id);
            if (synthetic_entry.version.read().is_zero()) {
                synthetic_entry.version.write(SYNTHETIC_VERSION);
                synthetic_entry.next.write(position.synthetic_assets_head.read());
                position.synthetic_assets_head.write(Option::Some(synthetic_id));
            }
        }

        /// Updates the balance of a given asset, determining its type (collateral or synthetic)
        /// and applying the appropriate logic.
        fn _apply_funding_and_set_balance(
            ref self: ComponentState<TContractState>,
            position_id: PositionId,
            asset_id: AssetId,
            balance: Balance,
        ) {
            let assets = get_dep_component!(@self, Assets);
            if assets.is_collateral(:asset_id) {
                let mut position = self._get_position_mut(:position_id);
                self.update_collateral_in_position(position, collateral_id: asset_id);
                position.collateral_assets.entry(asset_id).balance.write(balance);
            } else {
                self
                    ._update_synthetic_balance_and_funding(
                        :position_id, synthetic_id: asset_id, :balance,
                    );
            }
        }

        /// Updates the synthetic balance and handles the funding mechanism.
        /// This function adjusts the main collateral balance of a position by applying funding
        /// costs or earnings based on the difference between the global funding index and the
        /// current funding index.
        ///
        /// The main collateral balance is updated using the following formula:
        /// main_collateral_balance += synthetic_balance * (global_funding_index - funding_index).
        /// After the adjustment, the `funding_index` is set to `global_funding_index`.
        ///
        /// Example:
        /// main_collateral_balance = 1000;
        /// synthetic_balance = 50;
        /// funding_index = 200;
        /// global_funding_index = 210;
        ///
        /// new_synthetic_balance = 300;
        ///
        /// After the update:
        /// main_collateral_balance = 1500; // 1000 + 50 * (210 - 200)
        /// synthetic_balance = 300;
        /// synthetic_funding_index = 210;
        ///
        fn _update_synthetic_balance_and_funding(
            ref self: ComponentState<TContractState>,
            position_id: PositionId,
            synthetic_id: AssetId,
            balance: Balance,
        ) {
            let assets = get_dep_component!(@self, Assets);
            let position = self._get_position_mut(:position_id);
            let mut main_collateral_balance = position
                .collateral_assets
                .entry(assets.get_main_collateral_asset_id())
                .balance;
            let curr_funding_index = assets.get_funding_index(:synthetic_id);
            let funding = self._calc_funding(:position_id, :synthetic_id, :curr_funding_index);
            main_collateral_balance.add_and_write(funding);
            self._update_synthetic_in_position(:position, :synthetic_id);
            let synthetic_asset = position.synthetic_assets.entry(synthetic_id);
            synthetic_asset.balance.write(balance);
            synthetic_asset.funding_index.write(curr_funding_index);
        }
    }
}
