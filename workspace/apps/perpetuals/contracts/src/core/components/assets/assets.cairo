#[starknet::component]
pub(crate) mod AssetsComponent {
    use contracts_commons::errors::{assert_with_byte_array, panic_with_felt};
    use contracts_commons::math::Abs;
    use contracts_commons::types::time::time::{Time, TimeDelta, Timestamp};
    use core::num::traits::Zero;
    use perpetuals::core::components::assets::errors::{
        ASSET_NOT_EXISTS, BASE_ASSET_NOT_ACTIVE, COLLATERAL_EXPIRED_PRICE, COLLATERAL_NOT_ACTIVE,
        COLLATERAL_NOT_EXISTS, FUNDING_EXPIRED, SYNTHETIC_EXPIRED_PRICE, SYNTHETIC_NOT_ACTIVE,
        SYNTHETIC_NOT_EXISTS, invalid_funding_tick_err,
    };
    use perpetuals::core::components::assets::interface::IAssets;
    use perpetuals::core::types::asset::AssetId;
    use perpetuals::core::types::asset::collateral::{CollateralConfig, CollateralTimelyData};
    use perpetuals::core::types::asset::synthetic::{SyntheticConfig, SyntheticTimelyData};
    use perpetuals::core::types::funding::{FundingIndex, FundingTick, funding_rate_calc};
    use perpetuals::core::types::price::Price;
    use starknet::storage::{
        Map, StorageMapReadAccess, StoragePathEntry, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };


    #[storage]
    pub struct Storage {
        /// 32-bit fixed-point number with a 32-bit fractional part.
        max_funding_rate: u32,
        price_validation_interval: TimeDelta,
        funding_validation_interval: TimeDelta,
        // Updates each price validation.
        pub last_price_validation: Timestamp,
        // Updates every funding tick.
        pub last_funding_tick: Timestamp,
        pub collateral_configs: Map<AssetId, Option<CollateralConfig>>,
        pub synthetic_configs: Map<AssetId, Option<SyntheticConfig>>,
        pub collateral_timely_data_head: Option<AssetId>,
        pub collateral_timely_data: Map<AssetId, CollateralTimelyData>,
        num_of_active_synthetic_assets: usize,
        pub synthetic_timely_data_head: Option<AssetId>,
        pub synthetic_timely_data: Map<AssetId, SyntheticTimelyData>,
    }

    #[event]
    #[derive(Drop, PartialEq, starknet::Event)]
    pub enum Event {}

    #[embeddable_as(AssetsImpl)]
    impl Assets<
        TContractState, +HasComponent<TContractState>, +Drop<TContractState>,
    > of IAssets<ComponentState<TContractState>> {
        fn get_price_validation_interval(self: @ComponentState<TContractState>) -> TimeDelta {
            self.price_validation_interval.read()
        }
        fn get_funding_validation_interval(self: @ComponentState<TContractState>) -> TimeDelta {
            self.funding_validation_interval.read()
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
            price_validation_interval: TimeDelta,
            funding_validation_interval: TimeDelta,
            max_funding_rate: u32,
        ) {
            self.price_validation_interval.write(price_validation_interval);
            self.funding_validation_interval.write(funding_validation_interval);
            self.max_funding_rate.write(max_funding_rate);
        }

        fn _execute_funding_tick(
            ref self: ComponentState<TContractState>, funding_ticks: Span<FundingTick>,
        ) {
            let now = Time::now();
            let mut prev_synthetic_id: AssetId = Zero::zero();
            for funding_tick in funding_ticks {
                let synthetic_id = *funding_tick.asset_id;
                assert_with_byte_array(
                    condition: synthetic_id > prev_synthetic_id,
                    err: invalid_funding_tick_err(:synthetic_id),
                );
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
            let synthetic_timely_data = self.synthetic_timely_data.entry(synthetic_id);
            let index_diff: i64 = (synthetic_timely_data.funding_index.read() - new_funding_index)
                .into();
            let last_funding_tick = self.last_funding_tick.read();
            let time_diff: u64 = (now.sub(other: last_funding_tick)).into();
            assert_with_byte_array(
                condition: index_diff
                    .abs()
                    .into() <= funding_rate_calc(
                        max_funding_rate: self.max_funding_rate.read(),
                        :time_diff,
                        synthetic_price: synthetic_timely_data.price.read(),
                    ),
                err: invalid_funding_tick_err(:synthetic_id),
            );
            synthetic_timely_data.funding_index.write(new_funding_index);
        }

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
            self.collateral_configs.read(collateral_id).expect(COLLATERAL_NOT_EXISTS)
        }

        fn _get_collateral_price(
            self: @ComponentState<TContractState>, collateral_id: AssetId,
        ) -> Price {
            self.collateral_timely_data.entry(collateral_id).price.read()
        }

        fn _get_num_of_active_synthetic_assets(self: @ComponentState<TContractState>) -> usize {
            self.num_of_active_synthetic_assets.read()
        }

        fn _get_synthetic_config(
            self: @ComponentState<TContractState>, synthetic_id: AssetId,
        ) -> SyntheticConfig {
            self.synthetic_configs.read(synthetic_id).expect(SYNTHETIC_NOT_EXISTS)
        }

        fn _get_synthetic_price(
            self: @ComponentState<TContractState>, synthetic_id: AssetId,
        ) -> Price {
            self.synthetic_timely_data.entry(synthetic_id).price.read()
        }

        fn _is_main_collateral(self: @ComponentState<TContractState>, asset_id: AssetId) -> bool {
            if let Option::Some(main_collateral) = self.collateral_timely_data_head.read() {
                return main_collateral == asset_id;
            }
            false
        }

        fn _get_main_collateral_asset_id(self: @ComponentState<TContractState>) -> AssetId {
            self.collateral_timely_data_head.read().expect(COLLATERAL_NOT_EXISTS)
        }


        fn _is_collateral(self: @ComponentState<TContractState>, asset_id: AssetId) -> bool {
            self.collateral_configs.read(asset_id).is_some()
        }

        fn _is_synthetic(self: @ComponentState<TContractState>, asset_id: AssetId) -> bool {
            self.synthetic_configs.read(asset_id).is_some()
        }

        fn _validate_asset_active(self: @ComponentState<TContractState>, asset_id: AssetId) {
            let base_collateral_config = self.collateral_configs.read(asset_id);
            let is_base_collateral_active = match base_collateral_config {
                Option::Some(config) => config.is_active,
                Option::None => false,
            };
            let base_synthetic_config = self.synthetic_configs.read(asset_id);
            let is_base_synthetic_active = match base_synthetic_config {
                Option::Some(config) => config.is_active,
                Option::None => false,
            };
            assert(is_base_collateral_active || is_base_synthetic_active, BASE_ASSET_NOT_ACTIVE);
        }

        /// Validates assets integrity prerequisites:
        /// - Funding interval validation.
        /// - Prices validation.
        fn _validate_assets_integrity(ref self: ComponentState<TContractState>, now: Timestamp) {
            // Funding validation.
            assert(
                now.sub(self.last_funding_tick.read()) < self.funding_validation_interval.read(),
                FUNDING_EXPIRED,
            );
            // Price validation.
            self._validate_prices(:now);
        }

        fn _validate_collateral_active(
            self: @ComponentState<TContractState>, collateral_id: AssetId,
        ) -> CollateralConfig {
            let cfg = self._get_collateral_config(collateral_id);
            assert(cfg.is_active, COLLATERAL_NOT_ACTIVE);
            cfg
        }

        fn _validate_collateral_prices(
            self: @ComponentState<TContractState>,
            now: Timestamp,
            price_validation_interval: TimeDelta,
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

        /// If `price_validation_interval` has passed since `last_price_validation`, validate
        /// synthetic and collateral prices and update `last_price_validation` to current time.
        fn _validate_prices(ref self: ComponentState<TContractState>, now: Timestamp) {
            let price_validation_interval = self.price_validation_interval.read();
            if now.sub(self.last_price_validation.read()) >= price_validation_interval {
                self._validate_synthetic_prices(now, price_validation_interval);
                self._validate_collateral_prices(now, price_validation_interval);
                self.last_price_validation.write(now);
            }
        }

        fn _validate_synthetic_active(
            self: @ComponentState<TContractState>, synthetic_id: AssetId,
        ) {
            assert(self._get_synthetic_config(synthetic_id).is_active, SYNTHETIC_NOT_ACTIVE);
        }

        fn _validate_synthetic_prices(
            self: @ComponentState<TContractState>,
            now: Timestamp,
            price_validation_interval: TimeDelta,
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
    }
}
