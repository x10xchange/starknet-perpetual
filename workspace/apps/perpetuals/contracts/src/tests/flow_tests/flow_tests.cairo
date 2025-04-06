use perpetuals::tests::flow_tests::infra::*;

#[test]
fn two_users_two_synthetics() {
    /// This test is for demonstration purposes only. It will be changed to a more
    /// realistic test in the future.

    let mut test = FlowTestExtendedTrait::new(1);
    let user_a = test.new_user();
    let user_b = test.new_user();

    test.process_deposit(test.deposit(user_a, 10000));
    test.process_deposit(test.deposit(user_b, 10000));

    let buy_order_a = test.create_order_request(user: user_a, asset_index: BTC_ASSET, base: 1);
    let sell_order_b = test.create_order_request(user: user_b, asset_index: BTC_ASSET, base: -1);
    test.trade(buy_order_a, sell_order_b);

    test.validate_total_value(user_a, 9990);
    test.validate_total_risk(user_a, 102);
    test.validate_total_value(user_b, 9990);
    test.validate_total_risk(user_b, 102);

    test.hourly_funding_tick(array![(BTC_ASSET, 1)].span());
}
