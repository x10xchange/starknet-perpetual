#[starknet::contract]
pub mod Core {
    use contracts_commons::components::nonce::NonceComponent;
    use contracts_commons::components::nonce::NonceComponent::InternalTrait as NonceInternal;
    use contracts_commons::components::pausable::PausableComponent;
    use contracts_commons::components::pausable::PausableComponent::InternalTrait as PausableInternal;
    use contracts_commons::components::replaceability::ReplaceabilityComponent;
    use contracts_commons::components::roles::RolesComponent;
    use contracts_commons::components::roles::RolesComponent::InternalTrait as RolesInteral;
    use contracts_commons::errors::assert_with_byte_array;
    use contracts_commons::math::{Abs, have_same_sign};
    use contracts_commons::message_hash::OffchainMessageHash;
    use contracts_commons::types::time::time::{Time, TimeDelta, Timestamp};
    use contracts_commons::utils::{AddToStorage, SubFromStorage};
    use core::num::traits::Zero;
    use core::starknet::storage::StoragePointerWriteAccess;
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::introspection::src5::SRC5Component;
    use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use openzeppelin::utils::snip12::SNIP12Metadata;
    use perpetuals::core::components::assets::AssetsComponent;
    use perpetuals::core::components::assets::AssetsComponent::InternalTrait as AssetsInternal;
    use perpetuals::core::errors::{
        CALLER_IS_NOT_OWNER_ACCOUNT, DEPOSIT_EXPIRED, DIFFERENT_BASE_ASSET_IDS,
        DIFFERENT_QUOTE_ASSET_IDS, FACT_NOT_REGISTERED, INVALID_FUNDING_TICK_LEN,
        INVALID_NEGATIVE_FEE, INVALID_NON_POSITIVE_AMOUNT, INVALID_POSITION,
        INVALID_TRADE_QUOTE_AMOUNT_SIGN, INVALID_TRADE_WRONG_AMOUNT_SIGN, NO_OWNER_ACCOUNT,
        OWNER_ACCOUNT_DOES_NOT_MATCH, OWNER_PUBLIC_KEY_DOES_NOT_MATCH, POSITION_HAS_ACCOUNT,
        POSITION_IS_NOT_HEALTHIER, POSITION_IS_NOT_LIQUIDATABLE, POSITION_UNHEALTHY,
        SET_POSITION_OWNER_EXPIRED, SET_PUBLIC_KEY_EXPIRED, WITHDRAW_EXPIRED,
        fulfillment_exceeded_err, position_not_healthy_nor_healthier, trade_order_expired_err,
    };
    use perpetuals::core::interface::ICore;
    use perpetuals::core::types::asset::{AssetId, AssetIdImpl};
    use perpetuals::core::types::balance::{Balance, BalanceTrait};
    use perpetuals::core::types::deposit::DepositArgs;
    use perpetuals::core::types::funding::{FundingIndexMulTrait, FundingTick};
    use perpetuals::core::types::order::{Order, OrderTrait};
    use perpetuals::core::types::position::{Position, PositionTrait};
    use perpetuals::core::types::set_position_owner::SetPositionOwnerArgs;
    use perpetuals::core::types::set_public_key::SetPublicKeyArgs;
    use perpetuals::core::types::transfer::TransferArgs;
    use perpetuals::core::types::withdraw::WithdrawArgs;
    use perpetuals::core::types::{
        AssetAmount, AssetDiffEntry, AssetEntry, PositionData, PositionId, Signature,
    };
    use perpetuals::value_risk_calculator::interface::{
        IValueRiskCalculatorDispatcher, IValueRiskCalculatorDispatcherTrait, PositionState,
    };
    use starknet::storage::{
        Map, Mutable, StorageMapReadAccess, StorageMapWriteAccess, StoragePath, StoragePathEntry,
        StoragePointerReadAccess,
    };
    use starknet::{ContractAddress, get_caller_address, get_contract_address};

    component!(path: AccessControlComponent, storage: accesscontrol, event: AccessControlEvent);
    component!(path: NonceComponent, storage: nonce, event: NonceEvent);
    component!(path: PausableComponent, storage: pausable, event: PausableEvent);
    component!(path: ReplaceabilityComponent, storage: replaceability, event: ReplaceabilityEvent);
    component!(path: RolesComponent, storage: roles, event: RolesEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);
    component!(path: AssetsComponent, storage: assets, event: AssetsEvent);

    impl NonceImpl = NonceComponent::NonceImpl<ContractState>;
    impl NonceComponentInternalImpl = NonceComponent::InternalImpl<ContractState>;

    #[abi(embed_v0)]
    impl AssetsImpl = AssetsComponent::AssetsImpl<ContractState>;

    #[abi(embed_v0)]
    impl ReplaceabilityImpl =
        ReplaceabilityComponent::ReplaceabilityImpl<ContractState>;

    #[abi(embed_v0)]
    impl RolesImpl = RolesComponent::RolesImpl<ContractState>;

    #[abi(embed_v0)]
    impl PausableImpl = PausableComponent::PausableImpl<ContractState>;

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
        // --- Components ---
        #[substorage(v0)]
        accesscontrol: AccessControlComponent::Storage,
        #[substorage(v0)]
        pub nonce: NonceComponent::Storage,
        #[substorage(v0)]
        pausable: PausableComponent::Storage,
        #[substorage(v0)]
        replaceability: ReplaceabilityComponent::Storage,
        #[substorage(v0)]
        pub roles: RolesComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        #[substorage(v0)]
        pub assets: AssetsComponent::Storage,
        pub value_risk_calculator_dispatcher: IValueRiskCalculatorDispatcher,
        pub fact_registry: Map<felt252, Timestamp>,
        pending_deposits: Map<AssetId, i64>,
        // Message hash to fulfilled amount.
        fulfillment: Map<felt252, i64>,
        pub positions: Map<PositionId, Position>,
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
    }

    #[constructor]
    pub fn constructor(
        ref self: ContractState,
        governance_admin: ContractAddress,
        value_risk_calculator: ContractAddress,
        price_validation_interval: TimeDelta,
        funding_validation_interval: TimeDelta,
        max_funding_rate: u32,
    ) {
        self.roles.initialize(:governance_admin);
        self.replaceability.upgrade_delay.write(Zero::zero());
        self
            .value_risk_calculator_dispatcher
            .write(IValueRiskCalculatorDispatcher { contract_address: value_risk_calculator });
        self
            .assets
            .initialize(
                :price_validation_interval, :funding_validation_interval, :max_funding_rate,
            );
    }

    #[abi(embed_v0)]
    pub impl CoreImpl of ICore<ContractState> {
        // Flows
        fn deleverage(self: @ContractState) {}

        fn deposit(ref self: ContractState, deposit_args: DepositArgs) {
            let caller_address = get_caller_address();
            let msg_hash = deposit_args.get_message_hash(signer: caller_address);
            self.fact_registry.write(key: msg_hash, value: Time::now());
            let collateral_amount = deposit_args.collateral.amount;
            let asset_id = deposit_args.collateral.asset_id;
            self
                .pending_deposits
                .write(
                    key: asset_id, value: self.pending_deposits.read(asset_id) + collateral_amount,
                );
            let collateral_cfg = self.assets._get_collateral_config(collateral_id: asset_id);
            let quantum = collateral_cfg.quantum;
            assert(collateral_amount > 0, INVALID_NON_POSITIVE_AMOUNT);
            let amount = collateral_amount.abs() * quantum;
            let erc20_dispatcher = IERC20Dispatcher { contract_address: collateral_cfg.address };
            erc20_dispatcher
                .transfer_from(
                    sender: caller_address,
                    recipient: get_contract_address(),
                    amount: amount.into(),
                );
        }

        /// Process deposit a collateral amount from the 'depositing_address' to a given position.
        /// If the position is new (i.e., has no owner_public_key), the owner_public_key and
        /// owner_account are set.
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
            depositing_address: ContractAddress,
            deposit_args: DepositArgs,
        ) {
            self._validate_deposit(:operator_nonce, :depositing_address, :deposit_args);
            let position_id = deposit_args.position_id;
            let position = self._get_position(:position_id);
            /// Position with no owner_public_key is considered as a new position. Then we set the
            /// owner_public_key and owner_account. Otherwise, we check that they match.
            if position.owner_public_key.read().is_zero() {
                position.owner_public_key.write(deposit_args.owner_public_key);
                position.owner_account.write(deposit_args.owner_account);
            } else {
                assert(
                    position.owner_public_key.read() == deposit_args.owner_public_key,
                    OWNER_PUBLIC_KEY_DOES_NOT_MATCH,
                );
                assert(
                    position.owner_account.read() == deposit_args.owner_account,
                    OWNER_ACCOUNT_DOES_NOT_MATCH,
                );
            }
            let collateral_id = deposit_args.collateral.asset_id;
            let amount = deposit_args.collateral.amount;
            self
                .apply_funding_and_update_balance(
                    position_id: position_id, asset_id: collateral_id, diff: amount.into(),
                );
            self.pending_deposits.entry(collateral_id).sub_and_write(amount);
        }

        fn withdraw_request(ref self: ContractState, signature: Signature, message: WithdrawArgs) {
            self._register_fact(:signature, position_id: message.position_id, :message);
        }

        fn transfer_request(ref self: ContractState, signature: Signature, message: TransferArgs) {
            self._register_fact(:signature, position_id: message.sender, :message);
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
        fn set_public_key(ref self: ContractState, operator_nonce: u64, message: SetPublicKeyArgs) {
            self.pausable.assert_not_paused();
            self._consume_operator_nonce(:operator_nonce);
            assert(message.expiration > Time::now(), SET_PUBLIC_KEY_EXPIRED);
            let position_id = message.position_id;
            let position = self._get_position(:position_id);
            let owner_account = position.owner_account.read();
            assert(owner_account.is_non_zero(), NO_OWNER_ACCOUNT);
            let hash = message.get_message_hash(signer: owner_account);
            self._use_fact(:hash);
            position.owner_public_key.write(message.new_public_key);
        }

        fn set_public_key_request(
            ref self: ContractState, signature: Signature, message: SetPublicKeyArgs,
        ) {
            self._register_fact(:signature, position_id: message.position_id, :message);
        }

        /// Executes a liquidate of a user position with liquidator order.
        ///
        /// Validations:
        /// - Common user flow validations are performed.
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
        /// - Apply funding to both positions.
        /// - Subtract the fees from each position's collateral.
        /// - Add the fees to the `fee_position`.
        /// - Update orders' position, based on `actual_amount_base`.
        /// - Adjust collateral balances.
        /// - Perform fundamental validation for both positions after the trade.
        /// - Update liquidator order fulfillment.
        fn liquidate(
            ref self: ContractState,
            operator_nonce: u64,
            signature_liquidator: Signature,
            liquidated_position_id: PositionId,
            liquidator_order: Order,
            actual_amount_base_liquidated: i64,
            actual_amount_quote_liquidated: i64,
            actual_liquidator_fee: i64,
            insurance_fund_fee: AssetAmount,
        ) {
            /// Validations:
            let now = Time::now();
            self._validate_operator_flow(:operator_nonce, :now);

            // Signatures validation:
            let liquidator_position = self._get_position(position_id: liquidator_order.position_id);
            let liquidator_msg_hash = liquidator_position
                ._generate_message_hash_with_public_key(message: liquidator_order);
            liquidator_position
                ._validate_stark_signature(
                    msg_hash: liquidator_msg_hash, signature: signature_liquidator,
                );

            // Validate and update fulfilments.
            self
                ._update_fulfillment(
                    position_id: liquidator_order.position_id,
                    hash: liquidator_msg_hash,
                    order_amount: liquidator_order.base.amount,
                    // Passing the negative of actual amounts to `liquidator_order` as it is linked
                    // to liquidated_order.
                    actual_amount: -actual_amount_base_liquidated,
                );

            let liquidated_order = Order {
                position_id: liquidated_position_id,
                base: AssetAmount {
                    asset_id: liquidator_order.base.asset_id, amount: actual_amount_base_liquidated,
                },
                quote: AssetAmount {
                    asset_id: liquidator_order.quote.asset_id,
                    amount: actual_amount_quote_liquidated,
                },
                fee: insurance_fund_fee,
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
                    actual_fee_a: insurance_fund_fee.amount,
                    actual_fee_b: actual_liquidator_fee,
                    :now,
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
        fn set_position_owner(
            ref self: ContractState,
            operator_nonce: u64,
            signature: Signature,
            message: SetPositionOwnerArgs,
        ) {
            self.pausable.assert_not_paused();
            self._consume_operator_nonce(:operator_nonce);
            let now = Time::now();
            assert(message.expiration > now, SET_POSITION_OWNER_EXPIRED);
            let position_id = message.position_id;
            let position = self._get_position(:position_id);
            assert(position.owner_account.read().is_zero(), POSITION_HAS_ACCOUNT);
            position
                ._validate_stark_signature(
                    msg_hash: position._generate_message_hash_with_public_key(:message),
                    signature: signature,
                );
            position.owner_account.write(message.new_account_owner);
        }

        /// Executes a trade between two orders (Order A and Order B).
        ///
        /// Validations:
        /// - Common user flow validations are performed.
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
        /// - Perform fundamental validation for both positions after the trade.
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
            actual_fee_a: i64,
            actual_fee_b: i64,
        ) {
            /// Validations:

            let now = Time::now();
            let position_id_a = order_a.position_id;
            let position_id_b = order_b.position_id;

            self._validate_operator_flow(:operator_nonce, :now);

            // Signatures validation:
            let position_a = self._get_position(position_id: position_id_a);
            let position_b = self._get_position(position_id: position_id_b);
            let hash_a = position_a._generate_message_hash_with_public_key(message: order_a);
            position_a._validate_stark_signature(msg_hash: hash_a, signature: signature_a);
            let hash_b = position_b._generate_message_hash_with_public_key(message: order_b);
            position_b._validate_stark_signature(msg_hash: hash_b, signature: signature_b);

            // Validate and update fulfillments.
            self
                ._update_fulfillment(
                    position_id: position_id_a,
                    hash: hash_a,
                    order_amount: order_a.base.amount,
                    actual_amount: actual_amount_base_a,
                );
            self
                ._update_fulfillment(
                    position_id: position_id_b,
                    hash: hash_b,
                    order_amount: order_b.base.amount,
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
                    :now,
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
        }

        fn transfer(self: @ContractState) {}

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
        fn withdraw(ref self: ContractState, operator_nonce: u64, message: WithdrawArgs) {
            let now = Time::now();
            self._validate_operator_flow(:operator_nonce, :now);
            let amount = message.collateral.amount;
            assert(amount > 0, INVALID_NON_POSITIVE_AMOUNT);
            assert(now < message.expiration, WITHDRAW_EXPIRED);
            let collateral_id = message.collateral.asset_id;
            let collateral_cfg = self.assets._validate_collateral_active(:collateral_id);
            let position_id = message.position_id;
            let position = self._get_position(:position_id);
            let hash = position._generate_message_hash_with_owner_account_or_public_key(:message);
            self._use_fact(:hash);

            // Equivalent to `fulfillment` being zero.
            self
                ._update_fulfillment(
                    :position_id, :hash, order_amount: amount, actual_amount: amount,
                );

            /// Execution - Withdraw:
            let erc20_dispatcher = IERC20Dispatcher { contract_address: collateral_cfg.address };
            erc20_dispatcher
                .transfer(
                    recipient: message.recipient,
                    amount: (collateral_cfg.quantum * amount.abs()).into(),
                );

            /// Validations - Fundamentals:
            let position_data = self._get_position_data(:position_id);
            let balance = position.collateral_assets.entry(collateral_id).balance;
            let before = balance.read();
            let after = before.sub(amount);
            balance.write(after);
            let price = self.assets._get_collateral_price(:collateral_id);
            let position_diff = array![
                AssetDiffEntry {
                    id: collateral_id,
                    before,
                    after,
                    price,
                    risk_factor: self.assets._get_risk_factor(asset_id: collateral_id),
                },
            ]
                .span();

            let value_risk_calculator_dispatcher = self.value_risk_calculator_dispatcher.read();
            let position_change_result = value_risk_calculator_dispatcher
                .evaluate_position_change(position: position_data, :position_diff);
            assert(
                position_change_result.position_state_after_change == PositionState::Healthy,
                POSITION_UNHEALTHY,
            );
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
            ref self: ContractState, funding_ticks: Span<FundingTick>, operator_nonce: u64,
        ) {
            self._validate_funding_tick(:funding_ticks, :operator_nonce);
            self.assets._execute_funding_tick(:funding_ticks);
        }

        // Configuration
        fn add_asset(self: @ContractState) {}
        fn add_oracle(self: @ContractState) {}
        fn add_oracle_to_asset(self: @ContractState) {}
        fn remove_oracle(self: @ContractState) {}
        fn remove_oracle_from_asset(self: @ContractState) {}
        fn update_asset_price(self: @ContractState) {}
        fn update_max_funding_rate(self: @ContractState) {}
        fn update_oracle_identifiers(self: @ContractState) {}
    }

    #[generate_trait]
    pub impl InternalCoreFunctions of InternalCoreFunctionsTrait {
        fn _pre_update(self: @ContractState) {}
        fn _post_update(self: @ContractState) {}

        /// Validates the operator nonce and consumes it.
        /// Only the operator can call this function.
        fn _consume_operator_nonce(ref self: ContractState, operator_nonce: u64) {
            self.roles.only_operator();
            self.nonce.use_checked_nonce(nonce: operator_nonce);
        }

        fn _use_fact(ref self: ContractState, hash: felt252) {
            let fact = self.fact_registry.entry(hash);
            assert(fact.read().is_non_zero(), FACT_NOT_REGISTERED);
            fact.write(Zero::zero());
        }

        fn _update_fulfillment(
            ref self: ContractState,
            position_id: PositionId,
            hash: felt252,
            order_amount: i64,
            actual_amount: i64,
        ) {
            let fulfillment_entry = self.fulfillment.entry(hash);
            let final_amount = fulfillment_entry.read() + actual_amount;
            // Both `final_amount` and `order_amount` are guaranteed to have the same sign.
            assert_with_byte_array(
                final_amount.abs() <= order_amount.abs(), fulfillment_exceeded_err(:position_id),
            );
            fulfillment_entry.write(final_amount);
        }

        fn _get_provisional_balance(
            self: @ContractState, position_id: PositionId, asset_id: AssetId,
        ) -> Balance {
            if self.assets._is_main_collateral(:asset_id) {
                self._get_provisional_main_collateral_balance(:position_id)
            } else {
                self.positions.entry(position_id).synthetic_assets.entry(asset_id).balance.read()
            }
        }


        /// Updates the balance of a given asset, determining its type (collateral or synthetic)
        /// and applying the appropriate logic.
        fn _apply_funding_and_set_balance(
            ref self: ContractState, position_id: PositionId, asset_id: AssetId, balance: Balance,
        ) {
            let mut position = self._get_position(:position_id);
            if self.assets._is_main_collateral(:asset_id) {
                position.collateral_assets.entry(asset_id).balance.write(balance);
            } else {
                self
                    ._update_synthetic_balance_and_funding(
                        :position_id, synthetic_id: asset_id, :balance,
                    );
            }
        }

        fn apply_funding_and_update_balance(
            ref self: ContractState, position_id: PositionId, asset_id: AssetId, diff: Balance,
        ) {
            let current_balance = self._get_provisional_balance(:position_id, asset_id: asset_id);
            self
                ._apply_funding_and_set_balance(
                    :position_id, :asset_id, balance: current_balance + diff,
                );
        }

        fn _get_provisional_main_collateral_balance(
            self: @ContractState, position_id: PositionId,
        ) -> Balance {
            let position = self.positions.entry(position_id);
            let mut main_collateral_balance = position
                .collateral_assets
                .entry(self.assets._get_main_collateral_asset_id())
                .balance
                .read();
            let mut asset_id_opt = position.synthetic_assets_head.read();

            while let Option::Some(synthetic_id) = asset_id_opt {
                let synthetic_asset = position.synthetic_assets.read(synthetic_id);
                let balance = synthetic_asset.balance;
                let funding = synthetic_asset.funding_index;
                let global_funding = self
                    .assets
                    .synthetic_timely_data
                    .read(synthetic_id)
                    .funding_index;
                main_collateral_balance += (global_funding - funding).mul(balance);
                asset_id_opt = synthetic_asset.next;
            };
            main_collateral_balance
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
            ref self: ContractState,
            position_id: PositionId,
            synthetic_id: AssetId,
            balance: Balance,
        ) {
            let position = self._get_position(:position_id);
            let synthetic_asset = position.synthetic_assets.entry(synthetic_id);
            let funding = synthetic_asset.funding_index.read();
            let global_funding = self.assets.synthetic_timely_data.read(synthetic_id).funding_index;
            let synthetic_balance = synthetic_asset.balance.read();

            position
                .collateral_assets
                .entry(self.assets._get_main_collateral_asset_id())
                .balance
                .add_and_write((global_funding - funding).mul(synthetic_balance));
            synthetic_asset.balance.write(balance);
            synthetic_asset.funding_index.write(global_funding);
        }


        fn _get_position(
            ref self: ContractState, position_id: PositionId,
        ) -> StoragePath<Mutable<Position>> {
            let mut position = self.positions.entry(position_id);
            assert(position.owner_public_key.read().is_non_zero(), INVALID_POSITION);
            position
        }

        fn _collect_position_collaterals(
            self: @ContractState, ref asset_entries: Array<AssetEntry>, position_id: PositionId,
        ) {
            let position = self.positions.entry(position_id);
            let mut asset_id_opt = position.collateral_assets_head.read();
            while let Option::Some(collateral_id) = asset_id_opt {
                let collateral_asset = position.collateral_assets.read(collateral_id);
                asset_entries
                    .append(
                        AssetEntry {
                            id: collateral_id,
                            balance: self
                                ._get_provisional_balance(:position_id, asset_id: collateral_id),
                            price: self.assets._get_collateral_price(:collateral_id),
                            risk_factor: self.assets._get_risk_factor(asset_id: collateral_id),
                        },
                    );

                asset_id_opt = collateral_asset.next;
            };
        }

        fn _collect_position_synthetics(
            self: @ContractState, ref asset_entries: Array<AssetEntry>, position_id: PositionId,
        ) {
            let position = self.positions.entry(position_id);
            let mut asset_id_opt = position.synthetic_assets_head.read();
            while let Option::Some(synthetic_id) = asset_id_opt {
                let synthetic_asset = position.synthetic_assets.read(synthetic_id);
                asset_entries
                    .append(
                        AssetEntry {
                            id: synthetic_id,
                            balance: self
                                ._get_provisional_balance(:position_id, asset_id: synthetic_id),
                            price: self.assets._get_synthetic_price(:synthetic_id),
                            risk_factor: self.assets._get_risk_factor(asset_id: synthetic_id),
                        },
                    );

                asset_id_opt = synthetic_asset.next;
            };
        }


        fn _get_position_data(self: @ContractState, position_id: PositionId) -> PositionData {
            let mut asset_entries = array![];
            let position = self.positions.entry(position_id);
            assert(position.owner_public_key.read().is_non_zero(), INVALID_POSITION);
            self._collect_position_collaterals(ref :asset_entries, :position_id);
            self._collect_position_synthetics(ref :asset_entries, :position_id);
            PositionData { asset_entries: asset_entries.span() }
        }

        /// Validates operator flows prerequisites:
        /// - Contract is not paused.
        /// - Caller has operator role.
        /// - Operator nonce is valid.
        /// - Assets integrity [_validate_assets_integrity].
        fn _validate_operator_flow(ref self: ContractState, operator_nonce: u64, now: Timestamp) {
            self.pausable.assert_not_paused();
            self._consume_operator_nonce(:operator_nonce);
            self.assets._validate_assets_integrity(:now);
        }

        fn _validate_order(ref self: ContractState, order: Order, now: Timestamp) {
            // Positive fee check.
            assert(0 <= order.fee.amount, INVALID_NEGATIVE_FEE);

            // Expiration check.
            assert_with_byte_array(
                now < order.expiration, trade_order_expired_err(order.position_id),
            );

            // Assets check.
            self.assets._validate_collateral_active(collateral_id: order.fee.asset_id);
            self.assets._validate_collateral_active(collateral_id: order.quote.asset_id);
            self.assets._validate_asset_active(asset_id: order.base.asset_id);

            // Sign Validation for amounts.
            assert(
                !have_same_sign(a: order.quote.amount, b: order.base.amount),
                INVALID_TRADE_WRONG_AMOUNT_SIGN,
            );
        }

        fn _execute_orders(
            ref self: ContractState,
            order_a: Order,
            order_b: Order,
            actual_amount_base_a: i64,
            actual_amount_quote_a: i64,
            actual_fee_a: i64,
            actual_fee_b: i64,
        ) {
            // Handle fees.
            self
                .apply_funding_and_update_balance(
                    position_id: order_a.position_id,
                    asset_id: order_a.fee.asset_id,
                    diff: (-actual_fee_a).into(),
                );

            self
                .apply_funding_and_update_balance(
                    position_id: order_b.position_id,
                    asset_id: order_b.fee.asset_id,
                    diff: (-actual_fee_b).into(),
                );

            // Update base assets.

            self
                .apply_funding_and_update_balance(
                    position_id: order_a.position_id,
                    asset_id: order_a.base.asset_id,
                    diff: actual_amount_base_a.into(),
                );

            self
                .apply_funding_and_update_balance(
                    position_id: order_b.position_id,
                    asset_id: order_b.base.asset_id,
                    diff: (-actual_amount_base_a).into(),
                );

            // Update quote assets.

            self
                .apply_funding_and_update_balance(
                    position_id: order_a.position_id,
                    asset_id: order_a.quote.asset_id,
                    diff: actual_amount_quote_a.into(),
                );

            self
                .apply_funding_and_update_balance(
                    position_id: order_b.position_id,
                    asset_id: order_b.quote.asset_id,
                    diff: (-actual_amount_quote_a).into(),
                );
        }

        fn _validate_deposit(
            ref self: ContractState,
            operator_nonce: u64,
            depositing_address: ContractAddress,
            deposit_args: DepositArgs,
        ) {
            let now = Time::now();
            self._validate_operator_flow(:operator_nonce, :now);
            let amount = deposit_args.collateral.amount;
            assert(amount > 0, INVALID_NON_POSITIVE_AMOUNT);
            assert(now < deposit_args.expiration, DEPOSIT_EXPIRED);
            self
                .assets
                ._validate_collateral_active(collateral_id: deposit_args.collateral.asset_id);

            let hash = deposit_args.get_message_hash(signer: depositing_address);
            let position_id = deposit_args.position_id;
            self
                ._update_fulfillment(
                    :position_id, :hash, order_amount: amount, actual_amount: amount,
                );
            self._use_fact(:hash);
        }

        fn _validate_funding_tick(
            ref self: ContractState, funding_ticks: Span<FundingTick>, operator_nonce: u64,
        ) {
            self.pausable.assert_not_paused();
            self._consume_operator_nonce(:operator_nonce);
            assert(
                funding_ticks.len() == self.assets._get_num_of_active_synthetic_assets(),
                INVALID_FUNDING_TICK_LEN,
            );
        }

        fn _execute_liquidate(
            ref self: ContractState,
            liquidated_order: Order,
            liquidator_order: Order,
            actual_amount_base_liquidated: i64,
            actual_amount_quote_liquidated: i64,
            actual_liquidator_fee: i64,
        ) {
            let liquidated_position_data = self._get_position_data(liquidated_order.position_id);
            let liquidated_asset_diff_entries = self
                ._create_asset_diff_entries_from_order(
                    order: liquidated_order,
                    actual_amount_base: actual_amount_base_liquidated,
                    actual_amount_quote: actual_amount_quote_liquidated,
                    actual_fee: liquidated_order.fee.amount,
                );

            let liquidator_position_data = self._get_position_data(liquidator_order.position_id);
            let liquidator_asset_diff_entries = self
                ._create_asset_diff_entries_from_order(
                    order: liquidator_order,
                    // Passing the negative of actual amounts to order_b as it is linked to order_a.
                    actual_amount_base: -actual_amount_base_liquidated,
                    actual_amount_quote: -actual_amount_quote_liquidated,
                    actual_fee: actual_liquidator_fee,
                );

            self
                ._execute_orders(
                    order_a: liquidated_order,
                    order_b: liquidator_order,
                    actual_amount_base_a: actual_amount_base_liquidated,
                    actual_amount_quote_a: actual_amount_quote_liquidated,
                    actual_fee_a: liquidated_order.fee.amount,
                    actual_fee_b: actual_liquidator_fee,
                );

            /// Validations - Fundamentals:
            self
                ._validate_liquidated_position(
                    position_id: liquidated_order.position_id,
                    position_data: liquidated_position_data,
                    asset_diff_entries: liquidated_asset_diff_entries,
                );
            self
                ._validate_position_is_healthy_or_healthier(
                    position_id: liquidator_order.position_id,
                    position_data: liquidator_position_data,
                    asset_diff_entries: liquidator_asset_diff_entries,
                );
        }


        fn _validate_orders(
            ref self: ContractState,
            order_a: Order,
            order_b: Order,
            actual_amount_base_a: i64,
            actual_amount_quote_a: i64,
            actual_fee_a: i64,
            actual_fee_b: i64,
            now: Timestamp,
        ) {
            self._validate_order(order: order_a, :now);
            self._validate_order(order: order_b, :now);

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
            assert(order_a.quote.asset_id == order_b.quote.asset_id, DIFFERENT_QUOTE_ASSET_IDS);
            assert(order_a.base.asset_id == order_b.base.asset_id, DIFFERENT_BASE_ASSET_IDS);

            // Sign Validation for amounts.
            assert(
                !have_same_sign(a: order_a.quote.amount, b: order_b.quote.amount),
                INVALID_TRADE_QUOTE_AMOUNT_SIGN,
            );
        }

        /// Builds asset diff entries from an order's fee, quote, and base assets, handling overlaps
        /// by updating existing entries. If an asset matches an existing entry, only `after
        /// balance` is updated.
        fn _create_asset_diff_entries_from_order(
            ref self: ContractState,
            order: Order,
            actual_amount_base: i64,
            actual_amount_quote: i64,
            actual_fee: i64,
        ) -> Span<AssetDiffEntry> {
            let position_id = order.position_id;

            // fee asset.
            let fee_asset_id = order.fee.asset_id;
            let fee_price = self.assets._get_asset_price(asset_id: fee_asset_id);
            let fee_balance = self
                ._get_position(position_id)
                .collateral_assets
                .entry(fee_asset_id)
                .balance
                .read();

            let mut fee_diff = AssetDiffEntry {
                id: fee_asset_id,
                before: fee_balance,
                after: fee_balance.sub(actual_fee),
                price: fee_price,
                risk_factor: self.assets._get_risk_factor(asset_id: fee_asset_id),
            };

            // Quote asset.
            let quote_asset_id = order.quote.asset_id;
            let mut quote_diff: AssetDiffEntry = Default::default();

            if quote_asset_id == fee_asset_id {
                fee_diff.after.add(actual_amount_quote);
            } else {
                let quote_price = self.assets._get_collateral_price(collateral_id: quote_asset_id);
                let quote_balance = self
                    ._get_position(position_id)
                    .collateral_assets
                    .entry(quote_asset_id)
                    .balance
                    .read();

                quote_diff =
                    AssetDiffEntry {
                        id: quote_asset_id,
                        before: quote_balance,
                        after: quote_balance.add(actual_amount_quote),
                        price: quote_price,
                        risk_factor: self.assets._get_risk_factor(asset_id: quote_asset_id),
                    };
            }

            // Base asset.
            let base_asset_id = order.base.asset_id;
            let mut base_diff: AssetDiffEntry = Default::default();

            if base_asset_id == fee_asset_id {
                fee_diff.after.add(actual_amount_base);
            } else if base_asset_id == quote_asset_id {
                quote_diff.after.add(actual_amount_base);
            } else {
                let base_balance = self
                    ._get_position_asset_balance(:position_id, asset_id: base_asset_id);

                base_diff =
                    AssetDiffEntry {
                        id: base_asset_id,
                        before: base_balance,
                        after: base_balance.add(actual_amount_base),
                        price: self.assets._get_asset_price(asset_id: base_asset_id),
                        risk_factor: self.assets._get_risk_factor(asset_id: base_asset_id),
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

        fn _execute_trade(
            ref self: ContractState,
            order_a: Order,
            order_b: Order,
            actual_amount_base_a: i64,
            actual_amount_quote_a: i64,
            actual_fee_a: i64,
            actual_fee_b: i64,
        ) {
            let position_data_a = self._get_position_data(order_a.position_id);
            let asset_diff_entries_a = self
                ._create_asset_diff_entries_from_order(
                    order: order_a,
                    actual_amount_base: actual_amount_base_a,
                    actual_amount_quote: actual_amount_quote_a,
                    actual_fee: actual_fee_a,
                );

            let position_data_b = self._get_position_data(order_b.position_id);
            let asset_diff_entries_b = self
                ._create_asset_diff_entries_from_order(
                    order: order_b,
                    // Passing the negative of actual amounts to order_b as it is linked to order_a.
                    actual_amount_base: -actual_amount_base_a,
                    actual_amount_quote: -actual_amount_quote_a,
                    actual_fee: actual_fee_b,
                );

            self
                ._execute_orders(
                    :order_a,
                    :order_b,
                    :actual_amount_base_a,
                    :actual_amount_quote_a,
                    :actual_fee_a,
                    :actual_fee_b,
                );

            /// Validations - Fundamentals:
            self
                ._validate_position_is_healthy_or_healthier(
                    position_id: order_a.position_id,
                    position_data: position_data_a,
                    asset_diff_entries: asset_diff_entries_a,
                );
            self
                ._validate_position_is_healthy_or_healthier(
                    position_id: order_b.position_id,
                    position_data: position_data_b,
                    asset_diff_entries: asset_diff_entries_b,
                );
        }

        fn _get_position_asset_balance(
            ref self: ContractState, position_id: PositionId, asset_id: AssetId,
        ) -> Balance {
            if self.assets._is_collateral(:asset_id) {
                self._get_position(:position_id).collateral_assets.entry(asset_id).balance.read()
            } else {
                self._get_position(:position_id).synthetic_assets.entry(asset_id).balance.read()
            }
        }

        fn _validate_liquidated_position(
            self: @ContractState,
            position_id: PositionId,
            position_data: PositionData,
            asset_diff_entries: Span<AssetDiffEntry>,
        ) {
            let position_change_result = self
                .value_risk_calculator_dispatcher
                .read()
                .evaluate_position_change(position_data, asset_diff_entries);

            assert(
                position_change_result.position_state_before_change == PositionState::Liquidatable,
                POSITION_IS_NOT_LIQUIDATABLE,
            );

            // None means the position is empty; transitioning from liquidatable to empty is
            // allowed.
            if let Option::Some(change_effects) = position_change_result.change_effects {
                assert(change_effects.is_healthier, POSITION_IS_NOT_HEALTHIER);
            }
        }

        fn _validate_position_is_healthy_or_healthier(
            self: @ContractState,
            position_id: PositionId,
            position_data: PositionData,
            asset_diff_entries: Span<AssetDiffEntry>,
        ) {
            let position_change_result = self
                .value_risk_calculator_dispatcher
                .read()
                .evaluate_position_change(position_data, asset_diff_entries);

            let position_is_healthier = if let Option::Some(change_effects) = position_change_result
                .change_effects {
                change_effects.is_healthier
            } else {
                false
            };
            let position_is_healthy = position_change_result
                .position_state_after_change == PositionState::Healthy;
            assert_with_byte_array(
                position_is_healthier || position_is_healthy,
                position_not_healthy_nor_healthier(position_id),
            );
        }

        fn _register_fact<
            T, +OffchainMessageHash<T, ContractAddress>, +OffchainMessageHash<T, felt252>, +Drop<T>,
        >(
            ref self: ContractState, signature: Signature, position_id: PositionId, message: T,
        ) {
            let position = self._get_position(position_id);
            let msg_hash = position
                ._generate_message_hash_with_owner_account_or_public_key(:message);
            if position.owner_account.read().is_non_zero() {
                assert(
                    position.owner_account.read() == get_caller_address(),
                    CALLER_IS_NOT_OWNER_ACCOUNT,
                );
            }
            position._validate_stark_signature(:msg_hash, :signature);
            self.fact_registry.write(key: msg_hash, value: Time::now());
        }
    }
}
