use perpetuals::tests::flow_tests::infra::*;

#[test]
fn two_users_two_synthetics() {
    /// Link to spreadsheet with calculations:
    /// https://docs.google.com/spreadsheets/d/1BIJ6Oq7hAsF-Vb6EJSQFYbCQJMyrncuWDC4NoKLiV1U/edit?gid=0#gid=0

    let mut test = FlowTestExtendedTrait::new(fee_percentage: 1);
    let user_a = test.new_user();
    let user_b = test.new_user();

    test.process_deposit(test.deposit(user_a, 10_000));
    test.process_deposit(test.deposit(user_b, 10_000));

    let sell_eth_a = test.create_order_request(user: user_a, asset_index: ETH_ASSET, base: -10);
    let buy_eth_b = test.create_order_request(user: user_b, asset_index: ETH_ASSET, base: 200);
    let (buy_eth_b, _) = test.trade(buy_eth_b, sell_eth_a);

    let buy_btc_a = test.create_order_request(user: user_a, asset_index: BTC_ASSET, base: 1);
    let sell_btc_b = test.create_order_request(user: user_b, asset_index: BTC_ASSET, base: -2);
    let (_, sell_btc_b) = test.trade(buy_btc_a, sell_btc_b);
    let sell_eth_a = test.create_order_request(user: user_a, asset_index: ETH_ASSET, base: -10);

    ////                collateral (1st fee   2nd fee)   |    BTC    |    ETH
    ///                   14_035   (  -51       -10  )   |  1*1024   |  -10*512    = 9_939
    test.validate_total_value(user_a, 9_939);

    ////                 BTC       |     ETH
    ///               1*1024*0.1   |  10*512*0.1 = 614
    test.validate_total_risk(user_a, 614);

    ////                collateral  (1st fee   2nd fee)   |    BTC    |    ETH
    ///                   5_843    (  -51       -10  )    |  -1*1024   |  10*512   = 9_939
    test.validate_total_value(user_b, 9_939);

    ////                 BTC       |     ETH
    ///               1*1024*0.1   |  10*512*0.1 = 614
    test.validate_total_risk(user_b, 614);

    test.hourly_funding_tick(array![(BTC_ASSET, 1), (ETH_ASSET, -1)].span());

    ////                  provisional balance   |   BTC tick      |    ETH tick
    ///                          9_939          |  1 * (0 - 1)    | -10 * (0 - (-1))   = 9_928
    test.validate_total_value(user_a, 9_928);

    ////                  provisional balance   |   BTC tick      |    ETH tick
    ///                          9_939          | -1 * (0 - 1)    |  10 * (0 - (-1))   = 9_950
    test.validate_total_value(user_b, 9_950);

    test.price_tick(array![(BTC_ASSET, 1100), (ETH_ASSET, 600)].span());

    ////                collateral |    BTC    |    ETH
    ///                   14_024   |  1*1100   |  -10*600  = 9_124
    test.validate_total_value(user_a, 9124);

    ////                 BTC       |     ETH
    ///               1*110*0.1   |  10*600*0.1 = 710
    test.validate_total_risk(user_a, 710);

    ////                collateral |    BTC    |    ETH
    ///                   5_854   |  -1*1100   |  10*600  = 10_754
    test.validate_total_value(user_b, 10_754);

    ////                 BTC       |     ETH
    ///               1*110*0.1   |  10*600*0.1 = 710
    test.validate_total_risk(user_b, 710);

    let buy_btc_a = test.create_order_request(user: user_a, asset_index: BTC_ASSET, base: 1);
    test.trade(buy_btc_a, sell_btc_b);

    ////                collateral  fee
    ///                   9124     - 11     = 9113
    test.validate_total_value(user_a, 9113);

    ////                collateral  fee
    ///                   10_754     - 10     = 10_744
    test.validate_total_value(user_b, 10_744);

    test.trade(sell_eth_a, buy_eth_b);

    ////                 old TV     sold       fee     received
    ///                   9113    -10*600     - 51    + 10*512
    test.validate_total_value(user_a, 8182);

    ////                 BTC       |     ETH
    ///               2*110*0.1   |  20*600*0.5 = 1420
    test.validate_total_risk(user_a, 6220);

    ////                 old TV     bought       fee     paid
    ///                  10_744      10*600     - 51    + 10*512
    test.validate_total_value(user_b, 11_573);
}
