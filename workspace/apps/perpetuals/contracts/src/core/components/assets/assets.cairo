#[starknet::component]
pub mod AssetsComponent {
    use RolesComponent::InternalTrait as RolesInternalTrait;
    use contracts_commons::components::deposit::Deposit;
    use contracts_commons::components::deposit::Deposit::InternalTrait as DepositTrait;
    use contracts_commons::components::nonce::NonceComponent;
    use contracts_commons::components::nonce::NonceComponent::InternalTrait as NonceInternal;
    use contracts_commons::components::pausable::PausableComponent;
    use contracts_commons::components::pausable::PausableComponent::InternalTrait as PausableInternal;
    use contracts_commons::components::roles::RolesComponent;
    use contracts_commons::constants::{MAX_U32, MINUTE, TWO_POW_128, TWO_POW_32, TWO_POW_40};
    use contracts_commons::math::abs::Abs;
    use contracts_commons::types::PublicKey;
    use contracts_commons::types::fixed_two_decimal::{FixedTwoDecimal, FixedTwoDecimalTrait};
    use contracts_commons::types::time::time::{Time, TimeDelta, Timestamp};
    use contracts_commons::utils::{AddToStorage, SubFromStorage, validate_stark_signature};
    use core::cmp::min;
    use core::num::traits::{One, Zero};
    use core::panic_with_felt252;
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::introspection::src5::SRC5Component;
    use perpetuals::core::components::assets::errors::{
        ALREADY_INITIALIZED, ASSET_ALREADY_EXISTS, ASSET_NAME_TOO_LONG, ASSET_NOT_ACTIVE,
        ASSET_NOT_EXISTS, COLLATERAL_NOT_ACTIVE, COLLATERAL_NOT_EXISTS, DEACTIVATED_ASSET,
        FUNDING_EXPIRED, FUNDING_TICKS_NOT_SORTED, INVALID_FUNDING_TICK_LEN, INVALID_MEDIAN,
        INVALID_PRICE_TIMESTAMP, INVALID_SAME_QUORUM, INVALID_ZERO_ASSET_ID,
        INVALID_ZERO_ASSET_NAME, INVALID_ZERO_ORACLE_NAME, INVALID_ZERO_PUBLIC_KEY,
        INVALID_ZERO_QUANTUM, INVALID_ZERO_QUORUM, INVALID_ZERO_TOKEN_ADDRESS, NOT_COLLATERAL,
        NOT_SYNTHETIC, ORACLE_ALREADY_EXISTS, ORACLE_NAME_TOO_LONG, ORACLE_NOT_EXISTS,
        QUORUM_NOT_REACHED, SIGNED_PRICES_UNSORTED, SYNTHETIC_ALREADY_EXISTS,
        SYNTHETIC_EXPIRED_PRICE, SYNTHETIC_NOT_ACTIVE, SYNTHETIC_NOT_EXISTS,
        ZERO_MAX_FUNDING_INTERVAL, ZERO_MAX_FUNDING_RATE, ZERO_MAX_ORACLE_PRICE,
        ZERO_MAX_PRICE_INTERVAL,
    };

    use perpetuals::core::components::assets::events;
    use perpetuals::core::components::assets::interface::IAssets;
    use perpetuals::core::types::asset::collateral::{
        CollateralConfig, CollateralTimelyData, VERSION as COLLATERAL_VERSION,
    };
    use perpetuals::core::types::asset::synthetic::{
        SyntheticConfig, SyntheticTimelyData, VERSION as SYNTHETIC_VERSION,
    };
    use perpetuals::core::types::asset::{AssetId, AssetStatus};
    use perpetuals::core::types::balance::Balance;
    use perpetuals::core::types::funding::{FundingIndex, FundingTick, validate_funding_rate};
    use perpetuals::core::types::price::{Price, PriceMulTrait, PriceTrait, SignedPrice};
    use starknet::ContractAddress;
    use starknet::storage::{
        Map, MutableVecTrait, StorageMapReadAccess, StoragePathEntry, StoragePointerReadAccess,
        StoragePointerWriteAccess, Vec, VecTrait,
    };

    #[storage]
    pub struct Storage {
        /// 32-bit fixed-point number with a 32-bit fractional part.
        max_funding_rate: u32,
        max_price_interval: TimeDelta,
        max_funding_interval: TimeDelta,
        // Updates each price validation.
        pub last_price_validation: Timestamp,
        // Updates every funding tick.
        pub last_funding_tick: Timestamp,
        pub collateral_config: Map<AssetId, Option<CollateralConfig>>,
        pub synthetic_config: Map<AssetId, Option<SyntheticConfig>>,
        pub collateral_timely_data_head: Option<AssetId>,
        pub collateral_timely_data: Map<AssetId, CollateralTimelyData>,
        pub num_of_active_synthetic_assets: usize,
        pub synthetic_timely_data_head: Option<AssetId>,
        pub synthetic_timely_data: Map<AssetId, SyntheticTimelyData>,
        pub risk_factor_tiers: Map<AssetId, Vec<FixedTwoDecimal>>,
        asset_oracle: Map<AssetId, Map<PublicKey, felt252>>,
        max_oracle_price_validity: TimeDelta,
    }

    #[event]
    #[derive(Drop, PartialEq, starknet::Event)]
    pub enum Event {
        OracleAdded: events::OracleAdded,
        SyntheticAdded: events::SyntheticAdded,
        AssetActivated: events::AssetActivated,
        SyntheticAssetDeactivated: events::SyntheticAssetDeactivated,
        FundingTick: events::FundingTick,
        PriceTick: events::PriceTick,
        CollateralRegistered: events::CollateralRegistered,
        OracleRemoved: events::OracleRemoved,
        AssetQuorumUpdated: events::AssetQuorumUpdated,
    }

    #[embeddable_as(AssetsImpl)]
    impl Assets<
        TContractState,
        +HasComponent<TContractState>,
        +Drop<TContractState>,
        impl Roles: RolesComponent::HasComponent<TContractState>,
        impl Pause: PausableComponent::HasComponent<TContractState>,
        impl Nonce: NonceComponent::HasComponent<TContractState>,
        impl Deposits: Deposit::HasComponent<TContractState>,
        +AccessControlComponent::HasComponent<TContractState>,
        +SRC5Component::HasComponent<TContractState>,
    > of IAssets<ComponentState<TContractState>> {
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
            ref self: ComponentState<TContractState>,
            asset_id: AssetId,
            token_address: ContractAddress,
            quantum: u64,
        ) {
            // Validations:
            get_dep_component!(@self, Roles).only_app_governor();

            // An asset cannot be both collateral and synthetic.
            assert(self.synthetic_config.entry(asset_id).read().is_none(), ASSET_ALREADY_EXISTS);
            // We currently support only one collateral asset.
            assert(self.collateral_timely_data_head.read().is_none(), ASSET_ALREADY_EXISTS);

            assert(asset_id.is_non_zero(), INVALID_ZERO_ASSET_ID);
            assert(token_address.is_non_zero(), INVALID_ZERO_TOKEN_ADDRESS);
            assert(quantum.is_non_zero(), INVALID_ZERO_QUANTUM);

            // Execution:
            self._store_collateral(:asset_id, :token_address, :quantum);

            let mut deposits = get_dep_component_mut!(ref self, Deposits);
            deposits.register_token(asset_id: asset_id.into(), :token_address, :quantum);
        }

        /// Add oracle to a synthetic asset.
        ///
        /// Validations:
        /// - Only the app governor can call this function.
        /// - The 'oracle_public_key' does not exist in the Oracle map.
        /// - The size of 'oracle_name' is 40 bits.
        /// - The size of 'asset_name' is 128 bits.
        ///
        /// Execution:
        /// - Add a new entry to the Oracle map.
        fn add_oracle_to_asset(
            ref self: ComponentState<TContractState>,
            asset_id: AssetId,
            oracle_public_key: PublicKey,
            oracle_name: felt252,
            asset_name: felt252,
        ) {
            let roles = get_dep_component!(@self, Roles);
            roles.only_app_governor();

            let asset_config = self._get_synthetic_config(synthetic_id: asset_id);
            assert(asset_config.status != AssetStatus::DEACTIVATED, DEACTIVATED_ASSET);

            // Validate the oracle does not exist.
            let asset_oracle_entry = self.asset_oracle.entry(asset_id).entry(oracle_public_key);
            let asset_oracle_data = asset_oracle_entry.read();
            assert(asset_oracle_data.is_zero(), ORACLE_ALREADY_EXISTS);

            assert(oracle_public_key.is_non_zero(), INVALID_ZERO_PUBLIC_KEY);
            assert(asset_name.is_non_zero(), INVALID_ZERO_ASSET_NAME);
            assert(oracle_name.is_non_zero(), INVALID_ZERO_ORACLE_NAME);

            // Validate the size of the oracle name.
            if let Option::Some(oracle_name) = oracle_name.try_into() {
                assert(oracle_name < TWO_POW_40, ORACLE_NAME_TOO_LONG);
            } else {
                panic_with_felt252(ORACLE_NAME_TOO_LONG);
            }

            // Validate the size of the asset name.
            assert(asset_name.into() < TWO_POW_128, ASSET_NAME_TOO_LONG);

            // Add the oracle to the asset.
            let shifted_asset_name = TWO_POW_40.into() * asset_name;
            asset_oracle_entry.write(shifted_asset_name + oracle_name);
            self.emit(events::OracleAdded { asset_id, asset_name, oracle_public_key, oracle_name });
        }

        /// Add asset is called by the operator to add a new synthetic asset.
        ///
        /// Validations:
        /// - Only the app_governor can call this function.
        /// - The asset does not exists.
        /// - Each risk factor in risk_factor_tiers is less or equal to 100.
        /// - The quorum is greater than 0.
        ///
        /// Execution:
        /// - Add new entry to synthetic_config.
        ///     - Set the asset as in-active.
        /// - Add a new entry at the beginning of synthetic_timely_data
        ///     - Set the price to zero.
        ///     - Set the funding index to zero.
        ///     - Set the `last_price_update` to zero.
        ///
        /// Risk factor tiers example:
        /// - risk_factor_tiers = [1, 2, 3, 5, 10, 20, 40]
        /// - risk_factor_first_tier_boundary = 10,000
        /// - risk_factor_tier_size = 20,000
        /// which means:
        /// - 0 - 10,000 -> 1%
        /// - 10,000 - 30,000 -> 2%
        /// - 30,000 - 50,000 -> 3%
        /// - 50,000 - 70,000 -> 5%
        /// - 70,000 - 90,000 -> 10%
        /// - 90,000 - 110,000 -> 20%
        /// - 110,000+ -> 40%
        fn add_synthetic_asset(
            ref self: ComponentState<TContractState>,
            asset_id: AssetId,
            risk_factor_tiers: Span<u8>,
            risk_factor_first_tier_boundary: u128,
            risk_factor_tier_size: u128,
            quorum: u8,
            resolution: u64,
        ) {
            let roles = get_dep_component!(@self, Roles);
            roles.only_app_governor();
            assert(
                self.synthetic_config.entry(asset_id).read().is_none(), SYNTHETIC_ALREADY_EXISTS,
            );
            assert(self.collateral_config.entry(asset_id).read().is_none(), ASSET_ALREADY_EXISTS);
            assert(quorum.is_non_zero(), INVALID_ZERO_QUORUM);
            self
                .synthetic_config
                .entry(asset_id)
                .write(
                    Option::Some(
                        SyntheticConfig {
                            version: SYNTHETIC_VERSION,
                            // It'll be active in the next price tick.
                            status: AssetStatus::PENDING,
                            // It validates the range of the risk factor.
                            risk_factor_first_tier_boundary,
                            risk_factor_tier_size,
                            quorum,
                            resolution,
                        },
                    ),
                );

            self
                .synthetic_timely_data
                .entry(asset_id)
                .write(
                    SyntheticTimelyData {
                        version: SYNTHETIC_VERSION,
                        next: self.synthetic_timely_data_head.read(),
                        // These fields will be updated in the next price tick.
                        price: Zero::zero(),
                        last_price_update: Zero::zero(),
                        funding_index: Zero::zero(),
                    },
                );

            self.synthetic_timely_data_head.write(Option::Some(asset_id));
            for risk_factor in risk_factor_tiers {
                self
                    .risk_factor_tiers
                    .entry(asset_id)
                    .append()
                    .write(FixedTwoDecimalTrait::new(*risk_factor));
            };
            self
                .emit(
                    events::SyntheticAdded {
                        asset_id,
                        risk_factor_tiers,
                        risk_factor_first_tier_boundary,
                        risk_factor_tier_size,
                        resolution,
                        quorum,
                    },
                );
        }

        /// - Deactivate synthetic asset.
        ///
        /// Validations:
        /// - Only the app governor can call this function.
        /// - The asset is already exists and active.
        ///
        /// Execution:
        /// - Deactivate synthetic_config.
        ///     - Set the asset as active = false.
        /// - remove asset from `synthetic_timely_data` map
        /// - Decrement the number of active synthetic assets.
        ///
        /// When a synthetic asset is deactivated, it can no longer be traded or liquidated. It also
        /// stops receiving funding and price updates. Additionally, a deactivated asset cannot be
        /// reactivated.
        fn deactivate_synthetic(ref self: ComponentState<TContractState>, synthetic_id: AssetId) {
            let roles = get_dep_component!(@self, Roles);
            roles.only_app_governor();
            let mut config = self._get_synthetic_config(:synthetic_id);
            self._validate_synthetic_active(:synthetic_id);
            config.status = AssetStatus::DEACTIVATED;
            self.synthetic_config.entry(synthetic_id).write(Option::Some(config));
            self.num_of_active_synthetic_assets.sub_and_write(1);
            self.emit(events::SyntheticAssetDeactivated { asset_id: synthetic_id });
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
            ref self: ComponentState<TContractState>,
            operator_nonce: u64,
            funding_ticks: Span<FundingTick>,
        ) {
            // Validations:
            get_dep_component!(@self, Pause).assert_not_paused();
            get_dep_component!(@self, Roles).only_operator();
            let mut nonce = get_dep_component_mut!(ref self, Nonce);
            nonce.use_checked_nonce(nonce: operator_nonce);

            assert(
                funding_ticks.len() == self.get_num_of_active_synthetic_assets(),
                INVALID_FUNDING_TICK_LEN,
            );

            self._execute_funding_tick(:funding_ticks);
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
            ref self: ComponentState<TContractState>,
            operator_nonce: u64,
            asset_id: AssetId,
            price: u128,
            signed_prices: Span<SignedPrice>,
        ) {
            // Validations:
            get_dep_component!(@self, Pause).assert_not_paused();
            get_dep_component!(@self, Roles).only_operator();
            let mut nonce = get_dep_component_mut!(ref self, Nonce);
            nonce.use_checked_nonce(nonce: operator_nonce);

            self._validate_price_tick(:asset_id, :price, :signed_prices);

            let synthetic_config = self.get_synthetic_config(synthetic_id: asset_id);
            let converted_price = price.convert(resolution: synthetic_config.resolution);
            self._set_price(:asset_id, price: converted_price);
        }

        fn get_collateral_config(
            self: @ComponentState<TContractState>, collateral_id: AssetId,
        ) -> CollateralConfig {
            self._get_collateral_config(:collateral_id)
        }
        fn get_funding_validation_interval(self: @ComponentState<TContractState>) -> TimeDelta {
            self.max_funding_interval.read()
        }
        fn get_last_funding_tick(self: @ComponentState<TContractState>) -> Timestamp {
            self.last_funding_tick.read()
        }
        fn get_last_price_validation(self: @ComponentState<TContractState>) -> Timestamp {
            self.last_price_validation.read()
        }
        fn get_max_funding_rate(self: @ComponentState<TContractState>) -> u32 {
            self.max_funding_rate.read()
        }
        fn get_max_oracle_price_validity(self: @ComponentState<TContractState>) -> TimeDelta {
            self.max_oracle_price_validity.read()
        }
        fn get_num_of_active_synthetic_assets(self: @ComponentState<TContractState>) -> usize {
            self.num_of_active_synthetic_assets.read()
        }
        fn get_price_validation_interval(self: @ComponentState<TContractState>) -> TimeDelta {
            self.max_price_interval.read()
        }
        fn get_synthetic_config(
            self: @ComponentState<TContractState>, synthetic_id: AssetId,
        ) -> SyntheticConfig {
            self._get_synthetic_config(:synthetic_id)
        }
        fn get_synthetic_timely_data(
            self: @ComponentState<TContractState>, synthetic_id: AssetId,
        ) -> SyntheticTimelyData {
            self._get_synthetic_timely_data(:synthetic_id)
        }

        fn get_risk_factor_tiers(
            self: @ComponentState<TContractState>, asset_id: AssetId,
        ) -> Span<FixedTwoDecimal> {
            if (self.is_collateral(:asset_id)) {
                panic_with_felt252(NOT_SYNTHETIC)
            } else if (self.is_synthetic(:asset_id)) {
                let mut tiers = array![];
                let risk_factor_tiers = self.risk_factor_tiers.entry(asset_id);
                for i in 0..risk_factor_tiers.len() {
                    tiers.append(risk_factor_tiers.at(i).read());
                };
                tiers.span()
            } else {
                panic_with_felt252(ASSET_NOT_EXISTS)
            }
        }

        /// Remove oracle from asset.
        /// Validations:
        /// - Only the app governor can call this function.
        /// - The oracle exists.
        ///
        /// Execution:
        /// - Remove the oracle from the asset.
        /// - Emit `OracleRemoved` event.
        fn remove_oracle_from_asset(
            ref self: ComponentState<TContractState>,
            asset_id: AssetId,
            oracle_public_key: PublicKey,
        ) {
            let roles = get_dep_component!(@self, Roles);
            roles.only_app_governor();

            // Validate the oracle exists.
            let asset_oracle_entry = self.asset_oracle.entry(asset_id).entry(oracle_public_key);
            assert(asset_oracle_entry.read().is_non_zero(), ORACLE_NOT_EXISTS);
            asset_oracle_entry.write(Zero::zero());
            self.emit(events::OracleRemoved { asset_id, oracle_public_key });
        }

        /// Update synthetic quorum.
        ///
        /// Validations:
        /// - Only the app governor can call this function.
        /// - The asset is already exists and active.
        /// - The quorum is not the same as the current quorum.
        /// - The quorum is greater than 0.
        ///
        /// Execution:
        /// - Update the quorum.
        /// - Emit AssetQuorumUpdated event.
        fn update_synthetic_quorum(
            ref self: ComponentState<TContractState>, synthetic_id: AssetId, quorum: u8,
        ) {
            let roles = get_dep_component!(@self, Roles);
            roles.only_app_governor();
            let mut synthetic_config = self._get_synthetic_config(:synthetic_id);
            self._validate_synthetic_active(:synthetic_id);
            assert(quorum.is_non_zero(), INVALID_ZERO_QUORUM);
            let old_quorum = synthetic_config.quorum;
            assert(old_quorum != quorum, INVALID_SAME_QUORUM);
            synthetic_config.quorum = quorum;
            self.synthetic_config.entry(synthetic_id).write(Option::Some(synthetic_config));
            self
                .emit(
                    events::AssetQuorumUpdated {
                        asset_id: synthetic_id, new_quorum: quorum, old_quorum,
                    },
                );
        }
    }

    #[generate_trait]
    pub impl InternalImpl<
        TContractState, +HasComponent<TContractState>,
    > of InternalTrait<TContractState> {
        fn initialize(
            ref self: ComponentState<TContractState>,
            max_price_interval: TimeDelta,
            max_funding_interval: TimeDelta,
            max_funding_rate: u32,
            max_oracle_price_validity: TimeDelta,
        ) {
            // Checks that the component has not been initialized yet.
            assert(self.max_price_interval.read().is_zero(), ALREADY_INITIALIZED);
            assert(max_price_interval.is_non_zero(), ZERO_MAX_PRICE_INTERVAL);
            assert(max_funding_interval.is_non_zero(), ZERO_MAX_FUNDING_INTERVAL);
            assert(max_funding_rate.is_non_zero(), ZERO_MAX_FUNDING_RATE);
            assert(max_oracle_price_validity.is_non_zero(), ZERO_MAX_ORACLE_PRICE);
            self.max_price_interval.write(max_price_interval);
            self.max_funding_interval.write(max_funding_interval);
            self.max_funding_rate.write(max_funding_rate);
            self.max_oracle_price_validity.write(max_oracle_price_validity);
            self.last_funding_tick.write(Time::now());
            self.last_price_validation.write(Time::now());
        }


        fn store_collateral(
            ref self: ComponentState<TContractState>,
            asset_id: AssetId,
            token_address: ContractAddress,
            risk_factor: FixedTwoDecimal,
            quantum: u64,
            quorum: u8,
        ) {
            self
                .collateral_config
                .entry(asset_id)
                .write(
                    Option::Some(
                        CollateralConfig {
                            version: COLLATERAL_VERSION,
                            token_address,
                            status: AssetStatus::ACTIVE,
                            risk_factor: Zero::zero(),
                            quantum,
                            quorum,
                        },
                    ),
                );

            self
                .collateral_timely_data
                .entry(asset_id)
                .write(
                    CollateralTimelyData {
                        version: COLLATERAL_VERSION,
                        next: self.collateral_timely_data_head.read(),
                        price: One::one(),
                        last_price_update: Zero::zero(),
                    },
                );
            self.collateral_timely_data_head.write(Option::Some(asset_id));
            self.emit(events::CollateralRegistered { asset_id, token_address, quantum });
        }

        fn get_asset_price(self: @ComponentState<TContractState>, asset_id: AssetId) -> Price {
            if self.is_collateral(:asset_id) {
                self.get_collateral_price(collateral_id: asset_id)
            } else if self.is_synthetic(:asset_id) {
                self.get_synthetic_price(synthetic_id: asset_id)
            } else {
                panic_with_felt252(ASSET_NOT_EXISTS)
            }
        }

        fn get_collateral_price(
            self: @ComponentState<TContractState>, collateral_id: AssetId,
        ) -> Price {
            if self.is_collateral(asset_id: collateral_id) {
                self.collateral_timely_data.entry(collateral_id).price.read()
            } else {
                panic_with_felt252(NOT_COLLATERAL)
            }
        }

        fn get_synthetic_price(
            self: @ComponentState<TContractState>, synthetic_id: AssetId,
        ) -> Price {
            if self.is_synthetic(asset_id: synthetic_id) {
                self.synthetic_timely_data.entry(synthetic_id).price.read()
            } else {
                panic_with_felt252(NOT_SYNTHETIC)
            }
        }

        /// Get the risk factor of an asset.
        /// - If the asset is a collateral asset, return the risk factor (0).
        /// - If the asset is a synthetic asset, return the risk factor according to the tier
        /// corresponding to the synthetic value according to formula:
        ///   - synthetic_value = |price * balance|
        ///   - If the synthetic value is less than or equal to the first tier boundary, return the
        ///   first risk factor.
        ///   - index = (synthetic_value - risk_factor_first_tier_boundary) / risk_factor_tier_size
        ///   - risk_factor = risk_factor_tiers[index]
        ///   - If the index is out of bounds, return the last risk factor.
        /// - If the asset does not exist, panic.
        fn get_risk_factor(
            self: @ComponentState<TContractState>, asset_id: AssetId, balance: Balance,
        ) -> FixedTwoDecimal {
            if let Option::Some(collateral_config) = self.collateral_config.read(asset_id) {
                collateral_config.risk_factor
            } else if let Option::Some(synthetic_config) = self.synthetic_config.read(asset_id) {
                let price = self.get_synthetic_price(synthetic_id: asset_id);
                let synthetic_value: u128 = price.mul(rhs: balance).abs();
                let mut index = if synthetic_value <= synthetic_config
                    .risk_factor_first_tier_boundary {
                    0_u128
                } else {
                    let tier_size = synthetic_config.risk_factor_tier_size;
                    let first_tier_offset = synthetic_value
                        - synthetic_config.risk_factor_first_tier_boundary;
                    1_u128 + (first_tier_offset / tier_size)
                };
                let asset_risk_factor_tiers = self.risk_factor_tiers.entry(asset_id);
                index = min(index, asset_risk_factor_tiers.len().into() - 1);
                asset_risk_factor_tiers
                    .at(index.try_into().expect('INDEX_SHOULD_NEVER_OVERFLOW'))
                    .read()
            } else {
                panic_with_felt252(ASSET_NOT_EXISTS)
            }
        }

        fn get_funding_index(
            self: @ComponentState<TContractState>, synthetic_id: AssetId,
        ) -> FundingIndex {
            if self.is_synthetic(asset_id: synthetic_id) {
                self.synthetic_timely_data.entry(synthetic_id).funding_index.read()
            } else {
                panic_with_felt252(NOT_SYNTHETIC)
            }
        }

        /// The main collateral asset is the only collateral asset in the system.
        fn get_main_collateral_asset_id(self: @ComponentState<TContractState>) -> AssetId {
            self.collateral_timely_data_head.read().expect(COLLATERAL_NOT_EXISTS)
        }

        // The system has only the main collateral asset.
        fn is_collateral(self: @ComponentState<TContractState>, asset_id: AssetId) -> bool {
            self.collateral_config.read(asset_id).is_some()
        }

        fn is_synthetic(self: @ComponentState<TContractState>, asset_id: AssetId) -> bool {
            self.synthetic_config.read(asset_id).is_some()
        }

        fn validate_asset_active(self: @ComponentState<TContractState>, asset_id: AssetId) {
            let collateral_config = self.collateral_config.read(asset_id);
            let is_collateral_active = match collateral_config {
                Option::Some(config) => config.status == AssetStatus::ACTIVE,
                Option::None => false,
            };
            let synthetic_config = self.synthetic_config.read(asset_id);
            let is_synthetic_active = match synthetic_config {
                Option::Some(config) => config.status == AssetStatus::ACTIVE,
                Option::None => false,
            };
            assert(is_collateral_active || is_synthetic_active, ASSET_NOT_ACTIVE);
        }

        /// Validates assets integrity prerequisites:
        /// - Funding interval validation.
        /// - Prices validation.
        fn validate_assets_integrity(ref self: ComponentState<TContractState>) {
            let now = Time::now();
            // Funding validation.
            assert(
                now.sub(self.last_funding_tick.read()) < self.max_funding_interval.read(),
                FUNDING_EXPIRED,
            );
            // Price validation.
            self._validate_prices(:now);
        }

        fn validate_collateral_active(
            self: @ComponentState<TContractState>, collateral_id: AssetId,
        ) {
            assert(
                self._get_collateral_config(collateral_id).status == AssetStatus::ACTIVE,
                COLLATERAL_NOT_ACTIVE,
            );
        }

        fn validate_oracle_signature(
            self: @ComponentState<TContractState>, asset_id: AssetId, signed_price: SignedPrice,
        ) {
            let packed_asset_oracle = self
                .asset_oracle
                .entry(asset_id)
                .read(signed_price.signer_public_key);
            let packed_price_timestamp: felt252 = signed_price.price.into() * TWO_POW_32.into()
                + signed_price.timestamp.into();
            let msg_hash = core::pedersen::pedersen(packed_asset_oracle, packed_price_timestamp);
            validate_stark_signature(
                public_key: signed_price.signer_public_key,
                :msg_hash,
                signature: signed_price.signature,
            );
        }
    }

    #[generate_trait]
    impl PrivateImpl<
        TContractState, +HasComponent<TContractState>,
    > of PrivateTrait<TContractState> {
        fn _store_collateral(
            ref self: ComponentState<TContractState>,
            asset_id: AssetId,
            token_address: ContractAddress,
            quantum: u64,
        ) {
            self
                .collateral_config
                .entry(asset_id)
                .write(
                    Option::Some(
                        CollateralConfig {
                            version: COLLATERAL_VERSION,
                            token_address,
                            status: AssetStatus::ACTIVE,
                            risk_factor: Zero::zero(),
                            quantum,
                            quorum: Zero::zero(),
                        },
                    ),
                );

            self
                .collateral_timely_data
                .entry(asset_id)
                .write(
                    CollateralTimelyData {
                        version: COLLATERAL_VERSION,
                        next: self.collateral_timely_data_head.read(),
                        price: One::one(),
                        last_price_update: Zero::zero(),
                    },
                );
            self.collateral_timely_data_head.write(Option::Some(asset_id));
            self.emit(events::CollateralRegistered { asset_id, token_address, quantum });
        }

        fn _get_collateral_config(
            self: @ComponentState<TContractState>, collateral_id: AssetId,
        ) -> CollateralConfig {
            self.collateral_config.read(collateral_id).expect(COLLATERAL_NOT_EXISTS)
        }

        fn _get_synthetic_config(
            self: @ComponentState<TContractState>, synthetic_id: AssetId,
        ) -> SyntheticConfig {
            self.synthetic_config.read(synthetic_id).expect(SYNTHETIC_NOT_EXISTS)
        }

        fn _get_synthetic_timely_data(
            self: @ComponentState<TContractState>, synthetic_id: AssetId,
        ) -> SyntheticTimelyData {
            self._get_synthetic_config(:synthetic_id);
            self.synthetic_timely_data.read(synthetic_id)
        }

        fn _execute_funding_tick(
            ref self: ComponentState<TContractState>, funding_ticks: Span<FundingTick>,
        ) {
            let now = Time::now();
            let mut prev_synthetic_id: AssetId = Zero::zero();
            for funding_tick in funding_ticks {
                let synthetic_id = *funding_tick.asset_id;
                assert(synthetic_id > prev_synthetic_id, FUNDING_TICKS_NOT_SORTED);
                self._validate_synthetic_active(:synthetic_id);
                self
                    ._process_funding_tick(
                        :now, new_funding_index: *funding_tick.funding_index, :synthetic_id,
                    );
                prev_synthetic_id = synthetic_id;
            };
            self.last_funding_tick.write(now);
        }

        fn _process_funding_tick(
            ref self: ComponentState<TContractState>,
            now: Timestamp,
            new_funding_index: FundingIndex,
            synthetic_id: AssetId,
        ) {
            let last_funding_index = self.get_funding_index(:synthetic_id);
            let index_diff: i64 = (last_funding_index - new_funding_index).into();
            let last_funding_tick = self.last_funding_tick.read();
            let time_diff: u64 = (now.sub(other: last_funding_tick)).into();
            validate_funding_rate(
                :synthetic_id,
                index_diff: index_diff.abs(),
                max_funding_rate: self.max_funding_rate.read(),
                :time_diff,
                synthetic_price: self.get_synthetic_price(:synthetic_id),
            );
            self.synthetic_timely_data.entry(synthetic_id).funding_index.write(new_funding_index);
            self
                .emit(
                    events::FundingTick {
                        asset_id: synthetic_id, funding_index: new_funding_index,
                    },
                );
        }

        /// Validates a price tick.
        /// - The signed prices must be sorted by the public key.
        /// - The signed prices are signed by the oracles.
        /// - The number of signed prices (i.e. signing oracles) must not be smaller than the
        /// quorum.
        /// - The signed price time must not be in the future, and must not lag more than
        /// `max_oracle_price_validity`.
        /// - The `price` is the median of the signed_prices.
        fn _validate_price_tick(
            self: @ComponentState<TContractState>,
            asset_id: AssetId,
            price: u128,
            signed_prices: Span<SignedPrice>,
        ) {
            let asset_config = self._get_synthetic_config(synthetic_id: asset_id);
            assert(asset_config.status != AssetStatus::DEACTIVATED, DEACTIVATED_ASSET);
            assert(asset_config.quorum.into() <= signed_prices.len(), QUORUM_NOT_REACHED);

            let mut min_timestamp = MAX_U32;
            let mut lower_amount: usize = 0;
            let mut higher_amount: usize = 0;
            let mut equal_amount: usize = 0;

            let mut previous_public_key_opt: Option<PublicKey> = Option::None;
            for signed_price in signed_prices {
                if *signed_price.price < price {
                    lower_amount += 1;
                } else if *signed_price.price > price {
                    higher_amount += 1;
                } else {
                    equal_amount += 1;
                }

                min_timestamp = min(min_timestamp, (*signed_price).timestamp);
                self._validate_oracle_signature(:asset_id, signed_price: *signed_price);

                if let Option::Some(previous_public_key) = previous_public_key_opt {
                    let prev: u256 = previous_public_key.into();
                    let current: u256 = (*signed_price.signer_public_key).into();
                    assert(prev < current, SIGNED_PRICES_UNSORTED);
                }
                previous_public_key_opt = Option::Some((*signed_price.signer_public_key));
            };

            assert(2 * (lower_amount + equal_amount) >= signed_prices.len(), INVALID_MEDIAN);
            assert(2 * (higher_amount + equal_amount) >= signed_prices.len(), INVALID_MEDIAN);
            let now: u64 = Time::now().into();
            let max_oracle_price_validity = self.max_oracle_price_validity.read();
            let from = now - max_oracle_price_validity.into();
            // Add 2 minutes to allow timestamps that were signed after the block timestamp as the
            // timestamp is the open block timestamp and there could be a scenario where the oracle
            // signed the price after the block was opened and still got into the block.
            let to = now + 2 * MINUTE;
            assert(
                from <= min_timestamp.into() && min_timestamp.into() < to, INVALID_PRICE_TIMESTAMP,
            );
        }

        fn _set_price(ref self: ComponentState<TContractState>, asset_id: AssetId, price: Price) {
            let now = Time::now();
            let synthetic_timely_data = self.synthetic_timely_data.entry(asset_id);
            synthetic_timely_data.price.write(price);
            synthetic_timely_data.last_price_update.write(now);

            let synthetic_config = self._get_synthetic_config(synthetic_id: asset_id);
            // If the asset is not active, it'll be activated.
            if synthetic_config.status == AssetStatus::PENDING {
                // Activates the synthetic asset.
                self.num_of_active_synthetic_assets.add_and_write(1);
                self
                    .synthetic_config
                    .entry(asset_id)
                    .write(
                        Option::Some(
                            SyntheticConfig { status: AssetStatus::ACTIVE, ..synthetic_config },
                        ),
                    );
                self.emit(events::AssetActivated { asset_id });
            }
            self.emit(events::PriceTick { asset_id, price });
        }

        fn _validate_oracle_signature(
            self: @ComponentState<TContractState>, asset_id: AssetId, signed_price: SignedPrice,
        ) {
            let packed_asset_oracle = self
                .asset_oracle
                .entry(asset_id)
                .read(signed_price.signer_public_key);
            let packed_price_timestamp: felt252 = signed_price.price.into() * TWO_POW_32.into()
                + signed_price.timestamp.into();
            let msg_hash = core::pedersen::pedersen(packed_asset_oracle, packed_price_timestamp);
            validate_stark_signature(
                public_key: signed_price.signer_public_key,
                :msg_hash,
                signature: signed_price.signature,
            );
        }

        /// If `max_price_interval` has passed since `last_price_validation`, validate
        /// synthetic and collateral prices and update `last_price_validation` to current time.
        fn _validate_prices(ref self: ComponentState<TContractState>, now: Timestamp) {
            let max_price_interval = self.max_price_interval.read();
            if now.sub(self.last_price_validation.read()) >= max_price_interval {
                self._validate_synthetic_prices(now, max_price_interval);
                self.last_price_validation.write(now);
            }
        }

        fn _validate_synthetic_active(
            self: @ComponentState<TContractState>, synthetic_id: AssetId,
        ) {
            assert(
                self._get_synthetic_config(synthetic_id).status == AssetStatus::ACTIVE,
                SYNTHETIC_NOT_ACTIVE,
            );
        }

        fn _validate_synthetic_prices(
            self: @ComponentState<TContractState>, now: Timestamp, max_price_interval: TimeDelta,
        ) {
            let mut asset_id_opt = self.synthetic_timely_data_head.read();
            while let Option::Some(synthetic_id) = asset_id_opt {
                let synthetic_timely_data = self.synthetic_timely_data.read(synthetic_id);
                // Validate only active asset
                if self._get_synthetic_config(:synthetic_id).status == AssetStatus::ACTIVE {
                    assert(
                        now.sub(synthetic_timely_data.last_price_update) < max_price_interval,
                        SYNTHETIC_EXPIRED_PRICE,
                    );
                }
                asset_id_opt = synthetic_timely_data.next;
            };
        }
    }
}
