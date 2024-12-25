#[starknet::contract]
pub mod Core {
    use contracts_commons::components::pausable::PausableComponent;
    use contracts_commons::components::pausable::PausableComponent::InternalTrait as PausableInternal;
    use contracts_commons::components::replaceability::ReplaceabilityComponent;
    use contracts_commons::components::roles::RolesComponent;
    use contracts_commons::components::roles::RolesComponent::InternalTrait as RolesInteral;
    use contracts_commons::errors::assert_with_byte_array;
    use contracts_commons::math::Abs;
    use contracts_commons::message_hash::OffchainMessageHash;
    use contracts_commons::types::time::{Time, TimeDelta, Timestamp};
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
    use perpetuals::core::types::AssetEntry;
    use perpetuals::core::types::asset::AssetId;
    use perpetuals::core::types::asset::collateral::{
        CollateralAsset, CollateralConfig, CollateralTimelyData,
    };
    use perpetuals::core::types::asset::synthetic::{
        SyntheticAsset, SyntheticConfig, SyntheticTimelyData,
    };
    use perpetuals::core::types::funding::FundingTick;
    use perpetuals::core::types::order::Order;
    use perpetuals::core::types::price::{Price, PriceMulTrait};
    use perpetuals::core::types::withdraw_message::WithdrawMessage;
    use perpetuals::core::types::{PositionData, Signature};
    use perpetuals::value_risk_calculator::interface::IValueRiskCalculatorDispatcher;
    use starknet::storage::{Map, Mutable, StoragePath, StoragePathEntry, Vec};
    use starknet::{ContractAddress, get_contract_address};

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
    impl SNIP12MetadataImpl of SNIP12Metadata {
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
        nonces: NoncesComponent::Storage,
        #[substorage(v0)]
        pausable: PausableComponent::Storage,
        #[substorage(v0)]
        replaceability: ReplaceabilityComponent::Storage,
        #[substorage(v0)]
        roles: RolesComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        // --- Initialization ---
        value_risk_calculator_dispatcher: IValueRiskCalculatorDispatcher,
        // --- System Configuration ---
        price_validation_interval: TimeDelta,
        funding_validation_interval: TimeDelta,
        /// 32-bit fixed-point number with a 32-bit fractional part.
        max_funding_rate: u32,
        // --- Validations ---
        // Updates each price validation.
        last_price_validation: Timestamp,
        // Updates every funding tick.
        last_funding_tick: Timestamp,
        // Message hash to fulfilled amount.
        fulfillment: Map<felt252, i64>,
        // --- Asset Configuration ---
        collateral_configs: Map<AssetId, Option<CollateralConfig>>,
        synthetic_configs: Map<AssetId, Option<SyntheticConfig>>,
        oracles: Map<AssetId, Vec<ContractAddress>>,
        // --- Asset Data ---
        collateral_timely_data_head: Option<AssetId>,
        collateral_timely_data: Map<AssetId, CollateralTimelyData>,
        num_of_active_synthetic_assets: usize,
        synthetic_timely_data_head: Option<AssetId>,
        synthetic_timely_data: Map<AssetId, SyntheticTimelyData>,
        // --- Position Data ---
        positions: Map<felt252, Position>,
    }

    #[starknet::storage_node]
    struct Position {
        version: u8,
        owner_account: ContractAddress,
        owner_public_key: felt252,
        collateral_assets_head: Option<AssetId>,
        collateral_assets: Map<AssetId, CollateralAsset>,
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
        fn deposit(self: @ContractState) {}
        fn liquidate(self: @ContractState) {}
        fn trade(
            ref self: ContractState,
            system_nonce: felt252,
            signature_a: Signature,
            signature_b: Signature,
            order_a: Order,
            order_b: Order,
            actual_fee_a: i64,
            actual_fee_b: i64,
            actual_amount_base_a: i64,
            actual_amount_quote_a: i64,
        ) {
            /// Validations:
            self._validate_trade(:signature_a, :signature_b, :order_a, :order_b, :system_nonce);
            // TODO: execute trade flow.
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
            withdraw_message: WithdrawMessage,
        ) {
            let now = Time::now();
            self._validate_user_flow(:system_nonce, :now);
            let amount = withdraw_message.collateral.amount;
            assert(amount > 0, INVALID_WITHDRAW_AMOUNT);
            assert(now < withdraw_message.expiration, WITHDRAW_EXPIRED);
            let collateral_id = withdraw_message.collateral.asset_id;
            let collateral_cfg = self._get_collateral_config(:collateral_id);
            assert(collateral_cfg.is_active, COLLATERAL_NOT_ACTIVE);
            let position_id = withdraw_message.position_id;
            let position = self._get_position(:position_id);
            let position_owner = position.owner_account.read();
            let mut msg_hash = withdraw_message.get_message_hash(position_owner);
            if position_owner.is_non_zero() {
                assert(
                    is_valid_owner_signature(position_owner, msg_hash, signature),
                    INVALID_OWNER_SIGNATURE,
                );
            } else {
                let public_key = position.owner_public_key.read();
                msg_hash = withdraw_message.get_message_hash(public_key);
                assert(
                    is_valid_stark_signature(:msg_hash, :public_key, signature: signature.span()),
                    INVALID_STARK_SIGNATURE,
                );
            };
            let fulfillment_entry = self.fulfillment.entry(msg_hash);
            assert(fulfillment_entry.read().is_zero(), ALREADY_FULFILLED);
            /// Execution - Withdraw:
            self._apply_funding(:position_id);
            let erc20_dispatcher = IERC20Dispatcher { contract_address: collateral_cfg.address };
            erc20_dispatcher
                .transfer(recipient: withdraw_message.recipient, amount: amount.abs().into());
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
        fn _apply_funding(ref self: ContractState, position_id: felt252) {}
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

        fn _validate_stark_signature(
            self: @ContractState, public_key: felt252, hash: felt252, signature: Signature,
        ) {
            assert(
                is_valid_stark_signature(msg_hash: hash, :public_key, signature: signature.span()),
                INVALID_STARK_SIGNATURE,
            );
        }

        fn _get_position(
            ref self: ContractState, position_id: felt252,
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

        fn _get_position_data(self: @ContractState, position_id: felt252) -> PositionData {
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

        fn _validate_common_prerequisites(ref self: ContractState, system_nonce: felt252) {
            self.roles.only_operator();
            self.pausable.assert_not_paused();
            self._consume_nonce(system_nonce);
        }

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

        fn _validate_order(
            ref self: ContractState, signature: Signature, order: Order, now: Timestamp,
        ) {
            // Positive fee check.
            assert(order.fee.amount > 0, INVALID_NON_POSITIVE_FEE);

            // Expiration check.
            assert_with_byte_array(
                now < order.expiration, trade_order_expired_err(order.position_id),
            );

            // Asset check.
            let collateral = self._get_collateral_config(order.fee.asset_id);
            assert(collateral.is_active, COLLATERAL_NOT_ACTIVE);

            // Public key signature validation.
            let public_key = self.positions.entry(order.position_id).owner_public_key.read();
            let hash = order.get_message_hash(public_key);
            self._validate_stark_signature(:public_key, :hash, :signature);
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
            signature_a: Signature,
            signature_b: Signature,
            order_a: Order,
            order_b: Order,
            system_nonce: felt252,
        ) {
            let now = Time::now();
            self._validate_user_flow(:system_nonce, :now);

            self._validate_order(signature: signature_a, order: order_a, :now);
            self._validate_order(signature: signature_b, order: order_b, :now);
            // TODO: validate non-basic rules.
        }
    }

    fn is_valid_owner_signature(
        owner: ContractAddress, hash: felt252, signature: Signature,
    ) -> bool {
        let is_valid_signature_felt = ISRC6Dispatcher { contract_address: owner }
            .is_valid_signature(:hash, :signature);
        // Check either 'VALID' or true for backwards compatibility.
        is_valid_signature_felt == starknet::VALIDATED || is_valid_signature_felt == 1
    }

    /// Calculate the funding rate using the following formula:
    /// `max_funding_rate * time_diff * synthetic_price / 2^32`.
    fn _funding_rate_calc(max_funding_rate: u32, time_diff: u64, synthetic_price: Price) -> u128 {
        synthetic_price.mul(rhs: max_funding_rate) * time_diff.into() / TWO_POW_32.into()
    }
}
