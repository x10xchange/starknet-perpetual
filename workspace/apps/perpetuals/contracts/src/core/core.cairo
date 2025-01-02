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
    use openzeppelin::account::interface::{ISRC6Dispatcher, ISRC6DispatcherTrait};
    use openzeppelin::account::utils::is_valid_stark_signature;
    use openzeppelin::introspection::src5::SRC5Component;
    use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use openzeppelin::utils::cryptography::nonces::NoncesComponent;
    use openzeppelin::utils::snip12::SNIP12Metadata;
    use perpetuals::core::errors::*;
    use perpetuals::core::interface::ICore;
    use perpetuals::core::types::asset::AssetId;
    use perpetuals::core::types::asset::collateral::{
        CollateralAsset, CollateralConfig, CollateralTimelyData,
    };
    use perpetuals::core::types::asset::synthetic::{
        SyntheticAsset, SyntheticConfig, SyntheticTimelyData,
    };
    use perpetuals::core::types::balance::{Balance, BalanceTrait};
    use perpetuals::core::types::deposit_message::DepositMessage;
    use perpetuals::core::types::funding::FundingTick;
    use perpetuals::core::types::order::Order;
    use perpetuals::core::types::price::{Price, PriceMulTrait};
    use perpetuals::core::types::transfer_message::TransferMessage;
    use perpetuals::core::types::withdraw_message::WithdrawMessage;
    use perpetuals::core::types::{AssetAmount, AssetDiffEntry, AssetEntry, PositionId};
    use perpetuals::core::types::{PositionData, Signature};
    use perpetuals::value_risk_calculator::interface::IValueRiskCalculatorDispatcher;
    use starknet::storage::{
        Map, Mutable, StorageMapReadAccess, StorageMapWriteAccess, StoragePath, StoragePathEntry,
        StoragePointerReadAccess, Vec,
    };
    use starknet::{ContractAddress, get_caller_address, get_contract_address};

    component!(path: AccessControlComponent, storage: accesscontrol, event: AccessControlEvent);
    component!(path: NoncesComponent, storage: nonces, event: NoncesEvent);
    component!(path: PausableComponent, storage: pausable, event: PausableEvent);
    component!(path: ReplaceabilityComponent, storage: replaceability, event: ReplaceabilityEvent);
    component!(path: RolesComponent, storage: roles, event: RolesEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    impl NoncesImpl = NoncesComponent::NoncesImpl<ContractState>;
    impl NoncesComponentInternalImpl = NoncesComponent::InternalImpl<ContractState>;

    // 2^32
    const TWO_POW_32: u64 = 4294967296;

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

    #[abi(embed_v0)]
    impl ReplaceabilityImpl =
        ReplaceabilityComponent::ReplaceabilityImpl<ContractState>;

    #[abi(embed_v0)]
    impl RolesImpl = RolesComponent::RolesImpl<ContractState>;

    #[abi(embed_v0)]
    impl PausableImpl = PausableComponent::PausableImpl<ContractState>;

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
        // --- Initialization ---
        pub value_risk_calculator_dispatcher: IValueRiskCalculatorDispatcher,
        // --- System Configuration ---
        pub price_validation_interval: TimeDelta,
        pub funding_validation_interval: TimeDelta,
        /// 32-bit fixed-point number with a 32-bit fractional part.
        pub max_funding_rate: u32,
        // --- Validations ---
        // Updates each price validation.
        pub last_price_validation: Timestamp,
        // Updates every funding tick.
        pub last_funding_tick: Timestamp,
        // Message hash to fulfilled amount.
        fulfillment: Map<felt252, i64>,
        // --- Asset Configuration ---
        pub collateral_configs: Map<AssetId, Option<CollateralConfig>>,
        pub synthetic_configs: Map<AssetId, Option<SyntheticConfig>>,
        oracles: Map<AssetId, Vec<ContractAddress>>,
        // --- Asset Data ---
        pub collateral_timely_data_head: Option<AssetId>,
        pub collateral_timely_data: Map<AssetId, CollateralTimelyData>,
        num_of_active_synthetic_assets: usize,
        pub synthetic_timely_data_head: Option<AssetId>,
        pub synthetic_timely_data: Map<AssetId, SyntheticTimelyData>,
        fact_registry: Map<felt252, Timestamp>,
        pending_deposits: Map<AssetId, i64>,
        // --- Position Data ---
        pub positions: Map<PositionId, Position>,
    }

    #[starknet::storage_node]
    struct Position {
        version: u8,
        owner_account: ContractAddress,
        pub owner_public_key: felt252,
        collateral_assets_head: Option<AssetId>,
        pub collateral_assets: Map<AssetId, CollateralAsset>,
        synthetic_assets_head: Option<AssetId>,
        synthetic_assets: Map<AssetId, SyntheticAsset>,
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
        self.price_validation_interval.write(price_validation_interval);
        self.funding_validation_interval.write(funding_validation_interval);
        self.max_funding_rate.write(max_funding_rate);
    }

    #[abi(embed_v0)]
    pub impl CoreImpl of ICore<ContractState> {
        // Flows
        fn deleverage(self: @ContractState) {}

        fn deposit(ref self: ContractState, signature: Signature, deposit_message: DepositMessage) {
            let caller_address = get_caller_address();
            let msg_hash = deposit_message.get_message_hash(signer: caller_address);
            self.fact_registry.write(key: msg_hash, value: Time::now());
            let collateral_amount = deposit_message.collateral.amount;
            let asset_id = deposit_message.collateral.asset_id;
            self
                .pending_deposits
                .write(
                    key: asset_id, value: self.pending_deposits.read(asset_id) + collateral_amount,
                );
            let collateral_cfg = self._get_collateral_config(collateral_id: asset_id);
            let quantum = collateral_cfg.quantum;
            assert(collateral_amount > 0, INVALID_DEPOSIT_AMOUNT);
            let amount = collateral_amount.abs() * quantum;
            let erc20_dispatcher = IERC20Dispatcher { contract_address: collateral_cfg.address };
            erc20_dispatcher
                .transfer_from(
                    sender: caller_address,
                    recipient: get_contract_address(),
                    amount: amount.into(),
                );
        }

        fn withdraw_request(
            ref self: ContractState, signature: Signature, message: WithdrawMessage,
        ) {
            self._register_fact(:signature, position_id: message.position_id, :message);
        }

        fn transfer_request(
            ref self: ContractState, signature: Signature, message: TransferMessage,
        ) {
            self._register_fact(:signature, position_id: message.sender, :message);
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
            system_nonce: felt252,
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
            self._validate_user_flow(:system_nonce, :now);

            // Signatures validation:
            let position_a = self._get_position(order_a.position_id);
            let position_b = self._get_position(order_b.position_id);
            let msg_hash_a = position_a._generate_message_hash_with_public_key(message: order_a);
            position_a._validate_stark_signature(msg_hash: msg_hash_a, signature: signature_a);
            let msg_hash_b = position_b._generate_message_hash_with_public_key(message: order_b);
            position_b._validate_stark_signature(msg_hash: msg_hash_b, signature: signature_b);

            self
                ._validate_trade(
                    :order_a,
                    :order_b,
                    :actual_amount_base_a,
                    :actual_amount_quote_a,
                    :actual_fee_a,
                    :actual_fee_b,
                    :now,
                    :msg_hash_a,
                    :msg_hash_b,
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

            // Update fulfillments.
            self
                .fulfillment
                .entry(msg_hash_a)
                .write(self.fulfillment.entry(msg_hash_a).read() + actual_amount_base_a);
            self
                .fulfillment
                .entry(msg_hash_b)
                .write(self.fulfillment.entry(msg_hash_b).read() - actual_amount_base_a);
        }

        fn transfer(self: @ContractState) {}

        /// Withdraw collateral `amount` from the a position to `recipient`.
        ///
        /// Validations:
        /// - Only the operator can call this function.
        /// - The contract must not be paused.
        /// - The `system_nonce` must be valid.
        /// - The `expiration` time has not passed.
        /// - The collateral asset exists in the system.
        /// - The collateral asset is active.
        /// - The funding validation interval has not passed since the last funding tick.
        /// - [The prices of all assets in the system are valid](`_validate_prices`).
        /// - The withdrawal message has not been fulfilled.
        /// - The `signature` is valid.
        /// - Validate the position is healthy after the withdraw.
        ///
        /// Execution:
        /// - [Apply funding](`_apply_funding`) to the position.
        /// - Transfer the collateral `amount` to the `recipient`.
        /// - Update the position's collateral balance.
        /// - Mark the withdrawal message as fulfilled.
        fn withdraw(
            ref self: ContractState,
            system_nonce: felt252,
            signature: Signature,
            // WithdrawMessage
            message: WithdrawMessage,
        ) {
            let now = Time::now();
            self._validate_user_flow(:system_nonce, :now);
            let amount = message.collateral.amount;
            assert(amount > 0, INVALID_WITHDRAW_AMOUNT);
            assert(now < message.expiration, WITHDRAW_EXPIRED);
            let collateral_id = message.collateral.asset_id;
            let collateral_cfg = self._get_collateral_config(:collateral_id);
            assert(collateral_cfg.is_active, COLLATERAL_NOT_ACTIVE);
            let position_id = message.position_id;
            let position = self._get_position(:position_id);
            let hash = position._generate_message_hash_with_owner_account_or_public_key(:message);
            let fulfillment_entry = self.fulfillment.entry(hash);
            assert(fulfillment_entry.read().is_zero(), ALREADY_FULFILLED);

            /// Execution - Withdraw:
            self._apply_funding(:position_id);
            let erc20_dispatcher = IERC20Dispatcher { contract_address: collateral_cfg.address };
            erc20_dispatcher.transfer(recipient: message.recipient, amount: amount.abs().into());
            let amount = amount.try_into().expect(AMOUNT_TOO_LARGE);
            let balance_entry = position.collateral_assets.entry(collateral_id).balance;
            balance_entry.write(balance_entry.read() - amount.into());
            fulfillment_entry.write(amount);

            /// Validations - Fundamentals:
            // TODO: Validate position is healthy
            ()
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
            ref self: ContractState, funding_ticks: Span<FundingTick>, system_nonce: felt252,
        ) {
            self._validate_funding_tick(funding_ticks, system_nonce);
            self._execute_funding_tick(funding_ticks);
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
        fn _get_asset_price(self: @ContractState) {}
        fn _pre_update(self: @ContractState) {}
        fn _post_update(self: @ContractState) {}
        fn _consume_nonce(ref self: ContractState, system_nonce: felt252) {
            self.nonces.use_checked_nonce(get_contract_address(), system_nonce);
        }

        /// If `price_validation_interval` has passed since `last_price_validation`, validate
        /// synthetic and collateral prices and update `last_price_validation` to current time.
        fn _validate_prices(ref self: ContractState, now: Timestamp) {
            let price_validation_interval = self.price_validation_interval.read();
            if now.sub(self.last_price_validation.read()) >= price_validation_interval {
                self._validate_synthetic_prices(now, price_validation_interval);
                self._validate_collateral_prices(now, price_validation_interval);
                self.last_price_validation.write(now);
            }
        }

        fn _validate_synthetic_prices(
            self: @ContractState, now: Timestamp, price_validation_interval: TimeDelta,
        ) {
            let mut asset_id_opt = self.synthetic_timely_data_head.read();
            while let Option::Some(asset_id) = asset_id_opt {
                let synthetic_timely_data = self.synthetic_timely_data.read(asset_id);
                assert(
                    now.sub(synthetic_timely_data.last_price_update) < price_validation_interval,
                    SYNTHETIC_EXPIRED_PRICE,
                );
                asset_id_opt = synthetic_timely_data.next;
            };
        }

        fn _validate_collateral_prices(
            self: @ContractState, now: Timestamp, price_validation_interval: TimeDelta,
        ) {
            let mut asset_id_opt = self.collateral_timely_data_head.read();
            while let Option::Some(asset_id) = asset_id_opt {
                let collateral_timely_data = self.collateral_timely_data.read(asset_id);
                assert(
                    now.sub(collateral_timely_data.last_price_update) < price_validation_interval,
                    COLLATERAL_EXPIRED_PRICE,
                );
                asset_id_opt = collateral_timely_data.next;
            };
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
                let collateral_timely_data = self.collateral_timely_data.read(collateral_id);
                asset_entries
                    .append(
                        AssetEntry {
                            id: collateral_id,
                            // TODO: consider taking into account the funding index.
                            balance: collateral_asset.balance,
                            price: collateral_timely_data.price,
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
                let synthetic_timely_data = self.synthetic_timely_data.read(synthetic_id);
                asset_entries
                    .append(
                        AssetEntry {
                            id: synthetic_id,
                            balance: synthetic_asset.balance,
                            price: synthetic_timely_data.price,
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

        fn _get_collateral_config(
            self: @ContractState, collateral_id: AssetId,
        ) -> CollateralConfig {
            self.collateral_configs.read(collateral_id).expect(COLLATERAL_NOT_EXISTS)
        }

        fn _get_synthetic_config(self: @ContractState, synthetic_id: AssetId) -> SyntheticConfig {
            self.synthetic_configs.read(synthetic_id).expect(SYNTHETIC_NOT_EXISTS)
        }

        /// Validates common prerequisites:
        /// - Caller has operator role.
        /// - Contract is not paused.
        /// - System nonce is valid.
        fn _validate_common_prerequisites(ref self: ContractState, system_nonce: felt252) {
            self.roles.only_operator();
            self.pausable.assert_not_paused();
            self._consume_nonce(system_nonce);
        }

        /// Validates user flows prerequisites:
        /// - Common prerequisites (validated by [`_validate_common_prerequisites`]).
        /// - Funding interval validation.
        /// - Prices validation.
        fn _validate_user_flow(ref self: ContractState, system_nonce: felt252, now: Timestamp) {
            self._validate_common_prerequisites(:system_nonce);
            // Funding validation.
            assert(
                now.sub(self.last_funding_tick.read()) < self.funding_validation_interval.read(),
                FUNDING_EXPIRED,
            );
            // Price validation.
            self._validate_prices(:now);
        }

        fn _validate_order(ref self: ContractState, order: Order, now: Timestamp) {
            // Positive fee check.
            assert(order.fee.amount > 0, INVALID_NON_POSITIVE_FEE);

            // Expiration check.
            assert_with_byte_array(
                now < order.expiration, trade_order_expired_err(order.position_id),
            );

            // Assets check.
            let fee_collateral_config = self._get_collateral_config(order.fee.asset_id);
            assert(fee_collateral_config.is_active, COLLATERAL_NOT_ACTIVE);

            let quote_collateral_config = self._get_collateral_config(order.quote.asset_id);
            assert(quote_collateral_config.is_active, COLLATERAL_NOT_ACTIVE);

            let base_collateral_config = self.collateral_configs.read(order.base.asset_id);
            let is_base_collateral_active = match base_collateral_config {
                Option::Some(config) => config.is_active,
                Option::None => false,
            };
            let base_synthetic_config = self.synthetic_configs.read(order.base.asset_id);
            let is_base_synthetic_active = match base_synthetic_config {
                Option::Some(config) => config.is_active,
                Option::None => false,
            };
            assert(is_base_collateral_active || is_base_synthetic_active, BASE_ASSET_NOT_ACTIVE);

            // Sign Validation for amounts.
            assert(
                !have_same_sign(order.quote.amount, order.base.amount),
                INVALID_TRADE_WRONG_AMOUNT_SIGN,
            );
        }

        fn _validate_funding_tick(
            ref self: ContractState, funding_ticks: Span<FundingTick>, system_nonce: felt252,
        ) {
            self._validate_common_prerequisites(:system_nonce);
            assert(
                funding_ticks.len() == self.num_of_active_synthetic_assets.read(),
                INVALID_FUNDING_TICK_LEN,
            );
        }

        fn _execute_funding_tick(ref self: ContractState, funding_ticks: Span<FundingTick>) {
            let now = Time::now();
            let mut prev_synthetic_id: AssetId = Zero::zero();
            for funding_tick in funding_ticks {
                self
                    ._process_funding_tick(
                        funding_tick: *funding_tick, :now, ref :prev_synthetic_id,
                    );
            };
            self.last_funding_tick.write(now);
        }

        fn _process_funding_tick(
            ref self: ContractState,
            funding_tick: FundingTick,
            now: Timestamp,
            ref prev_synthetic_id: AssetId,
        ) {
            let synthetic_id = funding_tick.asset_id;
            assert_with_byte_array(
                condition: synthetic_id > prev_synthetic_id,
                err: invalid_funding_tick_err(:synthetic_id),
            );
            let synthetic_config = self._get_synthetic_config(:synthetic_id);
            assert(synthetic_config.is_active, SYNTHETIC_NOT_ACTIVE);
            let new_funding_index = funding_tick.funding_index;
            let synthetic_timely_data = self.synthetic_timely_data.read(synthetic_id);
            let index_diff: i64 = (synthetic_timely_data.funding_index - new_funding_index).into();
            let last_funding_tick = self.last_funding_tick.read();
            let time_diff: u64 = (now.sub(other: last_funding_tick)).into();
            assert_with_byte_array(
                condition: index_diff
                    .abs()
                    .into() <= _funding_rate_calc(
                        max_funding_rate: self.max_funding_rate.read(),
                        :time_diff,
                        synthetic_price: synthetic_timely_data.price,
                    ),
                err: invalid_funding_tick_err(:synthetic_id),
            );
            self.synthetic_timely_data.entry(synthetic_id).funding_index.write(new_funding_index);
            prev_synthetic_id = synthetic_id;
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
            msg_hash_a: felt252,
            msg_hash_b: felt252,
        ) {
            self._validate_order(order: order_a, :now);
            self._validate_order(order: order_b, :now);

            // Unpacking.
            let AssetAmount { asset_id: base_asset_id_a, amount: base_amount_a } = order_a.base;
            let AssetAmount { asset_id: quote_asset_id_a, amount: quote_amount_a } = order_a.quote;
            let AssetAmount { asset_id: base_asset_id_b, amount: base_amount_b } = order_b.base;
            let AssetAmount { asset_id: quote_asset_id_b, amount: quote_amount_b } = order_b.quote;
            let AssetAmount { amount: fee_amount_a, .. } = order_a.fee;
            let AssetAmount { amount: fee_amount_b, .. } = order_b.fee;

            // Actual fees amount are positive.
            assert(actual_fee_a > 0, INVALID_NON_POSITIVE_FEE);
            assert(actual_fee_b > 0, INVALID_NON_POSITIVE_FEE);

            // Types validation.
            assert(quote_asset_id_a == quote_asset_id_b, DIFFERENT_QUOTE_ASSET_IDS);
            assert(base_asset_id_a == base_asset_id_b, DIFFERENT_BASE_ASSET_IDS);

            // Sign Validation for amounts.
            assert(
                !have_same_sign(quote_amount_a, quote_amount_b), INVALID_TRADE_QUOTE_AMOUNT_SIGN,
            );
            assert(
                have_same_sign(base_amount_a, actual_amount_base_a), INVALID_TRADE_ACTUAL_BASE_SIGN,
            );
            assert(
                have_same_sign(quote_amount_a, actual_amount_quote_a),
                INVALID_TRADE_ACTUAL_QUOTE_SIGN,
            );

            // Order amount is not exceeded.
            let fulfillment_order_hash_a = self.fulfillment.entry(msg_hash_a).read().abs();
            assert_with_byte_array(
                fulfillment_order_hash_a + actual_amount_base_a.abs() <= base_amount_a.abs(),
                fulfillment_exceeded_err(order_a.position_id),
            );

            let fulfillment_order_hash_b = self.fulfillment.entry(msg_hash_b).read().abs();
            assert_with_byte_array(
                fulfillment_order_hash_b + actual_amount_base_a.abs() <= base_amount_b.abs(),
                fulfillment_exceeded_err(order_b.position_id),
            );

            // Fee to quote amount ratio does not increase.
            let actual_fee_to_quote_amount_ratio_a = FractionTrait::new(
                actual_fee_a, actual_amount_quote_a.abs(),
            );
            let order_a_fee_to_quote_amount_ratio = FractionTrait::new(
                fee_amount_a, quote_amount_a.abs(),
            );
            assert_with_byte_array(
                actual_fee_to_quote_amount_ratio_a <= order_a_fee_to_quote_amount_ratio,
                trade_illegal_fee_to_quote_ratio_err(order_a.position_id),
            );

            let actual_fee_to_quote_amount_ratio_b = FractionTrait::new(
                actual_fee_b, actual_amount_quote_a.abs(),
            );
            let order_b_fee_to_quote_amount_ratio = FractionTrait::new(
                fee_amount_b, quote_amount_b.abs(),
            );
            assert_with_byte_array(
                actual_fee_to_quote_amount_ratio_b <= order_b_fee_to_quote_amount_ratio,
                trade_illegal_fee_to_quote_ratio_err(order_b.position_id),
            );

            // The base-to-quote amount ratio does not decrease.
            let order_a_base_to_quote_ratio = FractionTrait::new(
                base_amount_a, quote_amount_a.abs(),
            );
            let order_b_base_to_quote_ratio = FractionTrait::new(
                base_amount_b, quote_amount_b.abs(),
            );
            let actual_base_to_quote_ratio = FractionTrait::new(
                actual_amount_base_a, actual_amount_quote_a.abs(),
            );

            assert_with_byte_array(
                order_a_base_to_quote_ratio <= actual_base_to_quote_ratio,
                trade_illegal_base_to_quote_ratio_err(order_a.position_id),
            );
            assert_with_byte_array(
                actual_base_to_quote_ratio <= -order_b_base_to_quote_ratio,
                trade_illegal_base_to_quote_ratio_err(order_b.position_id),
            );
        }

        /// Updates the asset entry diff. If the asset entry does not exist, it creates a new one;
        /// otherwise, it updates the after-balance.
        fn _update_asset_entry_diff(
            ref self: ContractState,
            ref asset_diff_entries: Array<AssetDiffEntry>,
            asset_id: AssetId,
            price: Price,
            balance: Balance,
            amount: i64,
        ) {
            let mut collateral_asset_diff_entry = Option::None;
            for asset_diff_entry in asset_diff_entries.span() {
                if asset_id == *asset_diff_entry.id {
                    collateral_asset_diff_entry = Option::Some(*asset_diff_entry);
                    break;
                }
            };
            if collateral_asset_diff_entry.is_none() {
                // Add new asset diff entry.
                collateral_asset_diff_entry =
                    Option::Some(
                        AssetDiffEntry {
                            id: asset_id, before: balance, after: balance, price: price,
                        },
                    );
                asset_diff_entries
                    .append(collateral_asset_diff_entry.expect('INVALID_ASSET_DIFF_ENTRY'));
            }

            collateral_asset_diff_entry.expect('INVALID_ASSET_DIFF_ENTRY').after.add(amount);
        }

        fn _create_asset_diff_entries_from_order(
            ref self: ContractState,
            order: Order,
            actual_amount_base: i64,
            actual_amount_quote: i64,
            actual_fee: i64,
        ) -> Span<AssetDiffEntry> {
            // TODO(Mohammad): Consider defining and using a set instead of an array.
            let mut asset_diff_entries: Array<AssetDiffEntry> = array![];
            let position_id = order.position_id;

            // fee asset.
            let fee_asset_id = order.fee.asset_id;
            let fee_price = self.collateral_timely_data.read(fee_asset_id).price;
            let fee_balance = self
                ._get_position(position_id)
                .collateral_assets
                .entry(fee_asset_id)
                .balance
                .read();
            self
                ._update_asset_entry_diff(
                    ref asset_diff_entries, fee_asset_id, fee_price, fee_balance, -actual_fee,
                );

            // Quote asset.
            let quote_asset_id = order.quote.asset_id;
            let quote_price = self.collateral_timely_data.read(quote_asset_id).price;
            let quote_balance = self
                ._get_position(position_id)
                .collateral_assets
                .entry(quote_asset_id)
                .balance
                .read();
            self
                ._update_asset_entry_diff(
                    ref asset_diff_entries,
                    quote_asset_id,
                    quote_price,
                    quote_balance,
                    -actual_amount_quote,
                );

            // Base asset.
            let base_asset_id = order.base.asset_id;
            let (price, balance) = match self.collateral_configs.read(base_asset_id) {
                Option::Some(_) => {
                    (
                        self.collateral_timely_data.read(base_asset_id).price,
                        self
                            ._get_position(position_id)
                            .collateral_assets
                            .entry(base_asset_id)
                            .balance
                            .read(),
                    )
                },
                Option::None => {
                    (
                        self.synthetic_timely_data.read(base_asset_id).price,
                        self
                            ._get_position(position_id)
                            .synthetic_assets
                            .entry(base_asset_id)
                            .balance
                            .read(),
                    )
                },
            };

            self
                ._update_asset_entry_diff(
                    ref asset_diff_entries, base_asset_id, price, balance, actual_amount_base,
                );

            asset_diff_entries.span()
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

            let _position_snapshot_a = self._get_position_data(order_a.position_id);
            let _asset_diff_entries_a = self
                ._create_asset_diff_entries_from_order(
                    order_a, actual_amount_base_a, actual_amount_quote_a, actual_fee_a,
                );

            let _position_snapshot_b = self._get_position_data(order_b.position_id);
            let _asset_diff_entries_b = self
                ._create_asset_diff_entries_from_order(
                    order_b, -actual_amount_base_a, -actual_amount_quote_a, actual_fee_b,
                );

            // TODO: calculate TVTR change.

            let position_entry_a = self._get_position(order_a.position_id);
            let position_entry_b = self._get_position(order_b.position_id);

            // Handle fees.
            let mut order_a_fee_balance_path = position_entry_a
                .collateral_assets
                .entry(order_a.fee.asset_id)
                .balance;
            let mut order_b_fee_balance_path = position_entry_b
                .collateral_assets
                .entry(order_b.fee.asset_id)
                .balance;
            order_a_fee_balance_path.write(order_a_fee_balance_path.read().sub(actual_fee_a));
            order_b_fee_balance_path.write(order_b_fee_balance_path.read().sub(actual_fee_b));
            // TODO: Add the fee to `fee_position`.

            // Update base position.
            let (mut order_a_base_balance_path, mut order_b_base_balance_path) =
                match (self.collateral_configs.read(order_a.base.asset_id)) {
                // Base is collateral.
                Option::Some(_) => {
                    (
                        position_entry_a.collateral_assets.entry(order_a.base.asset_id).balance,
                        position_entry_b.collateral_assets.entry(order_b.base.asset_id).balance,
                    )
                },
                // Base is synthetic.
                Option::None => {
                    (
                        position_entry_a.synthetic_assets.entry(order_a.base.asset_id).balance,
                        position_entry_b.synthetic_assets.entry(order_b.base.asset_id).balance,
                    )
                },
            };

            order_a_base_balance_path
                .write(order_a_base_balance_path.read().add(actual_amount_base_a));

            order_b_base_balance_path
                .write(order_b_base_balance_path.read().sub(actual_amount_base_a));

            // Update quote position.
            let mut order_a_quote_balance_path = position_entry_a
                .collateral_assets
                .entry(order_a.quote.asset_id)
                .balance;
            let mut order_b_quote_balance_path = position_entry_b
                .collateral_assets
                .entry(order_b.quote.asset_id)
                .balance;
            order_a_quote_balance_path
                .write(order_a_quote_balance_path.read().add(actual_amount_quote_a));
            order_b_quote_balance_path
                .write(order_b_quote_balance_path.read().sub(actual_amount_quote_a));
            /// Validations - Fundamentals:
        // TODO: Validate position is healthy or healthier.
        }

        fn _validate_stark_signature(
            self: @StoragePath<Mutable<Position>>, msg_hash: felt252, signature: Signature,
        ) {
            assert(
                is_valid_stark_signature(
                    :msg_hash, public_key: self.owner_public_key.read(), :signature,
                ),
                INVALID_STARK_SIGNATURE,
            );
        }

        fn _validate_owner_signature(
            self: @StoragePath<Mutable<Position>>, msg_hash: felt252, signature: Signature,
        ) -> bool {
            let contract_address = self.owner_account.read();
            if contract_address.is_zero() {
                return false;
            }
            let is_valid_signature_felt = ISRC6Dispatcher { contract_address }
                .is_valid_signature(hash: msg_hash, signature: signature.into());
            // Check either 'VALID' or true for backwards compatibility.
            assert(
                is_valid_signature_felt == starknet::VALIDATED || is_valid_signature_felt == 1,
                INVALID_OWNER_SIGNATURE,
            );
            true
        }

        fn _generate_message_hash_with_public_key<
            T, +OffchainMessageHash<T, ContractAddress>, +OffchainMessageHash<T, felt252>, +Drop<T>,
        >(
            self: @StoragePath<Mutable<Position>>, message: T,
        ) -> felt252 {
            message.get_message_hash(signer: self.owner_public_key.read())
        }

        fn _generate_message_hash_with_owner_account_or_public_key<
            T, +OffchainMessageHash<T, ContractAddress>, +OffchainMessageHash<T, felt252>, +Drop<T>,
        >(
            self: @StoragePath<Mutable<Position>>, message: T,
        ) -> felt252 {
            let signer = self.owner_account.read();
            if signer.is_non_zero() {
                message.get_message_hash(:signer)
            } else {
                message.get_message_hash(signer: self.owner_public_key.read())
            }
        }

        fn _register_fact<
            T, +OffchainMessageHash<T, ContractAddress>, +OffchainMessageHash<T, felt252>, +Drop<T>,
        >(
            ref self: ContractState, signature: Signature, position_id: PositionId, message: T,
        ) {
            let position = self._get_position(position_id);
            let msg_hash = position
                ._generate_message_hash_with_owner_account_or_public_key(:message);
            if !position._validate_owner_signature(:msg_hash, :signature) {
                position._validate_stark_signature(:msg_hash, :signature);
            };
            self.fact_registry.write(key: msg_hash, value: Time::now());
        }
    }


    /// Calculate the funding rate using the following formula:
    /// `max_funding_rate * time_diff * synthetic_price / 2^32`.
    fn _funding_rate_calc(max_funding_rate: u32, time_diff: u64, synthetic_price: Price) -> u128 {
        synthetic_price.mul(rhs: max_funding_rate) * time_diff.into() / TWO_POW_32.into()
    }
}
