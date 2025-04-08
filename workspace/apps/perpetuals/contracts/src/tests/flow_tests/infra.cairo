use core::cmp::min;
use core::num::traits::{Pow, Zero};
use perpetuals::core::types::balance::Balance;
use perpetuals::core::types::funding::FundingTick;
use perpetuals::core::types::position::PositionId;
use perpetuals::tests::flow_tests::perps_tests_facade::*;
use starkware_utils::constants::HOUR;
use starkware_utils::math::abs::Abs;
use crate::core::types::funding::{FUNDING_SCALE, FundingIndex};
use crate::core::types::price::PriceMulTrait;
use crate::tests::test_utils::create_token_state;


#[derive(Drop)]
pub struct FlowTestBase {
    pub facade: PerpsTestsFacade,
    position_id_gen: u32,
    key_gen: felt252,
}

#[generate_trait]
impl PrivateFlowTestBaseImpl of PrivateFlowTestBaseTrait {
    fn generate_position_id(ref self: FlowTestBase) -> PositionId {
        self.position_id_gen += 1;
        PositionId { value: self.position_id_gen }
    }

    fn generate_key(ref self: FlowTestBase) -> felt252 {
        self.key_gen += 1;
        self.key_gen
    }
}

#[generate_trait]
pub impl FlowTestBaseImpl of FlowTestBaseTrait {
    fn new() -> FlowTestBase {
        FlowTestBase {
            facade: PerpsTestsFacadeTrait::new(create_token_state()),
            position_id_gen: 100,
            key_gen: 0,
        }
    }

    fn new_user_with_position(ref self: FlowTestBase) -> User {
        let user = UserTrait::new(
            self.facade.token_state,
            secret_key: self.generate_key(),
            position_id: self.generate_position_id(),
        );
        self
            .facade
            .new_position(
                position_id: user.position_id,
                owner_public_key: user.account.key_pair.public_key,
                owner_account: user.account.address,
            );
        user
    }
}

#[derive(Drop)]
pub struct OrderRequest {
    pub order_info: OrderInfo,
    pub actual_base: u64,
}

#[derive(Drop)]
pub struct FlowTestExtended {
    pub flow_test_base: FlowTestBase,
    pub synthetics: Span<SyntheticInfo>,
    pub fee_percentage: u8,
}

pub const BTC_ASSET: u32 = 0;
pub const ETH_ASSET: u32 = 1;
pub const STRK_ASSET: u32 = 2;
pub const SOL_ASSET: u32 = 3;
pub const DOGE_ASSET: u32 = 4;
pub const PEPE_ASSET: u32 = 5;
pub const ETC_ASSET: u32 = 6;
pub const TAO_ASSET: u32 = 7;
pub const XRP_ASSET: u32 = 8;
pub const ADA_ASSET: u32 = 9;

#[generate_trait]
pub impl FlowTestImpl of FlowTestExtendedTrait {
    fn new(fee_percentage: u8) -> FlowTestExtended {
        let risk_factor_tiers = RiskFactorTiers {
            tiers: array![10, 20, 50].span(), first_tier_boundary: 10_000, tier_size: 1000,
        };
        let synthetics = array![
            SyntheticInfoTrait::new(
                asset_name: 'BTC', risk_factor_data: risk_factor_tiers, oracles_len: 1, asset_id: 1,
            ),
            SyntheticInfoTrait::new(
                asset_name: 'ETH', risk_factor_data: risk_factor_tiers, oracles_len: 1, asset_id: 2,
            ),
            SyntheticInfoTrait::new(
                asset_name: 'STRK',
                risk_factor_data: risk_factor_tiers,
                oracles_len: 1,
                asset_id: 3,
            ),
            SyntheticInfoTrait::new(
                asset_name: 'SOL', risk_factor_data: risk_factor_tiers, oracles_len: 1, asset_id: 4,
            ),
            SyntheticInfoTrait::new(
                asset_name: 'SOL', risk_factor_data: risk_factor_tiers, oracles_len: 1, asset_id: 5,
            ),
            SyntheticInfoTrait::new(
                asset_name: 'SOL', risk_factor_data: risk_factor_tiers, oracles_len: 1, asset_id: 6,
            ),
            SyntheticInfoTrait::new(
                asset_name: 'SOL', risk_factor_data: risk_factor_tiers, oracles_len: 1, asset_id: 7,
            ),
            SyntheticInfoTrait::new(
                asset_name: 'SOL', risk_factor_data: risk_factor_tiers, oracles_len: 1, asset_id: 8,
            ),
            SyntheticInfoTrait::new(
                asset_name: 'SOL', risk_factor_data: risk_factor_tiers, oracles_len: 1, asset_id: 9,
            ),
            SyntheticInfoTrait::new(
                asset_name: 'SOL',
                risk_factor_data: risk_factor_tiers,
                oracles_len: 1,
                asset_id: 10,
            ),
        ]
            .span();

        let mut flow_test_base = FlowTestBaseTrait::new();

        let mut initial_price = 2_u128.pow(10);
        for synthetic_info in synthetics {
            flow_test_base.facade.add_active_synthetic(:synthetic_info, :initial_price);
            initial_price /= 2;
        }

        FlowTestExtended { flow_test_base, synthetics, fee_percentage }
    }

    fn new_user(ref self: FlowTestExtended) -> User {
        self.flow_test_base.new_user_with_position()
    }

    fn deposit(ref self: FlowTestExtended, user: User, amount: u64) -> DepositInfo {
        self
            .flow_test_base
            .facade
            .deposit(
                depositor: user.account, position_id: user.position_id, quantized_amount: amount,
            )
    }
    fn process_deposit(ref self: FlowTestExtended, deposit_info: DepositInfo) {
        self.flow_test_base.facade.process_deposit(:deposit_info)
    }
    fn cancel_deposit(ref self: FlowTestExtended, deposit_info: DepositInfo) {
        self.flow_test_base.facade.cancel_deposit(:deposit_info)
    }
    fn withdraw_request(ref self: FlowTestExtended, user: User, amount: u64) -> RequestInfo {
        self.flow_test_base.facade.withdraw_request(:user, :amount)
    }
    fn withdraw(ref self: FlowTestExtended, withdraw_info: RequestInfo) {
        self.flow_test_base.facade.withdraw(:withdraw_info)
    }
    fn transfer_request(
        ref self: FlowTestExtended, sender: User, recipient: User, amount: u64,
    ) -> RequestInfo {
        self.flow_test_base.facade.transfer_request(:sender, :recipient, :amount)
    }
    fn deactivate_synthetic(ref self: FlowTestExtended, asset_index: u32) {
        let synthetic_info = self.synthetics.at(asset_index);
        self.flow_test_base.facade.deactivate_synthetic(synthetic_id: *synthetic_info.asset_id);
    }

    fn hourly_funding_tick(ref self: FlowTestExtended, funding_indexes: Span<(u32, i64)>) {
        advance_time(HOUR);
        let mut funding_ticks = array![];
        let mut current_asset_index = BTC_ASSET;
        for (asset_index, funding_index) in funding_indexes {
            let asset_id = *self.synthetics.at(current_asset_index).asset_id;
            if *asset_index == current_asset_index {
                let funding_index = FundingIndex { value: *funding_index * FUNDING_SCALE };
                funding_ticks.append(FundingTick { asset_id, funding_index });
                current_asset_index += 1;
            } else {
                while (current_asset_index < *asset_index) {
                    let asset_id = *self.synthetics.at(current_asset_index).asset_id;
                    funding_ticks.append(FundingTick { asset_id, funding_index: Zero::zero() });
                    current_asset_index += 1;
                }
            };
        }
        while (current_asset_index < self.synthetics.len()) {
            let asset_id = *self.synthetics.at(current_asset_index).asset_id;
            funding_ticks.append(FundingTick { asset_id, funding_index: Zero::zero() });
            current_asset_index += 1;
        }

        self.flow_test_base.facade.funding_tick(funding_ticks: funding_ticks.span());
    }

    fn price_tick(ref self: FlowTestExtended, prices: Span<(u32, u128)>) {
        for (asset_index, price) in prices {
            let synthetic_info = self.synthetics.at(*asset_index);
            self.flow_test_base.facade.price_tick(synthetic_info, price: *price);
        }
    }

    fn create_order_request(
        ref self: FlowTestExtended, user: User, asset_index: u32, base: i64,
    ) -> OrderRequest {
        let synthetic_info = self.synthetics.get(asset_index).unwrap();
        let synthetic_price = self
            .flow_test_base
            .facade
            .get_synthetic_price(synthetic_id: synthetic_info.asset_id);
        let quote: i64 = PriceMulTrait::<Balance>::mul(@synthetic_price, -base.into())
            .try_into()
            .expect('Value should not overflow');
        let order_info = self
            .flow_test_base
            .facade
            .create_order(
                :user,
                base_amount: base.into(),
                base_asset_id: synthetic_info.asset_id,
                quote_amount: quote,
                fee_amount: ((quote * self.fee_percentage.into()) / 100).abs().into(),
            );
        OrderRequest { order_info, actual_base: base.abs() }
    }

    fn trade(
        ref self: FlowTestExtended, order_a: OrderRequest, order_b: OrderRequest,
    ) -> (OrderRequest, OrderRequest) {
        let (mut buy, mut sell) = if order_a.order_info.order.base_amount > 0 {
            (order_a, order_b)
        } else {
            (order_b, order_a)
        };
        let base = min(buy.actual_base, sell.actual_base)
            .try_into()
            .expect('Value should not overflow');
        let quote = base * buy.order_info.order.quote_amount / buy.order_info.order.base_amount;

        let fee_a = quote.abs()
            * buy.order_info.order.fee_amount
            / buy.order_info.order.quote_amount.abs();

        let fee_b = quote.abs()
            * sell.order_info.order.fee_amount
            / sell.order_info.order.quote_amount.abs();

        self
            .flow_test_base
            .facade
            .trade(
                order_info_a: buy.order_info,
                order_info_b: sell.order_info,
                base: base,
                quote: quote,
                :fee_a,
                :fee_b,
            );
        buy.actual_base -= base.abs();
        sell.actual_base -= base.abs();
        (buy, sell)
    }

    fn liquidate(
        ref self: FlowTestExtended, liquidated_user: User, mut liquidator_order: OrderRequest,
    ) -> OrderRequest {
        let synthetic_id = liquidator_order.order_info.order.base_asset_id;
        let synthetic_balance: i64 = self
            .flow_test_base
            .facade
            .get_position_synthetic_balance(position_id: liquidated_user.position_id, :synthetic_id)
            .into();

        let base = min(synthetic_balance.abs(), liquidator_order.actual_base);

        let quote = base
            * liquidator_order.order_info.order.quote_amount.abs()
            / liquidator_order.order_info.order.base_amount.abs();

        let (liquidated_base, liquidated_quote) = if liquidator_order
            .order_info
            .order
            .base_amount > 0 {
            (
                -base.try_into().expect('Value should not overflow'),
                quote.try_into().expect('Value should not overflow'),
            )
        } else {
            (
                base.try_into().expect('Value should not overflow'),
                -quote.try_into().expect('Value should not overflow'),
            )
        };

        let liquidator_fee = ((quote * self.fee_percentage.into()) / 100);
        let liquidated_insurance_fee = ((quote * self.fee_percentage.into()) / 100);

        self
            .flow_test_base
            .facade
            .liquidate(
                :liquidated_user,
                liquidator_order: liquidator_order.order_info,
                :liquidated_base,
                :liquidated_quote,
                :liquidated_insurance_fee,
                :liquidator_fee,
            );

        liquidator_order.actual_base -= base;

        liquidator_order
    }

    fn deleverage(
        ref self: FlowTestExtended,
        deleveraged_user: User,
        deleverager_user: User,
        asset_index: u32,
        deleveraged_base: i64,
        deleveraged_quote: i64,
    ) {
        let synthetic_info = self.synthetics.at(asset_index);
        self
            .flow_test_base
            .facade
            .deleverage(
                :deleveraged_user,
                :deleverager_user,
                base_asset_id: *synthetic_info.asset_id,
                :deleveraged_base,
                :deleveraged_quote,
            );
    }

    fn reduce_inactive_asset_position(
        ref self: FlowTestExtended, asset_index: u32, user_a: User, user_b: User,
    ) {
        let synthetic_info = self.synthetics.at(asset_index);
        let balance_a: i64 = self
            .flow_test_base
            .facade
            .get_position_synthetic_balance(
                position_id: user_a.position_id, synthetic_id: *synthetic_info.asset_id,
            )
            .into();

        let balance_b: i64 = self
            .flow_test_base
            .facade
            .get_position_synthetic_balance(
                position_id: user_b.position_id, synthetic_id: *synthetic_info.asset_id,
            )
            .into();

        let base_amount_a = min(balance_a.abs(), balance_b.abs());
        let base_amount_a = if balance_a > 0 {
            base_amount_a.try_into().expect('Value should not overflow')
        } else {
            -base_amount_a.try_into().expect('Value should not overflow')
        };

        self
            .flow_test_base
            .facade
            .reduce_inactive_asset_position(
                position_id_a: user_a.position_id,
                position_id_b: user_b.position_id,
                base_asset_id: *synthetic_info.asset_id,
                :base_amount_a,
            );
    }
}

#[generate_trait]
pub impl FlowTestValidationsImpl of FlowTestExtendedValidationsTrait {
    fn validate_total_value(self: @FlowTestExtended, user: User, expected_total_value: i128) {
        self
            .flow_test_base
            .facade
            .validate_total_value(
                position_id: user.position_id, expected_total_value: expected_total_value,
            );
    }

    fn validate_total_risk(self: @FlowTestExtended, user: User, expected_total_risk: u128) {
        self
            .flow_test_base
            .facade
            .validate_total_risk(
                position_id: user.position_id, expected_total_risk: expected_total_risk,
            );
    }
}
