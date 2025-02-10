#[starknet::contract]
pub mod Core {
    use contracts_commons::components::deposit::Deposit;
    use contracts_commons::components::deposit::Deposit::InternalTrait as DepositInternal;
    use contracts_commons::components::nonce::NonceComponent;
    use contracts_commons::components::nonce::NonceComponent::InternalTrait as NonceInternal;
    use contracts_commons::components::pausable::PausableComponent;
    use contracts_commons::components::pausable::PausableComponent::InternalTrait as PausableInternal;
    use contracts_commons::components::replaceability::ReplaceabilityComponent;
    use contracts_commons::components::request_approvals::RequestApprovalsComponent;
    use contracts_commons::components::request_approvals::RequestApprovalsComponent::InternalTrait as RequestApprovalsInternal;
    use contracts_commons::components::roles::RolesComponent;
    use contracts_commons::components::roles::RolesComponent::InternalTrait as RolesInteral;
    use contracts_commons::errors::assert_with_byte_array;
    use contracts_commons::math::{Abs, have_same_sign};
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
        INSUFFICIENT_FUNDS, INVALID_DELEVERAGE_BASE_CHANGE, INVALID_FUNDING_TICK_LEN,
        INVALID_NEGATIVE_FEE, INVALID_NON_SYNTHETIC_ASSET, INVALID_TRADE_QUOTE_AMOUNT_SIGN,
        INVALID_TRADE_SAME_POSITIONS, INVALID_TRADE_WRONG_AMOUNT_SIGN, INVALID_TRANSFER_AMOUNT,
        INVALID_ZERO_AMOUNT, TRANSFER_EXPIRED, WITHDRAW_EXPIRED, fulfillment_exceeded_err,
        order_expired_err,
    };

    use perpetuals::core::events;
    use perpetuals::core::interface::ICore;
    use perpetuals::core::types::asset::AssetId;

    use perpetuals::core::types::asset::status::AssetStatus;
    use perpetuals::core::types::balance::{Balance, BalanceTrait};
    use perpetuals::core::types::funding::FundingTick;
    use perpetuals::core::types::order::{Order, OrderTrait};
    use perpetuals::core::types::price::{PriceTrait, SignedPrice};
    use perpetuals::core::types::transfer::TransferArgs;
    use perpetuals::core::types::withdraw::WithdrawArgs;
    use perpetuals::core::types::{AssetDiffEntry, PositionDiff, PositionId};
    use perpetuals::core::value_risk_calculator::{
        validate_deleveraged_position, validate_liquidated_position,
        validate_position_is_healthy_or_healthier,
    };
    use starknet::event::EventEmitter;
    use starknet::storage::{
        Map, StorageMapReadAccess, StoragePathEntry, StoragePointerReadAccess,
        StoragePointerWriteAccess,
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
        fee_position_owner_account: ContractAddress,
        fee_position_owner_public_key: PublicKey,
        insurance_fund_position_owner_account: ContractAddress,
        insurance_fund_position_owner_public_key: PublicKey,
    ) {
        self.roles.initialize(:governance_admin);
        self.replaceability.upgrade_delay.write(upgrade_delay);
        self
            .assets
            .initialize(
                :max_price_interval,
                :max_funding_interval,
                :max_funding_rate,
                :max_oracle_price_validity,
            );
        self.deposits.initialize();
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
            amount: u128,
            salt: felt252,
        ) {
            self._validate_deposit(:operator_nonce, :position_id, :collateral_id, :amount);
            self
                .deposits
                .process_deposit(
                    :depositor,
                    beneficiary: position_id.into(),
                    asset_id: collateral_id.into(),
                    quantized_amount: amount,
                    :salt,
                );
            let asset_diff_entries = self
                ._create_position_diff(
                    :position_id, asset_id: collateral_id, amount: amount.into(),
                );
            self.positions.apply_diff(:position_id, :asset_diff_entries);
        }

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
            let position = self.positions.get_position_const(:position_id);
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
            let position = self.positions.get_position_const(:position_id);
            let hash = self
                .request_approvals
                .consume_approved_request(
                    args: WithdrawArgs {
                        position_id, salt, expiration, collateral_id, amount, recipient,
                    },
                    public_key: position.owner_public_key.read(),
                );
            /// Validation - Not withdrawing from pending deposits:
            let collateral_cfg = self.assets.get_collateral_config(:collateral_id);
            let token_contract = IERC20Dispatcher {
                contract_address: collateral_cfg.token_address,
            };
            let withdraw_unquantized_amount = collateral_cfg.quantum * amount;
            self
                ._validate_sufficent_funds(
                    :token_contract, :collateral_id, amount: withdraw_unquantized_amount,
                );
            /// Execution - Withdraw:
            token_contract.transfer(:recipient, amount: withdraw_unquantized_amount.into());

            /// Validations - Fundamentals:
            let asset_diff_entries = self
                ._create_position_diff(
                    :position_id, asset_id: collateral_id, amount: amount.into(),
                );
            let position_data = self.positions.get_position_data(:position_id);

            validate_position_is_healthy_or_healthier(
                :position_id, :position_data, :asset_diff_entries,
            );
            self.positions.apply_diff(:position_id, :asset_diff_entries);
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
            let position = self.positions.get_position_const(:position_id);
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
            let position = self.positions.get_position_const(:position_id);
            self
                ._validate_transfer(
                    :operator_nonce,
                    :position_id,
                    :recipient,
                    :salt,
                    :expiration,
                    :collateral_id,
                    :amount,
                );
            self._execute_transfer(:position_id, :recipient, :collateral_id, :amount);
            let hash = self
                .request_approvals
                .consume_approved_request(
                    args: TransferArgs {
                        position_id, recipient, salt, expiration, collateral_id, amount,
                    },
                    public_key: position.owner_public_key.read(),
                );
            self
                .emit(
                    events::Transfer {
                        position_id,
                        recipient,
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
            self
                ._execute_trade(
                    :order_a,
                    :order_b,
                    :actual_amount_base_a,
                    :actual_amount_quote_a,
                    :actual_fee_a,
                    :actual_fee_b,
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
        /// - Validates liqudated position is liquidatable.
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

            // Signatures validation:
            let liquidator_order_hash = self
                ._validate_order_signature(
                    position_id: liquidator_order.position_id,
                    order: liquidator_order,
                    signature: liquidator_signature,
                );

            // Validate and update fulfilment.
            self
                ._update_fulfillment(
                    position_id: liquidator_order.position_id,
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
            self
                ._execute_liquidate(
                    :liquidated_order,
                    :liquidator_order,
                    :actual_amount_base_liquidated,
                    :actual_amount_quote_liquidated,
                    :actual_liquidator_fee,
                );
            self
                .emit(
                    events::Liquidate {
                        liquidated_position_id,
                        liquidator_order_position_id: liquidator_order.position_id,
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
        /// - Registers the token to depositis component.
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
            self: @ContractState, position_id: PositionId, asset_id: AssetId, amount: Balance,
        ) -> PositionDiff {
            array![self._create_asset_diff_entry(:position_id, :asset_id, :amount)].span()
        }

        fn _create_asset_diff_entry(
            self: @ContractState, position_id: PositionId, asset_id: AssetId, amount: Balance,
        ) -> AssetDiffEntry {
            let position_asset_balance = self
                .positions
                .get_provisional_balance(:position_id, :asset_id);

            AssetDiffEntry {
                id: asset_id,
                before: position_asset_balance,
                after: position_asset_balance + amount,
                price: self.assets.get_asset_price(:asset_id),
                risk_factor: self.assets.get_risk_factor(:asset_id),
            }
        }

        /// Builds asset diff entries from an order's fee, quote, and base assets, handling overlaps
        /// by updating existing entries. If an asset matches an existing entry, only `after
        /// balance` is updated.
        fn _create_asset_diff_entries_from_order(
            ref self: ContractState,
            order: Order,
            actual_amount_base: i64,
            actual_amount_quote: i64,
            actual_fee: u64,
        ) -> Span<AssetDiffEntry> {
            let position_id = order.position_id;

            // fee asset.
            let fee_asset_id = order.fee_asset_id;
            let fee_price = self.assets.get_asset_price(asset_id: fee_asset_id);
            let fee_balance = self
                .positions
                .get_provisional_balance(:position_id, asset_id: fee_asset_id);

            let mut fee_diff = AssetDiffEntry {
                id: fee_asset_id,
                before: fee_balance,
                after: fee_balance - actual_fee.into(),
                price: fee_price,
                risk_factor: self.assets.get_risk_factor(asset_id: fee_asset_id),
            };

            // Quote asset.
            let quote_asset_id = order.quote_asset_id;
            let mut quote_diff: AssetDiffEntry = Default::default();

            if quote_asset_id == fee_asset_id {
                fee_diff.after += actual_amount_quote.into();
            } else {
                let quote_price = self.assets.get_collateral_price(collateral_id: quote_asset_id);
                let quote_balance = self
                    .positions
                    .get_provisional_balance(:position_id, asset_id: quote_asset_id);
                quote_diff =
                    AssetDiffEntry {
                        id: quote_asset_id,
                        before: quote_balance,
                        after: quote_balance.add(actual_amount_quote),
                        price: quote_price,
                        risk_factor: self.assets.get_risk_factor(asset_id: quote_asset_id),
                    };
            }

            // Base asset.
            let base_asset_id = order.base_asset_id;
            let mut base_diff: AssetDiffEntry = Default::default();

            if base_asset_id == fee_asset_id {
                fee_diff.after += actual_amount_base.into();
            } else if base_asset_id == quote_asset_id {
                quote_diff.after += actual_amount_base.into();
            } else {
                let base_balance = self
                    .positions
                    .get_provisional_balance(position_id, asset_id: base_asset_id);
                base_diff =
                    AssetDiffEntry {
                        id: base_asset_id,
                        before: base_balance,
                        after: base_balance.add(actual_amount_base),
                        price: self.assets.get_asset_price(asset_id: base_asset_id),
                        risk_factor: self.assets.get_risk_factor(asset_id: base_asset_id),
                    };
            }

            // Build asset diff entries array.
            let mut diff_entries = array![];
            for asset_diff in array![fee_diff, quote_diff, base_diff] {
                if asset_diff.id != Default::default() {
                    diff_entries.append(asset_diff);
                }
            };
            diff_entries.span()
        }

        fn _execute_liquidate(
            ref self: ContractState,
            liquidated_order: Order,
            liquidator_order: Order,
            actual_amount_base_liquidated: i64,
            actual_amount_quote_liquidated: i64,
            actual_liquidator_fee: u64,
        ) {
            let liquidated_position_id = liquidated_order.position_id;
            let liquidated_position_data = self
                .positions
                .get_position_data(position_id: liquidated_position_id);
            let liquidated_asset_diff_entries = self
                ._create_asset_diff_entries_from_order(
                    order: liquidated_order,
                    actual_amount_base: actual_amount_base_liquidated,
                    actual_amount_quote: actual_amount_quote_liquidated,
                    actual_fee: liquidated_order.fee_amount,
                );

            let liquidator_position_id = liquidator_order.position_id;
            let liquidator_position_data = self
                .positions
                .get_position_data(position_id: liquidator_position_id);
            let liquidator_asset_diff_entries = self
                ._create_asset_diff_entries_from_order(
                    order: liquidator_order,
                    // Passing the negative of actual amounts to order_b as it is linked to order_a.
                    actual_amount_base: -actual_amount_base_liquidated,
                    actual_amount_quote: -actual_amount_quote_liquidated,
                    actual_fee: actual_liquidator_fee,
                );
            self
                .positions
                .apply_diff(
                    position_id: liquidated_position_id,
                    asset_diff_entries: liquidated_asset_diff_entries,
                );
            self
                .positions
                .apply_diff(
                    position_id: liquidator_position_id,
                    asset_diff_entries: liquidator_asset_diff_entries,
                );

            // Update fee positions.
            let asset_diff_entries_liquidated_fee = self
                ._create_position_diff(
                    position_id: FEE_POSITION,
                    asset_id: liquidated_order.fee_asset_id,
                    amount: liquidated_order.fee_amount.into(),
                );
            self
                .positions
                .apply_diff(
                    position_id: INSURANCE_FUND_POSITION,
                    asset_diff_entries: asset_diff_entries_liquidated_fee,
                );

            let asset_diff_entries_liquidator_fee = self
                ._create_position_diff(
                    position_id: FEE_POSITION,
                    asset_id: liquidator_order.fee_asset_id,
                    amount: actual_liquidator_fee.into(),
                );
            self
                .positions
                .apply_diff(
                    position_id: FEE_POSITION,
                    asset_diff_entries: asset_diff_entries_liquidator_fee,
                );

            /// Validations - Fundamentals:
            validate_liquidated_position(
                position_id: liquidated_position_id,
                position_data: liquidated_position_data,
                asset_diff_entries: liquidated_asset_diff_entries,
            );
            validate_position_is_healthy_or_healthier(
                position_id: liquidator_position_id,
                position_data: liquidator_position_data,
                asset_diff_entries: liquidator_asset_diff_entries,
            );
        }

        fn _execute_trade(
            ref self: ContractState,
            order_a: Order,
            order_b: Order,
            actual_amount_base_a: i64,
            actual_amount_quote_a: i64,
            actual_fee_a: u64,
            actual_fee_b: u64,
        ) {
            let position_data_a = self
                .positions
                .get_position_data(position_id: order_a.position_id);
            let asset_diff_entries_a = self
                ._create_asset_diff_entries_from_order(
                    order: order_a,
                    actual_amount_base: actual_amount_base_a,
                    actual_amount_quote: actual_amount_quote_a,
                    actual_fee: actual_fee_a,
                );

            let position_data_b = self
                .positions
                .get_position_data(position_id: order_b.position_id);
            let asset_diff_entries_b = self
                ._create_asset_diff_entries_from_order(
                    order: order_b,
                    // Passing the negative of actual amounts to order_b as it is linked to order_a.
                    actual_amount_base: -actual_amount_base_a,
                    actual_amount_quote: -actual_amount_quote_a,
                    actual_fee: actual_fee_b,
                );
            self
                .positions
                .apply_diff(
                    position_id: order_a.position_id, asset_diff_entries: asset_diff_entries_a,
                );
            self
                .positions
                .apply_diff(
                    position_id: order_b.position_id, asset_diff_entries: asset_diff_entries_b,
                );

            // Update fee positions.
            let asset_diff_entries_fee_a = self
                ._create_position_diff(
                    position_id: FEE_POSITION,
                    asset_id: order_a.fee_asset_id,
                    amount: actual_fee_a.into(),
                );
            self
                .positions
                .apply_diff(
                    position_id: FEE_POSITION, asset_diff_entries: asset_diff_entries_fee_a,
                );
            let asset_diff_entries_fee_b = self
                ._create_position_diff(
                    position_id: FEE_POSITION,
                    asset_id: order_b.fee_asset_id,
                    amount: actual_fee_b.into(),
                );
            self
                .positions
                .apply_diff(
                    position_id: FEE_POSITION, asset_diff_entries: asset_diff_entries_fee_b,
                );

            /// Validations - Fundamentals:
            validate_position_is_healthy_or_healthier(
                position_id: order_a.position_id,
                position_data: position_data_a,
                asset_diff_entries: asset_diff_entries_a,
            );
            validate_position_is_healthy_or_healthier(
                position_id: order_b.position_id,
                position_data: position_data_b,
                asset_diff_entries: asset_diff_entries_b,
            );
        }

        fn _execute_transfer(
            ref self: ContractState,
            position_id: PositionId,
            recipient: PositionId,
            collateral_id: AssetId,
            amount: u64,
        ) {
            // Parameters
            let sender_position_data = self.positions.get_position_data(:position_id);
            let asset_diff_entry_sender = self
                ._create_position_diff(
                    :position_id, asset_id: collateral_id, amount: -(amount.into()),
                );
            let asset_diff_entry_recipient = self
                ._create_position_diff(
                    position_id: recipient, asset_id: collateral_id, amount: amount.into(),
                );

            // Execute transfer
            self.positions.apply_diff(:position_id, asset_diff_entries: asset_diff_entry_sender);

            self
                .positions
                .apply_diff(position_id: recipient, asset_diff_entries: asset_diff_entry_recipient);

            /// Validations - Fundamentals:
            validate_position_is_healthy_or_healthier(
                :position_id,
                position_data: sender_position_data,
                asset_diff_entries: asset_diff_entry_sender,
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
            amount: u128,
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
                INVALID_TRADE_WRONG_AMOUNT_SIGN,
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
            assert(order_a.position_id != order_b.position_id, INVALID_TRADE_SAME_POSITIONS);
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
            // Actual fees amount are positive.
            assert(0 <= actual_fee_a, INVALID_NEGATIVE_FEE);
            assert(0 <= actual_fee_b, INVALID_NEGATIVE_FEE);

            // Types validation.
            assert(order_a.quote_asset_id == order_b.quote_asset_id, DIFFERENT_QUOTE_ASSET_IDS);
            assert(order_a.base_asset_id == order_b.base_asset_id, DIFFERENT_BASE_ASSET_IDS);

            // Sign Validation for amounts.
            assert(
                !have_same_sign(a: order_a.quote_amount, b: order_b.quote_amount),
                INVALID_TRADE_QUOTE_AMOUNT_SIGN,
            );
        }

        fn validate_deleverage_base_shrinks(
            ref self: ContractState, position_id: PositionId, asset_id: AssetId, amount: i64,
        ) {
            let position_base_balance: i64 = self
                .positions
                .get_provisional_balance(:position_id, :asset_id)
                .into();

            assert(
                !have_same_sign(a: amount, b: position_base_balance),
                INVALID_TRADE_WRONG_AMOUNT_SIGN,
            );
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
                INVALID_TRADE_WRONG_AMOUNT_SIGN,
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
            let deleveraged_order = Order {
                position_id: deleveraged_position,
                base_asset_id: deleveraged_base_asset_id,
                base_amount: deleveraged_base_amount,
                quote_asset_id: deleveraged_quote_asset_id,
                quote_amount: deleveraged_quote_amount,
                // Dummy values needed to initialize the struct and pass validation.
                fee_asset_id: deleveraged_quote_asset_id,
                fee_amount: Zero::zero(),
                salt: Zero::zero(),
                expiration: Time::now(),
            };

            let deleverager_order = Order {
                position_id: deleverager_position,
                base_asset_id: deleveraged_base_asset_id,
                base_amount: -deleveraged_base_amount,
                quote_asset_id: deleveraged_quote_asset_id,
                quote_amount: -deleveraged_quote_amount,
                // Dummy values needed to initialize the struct and pass validation.
                fee_asset_id: deleveraged_quote_asset_id,
                fee_amount: Zero::zero(),
                salt: Zero::zero(),
                expiration: Time::now(),
            };

            let deleveraged_position_id = deleveraged_order.position_id;
            let deleveraged_position_data = self
                .positions
                .get_position_data(position_id: deleveraged_position);
            let deleveraged_asset_diff_entries = self
                ._create_asset_diff_entries_from_order(
                    order: deleveraged_order,
                    actual_amount_base: deleveraged_base_amount,
                    actual_amount_quote: deleveraged_quote_amount,
                    actual_fee: Zero::zero(),
                );

            let deleverager_position_id = deleverager_order.position_id;
            let deleverager_position_data = self
                .positions
                .get_position_data(position_id: deleverager_position_id);
            let deleverager_asset_diff_entries = self
                ._create_asset_diff_entries_from_order(
                    order: deleverager_order,
                    // Passing the negative of actual amounts to order_b as it is linked to order_a.
                    actual_amount_base: -deleveraged_base_amount,
                    actual_amount_quote: -deleveraged_quote_amount,
                    actual_fee: Zero::zero(),
                );
            self
                .positions
                .apply_diff(
                    position_id: deleveraged_position_id,
                    asset_diff_entries: deleveraged_asset_diff_entries,
                );
            self
                .positions
                .apply_diff(
                    position_id: deleverager_position_id,
                    asset_diff_entries: deleverager_asset_diff_entries,
                );

            match self.assets.get_synthetic_config(deleveraged_base_asset_id).status {
                // If the synthetic asset is active, the position should be deleveragable
                // and changed to fair deleverage and healthier.
                AssetStatus::ACTIVATED => validate_deleveraged_position(
                    position_id: deleveraged_position_id,
                    position_data: deleveraged_position_data,
                    asset_diff_entries: deleveraged_asset_diff_entries,
                ),
                // In case of deactivated synthetic asset, the position should change to healthy or
                // healthier.
                AssetStatus::DEACTIVATED => validate_position_is_healthy_or_healthier(
                    position_id: deleveraged_position_id,
                    position_data: deleveraged_position_data,
                    asset_diff_entries: deleveraged_asset_diff_entries,
                ),
                // In case of pending synthetic asset, error should be thrown.
                AssetStatus::PENDING => panic_with_felt252(CANT_DELEVERAGE_PENDING_ASSET),
            };

            validate_position_is_healthy_or_healthier(
                position_id: deleverager_position_id,
                position_data: deleverager_position_data,
                asset_diff_entries: deleverager_asset_diff_entries,
            );
        }

        fn _validate_order_signature(
            self: @ContractState, position_id: PositionId, order: Order, signature: Signature,
        ) -> HashType {
            let position = self.positions.get_position_const(:position_id);
            let public_key = position.owner_public_key.read();
            let msg_hash = order.get_message_hash(:public_key);
            validate_stark_signature(:public_key, :msg_hash, :signature);
            msg_hash
        }

        fn _validate_position_exists(self: @ContractState, position_id: PositionId) {
            self.positions.get_position_const(:position_id);
        }

        fn _validate_transfer(
            ref self: ContractState,
            operator_nonce: u64,
            position_id: PositionId,
            recipient: PositionId,
            salt: felt252,
            expiration: Timestamp,
            collateral_id: AssetId,
            amount: u64,
        ) {
            self._validate_operator_flow(:operator_nonce);
            // Check positions.
            self._validate_position_exists(position_id: recipient);

            // Validate collateral.
            self.assets.validate_collateral_active(:collateral_id);
            assert(amount > 0, INVALID_TRANSFER_AMOUNT);
            // Validate expiration.
            validate_expiration(:expiration, err: TRANSFER_EXPIRED);
        }

        fn _validate_sufficent_funds(
            self: @ContractState,
            token_contract: IERC20Dispatcher,
            collateral_id: AssetId,
            amount: u64,
        ) {
            let pending_unquantized_amount = self
                .deposits
                .aggregate_pending_deposit
                .read(collateral_id.into());
            let erc20_balance = token_contract.balance_of(get_contract_address());
            assert(
                erc20_balance >= amount.into() + pending_unquantized_amount.into(),
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
            assert(amount > 0, INVALID_ZERO_AMOUNT);
            validate_expiration(expiration: expiration, err: WITHDRAW_EXPIRED);
            self.assets.validate_collateral_active(:collateral_id);
        }
    }
}
