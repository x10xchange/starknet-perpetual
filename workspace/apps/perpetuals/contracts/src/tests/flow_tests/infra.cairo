use core::cmp::min;
use perpetuals::core::types::position::PositionId;
use perpetuals::tests::flow_tests::perps_tests_facade::*;
use starkware_utils::math::abs::Abs;
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
pub struct FlowTestExtended {
    pub perpetual_contract: FlowTestBase,
    pub synthetics: Span<SyntheticInfo>,
    pub fee_percentage: u8,
}

pub const BTC_ASSET: u32 = 0;
pub const ETH_ASSET: u32 = 1;

#[generate_trait]
impl FlowTestImpl of FlowTestExtendedTrait {
    fn new(fee_percentage: u8) -> FlowTestExtended {
        let risk_factor_tiers = RiskFactorTiers {
            tiers: array![10, 20, 50].span(), first_tier_boundary: 10_000, tier_size: 1000,
        };
        let synthetics = array![
            SyntheticInfoTrait::new(
                asset_name: 'BTC', risk_factor_data: risk_factor_tiers, oracles_len: 1,
            ),
            SyntheticInfoTrait::new(
                asset_name: 'ETH', risk_factor_data: risk_factor_tiers, oracles_len: 1,
            ),
        ]
            .span();

        FlowTestExtended {
            perpetual_contract: FlowTestBaseTrait::new(), synthetics, fee_percentage,
        }
    }

    fn new_user(ref self: FlowTestExtended) -> User {
        self.perpetual_contract.new_user_with_position()
    }

    fn deposit(ref self: FlowTestExtended, user: User, amount: u64) -> DepositInfo {
        self
            .perpetual_contract
            .facade
            .deposit(
                depositor: user.account, position_id: user.position_id, quantized_amount: amount,
            )
    }
    fn process_deposit(ref self: FlowTestExtended, deposit_info: DepositInfo) {
        self.perpetual_contract.facade.process_deposit(:deposit_info)
    }
    fn cancel_deposit(ref self: FlowTestExtended, deposit_info: DepositInfo) {
        self.perpetual_contract.facade.cancel_deposit(:deposit_info)
    }
    fn withdraw_request(ref self: FlowTestExtended, user: User, amount: u64) -> RequestInfo {
        self.perpetual_contract.facade.withdraw_request(:user, :amount)
    }
    fn withdraw(ref self: FlowTestExtended, withdraw_info: RequestInfo) {
        self.perpetual_contract.facade.withdraw(:withdraw_info)
    }
    fn transfer_request(
        ref self: FlowTestExtended, sender: User, recipient: User, amount: u64,
    ) -> RequestInfo {
        self.perpetual_contract.facade.transfer_request(:sender, :recipient, :amount)
    }

    fn create_order_request(
        ref self: FlowTestExtended, user: User, base: i64, asset: u32, quote: i64,
    ) -> OrderRequest {
        let synthetic_info = self.synthetics.get(asset).unwrap();
        let order_info = self
            .perpetual_contract
            .facade
            .create_order(
                :user,
                base_amount: base.into(),
                base_asset_id: synthetic_info.asset_id,
                quote_amount: -quote.into(),
                fee_amount: ((quote * self.fee_percentage.into()) / 100).abs(),
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

        let fee_a = ((quote * self.fee_percentage.into()) / 100).abs();
        let fee_b = ((quote * self.fee_percentage.into()) / 100).abs();

        self
            .perpetual_contract
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
    fn liquidate(ref self: FlowTestExtended, user: User, liquidator_order: OrderInfo) {}
    fn deleverage(ref self: FlowTestExtended, deleveraged_user: User, deleverager: User) {}
}

#[derive(Drop)]
pub struct OrderRequest {
    pub order_info: OrderInfo,
    pub actual_base: u64,
}
