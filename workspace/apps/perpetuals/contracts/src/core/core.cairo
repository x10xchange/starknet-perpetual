#[starknet::contract]
pub mod Core {
    use contracts_commons::components::pausable::PausableComponent;
    use contracts_commons::components::pausable::PausableComponent::InternalTrait as PausableInternal;
    use contracts_commons::components::replaceability::ReplaceabilityComponent;
    use contracts_commons::components::roles::RolesComponent;
    use contracts_commons::components::roles::RolesComponent::InternalTrait as RolesInteral;
    use contracts_commons::errors::assert_with_byte_array;
    use contracts_commons::math::{Abs, FractionTrait, have_same_sign};
    use contracts_commons::message_hash::OffchainMessageHash;
    use contracts_commons::types::time::time::{Time, TimeDelta, Timestamp};
    use core::num::traits::Zero;
    use core::starknet::storage::StoragePointerWriteAccess;
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::introspection::src5::SRC5Component;
    use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use openzeppelin::utils::cryptography::nonces::NoncesComponent;
    use openzeppelin::utils::snip12::SNIP12Metadata;
    use perpetuals::core::components::assets::AssetsComponent;
    use perpetuals::core::components::assets::AssetsComponent::InternalTrait as AssetsInternal;
    use perpetuals::core::errors::*;
    use perpetuals::core::interface::ICore;
    use perpetuals::core::types::asset::AssetId;
    use perpetuals::core::types::balance::{Balance, BalanceTrait};
    use perpetuals::core::types::deposit::DepositArgs;
    use perpetuals::core::types::funding::FundingTick;
    use perpetuals::core::types::order::Order;
    use perpetuals::core::types::position::{Position, PositionTrait};
    use perpetuals::core::types::transfer::TransferArgs;
    use perpetuals::core::types::update_position_public_key::UpdatePositionPublicKeyArgs;
    use perpetuals::core::types::withdraw::WithdrawArgs;
    use perpetuals::core::types::{AssetDiffEntry, AssetEntry, PositionData, PositionId, Signature};
    use perpetuals::value_risk_calculator::interface::{
        IValueRiskCalculatorDispatcher, IValueRiskCalculatorDispatcherTrait, PositionState,
    };
    use starknet::storage::{
        Map, Mutable, StorageMapReadAccess, StorageMapWriteAccess, StoragePath, StoragePathEntry,
        StoragePointerReadAccess,
    };
    use starknet::{ContractAddress, get_caller_address, get_contract_address};

    component!(path: AccessControlComponent, storage: accesscontrol, event: AccessControlEvent);
    component!(path: NoncesComponent, storage: nonces, event: NoncesEvent);
    component!(path: PausableComponent, storage: pausable, event: PausableEvent);
    component!(path: ReplaceabilityComponent, storage: replaceability, event: ReplaceabilityEvent);
    component!(path: RolesComponent, storage: roles, event: RolesEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);
    component!(path: AssetsComponent, storage: assets, event: AssetsEvent);

    impl NoncesImpl = NoncesComponent::NoncesImpl<ContractState>;
    impl NoncesComponentInternalImpl = NoncesComponent::InternalImpl<ContractState>;

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
        pub nonces: NoncesComponent::Storage,
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
        NoncesEvent: NoncesComponent::Event,
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

        fn withdraw_request(ref self: ContractState, signature: Signature, message: WithdrawArgs) {
            self._register_fact(:signature, position_id: message.position_id, :message);
        }

        fn transfer_request(ref self: ContractState, signature: Signature, message: TransferArgs) {
            self._register_fact(:signature, position_id: message.sender, :message);
        }

        fn update_position_public_key_request(
            ref self: ContractState, signature: Signature, message: UpdatePositionPublicKeyArgs,
        ) {
            let position_id = message.position_id;
            let position = self.positions.entry(position_id);
            let msg_hash = message.get_message_hash(signer: position.owner_account.read());
            position._validate_owner_signature(:msg_hash, :signature);
            self.fact_registry.write(key: msg_hash, value: Time::now());
        }

        fn liquidate(self: @ContractState) {}

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
        /// - Apply funding to both positions.
        /// - Subtract the fees from each position's collateral.
        /// - Add the fees to the `fee_position`.
        /// - Update Order A's position and Order B's position, based on `actual_amount_base`.
        /// - Adjust collateral balances.
        /// - Perform fundamental validation for both positions after the trade.
        /// - Update order fulfillment.
        fn trade(
            ref self: ContractState,
            operator_nonce: felt252,
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
            let position_a = self._get_position(position_id_a);
            let position_b = self._get_position(position_id_b);
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
                    actual_amount: -actual_amount_base_a,
                );

            self
                ._validate_trade(
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
        /// - [Apply funding](`_apply_funding`) to the position.
        /// - Transfer the collateral `amount` to the `recipient`.
        /// - Update the position's collateral balance.
        /// - Mark the withdrawal message as fulfilled.
        fn withdraw(ref self: ContractState, operator_nonce: felt252, message: WithdrawArgs) {
            let now = Time::now();
            self._validate_operator_flow(:operator_nonce, :now);
            let amount = message.collateral.amount;
            assert(amount > 0, INVALID_NON_POSITIVE_AMOUNT);
            assert(now < message.expiration, WITHDRAW_EXPIRED);
            let collateral_id = message.collateral.asset_id;
            let collateral_cfg = self.assets._get_collateral_config(:collateral_id);
            assert(collateral_cfg.is_active, COLLATERAL_NOT_ACTIVE);
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
            self._apply_funding(:position_id);
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
            let position_diff = array![AssetDiffEntry { id: collateral_id, before, after, price }]
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
            ref self: ContractState, funding_ticks: Span<FundingTick>, operator_nonce: felt252,
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
        fn _apply_funding(ref self: ContractState, position_id: PositionId) {}
        fn _pre_update(self: @ContractState) {}
        fn _post_update(self: @ContractState) {}

        /// Validates the operator nonce and consumes it.
        /// Only the operator can call this function.
        fn _consume_operator_nonce(ref self: ContractState, operator_nonce: felt252) {
            self.roles.only_operator();
            self.nonces.use_checked_nonce(owner: get_contract_address(), nonce: operator_nonce);
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

        fn _get_position(
            ref self: ContractState, position_id: PositionId,
        ) -> StoragePath<Mutable<Position>> {
            let mut position = self.positions.entry(position_id);
            assert(position.owner_public_key.read().is_non_zero(), INVALID_POSITION);
            position
        }

        fn _collect_position_collaterals(
            self: @ContractState,
            ref asset_entries: Array<AssetEntry>,
            position: StoragePath<Position>,
        ) {
            let mut asset_id_opt = position.collateral_assets_head.read();
            while let Option::Some(collateral_id) = asset_id_opt {
                let collateral_asset = position.collateral_assets.read(collateral_id);
                asset_entries
                    .append(
                        AssetEntry {
                            id: collateral_id,
                            // TODO: consider taking into account the funding index.
                            balance: collateral_asset.balance,
                            price: self.assets._get_collateral_price(:collateral_id),
                        },
                    );

                asset_id_opt = collateral_asset.next;
            };
        }

        fn _collect_position_synthetics(
            self: @ContractState,
            ref asset_entries: Array<AssetEntry>,
            position: StoragePath<Position>,
        ) {
            let mut asset_id_opt = position.synthetic_assets_head.read();
            while let Option::Some(synthetic_id) = asset_id_opt {
                let synthetic_asset = position.synthetic_assets.read(synthetic_id);
                asset_entries
                    .append(
                        AssetEntry {
                            id: synthetic_id,
                            balance: synthetic_asset.balance,
                            price: self.assets._get_synthetic_price(:synthetic_id),
                        },
                    );

                asset_id_opt = synthetic_asset.next;
            };
        }

        fn _get_position_data(self: @ContractState, position_id: PositionId) -> PositionData {
            let mut asset_entries = array![];
            let position = self.positions.entry(position_id);
            assert(position.owner_public_key.read().is_non_zero(), INVALID_POSITION);
            self._collect_position_collaterals(ref :asset_entries, :position);
            self._collect_position_synthetics(ref :asset_entries, :position);
            PositionData { asset_entries: asset_entries.span() }
        }

        /// Validates operator flows prerequisites:
        /// - Contract is not paused.
        /// - Caller has operator role.
        /// - Operator nonce is valid.
        /// - Assets integrity [_validate_assets_integrity].
        fn _validate_operator_flow(
            ref self: ContractState, operator_nonce: felt252, now: Timestamp,
        ) {
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
            let position_entry_a = self._get_position(position_id: order_a.position_id);
            let position_entry_b = self._get_position(position_id: order_b.position_id);

            // Handle fees.
            position_entry_a
                ._update_balance(
                    asset_id: order_a.fee.asset_id,
                    actual_amount: -actual_fee_a,
                    is_collateral: true,
                );
            position_entry_b
                ._update_balance(
                    asset_id: order_b.fee.asset_id,
                    actual_amount: -actual_fee_b,
                    is_collateral: true,
                );

            // Update base assets.
            position_entry_a
                ._update_balance(
                    asset_id: order_a.base.asset_id,
                    actual_amount: actual_amount_base_a,
                    is_collateral: self.assets._is_collateral(asset_id: order_a.base.asset_id),
                );
            position_entry_b
                ._update_balance(
                    asset_id: order_b.base.asset_id,
                    actual_amount: -actual_amount_base_a,
                    is_collateral: self.assets._is_collateral(asset_id: order_b.base.asset_id),
                );

            // Update quote assets.
            position_entry_a
                ._update_balance(
                    asset_id: order_a.quote.asset_id,
                    actual_amount: actual_amount_quote_a,
                    is_collateral: true,
                );
            position_entry_b
                ._update_balance(
                    asset_id: order_b.quote.asset_id,
                    actual_amount: -actual_amount_quote_a,
                    is_collateral: true,
                );
        }

        fn _validate_funding_tick(
            ref self: ContractState, funding_ticks: Span<FundingTick>, operator_nonce: felt252,
        ) {
            self.pausable.assert_not_paused();
            self._consume_operator_nonce(:operator_nonce);
            assert(
                funding_ticks.len() == self.assets._get_num_of_active_synthetic_assets(),
                INVALID_FUNDING_TICK_LEN,
            );
        }

        fn _validate_trade(
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

            _validate_order_with_actual_amounts(
                order: order_a,
                actual_amount_base: actual_amount_base_a,
                actual_amount_quote: actual_amount_quote_a,
                actual_fee: actual_fee_a,
            );
            _validate_order_with_actual_amounts(
                order: order_b,
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
            // Apply funding to both positions.
            self._apply_funding(order_a.position_id);
            self._apply_funding(order_b.position_id);

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
                position._validate_owner_signature(:msg_hash, :signature);
            } else {
                position._validate_stark_signature(:msg_hash, :signature);
            }
            self.fact_registry.write(key: msg_hash, value: Time::now());
        }
    }

    /// It validates the given order with the actual amounts.
    fn _validate_order_with_actual_amounts(
        order: Order, actual_amount_base: i64, actual_amount_quote: i64, actual_fee: i64,
    ) {
        let order_amount_base = order.base.amount;
        let order_amount_quote = order.quote.amount;
        let order_amount_fee = order.fee.amount;

        // Sign Validation for amounts.
        assert(
            have_same_sign(a: order_amount_base, b: actual_amount_base),
            INVALID_TRADE_ACTUAL_BASE_SIGN,
        );
        assert(
            have_same_sign(a: order_amount_quote, b: actual_amount_quote),
            INVALID_TRADE_ACTUAL_QUOTE_SIGN,
        );

        _validate_fee_to_quote_ratio(
            position_id: order.position_id,
            :actual_fee,
            :actual_amount_quote,
            :order_amount_fee,
            :order_amount_quote,
        );

        _validate_base_to_quote_ratio(
            position_id: order.position_id,
            :actual_amount_base,
            :actual_amount_quote,
            :order_amount_base,
            :order_amount_quote,
        );
    }

    fn _validate_fee_to_quote_ratio(
        position_id: PositionId,
        actual_fee: i64,
        actual_amount_quote: i64,
        order_amount_fee: i64,
        order_amount_quote: i64,
    ) {
        // Fee to quote amount ratio does not increase.
        let actual_fee_to_quote_amount_ratio = FractionTrait::new(
            numerator: actual_fee, denominator: actual_amount_quote.abs(),
        );
        let order_fee_to_quote_amount_ratio = FractionTrait::new(
            numerator: order_amount_fee, denominator: order_amount_quote.abs(),
        );
        assert_with_byte_array(
            actual_fee_to_quote_amount_ratio <= order_fee_to_quote_amount_ratio,
            trade_illegal_fee_to_quote_ratio_err(position_id),
        );
    }

    fn _validate_base_to_quote_ratio(
        position_id: PositionId,
        actual_amount_base: i64,
        actual_amount_quote: i64,
        order_amount_base: i64,
        order_amount_quote: i64,
    ) {
        // The base-to-quote amount ratio does not decrease.
        let order_base_to_quote_ratio = FractionTrait::new(
            numerator: order_amount_base, denominator: order_amount_quote.abs(),
        );
        let actual_base_to_quote_ratio = FractionTrait::new(
            numerator: actual_amount_base, denominator: actual_amount_quote.abs(),
        );
        assert_with_byte_array(
            order_base_to_quote_ratio <= actual_base_to_quote_ratio,
            trade_illegal_base_to_quote_ratio_err(position_id),
        );
    }
}
