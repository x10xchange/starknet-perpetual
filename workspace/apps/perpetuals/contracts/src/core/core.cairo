#[starknet::contract]
pub mod Core {
    use core::dict::{Felt252Dict, Felt252DictTrait};
    use core::nullable::{FromNullableResult, match_nullable};
    use core::num::traits::{WideMul, Zero};
    use core::panic_with_felt252;
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use openzeppelin::interfaces::erc4626::{IERC4626Dispatcher, IERC4626DispatcherTrait};
    use openzeppelin::introspection::src5::SRC5Component;
    use openzeppelin::utils::snip12::SNIP12Metadata;
    use perpetuals::core::components::assets::AssetsComponent;
    use perpetuals::core::components::assets::AssetsComponent::InternalTrait as AssetsInternal;
    use perpetuals::core::components::assets::errors::{NOT_SYNTHETIC, SYNTHETIC_NOT_EXISTS};
    use perpetuals::core::components::deposit::Deposit;
    use perpetuals::core::components::deposit::Deposit::InternalTrait as DepositInternal;
    use perpetuals::core::components::operator_nonce::OperatorNonceComponent;
    use perpetuals::core::components::operator_nonce::OperatorNonceComponent::InternalTrait as OperatorNonceInternal;
    use perpetuals::core::components::positions::Positions;
    use perpetuals::core::components::positions::Positions::{
        FEE_POSITION, INSURANCE_FUND_POSITION, InternalTrait as PositionsInternalTrait,
    };
    use perpetuals::core::errors::{
        ASSET_ID_NOT_COLLATERAL, CANT_LIQUIDATE_IF_POSITION, CANT_TRADE_WITH_FEE_POSITION,
        DIFFERENT_BASE_ASSET_IDS, INVALID_ACTUAL_BASE_SIGN, INVALID_ACTUAL_QUOTE_SIGN,
        INVALID_AMOUNT_SIGN, INVALID_BASE_CHANGE, INVALID_QUOTE_AMOUNT_SIGN,
        INVALID_QUOTE_FEE_AMOUNT, INVALID_SAME_POSITIONS, INVALID_ZERO_AMOUNT, SYNTHETIC_IS_ACTIVE,
        TRANSFER_EXPIRED, WITHDRAW_EXPIRED, fulfillment_exceeded_err, order_expired_err,
    };
    use perpetuals::core::events;
    use perpetuals::core::interface::{ICore, Settlement};
    use perpetuals::core::types::asset::synthetic::AssetBalanceDiffEnriched;
    use perpetuals::core::types::asset::{AssetId, AssetStatus};
    use perpetuals::core::types::balance::{Balance, BalanceDiff};
    use perpetuals::core::types::order::{LimitOrder, LimitOrderTrait, Order, OrderTrait};
    use perpetuals::core::types::position::{
        AssetEnrichedPositionDiff, Position, PositionDiff, PositionDiffEnriched, PositionId,
        PositionTrait,
    };
    use perpetuals::core::types::price::PriceMulTrait;
    use perpetuals::core::types::transfer::TransferArgs;
    use perpetuals::core::types::vault::ConvertPositionToVault;
    use perpetuals::core::types::withdraw::WithdrawArgs;
    use perpetuals::core::value_risk_calculator::{
        PositionTVTR, assert_healthy_or_healthier, calculate_position_tvtr_before,
        calculate_position_tvtr_change, deleveraged_position_validations,
        liquidated_position_validations,
    };
    use starknet::ContractAddress;
    use starknet::event::EventEmitter;
    use starknet::storage::{
        Map, StorageMapReadAccess, StoragePath, StoragePathEntry, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starkware_utils::components::pausable::PausableComponent;
    use starkware_utils::components::pausable::PausableComponent::InternalTrait as PausableInternal;
    use starkware_utils::components::replaceability::ReplaceabilityComponent;
    use starkware_utils::components::replaceability::ReplaceabilityComponent::InternalReplaceabilityTrait;
    use starkware_utils::components::request_approvals::RequestApprovalsComponent;
    use starkware_utils::components::request_approvals::RequestApprovalsComponent::InternalTrait as RequestApprovalsInternal;
    use starkware_utils::components::roles::RolesComponent;
    use starkware_utils::components::roles::RolesComponent::InternalTrait as RolesInternal;
    use starkware_utils::errors::assert_with_byte_array;
    use starkware_utils::hash::message_hash::OffchainMessageHash;
    use starkware_utils::math::abs::Abs;
    use starkware_utils::math::utils::have_same_sign;
    use starkware_utils::signature::stark::{
        HashType, PublicKey, Signature, validate_stark_signature,
    };
    use starkware_utils::storage::iterable_map::{
        IterableMapIntoIterImpl, IterableMapReadAccessImpl, IterableMapWriteAccessImpl,
    };
    use starkware_utils::time::time::{Time, TimeDelta, Timestamp, validate_expiration};
    use crate::core::components::assets::interface::IAssets;
    use crate::core::components::vault;
    use crate::core::components::vault::protocol_vault::{
        IProtocolVaultDispatcher, IProtocolVaultDispatcherTrait,
    };
    use crate::core::components::vault::vaults::Vaults;
    use crate::core::components::vault::vaults::Vaults::InternalTrait as VaultsInternal;
    use crate::core::types::asset::synthetic::AssetType;
    use crate::core::types::price::PRICE_SCALE;

    component!(path: AccessControlComponent, storage: accesscontrol, event: AccessControlEvent);
    component!(path: OperatorNonceComponent, storage: operator_nonce, event: OperatorNonceEvent);
    component!(path: PausableComponent, storage: pausable, event: PausableEvent);
    component!(path: ReplaceabilityComponent, storage: replaceability, event: ReplaceabilityEvent);
    component!(path: RolesComponent, storage: roles, event: RolesEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);
    component!(path: AssetsComponent, storage: assets, event: AssetsEvent);
    component!(path: Deposit, storage: deposits, event: DepositEvent);
    component!(
        path: RequestApprovalsComponent, storage: request_approvals, event: RequestApprovalsEvent,
    );
    component!(path: Positions, storage: positions, event: PositionsEvent);
    component!(path: Vaults, storage: vaults, event: VaultsEvent);


    #[abi(embed_v0)]
    impl OperatorNonceImpl =
        OperatorNonceComponent::OperatorNonceImpl<ContractState>;

    #[abi(embed_v0)]
    impl DepositImpl = Deposit::DepositImpl<ContractState>;

    #[abi(embed_v0)]
    impl RequestApprovalsImpl =
        RequestApprovalsComponent::RequestApprovalsImpl<ContractState>;

    #[abi(embed_v0)]
    impl AssetsImpl = AssetsComponent::AssetsImpl<ContractState>;

    #[abi(embed_v0)]
    impl ReplaceabilityImpl =
        ReplaceabilityComponent::ReplaceabilityImpl<ContractState>;

    #[abi(embed_v0)]
    impl RolesImpl = RolesComponent::RolesImpl<ContractState>;

    #[abi(embed_v0)]
    impl PausableImpl = PausableComponent::PausableImpl<ContractState>;

    #[abi(embed_v0)]
    impl PositionsImpl = Positions::PositionsImpl<ContractState>;

    #[abi(embed_v0)]
    impl VaultsImpl = Vaults::VaultsImpl<ContractState>;


    const NAME: felt252 = 'Perpetuals';
    const VERSION: felt252 = 'v0';

    /// Required for hash computation.
    pub impl SNIP12MetadataImpl of SNIP12Metadata {
        fn name() -> felt252 {
            NAME
        }
        fn version() -> felt252 {
            VERSION
        }
    }

    #[storage]
    struct Storage {
        // Order hash to fulfilled absolute base amount.
        fulfillment: Map<HashType, u64>,
        // --- Components ---
        #[substorage(v0)]
        accesscontrol: AccessControlComponent::Storage,
        #[substorage(v0)]
        operator_nonce: OperatorNonceComponent::Storage,
        #[substorage(v0)]
        pausable: PausableComponent::Storage,
        #[substorage(v0)]
        pub replaceability: ReplaceabilityComponent::Storage,
        #[substorage(v0)]
        pub roles: RolesComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        #[substorage(v0)]
        pub assets: AssetsComponent::Storage,
        #[substorage(v0)]
        pub deposits: Deposit::Storage,
        #[substorage(v0)]
        pub request_approvals: RequestApprovalsComponent::Storage,
        #[substorage(v0)]
        pub positions: Positions::Storage,
        #[substorage(v0)]
        pub vaults: Vaults::Storage,
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
        Deleverage: events::Deleverage,
        InactiveAssetPositionReduced: events::InactiveAssetPositionReduced,
        Liquidate: events::Liquidate,
        Trade: events::Trade,
        Transfer: events::Transfer,
        TransferRequest: events::TransferRequest,
        Withdraw: events::Withdraw,
        WithdrawRequest: events::WithdrawRequest,
        InvestInVaultEvent: events::InvestInVault,
        #[flat]
        VaultsEvent: Vaults::Event,
    }

    #[constructor]
    pub fn constructor(
        ref self: ContractState,
        governance_admin: ContractAddress,
        upgrade_delay: u64,
        collateral_id: AssetId,
        collateral_token_address: ContractAddress,
        // Collateral quantum must make the minimal collateral unit == 10^-6 USD. For more details
        // see `SN_PERPS_SCALE` in the `price.cairo` file.
        collateral_quantum: u64,
        max_price_interval: TimeDelta,
        max_oracle_price_validity: TimeDelta,
        max_funding_interval: TimeDelta,
        max_funding_rate: u32,
        cancel_delay: TimeDelta,
        fee_position_owner_public_key: PublicKey,
        insurance_fund_position_owner_public_key: PublicKey,
    ) {
        self.roles.initialize(:governance_admin);
        self.replaceability.initialize(:upgrade_delay);
        self
            .assets
            .initialize(
                :collateral_id,
                :collateral_token_address,
                :collateral_quantum,
                :max_price_interval,
                :max_funding_interval,
                :max_funding_rate,
                :max_oracle_price_validity,
            );
        self.deposits.initialize(:cancel_delay);
        self
            .positions
            .initialize(:fee_position_owner_public_key, :insurance_fund_position_owner_public_key);

        self.vaults.initialize();
    }

    #[abi(embed_v0)]
    pub impl CoreImpl of ICore<ContractState> {
        /// Requests a withdrawal of a collateral amount from a position to a `recipient`.
        ///
        /// Validations:
        /// - Validates the signature.
        /// - Validates the position exists.
        /// - Validates the request does not exist.
        /// - Validates the owner account is the caller.
        ///
        /// Execution:
        /// - Registers the withdraw request.
        /// - Emits a `WithdrawRequest` event.
        fn withdraw_request(
            ref self: ContractState,
            signature: Signature,
            recipient: ContractAddress,
            position_id: PositionId,
            amount: u64,
            expiration: Timestamp,
            salt: felt252,
        ) {
            if (self.vaults.is_vault(vault_position: position_id)) {
                panic_with_felt252('VAULT_CANNOT_INITIATE_WITHDRAW');
            }

            let position = self.positions.get_position_snapshot(:position_id);
            let collateral_id = self.assets.get_collateral_id();
            assert(amount.is_non_zero(), INVALID_ZERO_AMOUNT);
            let owner_account = if (position.owner_protection_enabled.read()) {
                position.get_owner_account()
            } else {
                Option::None
            };
            let hash = self
                .request_approvals
                .register_approval(
                    owner_account: owner_account,
                    public_key: position.get_owner_public_key(),
                    :signature,
                    args: WithdrawArgs {
                        position_id, salt, expiration, collateral_id, amount, recipient,
                    },
                );
            self
                .emit(
                    events::WithdrawRequest {
                        position_id,
                        recipient,
                        collateral_id,
                        amount,
                        expiration,
                        withdraw_request_hash: hash,
                        salt,
                    },
                );
        }

        /// Withdraw collateral `amount` from the a position to `recipient`.
        ///
        /// Validations:
        /// - Only the operator can call this function.
        /// - The contract must not be paused.
        /// - The `operator_nonce` must be valid.
        /// - The `expiration` time has not passed.
        /// - The collateral asset exists in the system.
        /// - The collateral asset is active.
        /// - The funding validation interval has not passed since the last funding tick.
        /// - The prices of all assets in the system are valid.
        /// - The withdrawal message has not been fulfilled.
        /// - A fact was registered for the withdraw message.
        /// - Validate the position is healthy after the withdraw.
        ///
        /// Execution:
        /// - Transfer the collateral `amount` to the `recipient`.
        /// - Update the position's collateral balance.
        /// - Mark the withdrawal message as fulfilled.
        fn withdraw(
            ref self: ContractState,
            operator_nonce: u64,
            recipient: ContractAddress,
            position_id: PositionId,
            amount: u64,
            expiration: Timestamp,
            salt: felt252,
        ) {
            self.pausable.assert_not_paused();
            self.operator_nonce.use_checked_nonce(:operator_nonce);
            self.assets.validate_assets_integrity();
            validate_expiration(expiration: expiration, err: WITHDRAW_EXPIRED);
            let collateral_id = self.assets.get_collateral_id();
            let position = self.positions.get_position_snapshot(:position_id);
            let hash = self
                .request_approvals
                .consume_approved_request(
                    args: WithdrawArgs {
                        position_id, salt, expiration, collateral_id, amount, recipient,
                    },
                    public_key: position.get_owner_public_key(),
                );

            /// Validations - Fundamentals:
            let position_diff = PositionDiff {
                collateral_diff: -amount.into(), asset_diff: Option::None,
            };

            self
                ._validate_healthy_or_healthier_position(
                    :position_id, :position, :position_diff, tvtr_before: Default::default(),
                );

            self.positions.apply_diff(:position_id, :position_diff);
            let quantum = self.assets.get_collateral_quantum();
            let withdraw_unquantized_amount = quantum * amount;
            let token_contract = self.assets.get_collateral_token_contract();
            token_contract.transfer(:recipient, amount: withdraw_unquantized_amount.into());

            self
                .emit(
                    events::Withdraw {
                        position_id,
                        recipient,
                        collateral_id,
                        amount,
                        expiration,
                        withdraw_request_hash: hash,
                        salt,
                    },
                );
        }

        /// Executes a transfer request.
        ///
        /// Validations:
        /// - Validates the position exists.
        /// - Validates the request does not exist.
        /// - If the position has an owner account, validate that the caller is the position owner
        /// account.
        /// - Validates the signature.
        ///
        /// Execution:
        /// - Registers the transfer request.
        /// - Emits a `TransferRequest` event.
        fn transfer_request(
            ref self: ContractState,
            signature: Signature,
            asset_id: AssetId,
            recipient: PositionId,
            position_id: PositionId,
            amount: u64,
            expiration: Timestamp,
            salt: felt252,
        ) {
            if (asset_id != self.assets.get_collateral_id()) {
                let asset_config = self.assets.get_asset_config(asset_id);
                assert(
                    asset_config.asset_type == AssetType::SPOT_COLLATERAL
                        || asset_config.asset_type == AssetType::VAULT_SHARE_COLLATERAL,
                    'NOT_TRANSFERABLE_ASSET',
                );
            }

            if (self.vaults.is_vault(vault_position: position_id)) {
                panic_with_felt252('VAULT_CANNOT_INITIATE_TRANSFER');
            }

            self.positions.get_position_snapshot(position_id: recipient);
            let position = self.positions.get_position_snapshot(:position_id);
            assert(amount.is_non_zero(), INVALID_ZERO_AMOUNT);
            let owner_account = if (position.owner_protection_enabled.read()) {
                position.get_owner_account()
            } else {
                Option::None
            };
            let hash = self
                .request_approvals
                .register_approval(
                    owner_account: owner_account,
                    public_key: position.get_owner_public_key(),
                    :signature,
                    args: TransferArgs {
                        position_id, recipient, salt, expiration, collateral_id: asset_id, amount,
                    },
                );
            self
                .emit(
                    events::TransferRequest {
                        position_id,
                        recipient,
                        collateral_id: asset_id,
                        amount,
                        expiration,
                        transfer_request_hash: hash,
                        salt,
                    },
                );
        }

        /// Executes a transfer.
        ///
        /// Validations:
        /// - The contract must not be paused.
        /// - The `operator_nonce` must be valid.
        /// - The funding validation interval has not passed since the last funding tick.
        /// - The prices of all assets in the system are valid.
        /// - Validates both the sender and recipient positions exist.
        /// - Ensures the amount is positive.
        /// - Validates the expiration time.
        /// - Validates request approval.
        ///
        /// Execution:
        /// - Adjust collateral balances.
        /// - Validates the sender position is healthy or healthier after the execution.
        fn transfer(
            ref self: ContractState,
            operator_nonce: u64,
            asset_id: AssetId,
            recipient: PositionId,
            position_id: PositionId,
            amount: u64,
            expiration: Timestamp,
            salt: felt252,
        ) {
            self.pausable.assert_not_paused();
            self.operator_nonce.use_checked_nonce(:operator_nonce);
            self.assets.validate_assets_integrity();
            validate_expiration(:expiration, err: TRANSFER_EXPIRED);
            assert(recipient != position_id, INVALID_SAME_POSITIONS);
            let position = self.positions.get_position_snapshot(:position_id);
            let hash = self
                .request_approvals
                .consume_approved_request(
                    args: TransferArgs {
                        recipient, position_id, collateral_id: asset_id, amount, expiration, salt,
                    },
                    public_key: position.get_owner_public_key(),
                );

            self._execute_transfer(:recipient, :position_id, collateral_id: asset_id, :amount);

            self
                .emit(
                    events::Transfer {
                        recipient,
                        position_id,
                        collateral_id: asset_id,
                        amount,
                        expiration,
                        transfer_request_hash: hash,
                        salt,
                    },
                );
        }

        fn multi_trade(ref self: ContractState, operator_nonce: u64, trades: Span<Settlement>) {
            self.pausable.assert_not_paused();
            self.operator_nonce.use_checked_nonce(:operator_nonce);
            self.assets.validate_assets_integrity();

            let mut tvtr_cache: Felt252Dict<Nullable<PositionTVTR>> = Default::default();

            for _trade in trades {
                let trade = *_trade;
                let position_id_a: felt252 = trade.order_a.position_id.value.into();
                let position_id_b: felt252 = trade.order_b.position_id.value.into();
                // In case there is no cached tvtr for position, it will be Nullable::Null.
                let cached_pos_a_tvtr = tvtr_cache.get(position_id_a);
                let cached_pos_b_tvtr = tvtr_cache.get(position_id_b);
                let (updated_a, updated_b) = self
                    ._execute_trade(
                        signature_a: trade.signature_a,
                        signature_b: trade.signature_b,
                        order_a: trade.order_a,
                        order_b: trade.order_b,
                        actual_amount_base_a: trade.actual_amount_base_a,
                        actual_amount_quote_a: trade.actual_amount_quote_a,
                        actual_fee_a: trade.actual_fee_a,
                        actual_fee_b: trade.actual_fee_b,
                        tvtr_a_before: cached_pos_a_tvtr,
                        tvtr_b_before: cached_pos_b_tvtr,
                    );
                tvtr_cache.insert(position_id_a, NullableTrait::new(updated_a));
                tvtr_cache.insert(position_id_b, NullableTrait::new(updated_b));
            }
        }


        /// Executes a trade between two orders (Order A and Order B).
        ///
        /// Validations:
        /// - The contract must not be paused.
        /// - The `operator_nonce` must be valid.
        /// - The funding validation interval has not passed since the last funding tick.
        /// - The prices of all assets in the system are valid.
        /// - Validates signatures for both orders using the public keys of their respective owners.
        /// - Ensures the fee amounts in both orders are positive.
        /// - Validates that the base and quote asset types match between the two orders.
        /// - Verifies the signs of amounts:
        ///   - Ensures the sign of amounts in each order is consistent.
        ///   - Ensures the signs between Order A and Order B amounts are opposite where required.
        /// - Ensures the order fulfillment amounts do not exceed their respective limits.
        /// - Validates that the fee ratio does not increase.
        /// - Ensures the base-to-quote amount ratio does not decrease.
        ///
        /// Execution:
        /// - Subtract the fees from each position's collateral.
        /// - Add the fees to the `fee_position`.
        /// - Update Order A's position and Order B's position, based on `actual_amount_base`.
        /// - Adjust collateral balances.
        /// - Perform fundamental validation for both positions after the execution.
        /// - Update order fulfillment.
        fn trade(
            ref self: ContractState,
            operator_nonce: u64,
            signature_a: Signature,
            signature_b: Signature,
            order_a: Order,
            order_b: Order,
            actual_amount_base_a: i64,
            actual_amount_quote_a: i64,
            actual_fee_a: u64,
            actual_fee_b: u64,
        ) {
            self.pausable.assert_not_paused();
            self.operator_nonce.use_checked_nonce(:operator_nonce);
            self.assets.validate_assets_integrity();

            self
                ._execute_trade(
                    :signature_a,
                    :signature_b,
                    :order_a,
                    :order_b,
                    :actual_amount_base_a,
                    :actual_amount_quote_a,
                    :actual_fee_a,
                    :actual_fee_b,
                    tvtr_a_before: Default::default(),
                    tvtr_b_before: Default::default(),
                );
        }


        /// Executes a liquidate of a user position with liquidator order.
        ///
        /// Validations:
        /// - The contract must not be paused.
        /// - The `operator_nonce` must be valid.
        /// - The funding validation interval has not passed since the last funding tick.
        /// - The prices of all assets in the system are valid.
        /// - Validates signatures for liquidator order using the public keys of it owner.
        /// - Ensures the fee amounts are positive.
        /// - Validates that the base and quote asset types match between the liquidator and
        /// liquidated orders.
        /// - Verifies the signs of amounts:
        ///   - Ensures the sign of amounts in each order is consistent.
        ///   - Ensures the signs between liquidated order and liquidator order amount are opposite.
        /// - Ensures the liquidator order fulfillment amount do not exceed its limit.
        /// - Validates that the fee ratio does not increase.
        /// - Ensures the base-to-quote amount ratio does not decrease.
        /// - Validates liquidated position is liquidatable.
        ///
        /// Execution:
        /// - Subtract the fees from each position's collateral.
        /// - Add the fees to the `fee_position`.
        /// - Update orders' position, based on `actual_amount_base`.
        /// - Adjust collateral balances.
        /// - Perform fundamental validation for both positions after the execution.
        /// - Update liquidator order fulfillment.
        fn liquidate(
            ref self: ContractState,
            operator_nonce: u64,
            liquidator_signature: Signature,
            liquidated_position_id: PositionId,
            liquidator_order: Order,
            actual_amount_base_liquidated: i64,
            actual_amount_quote_liquidated: i64,
            actual_liquidator_fee: u64,
            /// The `liquidated_fee_amount` is paid by the liquidated position to the
            /// insurance fund position.
            liquidated_fee_amount: u64,
        ) {
            /// Validations:
            self.pausable.assert_not_paused();
            self.operator_nonce.use_checked_nonce(:operator_nonce);
            self.assets.validate_assets_integrity();

            assert(liquidated_position_id != INSURANCE_FUND_POSITION, CANT_LIQUIDATE_IF_POSITION);

            let liquidator_position_id = liquidator_order.position_id;
            assert(liquidator_position_id != INSURANCE_FUND_POSITION, CANT_LIQUIDATE_IF_POSITION);

            let collateral_id = self.assets.get_collateral_id();
            let liquidated_order = Order {
                position_id: liquidated_position_id,
                base_asset_id: liquidator_order.base_asset_id,
                base_amount: actual_amount_base_liquidated,
                quote_asset_id: liquidator_order.quote_asset_id,
                quote_amount: actual_amount_quote_liquidated,
                fee_asset_id: liquidator_order.fee_asset_id,
                fee_amount: liquidated_fee_amount,
                // Dummy values needed to initialize the struct and pass validation.
                salt: Zero::zero(),
                expiration: Time::now(),
            };

            // Validations.
            self
                ._validate_trade(
                    order_a: liquidated_order,
                    order_b: liquidator_order,
                    actual_amount_base_a: actual_amount_base_liquidated,
                    actual_amount_quote_a: actual_amount_quote_liquidated,
                    actual_fee_a: liquidated_fee_amount,
                    actual_fee_b: actual_liquidator_fee,
                );

            let liquidator_position = self.positions.get_position_snapshot(liquidator_position_id);
            let liquidated_position = self
                .positions
                .get_position_snapshot(position_id: liquidated_position_id);

            // Signatures validation:
            let liquidator_order_hash = self
                ._validate_signature(
                    public_key: liquidator_position.get_owner_public_key(),
                    order: liquidator_order,
                    signature: liquidator_signature,
                );

            // Validate and update fulfillment.
            self
                ._update_fulfillment(
                    position_id: liquidator_position_id,
                    hash: liquidator_order_hash,
                    order_base_amount: liquidator_order.base_amount,
                    // Passing the negative of actual amounts to `liquidator_order` as it is linked
                    // to liquidated_order.
                    actual_base_amount: -actual_amount_base_liquidated,
                );

            /// Execution:
            let liquidated_position_diff = PositionDiff {
                collateral_diff: actual_amount_quote_liquidated.into()
                    - liquidated_fee_amount.into(),
                asset_diff: Option::Some(
                    (liquidator_order.base_asset_id, actual_amount_base_liquidated.into()),
                ),
            };
            // Passing the negative of actual amounts to order_b as it is linked to order_a.
            let liquidator_position_diff = PositionDiff {
                collateral_diff: -actual_amount_quote_liquidated.into()
                    - actual_liquidator_fee.into(),
                asset_diff: Option::Some(
                    (liquidator_order.base_asset_id, -actual_amount_base_liquidated.into()),
                ),
            };
            let insurance_position_diff = PositionDiff {
                collateral_diff: liquidated_fee_amount.into(), asset_diff: Option::None,
            };
            let fee_position_diff = PositionDiff {
                collateral_diff: actual_liquidator_fee.into(), asset_diff: Option::None,
            };

            /// Validations - Fundamentals:
            self
                ._validate_liquidated_position(
                    position_id: liquidated_position_id,
                    position: liquidated_position,
                    position_diff: liquidated_position_diff,
                );
            self
                ._validate_healthy_or_healthier_position(
                    position_id: liquidator_position_id,
                    position: liquidator_position,
                    position_diff: liquidator_position_diff,
                    tvtr_before: Default::default(),
                );

            // Apply Diffs.
            self
                .positions
                .apply_diff(
                    position_id: liquidated_position_id, position_diff: liquidated_position_diff,
                );

            self
                .positions
                .apply_diff(
                    position_id: liquidator_order.position_id,
                    position_diff: liquidator_position_diff,
                );

            self.positions.apply_diff(position_id: FEE_POSITION, position_diff: fee_position_diff);

            self
                .positions
                .apply_diff(
                    position_id: INSURANCE_FUND_POSITION, position_diff: insurance_position_diff,
                );

            self
                .emit(
                    events::Liquidate {
                        liquidated_position_id,
                        liquidator_order_position_id: liquidator_position_id,
                        liquidator_order_base_asset_id: liquidator_order.base_asset_id,
                        liquidator_order_base_amount: liquidator_order.base_amount,
                        liquidator_order_quote_asset_id: liquidator_order.quote_asset_id,
                        liquidator_order_quote_amount: liquidator_order.quote_amount,
                        liquidator_order_fee_asset_id: liquidator_order.fee_asset_id,
                        liquidator_order_fee_amount: liquidator_order.fee_amount,
                        actual_amount_base_liquidated,
                        actual_amount_quote_liquidated,
                        actual_liquidator_fee,
                        insurance_fund_fee_asset_id: collateral_id,
                        insurance_fund_fee_amount: liquidated_fee_amount,
                        liquidator_order_hash: liquidator_order_hash,
                    },
                );
        }

        /// Executes a deleverage of a user position with a deleverager position.
        ///
        /// Validations:
        /// - The contract must not be paused.
        /// - The `operator_nonce` must be valid.
        /// - The funding validation interval has not passed since the last funding tick.
        /// - The prices of all assets in the system are valid.
        /// - Verifies the signs of amounts:
        ///   - Ensures the opposite sign of amounts in base and quote.
        ///   - Ensures the sign of amounts in each position is consistent.
        /// - Verifies that the base asset is active.
        /// - validates the deleveraged position is deleveragable.
        ///
        /// Execution:
        /// - Update the position, based on `delevereged_base_asset`.
        /// - Adjust collateral balances based on `delevereged_quote_asset`.
        /// - Perform fundamental validation for both positions after the execution.
        fn deleverage(
            ref self: ContractState,
            operator_nonce: u64,
            deleveraged_position_id: PositionId,
            deleverager_position_id: PositionId,
            base_asset_id: AssetId,
            deleveraged_base_amount: i64,
            deleveraged_quote_amount: i64,
        ) {
            /// Validations:
            self.pausable.assert_not_paused();
            self.operator_nonce.use_checked_nonce(:operator_nonce);
            self.assets.validate_assets_integrity();

            let deleveraged_position = self
                .positions
                .get_position_snapshot(position_id: deleveraged_position_id);
            let deleverager_position = self
                .positions
                .get_position_snapshot(position_id: deleverager_position_id);

            self.assets.validate_asset_active(synthetic_id: base_asset_id);
            self
                ._validate_imposed_reduction_trade(
                    position_id_a: deleveraged_position_id,
                    position_id_b: deleverager_position_id,
                    position_a: deleveraged_position,
                    position_b: deleverager_position,
                    :base_asset_id,
                    base_amount_a: deleveraged_base_amount,
                    quote_amount_a: deleveraged_quote_amount,
                );

            /// Execution:
            let deleveraged_position_diff = PositionDiff {
                collateral_diff: deleveraged_quote_amount.into(),
                asset_diff: Option::Some((base_asset_id, deleveraged_base_amount.into())),
            };
            // Passing the negative of actual amounts to deleverager as it is linked to
            // deleveraged.
            let deleverager_position_diff = PositionDiff {
                collateral_diff: -deleveraged_quote_amount.into(),
                asset_diff: Option::Some((base_asset_id, -deleveraged_base_amount.into())),
            };

            /// Validations - Fundamentals:
            // The deleveraged position should be deleveragable before
            // and healthy or healthier after and the deleverage must be fair.
            self
                ._validate_deleveraged_position(
                    position_id: deleveraged_position_id,
                    position: deleveraged_position,
                    position_diff: deleveraged_position_diff,
                );
            self
                ._validate_healthy_or_healthier_position(
                    position_id: deleverager_position_id,
                    position: deleverager_position,
                    position_diff: deleverager_position_diff,
                    tvtr_before: Default::default(),
                );

            // Apply diffs
            self
                .positions
                .apply_diff(
                    position_id: deleveraged_position_id, position_diff: deleveraged_position_diff,
                );
            self
                .positions
                .apply_diff(
                    position_id: deleverager_position_id, position_diff: deleverager_position_diff,
                );

            self
                .emit(
                    events::Deleverage {
                        deleveraged_position_id,
                        deleverager_position_id,
                        base_asset_id,
                        deleveraged_base_amount,
                        quote_asset_id: self.assets.get_collateral_id(),
                        deleveraged_quote_amount,
                    },
                )
        }

        /// Executes a trade between position with inactive synthetic assets.
        ///
        /// Validations:
        /// - The contract must not be paused.
        /// - The `operator_nonce` must be valid.
        /// - The funding validation interval has not passed since the last funding tick.
        /// - The prices of all assets in the system are valid.
        /// - Verifies that the base asset is inactive.
        /// - Verifies the signs of amounts:
        ///   - Ensures the opposite sign of amounts in base and quote.
        ///   - Ensures the sign of amounts in each position is consistent.
        ///
        /// Execution:
        /// - Update the position, based on `base_asset`.
        /// - Adjust collateral balances based on `quote_amount`.
        fn reduce_inactive_asset_position(
            ref self: ContractState,
            operator_nonce: u64,
            position_id_a: PositionId,
            position_id_b: PositionId,
            base_asset_id: AssetId,
            base_amount_a: i64,
        ) {
            /// Validations:
            self.pausable.assert_not_paused();
            self.operator_nonce.use_checked_nonce(:operator_nonce);
            self.assets.validate_assets_integrity();

            let position_a = self.positions.get_position_snapshot(position_id: position_id_a);
            let position_b = self.positions.get_position_snapshot(position_id: position_id_b);

            // Validate base asset is inactive synthetic.
            if let Option::Some(config) = self.assets.asset_config.read(base_asset_id) {
                assert(config.status == AssetStatus::INACTIVE, SYNTHETIC_IS_ACTIVE);
            } else {
                panic_with_felt252(NOT_SYNTHETIC);
            }
            let base_balance: Balance = base_amount_a.into();
            let quote_amount_a: i64 = -1
                * self
                    .assets
                    .get_asset_price(synthetic_id: base_asset_id)
                    .mul(rhs: base_balance)
                    .try_into()
                    .expect('QUOTE_AMOUNT_OVERFLOW');
            self
                ._validate_imposed_reduction_trade(
                    :position_id_a,
                    :position_id_b,
                    :position_a,
                    :position_b,
                    :base_asset_id,
                    :base_amount_a,
                    :quote_amount_a,
                );

            /// Execution:
            let position_diff_a = PositionDiff {
                collateral_diff: quote_amount_a.into(),
                asset_diff: Option::Some((base_asset_id, base_amount_a.into())),
            };
            // Passing the negative of actual amounts to position_b as it is linked to position_a.
            let position_diff_b = PositionDiff {
                collateral_diff: -quote_amount_a.into(),
                asset_diff: Option::Some((base_asset_id, -base_amount_a.into())),
            };

            // Apply diffs
            self.positions.apply_diff(position_id: position_id_a, position_diff: position_diff_a);
            self.positions.apply_diff(position_id: position_id_b, position_diff: position_diff_b);

            self
                .emit(
                    events::InactiveAssetPositionReduced {
                        position_id_a,
                        position_id_b,
                        base_asset_id,
                        base_amount_a,
                        quote_asset_id: self.assets.get_collateral_id(),
                        quote_amount_a,
                    },
                )
        }

        /// Executes an investment in a vault position.
        ///
        /// Validations:
        /// - The contract must not be paused.
        /// - It should be called by operator.
        /// - The `operator_nonce` must be valid.
        /// - The funding validation interval has not passed since the last funding tick.
        /// - The prices of all assets in the system are valid.
        /// - Validates both from_position_id and vault_id exist.
        /// - Validates that vault_id is actually a vault position.
        /// - Validates that from_position_id is not a vault position./
        /// - Ensures the amount is non-zero.
        /// - Validates the expiration time.
        /// - Validates the signature for the InvestInVault order.
        ///
        /// Execution:
        /// - Transfer collateral from from_position_id to vault_id.
        /// - Transfer shares to from_position_id.
        /// - Validates the from_position is healthy or healthier after the transfer.
        fn invest_in_vault(
            ref self: ContractState, operator_nonce: u64, signature: Signature, order: LimitOrder,
        ) {
            //     /// Validations - System State:
            self.pausable.assert_not_paused();
            self.operator_nonce.use_checked_nonce(:operator_nonce);
            self.assets.validate_assets_integrity();

            let vault_config = self.vaults.get_vault_config_for_asset(order.base_asset_id);
            let from_position_id = order.source_position;
            let vault_position_id = vault_config.position_id.into();

            /// Validations - Order Parameters:
            assert(order.base_amount > 0, 'INVALID_NEGATIVE_BASE_AMOUNT');
            assert(order.quote_amount < 0, 'INVALID_POSITIVE_QUOTE_AMOUNT');
            // Expiration check.
            let now = Time::now();
            assert_with_byte_array(now <= order.expiration, order_expired_err(from_position_id));
            assert(order.quote_asset_id == self.assets.get_collateral_id(), 'INVALID_QUOTE_ASSET');

            let receiving_position_id = order.receive_position;
            let salt = order.salt;

            let sending_position_snapshot = self
                .positions
                .get_position_snapshot(position_id: from_position_id);

            self
                ._update_fulfillment(
                    position_id: from_position_id,
                    hash: order.get_message_hash(sending_position_snapshot.get_owner_public_key()),
                    order_base_amount: order.quote_amount,
                    actual_base_amount: order.quote_amount,
                );

            // self
            //     ._validate_signature(
            //         public_key: sending_position_snapshot.get_owner_public_key(),
            //         :order,
            //         :signature,
            //     );

            assert(!self.is_vault(from_position_id), 'FROM_POSITION_IS_VAULT');
            let vault_share_config = self.get_asset_config(vault_config.asset_id);

            let vault_dispatcher = IERC4626Dispatcher {
                contract_address: vault_share_config.token_contract.expect('NOT_ERC4626'),
            };
            let collateral_token_dispatcher = self.get_collateral_token_contract();
            let current_collateral_balance = collateral_token_dispatcher
                .balance_of(starknet::get_contract_address());

            let on_chain_amount: u128 = order
                .quote_amount
                .abs()
                .wide_mul(self.assets.get_collateral_quantum());

            collateral_token_dispatcher
                .approve(
                    spender: vault_dispatcher.contract_address, amount: on_chain_amount.into(),
                );

            let minted_shares: u128 = vault_dispatcher
                .deposit(on_chain_amount.into(), starknet::get_contract_address())
                .try_into()
                .unwrap();

            let quantised_minted_shares: u64 = (minted_shares / vault_share_config.quantum.into())
                .try_into()
                .unwrap();

            order
                .validate_against_actual_amounts(
                    actual_amount_base: quantised_minted_shares.try_into().unwrap(),
                    actual_amount_quote: order.quote_amount,
                    actual_fee: 0_u64,
                );

            let sending_position_diff = PositionDiff {
                collateral_diff: order.quote_amount.into(), asset_diff: Option::None,
            };

            self
                ._validate_healthy_or_healthier_position(
                    position_id: from_position_id,
                    position: sending_position_snapshot,
                    position_diff: sending_position_diff,
                    tvtr_before: Default::default(),
                );

            self
                .positions
                .apply_diff(position_id: from_position_id, position_diff: sending_position_diff);

            // 1. check that the collateral balance of the perps contract is returned to the
            // same amount as before deposit into vault
            // 2. apply diff to the vault position
            let new_collateral_balance = collateral_token_dispatcher
                .balance_of(starknet::get_contract_address());
            assert(new_collateral_balance == current_collateral_balance, 'COLLATERAL_NOT_RETURNED');

            let vault_position_diff = PositionDiff {
                collateral_diff: order.quote_amount.abs().into(), asset_diff: Option::None,
            };

            self
                .positions
                .apply_diff(position_id: vault_position_id, position_diff: vault_position_diff);

            let vault_token_erc20_dispatcher = IERC20Dispatcher {
                contract_address: vault_share_config.token_contract.expect('NOT_ERC20'),
            };

            vault_token_erc20_dispatcher
                .approve(
                    spender: starknet::get_contract_address(),
                    amount: quantised_minted_shares.into(),
                );

            self
                .emit(
                    events::InvestInVault {
                        vault_position_id: vault_position_id,
                        investing_position_id: from_position_id,
                        receiving_position_id: receiving_position_id,
                        shares_received: quantised_minted_shares,
                        user_investment: order.quote_amount.abs(),
                        vault_asset_id: vault_config.asset_id,
                        invested_asset_id: self.assets.get_collateral_id(),
                    },
                );

            self
                .deposits
                ._deposit(
                    caller_address: starknet::get_contract_address(),
                    asset_id: vault_config.asset_id,
                    position_id: receiving_position_id,
                    quantized_amount: quantised_minted_shares,
                    salt: salt,
                );
        }


        fn redeem_from_vault(
            ref self: ContractState,
            operator_nonce: u64,
            signature: Signature,
            order: LimitOrder,
            vault_approval: LimitOrder,
            vault_signature: Signature,
            actual_shares_user: i64,
            actual_collateral_user: i64,
        ) {
            //     /// Validations - System State:
            self.pausable.assert_not_paused();
            self.operator_nonce.use_checked_nonce(:operator_nonce);
            self.assets.validate_assets_integrity();

            //TODO signature validation

            self
                ._execute_redeem(
                    :order,
                    :vault_approval,
                    :vault_signature,
                    :actual_shares_user,
                    :actual_collateral_user,
                    validate_user_fulfillment: true,
                );
        }

        fn liquidate_vault_shares(
            ref self: ContractState,
            operator_nonce: u64,
            liquidated_position_id: PositionId,
            vault_approval: LimitOrder,
            vault_signature: Span<felt252>,
            liquidated_asset_id: AssetId,
            actual_shares_user: i64,
            actual_collateral_user: i64,
        ) {
            //     /// Validations - System State:
            self.pausable.assert_not_paused();
            self.operator_nonce.use_checked_nonce(:operator_nonce);
            self.assets.validate_assets_integrity();

            assert(
                self.positions.is_liquidatable(liquidated_position_id), 'POSITION_NOT_LIQUIDATABLE',
            );

            let user_order = LimitOrder {
                source_position: liquidated_position_id,
                receive_position: liquidated_position_id,
                base_asset_id: liquidated_asset_id,
                base_amount: -actual_shares_user,
                quote_asset_id: self.assets.get_collateral_id(),
                quote_amount: actual_collateral_user,
                fee_asset_id: self.assets.get_collateral_id(),
                fee_amount: 0_u64,
                salt: Zero::zero(),
                expiration: Time::now(),
            };

            self
                ._execute_redeem(
                    order: user_order,
                    :vault_approval,
                    :vault_signature,
                    :actual_shares_user,
                    :actual_collateral_user,
                    validate_user_fulfillment: false,
                );
        }
    }

    #[generate_trait]
    pub impl InternalCoreFunctions of InternalCoreFunctionsTrait {
        fn _execute_redeem(
            ref self: ContractState,
            order: LimitOrder,
            vault_approval: LimitOrder,
            vault_signature: Signature,
            actual_shares_user: i64,
            actual_collateral_user: i64,
            validate_user_fulfillment: bool,
        ) {
            let vault_config = self.vaults.get_vault_config_for_asset(order.base_asset_id);
            let vault_position_id: PositionId = vault_config.position_id.into();
            let redeeming_position_id = order.source_position;
            let receiving_position_id = order.receive_position;

            assert_with_byte_array(
                actual_shares_user < 0,
                format!("INVALID_ACTUAL_SHARES_AMOUNT: {}", actual_shares_user),
            );
            assert_with_byte_array(
                actual_collateral_user >= 0,
                format!("INVALID_ACTUAL_COLLATERAL_AMOUNT: {}", actual_collateral_user),
            );

            order
                .validate_against_actual_amounts(
                    actual_amount_base: actual_shares_user,
                    actual_amount_quote: actual_collateral_user,
                    actual_fee: 0_u64,
                );

            vault_approval
                .validate_against_actual_amounts(
                    actual_amount_base: -actual_shares_user,
                    actual_amount_quote: -actual_collateral_user,
                    actual_fee: 0_u64,
                );

            let vault_position = self.positions.get_position_snapshot(vault_position_id);
            let redeeming_position = self.positions.get_position_snapshot(redeeming_position_id);

            let amount_to_burn = actual_shares_user;
            let value_to_receive = actual_collateral_user;

            if (validate_user_fulfillment) {
                self
                    ._update_fulfillment(
                        position_id: redeeming_position_id,
                        hash: order.get_message_hash(redeeming_position.get_owner_public_key()),
                        order_base_amount: order.base_amount.try_into().unwrap(),
                        actual_base_amount: actual_shares_user.try_into().unwrap(),
                    );
            }
            self
                ._update_fulfillment(
                    position_id: vault_position_id,
                    hash: order.get_message_hash(vault_position.get_owner_public_key()),
                    order_base_amount: vault_approval.base_amount.try_into().unwrap(),
                    actual_base_amount: -actual_shares_user.try_into().unwrap(),
                );

            let vault_config = self
                .vaults
                .get_vault_config_for_position(vault_position: vault_position_id);
            let vault_asset = self.assets.get_asset_config(vault_config.asset_id);

            let vault_dispatcher = IProtocolVaultDispatcher {
                contract_address: vault_asset.token_contract.expect('NOT_ERC20'),
            };

            let vault_erc20Dispatcher = IERC20Dispatcher {
                contract_address: vault_asset.token_contract.expect('NOT_ERC20'),
            };

            let pnl_collateral_dispatcher = self.assets.get_collateral_token_contract();

            let unquantized_amount_to_burn = amount_to_burn.abs().wide_mul(vault_asset.quantum);

            //approve the vault contract to transfer pnl collateral to itself to "send back" to
            //perps
            pnl_collateral_dispatcher
                .approve(
                    spender: vault_asset.token_contract.expect('NOT_ERC20'),
                    amount: value_to_receive.abs().into(),
                );

            //approve the vault contract transferring vault shares to itself for burning
            vault_erc20Dispatcher
                .approve(
                    spender: vault_asset.token_contract.expect('NOT_ERC20'),
                    amount: unquantized_amount_to_burn.into(),
                );

            let burn_result = vault_dispatcher
                .redeem_with_price(
                    shares: unquantized_amount_to_burn.into(),
                    value_of_shares: value_to_receive.abs().into(),
                );

            assert_with_byte_array(
                burn_result == value_to_receive.abs().into(),
                format!("UNFAIR_REDEEM: expected {:?}, got {:?}", value_to_receive, burn_result),
            );

            let vault_position_diff = PositionDiff {
                collateral_diff: -value_to_receive.into(), asset_diff: None,
            };

            let (redeeming_position_diff, receiving_position_diff) =
                if (receiving_position_id == redeeming_position_id) {
                (
                    PositionDiff {
                        collateral_diff: value_to_receive.into(),
                        asset_diff: Some((vault_config.asset_id, amount_to_burn.into())),
                    },
                    None,
                )
            } else {
                (
                    PositionDiff {
                        asset_diff: Some((vault_config.asset_id, amount_to_burn.into())),
                        collateral_diff: 0_i64.into(),
                    },
                    Some(
                        PositionDiff { collateral_diff: value_to_receive.into(), asset_diff: None },
                    ),
                )
            };

            // vault health checks
            self
                ._validate_healthy_or_healthier_position(
                    position_id: vault_position_id,
                    position: vault_position,
                    position_diff: vault_position_diff,
                    tvtr_before: Default::default(),
                );

            self
                .positions
                .apply_diff(position_id: vault_position_id, position_diff: vault_position_diff);

            // prevent withdrawal of more collateral than is contained with the vault
            // protection against malicious operator
            self
                ._validate_asset_balance_is_not_negative(
                    position: vault_position, asset_id: self.assets.get_collateral_id(),
                );
            // user health checks

            self
                ._validate_healthy_or_healthier_position(
                    position_id: redeeming_position_id,
                    position: redeeming_position,
                    position_diff: redeeming_position_diff,
                    tvtr_before: Default::default(),
                );

            self
                .positions
                .apply_diff(
                    position_id: redeeming_position_id, position_diff: redeeming_position_diff,
                );

            // no need to validate health as can only receive collateral
            if let Option::Some(position_diff) = receiving_position_diff {
                self
                    .positions
                    .apply_diff(position_id: receiving_position_id, position_diff: position_diff);
            };
        }

        fn _execute_trade(
            ref self: ContractState,
            signature_a: Signature,
            signature_b: Signature,
            order_a: Order,
            order_b: Order,
            actual_amount_base_a: i64,
            actual_amount_quote_a: i64,
            actual_fee_a: u64,
            actual_fee_b: u64,
            tvtr_a_before: Nullable<PositionTVTR>,
            tvtr_b_before: Nullable<PositionTVTR>,
        ) -> (PositionTVTR, PositionTVTR) {
            self
                ._validate_trade(
                    :order_a,
                    :order_b,
                    :actual_amount_base_a,
                    :actual_amount_quote_a,
                    :actual_fee_a,
                    :actual_fee_b,
                );

            let position_id_a = order_a.position_id;
            let position_id_b = order_b.position_id;

            let position_a = self.positions.get_position_snapshot(position_id_a);
            let position_b = self.positions.get_position_snapshot(position_id_b);
            // Signatures validation:
            let hash_a = self
                ._validate_signature(
                    public_key: position_a.get_owner_public_key(),
                    order: order_a,
                    signature: signature_a,
                );
            let hash_b = self
                ._validate_signature(
                    public_key: position_b.get_owner_public_key(),
                    order: order_b,
                    signature: signature_b,
                );

            // Validate and update fulfillments.
            self
                ._update_fulfillment(
                    position_id: position_id_a,
                    hash: hash_a,
                    order_base_amount: order_a.base_amount,
                    actual_base_amount: actual_amount_base_a,
                );

            self
                ._update_fulfillment(
                    position_id: position_id_b,
                    hash: hash_b,
                    order_base_amount: order_b.base_amount,
                    // Passing the negative of actual amounts to `order_b` as it is linked to
                    // `order_a`.
                    actual_base_amount: -actual_amount_base_a,
                );

            /// Positions' Diffs:
            let position_diff_a = PositionDiff {
                collateral_diff: actual_amount_quote_a.into() - actual_fee_a.into(),
                asset_diff: Option::Some((order_a.base_asset_id, actual_amount_base_a.into())),
            };

            // Passing the negative of actual amounts to order_b as it is linked to order_a.
            let position_diff_b = PositionDiff {
                collateral_diff: -actual_amount_quote_a.into() - actual_fee_b.into(),
                asset_diff: Option::Some((order_b.base_asset_id, -actual_amount_base_a.into())),
            };

            // Assuming fee_asset_id is the same for both orders.
            let fee_position_diff = PositionDiff {
                collateral_diff: (actual_fee_a + actual_fee_b).into(), asset_diff: Option::None,
            };

            /// Validations - Fundamentals:
            let tvtr_a_after = self
                ._validate_healthy_or_healthier_position(
                    position_id: order_a.position_id,
                    position: position_a,
                    position_diff: position_diff_a,
                    tvtr_before: tvtr_a_before,
                );
            let tvtr_b_after = self
                ._validate_healthy_or_healthier_position(
                    position_id: order_b.position_id,
                    position: position_b,
                    position_diff: position_diff_b,
                    tvtr_before: tvtr_b_before,
                );

            // Apply Diffs.
            self
                .positions
                .apply_diff(position_id: order_a.position_id, position_diff: position_diff_a);

            self
                .positions
                .apply_diff(position_id: order_b.position_id, position_diff: position_diff_b);

            self.positions.apply_diff(position_id: FEE_POSITION, position_diff: fee_position_diff);

            self
                .emit(
                    events::Trade {
                        order_a_position_id: position_id_a,
                        order_a_base_asset_id: order_a.base_asset_id,
                        order_a_base_amount: order_a.base_amount,
                        order_a_quote_asset_id: order_a.quote_asset_id,
                        order_a_quote_amount: order_a.quote_amount,
                        fee_a_asset_id: order_a.fee_asset_id,
                        fee_a_amount: order_a.fee_amount,
                        order_b_position_id: position_id_b,
                        order_b_base_asset_id: order_b.base_asset_id,
                        order_b_base_amount: order_b.base_amount,
                        order_b_quote_asset_id: order_b.quote_asset_id,
                        order_b_quote_amount: order_b.quote_amount,
                        fee_b_asset_id: order_b.fee_asset_id,
                        fee_b_amount: order_b.fee_amount,
                        actual_amount_base_a,
                        actual_amount_quote_a,
                        actual_fee_a,
                        actual_fee_b,
                        order_a_hash: hash_a,
                        order_b_hash: hash_b,
                    },
                );
            (tvtr_a_after, tvtr_b_after)
        }


        fn _execute_transfer(
            ref self: ContractState,
            recipient: PositionId,
            position_id: PositionId,
            collateral_id: AssetId,
            amount: u64,
        ) {
            // Parameters

            let (position_diff_sender, position_diff_recipient) = if (collateral_id == self
                .assets
                .get_collateral_id()) {
                let position_diff_sender = PositionDiff {
                    collateral_diff: -amount.into(), asset_diff: Option::None,
                };

                let position_diff_recipient = PositionDiff {
                    collateral_diff: amount.into(), asset_diff: Option::None,
                };
                (position_diff_sender, position_diff_recipient)
            } else {
                let position_diff_sender = PositionDiff {
                    collateral_diff: 0_i64.into(),
                    asset_diff: Option::Some((collateral_id, -amount.into())),
                };

                let position_diff_recipient = PositionDiff {
                    collateral_diff: 0_i64.into(),
                    asset_diff: Option::Some((collateral_id, amount.into())),
                };
                (position_diff_sender, position_diff_recipient)
            };

            /// Validations - Fundamentals:
            let position = self.positions.get_position_snapshot(:position_id);
            self
                ._validate_healthy_or_healthier_position(
                    :position_id,
                    :position,
                    position_diff: position_diff_sender,
                    tvtr_before: Default::default(),
                );

            // Execute transfer
            self.positions.apply_diff(:position_id, position_diff: position_diff_sender);
            self
                .positions
                .apply_diff(position_id: recipient, position_diff: position_diff_recipient);

            self._validate_asset_balance_is_not_negative(:position, asset_id: collateral_id);
        }

        fn _update_fulfillment(
            ref self: ContractState,
            position_id: PositionId,
            hash: HashType,
            order_base_amount: i64,
            actual_base_amount: i64,
        ) {
            let fulfillment_entry = self.fulfillment.entry(hash);
            let total_amount = fulfillment_entry.read() + actual_base_amount.abs();
            assert_with_byte_array(
                total_amount <= order_base_amount.abs(), fulfillment_exceeded_err(:position_id),
            );
            fulfillment_entry.write(total_amount);
        }

        fn _validate_asset_balance_is_not_negative(
            ref self: ContractState, position: StoragePath<Position>, asset_id: AssetId,
        ) {
            let balance = if (asset_id == self.assets.get_collateral_id()) {
                self.positions.get_collateral_provisional_balance(position, None)
            } else {
                self.positions.get_synthetic_balance(:position, synthetic_id: asset_id)
            };

            assert(balance >= 0_i64.into(), 'ASSET_BALANCE_NEGATIVE');
        }

        fn _validate_order(ref self: ContractState, order: Order) {
            // Verify that position is not fee position.
            assert(order.position_id != FEE_POSITION, CANT_TRADE_WITH_FEE_POSITION);
            // This is to make sure that the fee is relative to the quote amount.
            assert(order.quote_amount.abs() > order.fee_amount, INVALID_QUOTE_FEE_AMOUNT);
            // Non-zero amount check.
            assert(order.base_amount.is_non_zero(), INVALID_ZERO_AMOUNT);
            assert(order.quote_amount.is_non_zero(), INVALID_ZERO_AMOUNT);

            // Expiration check.
            let now = Time::now();
            assert_with_byte_array(now <= order.expiration, order_expired_err(order.position_id));

            // Sign Validation for amounts.
            assert(!have_same_sign(order.quote_amount, order.base_amount), INVALID_AMOUNT_SIGN);

            // Validate asset ids.
            let collateral_id = self.assets.get_collateral_id();
            assert(order.quote_asset_id == collateral_id, ASSET_ID_NOT_COLLATERAL);
            assert(order.fee_asset_id == collateral_id, ASSET_ID_NOT_COLLATERAL);
        }

        fn _validate_trade(
            ref self: ContractState,
            order_a: Order,
            order_b: Order,
            actual_amount_base_a: i64,
            actual_amount_quote_a: i64,
            actual_fee_a: u64,
            actual_fee_b: u64,
        ) {
            // Base asset check.
            assert(order_a.base_asset_id == order_b.base_asset_id, DIFFERENT_BASE_ASSET_IDS);
            self.assets.validate_asset_active(synthetic_id: order_a.base_asset_id);

            assert(order_a.position_id != order_b.position_id, INVALID_SAME_POSITIONS);

            self._validate_order(order: order_a);
            self._validate_order(order: order_b);

            // Non-zero actual amount check.
            assert(actual_amount_base_a.is_non_zero(), INVALID_ZERO_AMOUNT);
            assert(actual_amount_quote_a.is_non_zero(), INVALID_ZERO_AMOUNT);

            // Sign Validation for amounts.
            assert(
                !have_same_sign(order_a.quote_amount, order_b.quote_amount),
                INVALID_QUOTE_AMOUNT_SIGN,
            );
            assert(
                have_same_sign(order_a.base_amount, actual_amount_base_a), INVALID_ACTUAL_BASE_SIGN,
            );
            assert(
                have_same_sign(order_a.quote_amount, actual_amount_quote_a),
                INVALID_ACTUAL_QUOTE_SIGN,
            );

            order_a
                .validate_against_actual_amounts(
                    actual_amount_base: actual_amount_base_a,
                    actual_amount_quote: actual_amount_quote_a,
                    actual_fee: actual_fee_a,
                );
            order_b
                .validate_against_actual_amounts(
                    // Passing the negative of actual amounts to order_b as it is linked to order_a.
                    actual_amount_base: -actual_amount_base_a,
                    actual_amount_quote: -actual_amount_quote_a,
                    actual_fee: actual_fee_b,
                );
        }

        fn _validate_synthetic_shrinks(
            ref self: ContractState,
            position: StoragePath<Position>,
            asset_id: AssetId,
            amount: i64,
        ) {
            let position_base_balance: i64 = self
                .positions
                .get_synthetic_balance(:position, synthetic_id: asset_id)
                .into();

            assert(!have_same_sign(amount, position_base_balance), INVALID_AMOUNT_SIGN);
            assert(amount.abs() <= position_base_balance.abs(), INVALID_BASE_CHANGE);
        }

        fn _validate_imposed_reduction_trade(
            ref self: ContractState,
            position_id_a: PositionId,
            position_id_b: PositionId,
            position_a: StoragePath<Position>,
            position_b: StoragePath<Position>,
            base_asset_id: AssetId,
            base_amount_a: i64,
            quote_amount_a: i64,
        ) {
            // Validate positions.
            assert(position_id_a != position_id_b, INVALID_SAME_POSITIONS);

            // Non-zero amount check.
            assert(base_amount_a.is_non_zero(), INVALID_ZERO_AMOUNT);
            assert(quote_amount_a.is_non_zero(), INVALID_ZERO_AMOUNT);

            // Sign Validation for amounts.
            assert(!have_same_sign(base_amount_a, quote_amount_a), INVALID_AMOUNT_SIGN);

            // Ensure that TR does not increase and that the base amount retains the same sign.
            self
                ._validate_synthetic_shrinks(
                    position: position_a, asset_id: base_asset_id, amount: base_amount_a,
                );
            self
                ._validate_synthetic_shrinks(
                    position: position_b, asset_id: base_asset_id, amount: -base_amount_a,
                );
        }

        fn _validate_signature<T, +Drop<T>, +Copy<T>, +OffchainMessageHash<T>>(
            self: @ContractState, public_key: PublicKey, order: T, signature: Signature,
        ) -> HashType {
            let msg_hash = order.get_message_hash(:public_key);
            validate_stark_signature(:public_key, :msg_hash, :signature);
            msg_hash
        }

        fn _validate_healthy_or_healthier_position(
            self: @ContractState,
            position_id: PositionId,
            position: StoragePath<Position>,
            position_diff: PositionDiff,
            tvtr_before: Nullable<PositionTVTR>,
        ) -> PositionTVTR {
            let synthetic_enriched_position_diff = self.enrich_asset(:position, :position_diff);
            let tvtr_before = match match_nullable(tvtr_before) {
                FromNullableResult::Null => {
                    let (provisional_delta, unchanged_assets) = self
                        .positions
                        .derive_funding_delta_and_unchanged_assets(:position, :position_diff);
                    let position_diff_enriched = self
                        .enrich_collateral(
                            :position,
                            position_diff: synthetic_enriched_position_diff,
                            provisional_delta: Option::Some(provisional_delta),
                        );

                    calculate_position_tvtr_before(:unchanged_assets, :position_diff_enriched)
                },
                FromNullableResult::NotNull(value) => value.unbox(),
            };
            let tvtr = calculate_position_tvtr_change(
                :tvtr_before, :synthetic_enriched_position_diff,
            );
            assert_healthy_or_healthier(:position_id, :tvtr);
            tvtr.after
        }

        fn _validate_liquidated_position(
            ref self: ContractState,
            position_id: PositionId,
            position: StoragePath<Position>,
            position_diff: PositionDiff,
        ) {
            let (synthetic_diff_id, synthetic_diff_balance) = if let Option::Some((id, balance)) =
                position_diff
                .asset_diff {
                (id, balance)
            } else {
                panic_with_felt252(SYNTHETIC_NOT_EXISTS)
            };
            self
                ._validate_synthetic_shrinks(
                    :position, asset_id: synthetic_diff_id, amount: synthetic_diff_balance.into(),
                );
            let (provisional_delta, unchanged_assets) = self
                .positions
                .derive_funding_delta_and_unchanged_assets(:position, :position_diff);
            let synthetic_enriched_position_diff = self.enrich_asset(:position, :position_diff);
            let position_diff_enriched = self
                .enrich_collateral(
                    :position,
                    position_diff: synthetic_enriched_position_diff,
                    provisional_delta: Option::Some(provisional_delta),
                );

            liquidated_position_validations(
                :position_id, :unchanged_assets, :position_diff_enriched,
            );
        }

        fn _validate_deleveraged_position(
            self: @ContractState,
            position_id: PositionId,
            position: StoragePath<Position>,
            position_diff: PositionDiff,
        ) {
            let (provisional_delta, unchanged_assets) = self
                .positions
                .derive_funding_delta_and_unchanged_assets(:position, :position_diff);

            let synthetic_enriched_position_diff = self.enrich_asset(:position, :position_diff);
            let position_diff_enriched = self
                .enrich_collateral(
                    :position,
                    position_diff: synthetic_enriched_position_diff,
                    provisional_delta: Option::Some(provisional_delta),
                );

            deleveraged_position_validations(
                :position_id, :unchanged_assets, :position_diff_enriched,
            );
        }

        /// Enriches collateral, producing a fully enriched diff.
        /// This computation is relatively expensive due to the funding mechanism.
        /// If the calculation can rely on the raw collateral values, prefer using
        /// `PositionDiff` or `AssetEnrichedPositionDiff` without fully enriching.
        fn enrich_collateral(
            self: @ContractState,
            position: StoragePath<Position>,
            position_diff: AssetEnrichedPositionDiff,
            provisional_delta: Option<Balance>,
        ) -> PositionDiffEnriched {
            let before = self
                .positions
                .get_collateral_provisional_balance(:position, :provisional_delta);
            let after = before + position_diff.collateral_diff;
            let collateral_enriched = BalanceDiff { before: before, after };

            PositionDiffEnriched {
                collateral_enriched: collateral_enriched,
                asset_diff_enriched: position_diff.asset_diff_enriched,
            }
        }

        /// Enriches the synthetic part, leaving collateral raw.
        fn enrich_asset(
            self: @ContractState, position: StoragePath<Position>, position_diff: PositionDiff,
        ) -> AssetEnrichedPositionDiff {
            let asset_diff_enriched = if let Option::Some((synthetic_id, diff)) = position_diff
                .asset_diff {
                let balance_before = self.positions.get_synthetic_balance(:position, :synthetic_id);
                let balance_after = balance_before + diff;
                let price = self.assets.get_asset_price(synthetic_id);
                let risk_factor_before = self
                    .assets
                    .get_asset_risk_factor(synthetic_id, balance_before, price);
                let risk_factor_after = self
                    .assets
                    .get_asset_risk_factor(synthetic_id, balance_after, price);

                let asset_diff_enriched = AssetBalanceDiffEnriched {
                    asset_id: synthetic_id,
                    balance_before,
                    balance_after,
                    price,
                    risk_factor_before,
                    risk_factor_after,
                };
                Option::Some(asset_diff_enriched)
            } else {
                Option::None
            };
            AssetEnrichedPositionDiff {
                collateral_diff: position_diff.collateral_diff,
                asset_diff_enriched: asset_diff_enriched,
            }
        }
    }
}
