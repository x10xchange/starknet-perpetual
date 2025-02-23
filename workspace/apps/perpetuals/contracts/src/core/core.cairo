#[starknet::contract]
pub mod Core {
    use contracts_commons::components::deposit::Deposit;
    use contracts_commons::components::deposit::Deposit::InternalTrait as DepositInternal;
    use contracts_commons::components::nonce::NonceComponent;
    use contracts_commons::components::nonce::NonceComponent::InternalTrait as NonceInternal;
    use contracts_commons::components::pausable::PausableComponent;
    use contracts_commons::components::pausable::PausableComponent::InternalTrait as PausableInternal;
    use contracts_commons::components::replaceability::ReplaceabilityComponent;
    use contracts_commons::components::replaceability::ReplaceabilityComponent::InternalReplaceabilityTrait;
    use contracts_commons::components::request_approvals::RequestApprovalsComponent;
    use contracts_commons::components::request_approvals::RequestApprovalsComponent::InternalTrait as RequestApprovalsInternal;
    use contracts_commons::components::roles::RolesComponent;
    use contracts_commons::components::roles::RolesComponent::InternalTrait as RolesInternal;
    use contracts_commons::errors::assert_with_byte_array;
    use contracts_commons::math::abs::Abs;
    use contracts_commons::math::utils::have_same_sign;
    use contracts_commons::message_hash::OffchainMessageHash;
    use contracts_commons::types::time::time::{Time, TimeDelta, Timestamp};
    use contracts_commons::types::{HashType, PublicKey, Signature};
    use contracts_commons::utils::{validate_expiration, validate_stark_signature};
    use core::num::traits::Zero;
    use core::panic_with_felt252;
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::introspection::src5::SRC5Component;
    use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use openzeppelin::utils::snip12::SNIP12Metadata;
    use perpetuals::core::components::assets::AssetsComponent;
    use perpetuals::core::components::assets::AssetsComponent::InternalTrait as AssetsInternal;
    use perpetuals::core::components::positions::Positions;
    use perpetuals::core::components::positions::Positions::{
        FEE_POSITION, INSURANCE_FUND_POSITION, InternalTrait as PositionsInternalTrait,
    };
    use perpetuals::core::errors::{
        CANT_DELEVERAGE_PENDING_ASSET, DIFFERENT_BASE_ASSET_IDS, DIFFERENT_QUOTE_ASSET_IDS,
        FEE_ASSET_AMOUNT_MISMATCH, INSUFFICIENT_FUNDS, INVALID_DELEVERAGE_BASE_CHANGE,
        INVALID_FUNDING_TICK_LEN, INVALID_NON_SYNTHETIC_ASSET, INVALID_QUOTE_AMOUNT_SIGN,
        INVALID_SAME_POSITIONS, INVALID_WRONG_AMOUNT_SIGN, INVALID_ZERO_AMOUNT, TRANSFER_EXPIRED,
        WITHDRAW_EXPIRED, fulfillment_exceeded_err, order_expired_err,
    };

    use perpetuals::core::events;
    use perpetuals::core::interface::ICore;
    use perpetuals::core::types::asset::{AssetId, AssetStatus};
    use perpetuals::core::types::balance::Balance;
    use perpetuals::core::types::funding::FundingTick;
    use perpetuals::core::types::order::{Order, OrderTrait};
    use perpetuals::core::types::price::{PriceTrait, SignedPrice};
    use perpetuals::core::types::transfer::TransferArgs;
    use perpetuals::core::types::withdraw::WithdrawArgs;
    use perpetuals::core::types::{AssetDiff, PositionDiff, PositionId};
    use perpetuals::core::value_risk_calculator::{
        validate_deleveraged_position, validate_liquidated_position,
        validate_position_is_healthy_or_healthier,
    };
    use starknet::event::EventEmitter;
    use starknet::storage::{
        Map, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_contract_address};

    component!(path: AccessControlComponent, storage: accesscontrol, event: AccessControlEvent);
    component!(path: NonceComponent, storage: nonce, event: NonceEvent);
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

    #[abi(embed_v0)]
    impl NonceImpl = NonceComponent::NonceImpl<ContractState>;
    impl NonceComponentInternalImpl = NonceComponent::InternalImpl<ContractState>;

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
        nonce: NonceComponent::Storage,
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
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        AccessControlEvent: AccessControlComponent::Event,
        #[flat]
        NonceEvent: NonceComponent::Event,
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
        Liquidate: events::Liquidate,
        Trade: events::Trade,
        Transfer: events::Transfer,
        TransferRequest: events::TransferRequest,
        Withdraw: events::Withdraw,
        WithdrawRequest: events::WithdrawRequest,
    }

    #[constructor]
    pub fn constructor(
        ref self: ContractState,
        governance_admin: ContractAddress,
        upgrade_delay: u64,
        max_price_interval: TimeDelta,
        max_funding_interval: TimeDelta,
        max_funding_rate: u32,
        max_oracle_price_validity: TimeDelta,
        deposit_grace_period: TimeDelta,
        fee_position_owner_account: ContractAddress,
        fee_position_owner_public_key: PublicKey,
        insurance_fund_position_owner_account: ContractAddress,
        insurance_fund_position_owner_public_key: PublicKey,
    ) {
        self.roles.initialize(:governance_admin);
        self.replaceability.initialize(:upgrade_delay);
        self
            .assets
            .initialize(
                :max_price_interval,
                :max_funding_interval,
                :max_funding_rate,
                :max_oracle_price_validity,
            );
        self.deposits.initialize(deposit_grace_period);
        self
            .positions
            .initialize(
                :fee_position_owner_account,
                :fee_position_owner_public_key,
                :insurance_fund_position_owner_account,
                :insurance_fund_position_owner_public_key,
            );
    }

    #[abi(embed_v0)]
    pub impl CoreImpl of ICore<ContractState> {
        /// Process deposit a collateral amount from the 'depositing_address' to a given position.
        ///
        /// Validations:
        /// - Only the operator can call this function.
        /// - The contract must not be paused.
        /// - The `operator_nonce` must be valid.
        /// - The `expiration` time has not passed.
        /// - The collateral asset exists in the system.
        /// - The collateral asset is active.
        /// - The funding validation interval has not passed since the last funding tick.
        /// - [The prices of all assets in the system are valid](`_validate_prices`).
        /// - The deposit message has not been fulfilled.
        /// - A fact was registered for the deposit message.
        /// - If position exists, validate the owner_public_key and owner_account are the same.
        ///
        /// Execution:
        /// - Transfer the collateral `amount` to the position from the pending deposits.
        /// - Update the position's collateral balance.
        /// - Mark the deposit message as fulfilled.
        fn process_deposit(
            ref self: ContractState,
            operator_nonce: u64,
            depositor: ContractAddress,
            position_id: PositionId,
            collateral_id: AssetId,
            amount: u64,
            salt: felt252,
        ) {
            self._validate_deposit(:operator_nonce, :position_id, :collateral_id, :amount);
            self
                .deposits
                .process_deposit(
                    :depositor,
                    beneficiary: position_id.into(),
                    asset_id: collateral_id.into(),
                    quantized_amount: amount.into(),
                    :salt,
                );
            let position_diff = self
                ._create_position_diff(:position_id, asset_id: collateral_id, diff: amount.into());
            self.positions.apply_diff(:position_id, :position_diff);
        }

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
            collateral_id: AssetId,
            amount: u64,
            expiration: Timestamp,
            salt: felt252,
        ) {
            let position = self.positions.get_position_snapshot(:position_id);
            assert(amount.is_non_zero(), INVALID_ZERO_AMOUNT);
            let hash = self
                .request_approvals
                .register_approval(
                    owner_account: position.owner_account.read(),
                    public_key: position.owner_public_key.read(),
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
        /// - [The prices of all assets in the system are valid](`_validate_prices`).
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
            collateral_id: AssetId,
            amount: u64,
            expiration: Timestamp,
            salt: felt252,
        ) {
            self
                ._validate_withdraw(
                    :operator_nonce, :position_id, :collateral_id, :amount, :expiration,
                );
            /// Validation - Not withdrawing from pending deposits:
            let collateral_cfg = self.assets.get_collateral_config(:collateral_id);
            let token_contract = IERC20Dispatcher {
                contract_address: collateral_cfg.token_address,
            };
            let withdraw_unquantized_amount = collateral_cfg.quantum * amount;
            self
                ._validate_sufficient_funds(
                    :token_contract, :collateral_id, :withdraw_unquantized_amount,
                );
            /// Execution - Withdraw:
            token_contract.transfer(:recipient, amount: withdraw_unquantized_amount.into());

            /// Validations - Fundamentals:
            let position_diff = self
                ._create_position_diff(:position_id, asset_id: collateral_id, diff: amount.into());
            let position_data = self.positions.get_position_data(:position_id);

            validate_position_is_healthy_or_healthier(:position_id, :position_data, :position_diff);
            self.positions.apply_diff(:position_id, :position_diff);
            let position = self.positions.get_position_snapshot(:position_id);
            let hash = self
                .request_approvals
                .consume_approved_request(
                    args: WithdrawArgs {
                        position_id, salt, expiration, collateral_id, amount, recipient,
                    },
                    public_key: position.owner_public_key.read(),
                );
            self
                .emit(
                    events::Withdraw {
                        position_id,
                        recipient,
                        collateral_id,
                        amount,
                        expiration,
                        withdraw_request_hash: hash,
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
            recipient: PositionId,
            position_id: PositionId,
            collateral_id: AssetId,
            amount: u64,
            expiration: Timestamp,
            salt: felt252,
        ) {
            let position = self.positions.get_position_snapshot(:position_id);
            assert(amount.is_non_zero(), INVALID_ZERO_AMOUNT);
            let hash = self
                .request_approvals
                .register_approval(
                    owner_account: position.owner_account.read(),
                    public_key: position.owner_public_key.read(),
                    :signature,
                    args: TransferArgs {
                        position_id, recipient, salt, expiration, collateral_id, amount,
                    },
                );
            self
                .emit(
                    events::TransferRequest {
                        position_id,
                        recipient,
                        collateral_id,
                        amount,
                        expiration,
                        transfer_request_hash: hash,
                    },
                );
        }

        /// Executes a transfer.
        ///
        /// Validations:
        /// - Performs operator flow validations [`_validate_operator_flow`].
        /// - Validates both the sender and recipient positions exist.
        /// - Validates the collateral asset exists.
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
            recipient: PositionId,
            position_id: PositionId,
            collateral_id: AssetId,
            amount: u64,
            expiration: Timestamp,
            salt: felt252,
        ) {
            self
                ._validate_transfer(
                    :operator_nonce,
                    :recipient,
                    :position_id,
                    :collateral_id,
                    :amount,
                    :expiration,
                    :salt,
                );
            let position = self.positions.get_position_snapshot(:position_id);
            self._execute_transfer(:recipient, :position_id, :collateral_id, :amount);
            let hash = self
                .request_approvals
                .consume_approved_request(
                    args: TransferArgs {
                        recipient, position_id, collateral_id, amount, expiration, salt,
                    },
                    public_key: position.owner_public_key.read(),
                );
            self
                .emit(
                    events::Transfer {
                        recipient,
                        position_id,
                        collateral_id,
                        amount,
                        expiration,
                        transfer_request_hash: hash,
                    },
                );
        }

        /// Executes a trade between two orders (Order A and Order B).
        ///
        /// Validations:
        /// - Performs operator flow validations [`_validate_operator_flow`].
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
            self._validate_operator_flow(:operator_nonce);

            let position_id_a = order_a.position_id;
            let position_id_b = order_b.position_id;
            // Signatures validation:
            let hash_a = self
                ._validate_order_signature(
                    position_id: position_id_a, order: order_a, signature: signature_a,
                );
            let hash_b = self
                ._validate_order_signature(
                    position_id: position_id_b, order: order_b, signature: signature_b,
                );

            // Validate and update fulfillments.
            self
                ._update_fulfillment(
                    position_id: position_id_a,
                    hash: hash_a,
                    order_amount: order_a.base_amount,
                    actual_amount: actual_amount_base_a,
                );
            self
                ._update_fulfillment(
                    position_id: position_id_b,
                    hash: hash_b,
                    order_amount: order_b.base_amount,
                    // Passing the negative of actual amounts to `order_b` as it is linked to
                    // `order_a`.
                    actual_amount: -actual_amount_base_a,
                );

            self
                ._validate_orders(
                    :order_a,
                    :order_b,
                    :actual_amount_base_a,
                    :actual_amount_quote_a,
                    :actual_fee_a,
                    :actual_fee_b,
                );

            /// Execution:
            let position_data_a = self.positions.get_position_data(position_id: position_id_a);
            let position_data_b = self.positions.get_position_data(position_id: position_id_b);

            let (position_diff_a, position_diff_b) = self
                ._update_positions(
                    :order_a,
                    :order_b,
                    :actual_amount_base_a,
                    :actual_amount_quote_a,
                    :actual_fee_a,
                    :actual_fee_b,
                    fee_position_a: FEE_POSITION,
                    fee_position_b: FEE_POSITION,
                );

            /// Validations - Fundamentals:
            validate_position_is_healthy_or_healthier(
                position_id: order_a.position_id,
                position_data: position_data_a,
                position_diff: position_diff_a,
            );
            validate_position_is_healthy_or_healthier(
                position_id: order_b.position_id,
                position_data: position_data_b,
                position_diff: position_diff_b,
            );

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
        }

        /// Executes a liquidate of a user position with liquidator order.
        ///
        /// Validations:
        /// - Performs operator flow validations [`_validate_operator_flow`].
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
            fee_asset_id: AssetId,
            fee_amount: u64,
        ) {
            /// Validations:
            self._validate_operator_flow(:operator_nonce);

            let liquidator_position_id = liquidator_order.position_id;
            // Signatures validation:
            let liquidator_order_hash = self
                ._validate_order_signature(
                    position_id: liquidator_position_id,
                    order: liquidator_order,
                    signature: liquidator_signature,
                );

            // Validate and update fulfillment.
            self
                ._update_fulfillment(
                    position_id: liquidator_position_id,
                    hash: liquidator_order_hash,
                    order_amount: liquidator_order.base_amount,
                    // Passing the negative of actual amounts to `liquidator_order` as it is linked
                    // to liquidated_order.
                    actual_amount: -actual_amount_base_liquidated,
                );

            let liquidated_order = Order {
                position_id: liquidated_position_id,
                base_asset_id: liquidator_order.base_asset_id,
                base_amount: actual_amount_base_liquidated,
                quote_asset_id: liquidator_order.quote_asset_id,
                quote_amount: actual_amount_quote_liquidated,
                fee_asset_id,
                fee_amount,
                // Dummy values needed to initialize the struct and pass validation.
                ..liquidator_order,
            };

            // Validations.
            self
                ._validate_orders(
                    order_a: liquidated_order,
                    order_b: liquidator_order,
                    actual_amount_base_a: actual_amount_base_liquidated,
                    actual_amount_quote_a: actual_amount_quote_liquidated,
                    actual_fee_a: fee_amount,
                    actual_fee_b: actual_liquidator_fee,
                );

            /// Execution:
            let liquidated_position_data = self
                .positions
                .get_position_data(position_id: liquidated_position_id);
            let liquidator_position_data = self
                .positions
                .get_position_data(position_id: liquidator_position_id);

            let (liquidated_position_diff, liquidator_position_diff) = self
                ._update_positions(
                    order_a: liquidated_order,
                    order_b: liquidator_order,
                    actual_amount_base_a: actual_amount_base_liquidated,
                    actual_amount_quote_a: actual_amount_quote_liquidated,
                    actual_fee_a: fee_amount,
                    actual_fee_b: actual_liquidator_fee,
                    fee_position_a: INSURANCE_FUND_POSITION,
                    fee_position_b: FEE_POSITION,
                );

            /// Validations - Fundamentals:
            validate_liquidated_position(
                position_id: liquidated_position_id,
                position_data: liquidated_position_data,
                position_diff: liquidated_position_diff,
            );
            validate_position_is_healthy_or_healthier(
                position_id: liquidator_position_id,
                position_data: liquidator_position_data,
                position_diff: liquidator_position_diff,
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
                        insurance_fund_fee_asset_id: fee_asset_id,
                        insurance_fund_fee_amount: fee_amount,
                        liquidator_order_hash: liquidator_order_hash,
                    },
                );
        }

        /// Executes a deleverage of a user position with a deleverager position.
        ///
        /// Validations:
        /// - Performs operator flow validations [`_validate_operator_flow`].
        /// - Verifies the signs of amounts:
        ///   - Ensures the opposite sign of amounts in base and quote.
        ///   - Ensures the sign of amounts in each position is consistent.
        /// - If base asset is active, validates the deleveraged position is deleveragable.
        /// - If base asset is inactive, it can always be deleveraged.
        ///
        /// Execution:
        /// - Update the position, based on `delevereged_base_asset`.
        /// - Adjust collateral balances based on `delevereged_quote_asset`.
        /// - Perform fundamental validation for both positions after the execution.
        fn deleverage(
            ref self: ContractState,
            operator_nonce: u64,
            deleveraged_position: PositionId,
            deleverager_position: PositionId,
            deleveraged_base_asset_id: AssetId,
            deleveraged_base_amount: i64,
            deleveraged_quote_asset_id: AssetId,
            deleveraged_quote_amount: i64,
        ) {
            /// Validations:
            self._validate_operator_flow(:operator_nonce);

            self
                ._validate_deleverage(
                    :deleveraged_position,
                    :deleverager_position,
                    :deleveraged_base_asset_id,
                    :deleveraged_base_amount,
                    :deleveraged_quote_asset_id,
                    :deleveraged_quote_amount,
                );

            /// Execution:
            self
                ._execute_deleverage(
                    :deleveraged_position,
                    :deleverager_position,
                    :deleveraged_base_asset_id,
                    :deleveraged_base_amount,
                    :deleveraged_quote_asset_id,
                    :deleveraged_quote_amount,
                );

            self
                .emit(
                    events::Deleverage {
                        deleveraged_position,
                        deleverager_position,
                        deleveraged_base_asset_id,
                        deleveraged_base_amount,
                        deleveraged_quote_asset_id,
                        deleveraged_quote_amount,
                    },
                )
        }

        /// Add collateral asset is called by the operator to add a new collateral asset.
        /// We only have one collateral asset.
        ///
        /// Validations:
        /// - Only the operator can call this function.
        /// - The asset does not exists.
        /// - There's no collateral asset in the system.
        ///
        /// Execution:
        /// - Adds a new entry to collateral_config.
        /// - Adds a new entry at the beginning of collateral_timely_data
        ///     - Sets the price to TWO_POW_28.
        ///     - Sets the `last_price_update` to zero.
        ///     - Sets the risk factor to zero.
        ///     - Sets the quorum to zero.
        /// - Registers the token to deposits component.
        fn register_collateral(
            ref self: ContractState,
            asset_id: AssetId,
            token_address: ContractAddress,
            quantum: u64,
        ) {
            // Validations:
            self.roles.only_app_governor();

            // Execution:
            self
                .assets
                .add_collateral(
                    :asset_id,
                    :token_address,
                    risk_factor: Zero::zero(),
                    :quantum,
                    quorum: Zero::zero(),
                );
            self.deposits.register_token(asset_id: asset_id.into(), :token_address, :quantum)
        }


        /// Funding tick is called by the operator to update the funding index of all synthetic
        /// assets.
        ///
        /// Funding ticks asset ids MUST be in ascending order.
        /// Validations:
        /// - Only the operator can call this function.
        /// - The contract must not be paused.
        /// - The system nonce must be valid.
        /// - The number of funding ticks must be equal to the number of active synthetic assets.
        ///
        /// Execution:
        /// - Initialize the previous asset id to zero.
        /// - For each funding tick in funding_ticks:
        ///     - Validate the the funding tick asset_id is larger then the previous asset id.
        ///     - The funding tick synthetic asset_id asset exists in the system.
        ///     - The funding tick synthetic asset_id asset is active.
        ///     - The funding index must be within the max funding rate using the following formula:
        ///         |prev_funding_index-new_funding_index| <= max_funding_rate * time_diff *
        ///         synthetic_price
        ///    - Update the synthetic asset's funding index.
        ///    - Update the previous asset id to the current funding tick asset id.
        /// - Update the last funding tick time.
        fn funding_tick(
            ref self: ContractState, operator_nonce: u64, funding_ticks: Span<FundingTick>,
        ) {
            self._validate_funding_tick(:funding_ticks, :operator_nonce);
            self.assets.execute_funding_tick(:funding_ticks);
        }

        /// Price tick for an asset to update the price of the asset.
        ///
        /// Validations:
        /// - Contract is not paused
        /// - Only the operator can call this function.
        /// - Operator nonce is valid.
        /// - Prices array is sorted according to the signer public key.
        /// - The price is the median of the prices.
        /// - The signature is valid.
        /// - The timestamp is valid(less than the max oracle price validity).
        ///
        /// Execution:
        /// - Update the asset price.
        ///     The updated price is: (price * 2^28)/ (resolution_factor * 10^12).
        fn price_tick(
            ref self: ContractState,
            operator_nonce: u64,
            asset_id: AssetId,
            price: u128,
            signed_prices: Span<SignedPrice>,
        ) {
            self.pausable.assert_not_paused();
            self.roles.only_operator();
            self.nonce.use_checked_nonce(nonce: operator_nonce);
            self.assets.validate_price_tick(:asset_id, :price, :signed_prices);

            let synthetic_config = self.assets.get_synthetic_config(synthetic_id: asset_id);
            let converted_price = price.convert(resolution: synthetic_config.resolution);
            self.assets.set_price(:asset_id, price: converted_price);
        }
    }

    #[generate_trait]
    pub impl InternalCoreFunctions of InternalCoreFunctionsTrait {
        fn _create_position_diff(
            self: @ContractState, position_id: PositionId, asset_id: AssetId, diff: Balance,
        ) -> PositionDiff {
            array![self._create_asset_diff(:position_id, :asset_id, :diff)].span()
        }

        fn _create_asset_diff(
            self: @ContractState, position_id: PositionId, asset_id: AssetId, diff: Balance,
        ) -> AssetDiff {
            let position_asset_balance = self
                .positions
                .get_provisional_balance(:position_id, :asset_id);
            let price = self.assets.get_asset_price(:asset_id);
            let balance_before = position_asset_balance;
            let balance_after = position_asset_balance + diff;
            AssetDiff {
                id: asset_id,
                balance_before,
                balance_after,
                price,
                risk_factor_before: self.assets.get_risk_factor(:asset_id, balance: balance_before),
                risk_factor_after: self.assets.get_risk_factor(:asset_id, balance: balance_after),
            }
        }

        /// Builds assets diff from an order's fee, quote, and base assets, handling overlaps
        /// by updating existing diffs. If an asset matches an existing entry, only `after
        /// balance` is updated.
        fn _create_position_diff_from_order(
            ref self: ContractState,
            order: Order,
            actual_amount_base: i64,
            actual_amount_quote: i64,
            actual_fee: u64,
        ) -> PositionDiff {
            self
                ._create_position_diff_from_asset_amounts(
                    position_id: order.position_id,
                    base_id: order.base_asset_id,
                    base_amount: actual_amount_base,
                    quote_id: order.quote_asset_id,
                    quote_amount: actual_amount_quote,
                    fee_id: Option::Some(order.fee_asset_id),
                    fee_amount: Option::Some(actual_fee),
                )
        }

        fn _create_position_diff_from_asset_amounts(
            ref self: ContractState,
            position_id: PositionId,
            base_id: AssetId,
            base_amount: i64,
            quote_id: AssetId,
            quote_amount: i64,
            fee_id: Option<AssetId>,
            fee_amount: Option<u64>,
        ) -> PositionDiff {
            assert(fee_id.is_some() == fee_amount.is_some(), FEE_ASSET_AMOUNT_MISMATCH);
            let is_fee_exist = fee_id.is_some();

            // fee asset.
            let mut fee_diff: AssetDiff = Default::default();
            let mut fee_asset_id: AssetId = Zero::zero();
            if let (Option::Some(fee_amount), Option::Some(fee_id)) = (fee_amount, fee_id) {
                fee_asset_id = fee_id;
                fee_diff = self
                    ._create_asset_diff(
                        :position_id, asset_id: fee_asset_id, diff: -(fee_amount.into()),
                    );
            }

            // Quote asset.
            let mut quote_diff: AssetDiff = Default::default();

            if is_fee_exist && (quote_id == fee_asset_id) {
                fee_diff.balance_after += quote_amount.into();
            } else {
                quote_diff = self
                    ._create_asset_diff(
                        :position_id, asset_id: quote_id, diff: quote_amount.into(),
                    );
            }

            // Base asset.
            let mut base_diff: AssetDiff = Default::default();

            if is_fee_exist && (base_id == fee_asset_id) {
                fee_diff.balance_after += base_amount.into();
            } else if base_id == quote_id {
                quote_diff.balance_after += base_amount.into();
            } else {
                base_diff = self
                    ._create_asset_diff(:position_id, asset_id: base_id, diff: base_amount.into());
            }

            // Build position diff.
            let mut position_diff = array![];
            for asset_diff in array![fee_diff, quote_diff, base_diff] {
                if asset_diff.id != Default::default() {
                    position_diff.append(asset_diff);
                }
            };
            position_diff.span()
        }

        fn _update_positions(
            ref self: ContractState,
            order_a: Order,
            order_b: Order,
            actual_amount_base_a: i64,
            actual_amount_quote_a: i64,
            actual_fee_a: u64,
            actual_fee_b: u64,
            fee_position_a: PositionId,
            fee_position_b: PositionId,
        ) -> (PositionDiff, PositionDiff) {
            let position_diff_a = self
                ._create_position_diff_from_order(
                    order: order_a,
                    actual_amount_base: actual_amount_base_a,
                    actual_amount_quote: actual_amount_quote_a,
                    actual_fee: actual_fee_a,
                );
            let position_diff_b = self
                ._create_position_diff_from_order(
                    order: order_b,
                    // Passing the negative of actual amounts to order_b as it is linked to order_a.
                    actual_amount_base: -actual_amount_base_a,
                    actual_amount_quote: -actual_amount_quote_a,
                    actual_fee: actual_fee_b,
                );

            // Apply the position diff.
            self
                .positions
                .apply_diff(position_id: order_a.position_id, position_diff: position_diff_a);
            self
                .positions
                .apply_diff(position_id: order_b.position_id, position_diff: position_diff_b);

            // Update fee positions.
            let fee_position_diff_a = self
                ._create_position_diff(
                    position_id: fee_position_a,
                    asset_id: order_a.fee_asset_id,
                    diff: actual_fee_a.into(),
                );
            self
                .positions
                .apply_diff(position_id: fee_position_a, position_diff: fee_position_diff_a);

            let fee_position_diff_b = self
                ._create_position_diff(
                    position_id: fee_position_b,
                    asset_id: order_b.fee_asset_id,
                    diff: actual_fee_b.into(),
                );
            self
                .positions
                .apply_diff(position_id: fee_position_b, position_diff: fee_position_diff_b);

            (position_diff_a, position_diff_b)
        }

        fn _execute_transfer(
            ref self: ContractState,
            recipient: PositionId,
            position_id: PositionId,
            collateral_id: AssetId,
            amount: u64,
        ) {
            // Parameters
            let sender_position_data = self.positions.get_position_data(:position_id);
            let position_diff_sender = self
                ._create_position_diff(
                    :position_id, asset_id: collateral_id, diff: -(amount.into()),
                );
            let position_diff_recipient = self
                ._create_position_diff(
                    position_id: recipient, asset_id: collateral_id, diff: amount.into(),
                );

            // Execute transfer
            self.positions.apply_diff(:position_id, position_diff: position_diff_sender);

            self
                .positions
                .apply_diff(position_id: recipient, position_diff: position_diff_recipient);

            /// Validations - Fundamentals:
            validate_position_is_healthy_or_healthier(
                :position_id,
                position_data: sender_position_data,
                position_diff: position_diff_sender,
            );
        }

        fn _update_fulfillment(
            ref self: ContractState,
            position_id: PositionId,
            hash: HashType,
            order_amount: i64,
            actual_amount: i64,
        ) {
            let fulfillment_entry = self.fulfillment.entry(hash);
            let total_amount = fulfillment_entry.read() + actual_amount.abs();
            assert_with_byte_array(
                total_amount <= order_amount.abs(), fulfillment_exceeded_err(:position_id),
            );
            fulfillment_entry.write(total_amount);
        }

        fn _validate_deposit(
            ref self: ContractState,
            operator_nonce: u64,
            position_id: PositionId,
            collateral_id: AssetId,
            amount: u64,
        ) {
            self._validate_operator_flow(:operator_nonce);
            self._validate_position_exists(:position_id);
            self.assets.validate_collateral_active(:collateral_id);
            assert(amount.is_non_zero(), INVALID_ZERO_AMOUNT);
        }

        /// Validates operator flows prerequisites:
        /// - Contract is not paused.
        /// - Caller has operator role.
        /// - Operator nonce is valid.
        /// - Assets integrity [_validate_assets_integrity].
        fn _validate_operator_flow(ref self: ContractState, operator_nonce: u64) {
            self.pausable.assert_not_paused();
            self.roles.only_operator();
            self.nonce.use_checked_nonce(nonce: operator_nonce);
            self.assets.validate_assets_integrity();
        }

        fn _validate_order(ref self: ContractState, order: Order) {
            // Non-zero amount check.
            assert(order.base_amount.is_non_zero(), INVALID_ZERO_AMOUNT);
            assert(order.quote_amount.is_non_zero(), INVALID_ZERO_AMOUNT);

            // Expiration check.
            let now = Time::now();
            assert_with_byte_array(now < order.expiration, order_expired_err(order.position_id));

            // Assets check.
            self.assets.validate_collateral_active(collateral_id: order.fee_asset_id);
            self.assets.validate_collateral_active(collateral_id: order.quote_asset_id);
            self.assets.validate_asset_active(asset_id: order.base_asset_id);

            // Sign Validation for amounts.
            assert(
                !have_same_sign(a: order.quote_amount, b: order.base_amount),
                INVALID_WRONG_AMOUNT_SIGN,
            );
        }

        fn _validate_funding_tick(
            ref self: ContractState, funding_ticks: Span<FundingTick>, operator_nonce: u64,
        ) {
            self.pausable.assert_not_paused();
            self.roles.only_operator();
            self.nonce.use_checked_nonce(nonce: operator_nonce);
            assert(
                funding_ticks.len() == self.assets.get_num_of_active_synthetic_assets(),
                INVALID_FUNDING_TICK_LEN,
            );
        }

        fn _validate_orders(
            ref self: ContractState,
            order_a: Order,
            order_b: Order,
            actual_amount_base_a: i64,
            actual_amount_quote_a: i64,
            actual_fee_a: u64,
            actual_fee_b: u64,
        ) {
            assert(order_a.position_id != order_b.position_id, INVALID_SAME_POSITIONS);
            self._validate_order(order: order_a);
            self._validate_order(order: order_b);

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
            // Types validation.
            assert(order_a.quote_asset_id == order_b.quote_asset_id, DIFFERENT_QUOTE_ASSET_IDS);
            assert(order_a.base_asset_id == order_b.base_asset_id, DIFFERENT_BASE_ASSET_IDS);

            // Sign Validation for amounts.
            assert(
                !have_same_sign(a: order_a.quote_amount, b: order_b.quote_amount),
                INVALID_QUOTE_AMOUNT_SIGN,
            );
        }

        fn validate_deleverage_base_shrinks(
            ref self: ContractState, position_id: PositionId, asset_id: AssetId, amount: i64,
        ) {
            let position_base_balance: i64 = self
                .positions
                .get_provisional_balance(:position_id, :asset_id)
                .into();

            assert(!have_same_sign(a: amount, b: position_base_balance), INVALID_WRONG_AMOUNT_SIGN);
            assert(amount.abs() <= position_base_balance.abs(), INVALID_DELEVERAGE_BASE_CHANGE);
        }

        fn _validate_deleverage(
            ref self: ContractState,
            deleveraged_position: PositionId,
            deleverager_position: PositionId,
            deleveraged_base_asset_id: AssetId,
            deleveraged_base_amount: i64,
            deleveraged_quote_asset_id: AssetId,
            deleveraged_quote_amount: i64,
        ) {
            // Non-zero amount check.
            assert(deleveraged_base_amount.is_non_zero(), INVALID_ZERO_AMOUNT);
            assert(deleveraged_quote_amount.is_non_zero(), INVALID_ZERO_AMOUNT);

            // Assets check.
            self.assets.validate_collateral_active(collateral_id: deleveraged_quote_asset_id);
            assert(
                self.assets.is_synthetic(asset_id: deleveraged_base_asset_id),
                INVALID_NON_SYNTHETIC_ASSET,
            );

            // Sign Validation for amounts.
            assert(
                !have_same_sign(a: deleveraged_base_amount, b: deleveraged_quote_amount),
                INVALID_WRONG_AMOUNT_SIGN,
            );

            // Ensure that TR does not increase and that the base amount retains the same sign.
            self
                .validate_deleverage_base_shrinks(
                    position_id: deleveraged_position,
                    asset_id: deleveraged_base_asset_id,
                    amount: deleveraged_base_amount,
                );
            self
                .validate_deleverage_base_shrinks(
                    position_id: deleverager_position,
                    asset_id: deleveraged_base_asset_id,
                    amount: -deleveraged_base_amount,
                );
        }

        fn _execute_deleverage(
            ref self: ContractState,
            deleveraged_position: PositionId,
            deleverager_position: PositionId,
            deleveraged_base_asset_id: AssetId,
            deleveraged_base_amount: i64,
            deleveraged_quote_asset_id: AssetId,
            deleveraged_quote_amount: i64,
        ) {
            let deleveraged_position_data = self
                .positions
                .get_position_data(position_id: deleveraged_position);
            let deleveraged_position_diff = self
                ._create_position_diff_from_asset_amounts(
                    position_id: deleveraged_position,
                    base_id: deleveraged_base_asset_id,
                    base_amount: deleveraged_base_amount,
                    quote_id: deleveraged_quote_asset_id,
                    quote_amount: deleveraged_quote_amount,
                    fee_id: Option::None,
                    fee_amount: Option::None,
                );

            let deleverager_position_data = self
                .positions
                .get_position_data(position_id: deleverager_position);
            let deleverager_position_diff = self
                ._create_position_diff_from_asset_amounts(
                    position_id: deleverager_position,
                    base_id: deleveraged_base_asset_id,
                    // Passing the negative of actual amounts to deleverager as it is linked to
                    // deleveraged.
                    base_amount: -deleveraged_base_amount,
                    quote_id: deleveraged_quote_asset_id,
                    quote_amount: -deleveraged_quote_amount,
                    fee_id: Option::None,
                    fee_amount: Option::None,
                );

            self
                .positions
                .apply_diff(
                    position_id: deleveraged_position, position_diff: deleveraged_position_diff,
                );
            self
                .positions
                .apply_diff(
                    position_id: deleverager_position, position_diff: deleverager_position_diff,
                );

            match self.assets.get_synthetic_config(deleveraged_base_asset_id).status {
                // If the synthetic asset is active, the position should be deleveragable
                // and changed to fair deleverage and healthier.
                AssetStatus::ACTIVE => validate_deleveraged_position(
                    position_id: deleveraged_position,
                    position_data: deleveraged_position_data,
                    position_diff: deleveraged_position_diff,
                ),
                // In case of deactivated synthetic asset, the position should change to healthy or
                // healthier.
                AssetStatus::DEACTIVATED => validate_position_is_healthy_or_healthier(
                    position_id: deleveraged_position,
                    position_data: deleveraged_position_data,
                    position_diff: deleveraged_position_diff,
                ),
                // In case of pending synthetic asset, error should be thrown.
                AssetStatus::PENDING => panic_with_felt252(CANT_DELEVERAGE_PENDING_ASSET),
            };

            validate_position_is_healthy_or_healthier(
                position_id: deleverager_position,
                position_data: deleverager_position_data,
                position_diff: deleverager_position_diff,
            );
        }

        fn _validate_order_signature(
            self: @ContractState, position_id: PositionId, order: Order, signature: Signature,
        ) -> HashType {
            let position = self.positions.get_position_snapshot(:position_id);
            let public_key = position.owner_public_key.read();
            let msg_hash = order.get_message_hash(:public_key);
            validate_stark_signature(:public_key, :msg_hash, :signature);
            msg_hash
        }

        fn _validate_position_exists(self: @ContractState, position_id: PositionId) {
            self.positions.get_position_snapshot(:position_id);
        }

        fn _validate_transfer(
            ref self: ContractState,
            operator_nonce: u64,
            recipient: PositionId,
            position_id: PositionId,
            collateral_id: AssetId,
            amount: u64,
            expiration: Timestamp,
            salt: felt252,
        ) {
            self._validate_operator_flow(:operator_nonce);

            // Validate collateral.
            self.assets.validate_collateral_active(:collateral_id);
            assert(amount.is_non_zero(), INVALID_ZERO_AMOUNT);
            // Validate expiration.
            validate_expiration(:expiration, err: TRANSFER_EXPIRED);
        }

        fn _validate_sufficient_funds(
            self: @ContractState,
            token_contract: IERC20Dispatcher,
            collateral_id: AssetId,
            withdraw_unquantized_amount: u64,
        ) {
            let pending_quantized_amount = self
                .deposits
                .get_asset_aggregate_quantized_pending_deposits(asset_id: collateral_id.into());
            let (_, quantum) = self.deposits.get_asset_info(asset_id: collateral_id.into());
            let erc20_balance = token_contract.balance_of(get_contract_address());
            let pending_unquantized_amount = pending_quantized_amount * quantum.into();
            assert(
                erc20_balance >= withdraw_unquantized_amount.into()
                    + pending_unquantized_amount.into(),
                INSUFFICIENT_FUNDS,
            );
        }

        fn _validate_withdraw(
            ref self: ContractState,
            operator_nonce: u64,
            position_id: PositionId,
            collateral_id: AssetId,
            amount: u64,
            expiration: Timestamp,
        ) {
            self._validate_operator_flow(:operator_nonce);
            self._validate_position_exists(:position_id);
            assert(amount.is_non_zero(), INVALID_ZERO_AMOUNT);
            validate_expiration(expiration: expiration, err: WITHDRAW_EXPIRED);
            self.assets.validate_collateral_active(:collateral_id);
        }
    }
}
