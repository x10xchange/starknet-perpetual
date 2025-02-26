#[starknet::component]
pub(crate) mod Positions {
    use contracts_commons::components::nonce::NonceComponent;
    use contracts_commons::components::nonce::NonceComponent::InternalTrait as NonceInternal;
    use contracts_commons::components::pausable::PausableComponent;
    use contracts_commons::components::pausable::PausableComponent::InternalTrait as PausableInternal;
    use contracts_commons::components::request_approvals::RequestApprovalsComponent;
    use contracts_commons::components::request_approvals::RequestApprovalsComponent::InternalTrait as RequestApprovalsInternal;
    use contracts_commons::components::roles::RolesComponent;
    use contracts_commons::components::roles::RolesComponent::InternalTrait as RolesInternal;
    use contracts_commons::types::time::time::Timestamp;
    use contracts_commons::types::{PublicKey, Signature};
    use contracts_commons::utils::{AddToStorage, validate_expiration};
    use core::num::traits::zero::Zero;
    use core::panic_with_felt252;
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::introspection::src5::SRC5Component;
    use perpetuals::core::components::assets::AssetsComponent;
    use perpetuals::core::components::assets::AssetsComponent::InternalTrait as AssetsInternalTrait;
    use perpetuals::core::components::assets::errors::ASSET_NOT_EXISTS;
    use perpetuals::core::components::positions::errors::{
        ALREADY_INITIALIZED, APPLY_DIFF_MISMATCH, CALLER_IS_NOT_OWNER_ACCOUNT,
        INVALID_ZERO_OWNER_ACCOUNT, INVALID_ZERO_PUBLIC_KEY, NO_OWNER_ACCOUNT,
        POSITION_ALREADY_EXISTS, POSITION_DOESNT_EXIST, POSITION_HAS_OWNER_ACCOUNT, SAME_PUBLIC_KEY,
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
    use perpetuals::core::types::{Asset, PositionData, PositionDiff, PositionId};
    use perpetuals::core::value_risk_calculator::PositionTVTR;
    use perpetuals::core::value_risk_calculator::{
        PositionState, calculate_position_tvtr, evaluate_position,
    };
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
        SetOwnerAccountRequest: events::SetOwnerAccountRequest,
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
        fn get_position_assets(
            self: @ComponentState<TContractState>, position_id: PositionId,
        ) -> PositionData {
            self.get_position_data(position: self._get_position_snapshot(:position_id))
        }

        /// This function is primarily used as a view function—knowing the total value and/or
        /// total risk without context is unnecessary.
        fn get_position_tv_tr(
            self: @ComponentState<TContractState>, position_id: PositionId,
        ) -> PositionTVTR {
            let position = self._get_position_snapshot(:position_id);
            let position_data = self.get_position_data(:position);
            calculate_position_tvtr(:position_data)
        }

        /// This function is mostly used as view function - it's better to use the
        /// `evaluate_position_change` function as it gives all the information needed at the same
        /// cost.
        fn is_healthy(self: @ComponentState<TContractState>, position_id: PositionId) -> bool {
            let position_state = self._get_position_state(:position_id);
            position_state == PositionState::Healthy
        }

        /// This function is mostly used as view function - it's better to use the
        /// `evaluate_position_change` function as it gives all the information needed at the same
        /// cost.
        fn is_liquidatable(self: @ComponentState<TContractState>, position_id: PositionId) -> bool {
            let position_state = self._get_position_state(:position_id);
            position_state == PositionState::Liquidatable
                || position_state == PositionState::Deleveragable
        }

        /// This function is mostly used as view function - it's better to use the
        /// `evaluate_position_change` function as it gives all the information needed at the same
        /// cost.
        fn is_deleveragable(
            self: @ComponentState<TContractState>, position_id: PositionId,
        ) -> bool {
            let position_state = self._get_position_state(:position_id);
            position_state == PositionState::Deleveragable
        }

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
            assert(owner_public_key.is_non_zero(), INVALID_ZERO_PUBLIC_KEY);
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

        /// Registers a request to set the position's owner_account.
        ///
        /// Validations:
        /// - Validates the signature.
        /// - Validates the position exists.
        /// - Validates the caller is the new_owner_account.
        /// - Validates the request does not exist.
        ///
        /// Execution:
        /// - Registers the set owner account request.
        /// - Emits a `SetOwnerAccountRequest` event.
        fn set_owner_account_request(
            ref self: ComponentState<TContractState>,
            signature: Signature,
            position_id: PositionId,
            new_owner_account: ContractAddress,
            expiration: Timestamp,
        ) {
            let position = self._get_position_snapshot(:position_id);
            let owner_account = position.owner_account.read();
            assert(owner_account.is_zero(), POSITION_HAS_OWNER_ACCOUNT);
            assert(new_owner_account.is_non_zero(), INVALID_ZERO_OWNER_ACCOUNT);
            let public_key = position.owner_public_key.read();
            let mut request_approvals = get_dep_component_mut!(ref self, RequestApprovals);
            let hash = request_approvals
                .register_approval(
                    owner_account: new_owner_account,
                    :public_key,
                    :signature,
                    args: SetOwnerAccountArgs {
                        position_id, public_key, new_owner_account, expiration,
                    },
                );
            self
                .emit(
                    events::SetOwnerAccountRequest {
                        position_id,
                        public_key,
                        new_owner_account,
                        expiration,
                        set_owner_account_hash: hash,
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
            position_id: PositionId,
            new_owner_account: ContractAddress,
            expiration: Timestamp,
        ) {
            get_dep_component!(@self, Pausable).assert_not_paused();
            get_dep_component!(@self, Roles).only_operator();
            let mut nonce = get_dep_component_mut!(ref self, Nonce);
            nonce.use_checked_nonce(nonce: operator_nonce);
            validate_expiration(:expiration, err: SET_POSITION_OWNER_EXPIRED);
            let position = self._get_position_mut(:position_id);
            assert(position.owner_account.read().is_zero(), POSITION_HAS_OWNER_ACCOUNT);
            let mut request_approvals = get_dep_component_mut!(ref self, RequestApprovals);
            let public_key = position.owner_public_key.read();
            let hash = request_approvals
                .consume_approved_request(
                    args: SetOwnerAccountArgs {
                        position_id, public_key, new_owner_account, expiration,
                    },
                    :public_key,
                );
            position.owner_account.write(new_owner_account);
            self
                .emit(
                    events::SetOwnerAccount {
                        position_id, public_key, new_owner_account, set_owner_account_hash: hash,
                    },
                );
        }

        /// Registers a request to set the position's public key.
        ///
        /// Validations:
        /// - Validates the signature.
        /// - Validates the position exists.
        /// - Validates the caller is the owner of the position.
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
            let position = self._get_position_snapshot(:position_id);
            let owner_account = position.owner_account.read();
            let old_public_key = position.owner_public_key.read();
            assert(owner_account == get_caller_address(), CALLER_IS_NOT_OWNER_ACCOUNT);
            assert(new_public_key != old_public_key, SAME_PUBLIC_KEY);
            let mut request_approvals = get_dep_component_mut!(ref self, RequestApprovals);
            let hash = request_approvals
                .register_approval(
                    :owner_account,
                    public_key: new_public_key,
                    :signature,
                    args: SetPublicKeyArgs {
                        position_id, old_public_key, new_public_key, expiration,
                    },
                );
            self
                .emit(
                    events::SetPublicKeyRequest {
                        position_id,
                        new_public_key,
                        old_public_key,
                        expiration,
                        set_public_key_request_hash: hash,
                    },
                );
        }

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
            let old_public_key = position.owner_public_key.read();
            assert(owner_account.is_non_zero(), NO_OWNER_ACCOUNT);
            let mut request_approvals = get_dep_component_mut!(ref self, RequestApprovals);
            let hash = request_approvals
                .consume_approved_request(
                    args: SetPublicKeyArgs {
                        position_id, old_public_key, new_public_key, expiration,
                    },
                    public_key: new_public_key,
                );
            position.owner_public_key.write(new_public_key);
            self
                .emit(
                    events::SetPublicKey {
                        position_id,
                        new_public_key,
                        old_public_key,
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
            fee_position_owner_public_key: PublicKey,
            insurance_fund_position_owner_public_key: PublicKey,
        ) {
            // Checks that the component has not been initialized yet.
            let fee_position = self.positions.entry(FEE_POSITION);
            assert(fee_position.owner_public_key.read().is_zero(), ALREADY_INITIALIZED);

            // Checks that the input public keys are non-zero.
            assert(fee_position_owner_public_key.is_non_zero(), INVALID_ZERO_PUBLIC_KEY);
            assert(insurance_fund_position_owner_public_key.is_non_zero(), INVALID_ZERO_PUBLIC_KEY);

            // Create fee positions.
            fee_position.version.write(POSITION_VERSION);
            fee_position.owner_public_key.write(fee_position_owner_public_key);

            let insurance_fund_position = self.positions.entry(INSURANCE_FUND_POSITION);
            insurance_fund_position.version.write(POSITION_VERSION);
            insurance_fund_position
                .owner_public_key
                .write(insurance_fund_position_owner_public_key);
        }

        fn apply_diff(
            ref self: ComponentState<TContractState>,
            position_id: PositionId,
            position_diff: PositionDiff,
        ) {
            let position = self._get_position_snapshot(:position_id);
            let position_mut = self._get_position_mut(:position_id);
            for diff in position_diff {
                let asset_id = *diff.id;
                let balance = self.get_provisional_balance(:position, :asset_id);
                assert(*diff.balance_before == balance, APPLY_DIFF_MISMATCH);
                self
                    ._apply_funding_and_set_balance(
                        position: position_mut, :asset_id, balance: *diff.balance_after,
                    );
            }
        }

        fn get_position_snapshot(
            self: @ComponentState<TContractState>, position_id: PositionId,
        ) -> StoragePath<Position> {
            self._get_position_snapshot(:position_id)
        }

        /// Returns the position at the given `position_id`.
        /// The function asserts that the position exists and has a non-zero owner public key.
        fn get_position_mut(
            ref self: ComponentState<TContractState>, position_id: PositionId,
        ) -> StoragePath<Mutable<Position>> {
            self._get_position_mut(:position_id)
        }

        fn get_provisional_balance(
            self: @ComponentState<TContractState>,
            position: StoragePath<Position>,
            asset_id: AssetId,
        ) -> Balance {
            let assets = get_dep_component!(self, Assets);
            if assets.is_collateral(:asset_id) {
                self._get_provisional_main_collateral_balance(:position)
            } else if assets.is_synthetic(:asset_id) {
                position.synthetic_assets.entry(asset_id).balance.read()
            } else {
                panic_with_felt252(ASSET_NOT_EXISTS)
            }
        }

        fn get_position_data(
            self: @ComponentState<TContractState>, position: StoragePath<Position>,
        ) -> PositionData {
            let mut position_data = array![];
            self._collect_position_collaterals(:position, ref :position_data);
            self._collect_position_synthetics(:position, ref :position_data);
            position_data.span()
        }
    }

    #[generate_trait]
    impl PrivateImpl<
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
        /// Returns the position at the given `position_id`.
        /// The function asserts that the position exists and has a non-zero owner public key.
        fn _get_position_mut(
            ref self: ComponentState<TContractState>, position_id: PositionId,
        ) -> StoragePath<Mutable<Position>> {
            let mut position = self.positions.entry(position_id);
            assert(position.owner_public_key.read().is_non_zero(), POSITION_DOESNT_EXIST);
            position
        }

        fn _get_position_snapshot(
            self: @ComponentState<TContractState>, position_id: PositionId,
        ) -> StoragePath<Position> {
            let position = self.positions.entry(position_id);
            assert(position.owner_public_key.read().is_non_zero(), POSITION_DOESNT_EXIST);
            position
        }

        /// Returns the main collateral balance of a position while taking into account the funding
        /// of all synthetic assets in the position.
        fn _get_provisional_main_collateral_balance(
            self: @ComponentState<TContractState>, position: StoragePath<Position>,
        ) -> Balance {
            let assets = get_dep_component!(self, Assets);
            let mut main_collateral_balance = position
                .collateral_assets
                .entry(assets.get_main_collateral_asset_id())
                .balance
                .read();
            let mut asset_id_opt = position.synthetic_assets_head.read();
            while let Option::Some(synthetic_id) = asset_id_opt {
                let curr_funding_index = assets.get_funding_index(:synthetic_id);
                let synthetic_asset = position.synthetic_assets.entry(synthetic_id);
                let funding = (curr_funding_index - synthetic_asset.funding_index.read())
                    .mul(synthetic_asset.balance.read());
                main_collateral_balance += funding;
                asset_id_opt = position.synthetic_assets.entry(synthetic_id).next.read();
            };
            main_collateral_balance
        }

        fn _validate_position_exists(
            self: @ComponentState<TContractState>, position_id: PositionId,
        ) {
            self._get_position_snapshot(:position_id);
        }

        fn _collect_position_collaterals(
            self: @ComponentState<TContractState>,
            position: StoragePath<Position>,
            ref position_data: Array<Asset>,
        ) {
            let mut asset_id_opt = position.collateral_assets_head.read();
            while let Option::Some(asset_id) = asset_id_opt {
                self._collect_position_asset(:asset_id, :position, ref :position_data);
                asset_id_opt = position.collateral_assets.read(asset_id).next;
            }
        }

        fn _collect_position_synthetics(
            self: @ComponentState<TContractState>,
            position: StoragePath<Position>,
            ref position_data: Array<Asset>,
        ) {
            let mut asset_id_opt = position.synthetic_assets_head.read();
            while let Option::Some(asset_id) = asset_id_opt {
                self._collect_position_asset(:asset_id, :position, ref :position_data);
                asset_id_opt = position.synthetic_assets.read(asset_id).next;
            }
        }

        fn _collect_position_asset(
            self: @ComponentState<TContractState>,
            asset_id: AssetId,
            position: StoragePath<Position>,
            ref position_data: Array<Asset>,
        ) {
            let assets = get_dep_component!(self, Assets);
            let balance = self.get_provisional_balance(:position, :asset_id);
            if balance.is_non_zero() {
                let price = assets.get_asset_price(:asset_id);
                position_data
                    .append(
                        Asset {
                            id: asset_id,
                            balance,
                            price,
                            risk_factor: assets.get_risk_factor(:asset_id, :balance),
                        },
                    );
            }
        }

        fn _update_collateral_in_position(
            ref self: ComponentState<TContractState>,
            position: StoragePath<Mutable<Position>>,
            collateral_id: AssetId,
            balance: Balance,
        ) {
            let collateral_asset = position.collateral_assets.entry(collateral_id);
            if (collateral_asset.version.read().is_zero()) {
                collateral_asset.version.write(COLLATERAL_VERSION);
                collateral_asset.next.write(position.collateral_assets_head.read());
                position.collateral_assets_head.write(Option::Some(collateral_id));
            }
            collateral_asset.balance.write(balance);
        }

        fn _update_synthetic_in_position(
            ref self: ComponentState<TContractState>,
            position: StoragePath<Mutable<Position>>,
            synthetic_id: AssetId,
            balance: Balance,
            funding_index: FundingIndex,
        ) {
            let synthetic_asset = position.synthetic_assets.entry(synthetic_id);
            if (synthetic_asset.version.read().is_zero()) {
                synthetic_asset.version.write(SYNTHETIC_VERSION);
                synthetic_asset.next.write(position.synthetic_assets_head.read());
                position.synthetic_assets_head.write(Option::Some(synthetic_id));
            }
            synthetic_asset.balance.write(balance);
            synthetic_asset.funding_index.write(funding_index);
        }

        /// Updates the balance of a given asset, determining its type (collateral or synthetic)
        /// and applying the appropriate logic.
        fn _apply_funding_and_set_balance(
            ref self: ComponentState<TContractState>,
            position: StoragePath<Mutable<Position>>,
            asset_id: AssetId,
            balance: Balance,
        ) {
            let assets = get_dep_component!(@self, Assets);
            if assets.is_collateral(:asset_id) {
                self._update_collateral_in_position(position, collateral_id: asset_id, :balance);
            } else {
                self
                    ._update_synthetic_balance_and_funding(
                        :position, synthetic_id: asset_id, :balance,
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
            position: StoragePath<Mutable<Position>>,
            synthetic_id: AssetId,
            balance: Balance,
        ) {
            let assets = get_dep_component!(@self, Assets);
            let mut main_collateral_balance = position
                .collateral_assets
                .entry(assets.get_main_collateral_asset_id())
                .balance;
            let curr_funding_index = assets.get_funding_index(:synthetic_id);
            let synthetic_asset = position.synthetic_assets.entry(synthetic_id);
            let funding = (curr_funding_index - synthetic_asset.funding_index.read())
                .mul(synthetic_asset.balance.read());
            main_collateral_balance.add_and_write(funding);
            self
                ._update_synthetic_in_position(
                    :position, :synthetic_id, :balance, funding_index: curr_funding_index,
                );
        }

        fn _get_position_state(
            self: @ComponentState<TContractState>, position_id: PositionId,
        ) -> PositionState {
            let position = self._get_position_snapshot(:position_id);
            let position_data = self.get_position_data(:position);

            let position_change_result = evaluate_position(:position_data);
            position_change_result.position_state_after_change
        }
    }
}
