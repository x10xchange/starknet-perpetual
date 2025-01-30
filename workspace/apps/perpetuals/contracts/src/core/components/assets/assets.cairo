#[starknet::component]
pub(crate) mod AssetsComponent {
    use contracts_commons::errors::panic_with_felt;
    use contracts_commons::math::Abs;
    use contracts_commons::types::PublicKey;
    use contracts_commons::types::fixed_two_decimal::{FixedTwoDecimal, FixedTwoDecimalTrait};
    use contracts_commons::types::time::time::{Time, TimeDelta, Timestamp};
    use contracts_commons::utils::{AddToStorage, SubFromStorage};
    use core::num::traits::{One, Zero};
    use perpetuals::core::components::assets::errors::{
        ASSET_ALREADY_EXISTS, ASSET_NOT_ACTIVE, ASSET_NOT_EXISTS, COLLATERAL_NOT_ACTIVE,
        COLLATERAL_NOT_EXISTS, FUNDING_EXPIRED, FUNDING_TICKS_NOT_SORTED, INVALID_ZERO_QUORUM,
        NOT_COLLATERAL, NOT_SYNTHETIC, SYNTHETIC_EXPIRED_PRICE, SYNTHETIC_NOT_ACTIVE,
        SYNTHETIC_NOT_EXISTS,
    };
    use perpetuals::core::components::assets::events;
    use perpetuals::core::components::assets::interface::IAssets;
    use perpetuals::core::types::asset::AssetId;
    use perpetuals::core::types::asset::collateral::{
        CollateralConfig, CollateralTimelyData, VERSION as COLLATERAL_VERSION,
    };
    use perpetuals::core::types::asset::synthetic::{
        SyntheticConfig, SyntheticTimelyData, VERSION as SYNTHETIC_VERSION,
    };
    use perpetuals::core::types::funding::{FundingIndex, FundingTick, validate_funding_rate};
    use perpetuals::core::types::price::{Price, PriceTick};
    use starknet::ContractAddress;
    use starknet::storage::{
        Map, StorageMapReadAccess, StoragePathEntry, StoragePointerReadAccess,
        StoragePointerWriteAccess,
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
        pub oracels: Map<AssetId, Map<PublicKey, felt252>>,
        max_oracle_price_validity: TimeDelta,
    }

    #[event]
    #[derive(Drop, PartialEq, starknet::Event)]
    pub enum Event {
        FundingTick: events::FundingTick,
        PriceTick: events::PriceTick,
    }

    #[embeddable_as(AssetsImpl)]
    impl Assets<
        TContractState, +HasComponent<TContractState>, +Drop<TContractState>,
    > of IAssets<ComponentState<TContractState>> {
        fn get_price_validation_interval(self: @ComponentState<TContractState>) -> TimeDelta {
            self.max_price_interval.read()
        }
        fn get_funding_validation_interval(self: @ComponentState<TContractState>) -> TimeDelta {
            self.max_funding_interval.read()
        }
        fn get_max_funding_rate(self: @ComponentState<TContractState>) -> u32 {
            self.max_funding_rate.read()
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
            self.max_price_interval.write(max_price_interval);
            self.max_funding_interval.write(max_funding_interval);
            self.max_funding_rate.write(max_funding_rate);
            self.max_oracle_price_validity.write(max_oracle_price_validity);
        }


        fn add_collateral(
            ref self: ComponentState<TContractState>,
            asset_id: AssetId,
            token_address: ContractAddress,
            risk_factor: FixedTwoDecimal,
            quantum: u64,
            quorum: u8,
        ) {
            assert(self.collateral_config.entry(asset_id).read().is_none(), ASSET_ALREADY_EXISTS);

            self
                .collateral_config
                .entry(asset_id)
                .write(
                    Option::Some(
                        CollateralConfig {
                            version: COLLATERAL_VERSION,
                            token_address,
                            is_active: true,
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
        }


        fn add_synthetic_asset(
            ref self: ComponentState<TContractState>,
            asset_id: AssetId,
            name: felt252,
            risk_factor: u8,
            quorum: u8,
            resolution: u64,
        ) {
            assert(self.synthetic_config.entry(asset_id).read().is_none(), ASSET_ALREADY_EXISTS);
            assert(quorum.is_non_zero(), INVALID_ZERO_QUORUM);
            self
                .synthetic_config
                .entry(asset_id)
                .write(
                    Option::Some(
                        SyntheticConfig {
                            version: SYNTHETIC_VERSION,
                            name,
                            // It'll be active in the next price tick.
                            is_active: false,
                            // It validates the range of the risk factor.
                            risk_factor: FixedTwoDecimalTrait::new(risk_factor),
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
        }

        fn deactivate_synthetic(ref self: ComponentState<TContractState>, synthetic_id: AssetId) {
            let mut config = self._get_synthetic_config(:synthetic_id);
            self._validate_synthetic_active(:synthetic_id);
            config.is_active = false;
            self.synthetic_config.entry(synthetic_id).write(Option::Some(config));

            self.num_of_active_synthetic_assets.sub_and_write(1);
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
            let last_funding_index = self._get_funding_index(:synthetic_id);
            let index_diff: i64 = (last_funding_index - new_funding_index).into();
            let last_funding_tick = self.last_funding_tick.read();
            let time_diff: u64 = (now.sub(other: last_funding_tick)).into();
            validate_funding_rate(
                :synthetic_id,
                index_diff: index_diff.abs(),
                max_funding_rate: self.max_funding_rate.read(),
                :time_diff,
                synthetic_price: self._get_synthetic_price(:synthetic_id),
            );
            self.synthetic_timely_data.entry(synthetic_id).funding_index.write(new_funding_index);
            self
                .emit(
                    events::FundingTick {
                        asset_id: synthetic_id, funding_index: new_funding_index,
                    },
                );
        }


        fn set_price(ref self: ComponentState<TContractState>, asset_id: AssetId, price: Price) {
            let now = Time::now();
            let synthetic_timely_data = self.synthetic_timely_data.entry(asset_id);
            synthetic_timely_data.price.write(price);
            synthetic_timely_data.last_price_update.write(now);

            let synthetic_config = self._get_synthetic_config(asset_id);
            // If the asset is not active, it'll be activated.
            if !synthetic_config.is_active {
                // Activates the synthetic asset.
                self.num_of_active_synthetic_assets.add_and_write(1);
                self
                    .synthetic_config
                    .entry(asset_id)
                    .write(Option::Some(SyntheticConfig { is_active: true, ..synthetic_config }));
            }
        }

        /// TODO : Impl
        fn _validate_price_ticks(
            self: @ComponentState<TContractState>,
            asset_id: AssetId,
            price: Price,
            price_ticks: Span<PriceTick>,
        ) {}

        fn _get_asset_price(self: @ComponentState<TContractState>, asset_id: AssetId) -> Price {
            if self._is_collateral(:asset_id) {
                self._get_collateral_price(collateral_id: asset_id)
            } else if self._is_synthetic(:asset_id) {
                self._get_synthetic_price(synthetic_id: asset_id)
            } else {
                panic_with_felt(ASSET_NOT_EXISTS)
            }
        }

        fn _get_collateral_config(
            self: @ComponentState<TContractState>, collateral_id: AssetId,
        ) -> CollateralConfig {
            self.collateral_config.read(collateral_id).expect(COLLATERAL_NOT_EXISTS)
        }

        fn _get_collateral_price(
            self: @ComponentState<TContractState>, collateral_id: AssetId,
        ) -> Price {
            if self._is_collateral(asset_id: collateral_id) {
                self.collateral_timely_data.entry(collateral_id).price.read()
            } else {
                panic_with_felt(NOT_COLLATERAL)
            }
        }

        fn _get_num_of_active_synthetic_assets(self: @ComponentState<TContractState>) -> usize {
            self.num_of_active_synthetic_assets.read()
        }

        fn _get_synthetic_config(
            self: @ComponentState<TContractState>, synthetic_id: AssetId,
        ) -> SyntheticConfig {
            self.synthetic_config.read(synthetic_id).expect(SYNTHETIC_NOT_EXISTS)
        }

        fn _get_synthetic_price(
            self: @ComponentState<TContractState>, synthetic_id: AssetId,
        ) -> Price {
            if self._is_synthetic(asset_id: synthetic_id) {
                self.synthetic_timely_data.entry(synthetic_id).price.read()
            } else {
                panic_with_felt(NOT_SYNTHETIC)
            }
        }

        fn _get_risk_factor(
            self: @ComponentState<TContractState>, asset_id: AssetId,
        ) -> FixedTwoDecimal {
            if self._is_collateral(:asset_id) {
                self._get_collateral_config(collateral_id: asset_id).risk_factor
            } else if self._is_synthetic(:asset_id) {
                self._get_synthetic_config(synthetic_id: asset_id).risk_factor
            } else {
                panic_with_felt(ASSET_NOT_EXISTS)
            }
        }

        fn _get_funding_index(
            self: @ComponentState<TContractState>, synthetic_id: AssetId,
        ) -> FundingIndex {
            if self._is_synthetic(asset_id: synthetic_id) {
                self.synthetic_timely_data.entry(synthetic_id).funding_index.read()
            } else {
                panic_with_felt(NOT_SYNTHETIC)
            }
        }

        /// The main collateral asset is the only collateral asset in the system.
        fn _get_main_collateral_asset_id(self: @ComponentState<TContractState>) -> AssetId {
            self.collateral_timely_data_head.read().expect(COLLATERAL_NOT_EXISTS)
        }

        // The system has only the main collateral asset.
        fn _is_collateral(self: @ComponentState<TContractState>, asset_id: AssetId) -> bool {
            self.collateral_config.read(asset_id).is_some()
        }

        fn _is_synthetic(self: @ComponentState<TContractState>, asset_id: AssetId) -> bool {
            self.synthetic_config.read(asset_id).is_some()
        }

        fn _validate_asset_active(self: @ComponentState<TContractState>, asset_id: AssetId) {
            let collateral_config = self.collateral_config.read(asset_id);
            let is_collateral_active = match collateral_config {
                Option::Some(config) => config.is_active,
                Option::None => false,
            };
            let synthetic_config = self.synthetic_config.read(asset_id);
            let is_synthetic_active = match synthetic_config {
                Option::Some(config) => config.is_active,
                Option::None => false,
            };
            assert(is_collateral_active || is_synthetic_active, ASSET_NOT_ACTIVE);
        }

        /// Validates assets integrity prerequisites:
        /// - Funding interval validation.
        /// - Prices validation.
        fn _validate_assets_integrity(ref self: ComponentState<TContractState>) {
            let now = Time::now();
            // Funding validation.
            assert(
                now.sub(self.last_funding_tick.read()) < self.max_funding_interval.read(),
                FUNDING_EXPIRED,
            );
            // Price validation.
            self._validate_prices(:now);
        }

        fn _validate_collateral_active(
            self: @ComponentState<TContractState>, collateral_id: AssetId,
        ) {
            assert(self._get_collateral_config(collateral_id).is_active, COLLATERAL_NOT_ACTIVE);
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
            assert(self._get_synthetic_config(synthetic_id).is_active, SYNTHETIC_NOT_ACTIVE);
        }

        fn _validate_synthetic_prices(
            self: @ComponentState<TContractState>, now: Timestamp, max_price_interval: TimeDelta,
        ) {
            let mut asset_id_opt = self.synthetic_timely_data_head.read();
            while let Option::Some(asset_id) = asset_id_opt {
                let synthetic_timely_data = self.synthetic_timely_data.read(asset_id);
                // In case of a new asset, `last_price_update` is zero. Don't validate the price
                // since it has not been set yet.
                if synthetic_timely_data.last_price_update != Zero::zero() {
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
