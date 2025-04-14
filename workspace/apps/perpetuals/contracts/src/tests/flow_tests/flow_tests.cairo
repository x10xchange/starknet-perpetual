use perpetuals::tests::flow_tests::infra::*;

#[test]
fn test_two_users_two_synthetics() {
    /// Link to spreadsheet with calculations:
    /// https://docs.google.com/spreadsheets/d/1BIJ6Oq7hAsF-Vb6EJSQFYbCQJMyrncuWDC4NoKLiV1U/edit?gid=0#gid=0

    let mut test = FlowTestExtendedTrait::new(fee_percentage: 1);
    let user_a = test.new_user();
    let user_b = test.new_user();

    test.process_deposit(test.deposit(user_a, 10_000));
    test.process_deposit(test.deposit(user_b, 10_000));

    let sell_eth_a = test.create_order_request(user: user_a, asset: ETH_ASSET, base: -10);
    let buy_eth_b = test.create_order_request(user: user_b, asset: ETH_ASSET, base: 200);
    let (buy_eth_b, _) = test.trade(buy_eth_b, sell_eth_a);

    let buy_btc_a = test.create_order_request(user: user_a, asset: BTC_ASSET, base: 1);
    let sell_btc_b = test.create_order_request(user: user_b, asset: BTC_ASSET, base: -2);
    let (_, sell_btc_b) = test.trade(buy_btc_a, sell_btc_b);
    let sell_eth_a = test.create_order_request(user: user_a, asset: ETH_ASSET, base: -10);

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
    ///               1*1100*0.1   |  10*600*0.1 = 710
    test.validate_total_risk(user_a, 710);

    ////                collateral |    BTC    |    ETH
    ///                   5_854   |  -1*1100   |  10*600  = 10_754
    test.validate_total_value(user_b, 10_754);

    ////                 BTC       |     ETH
    ///               1*1100*0.1   |  10*600*0.1 = 710
    test.validate_total_risk(user_b, 710);

    let buy_btc_a = test.create_order_request(user: user_a, asset: BTC_ASSET, base: 1);
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
    ///               2*1100*0.1   |  20*600*0.2 = 2620
    test.validate_total_risk(user_a, 2620);

    ////                 old TV     bought       fee     paid
    ///                  10_744      10*600     - 51    + 10*512
    test.validate_total_value(user_b, 11_573);

    ////                 BTC       |     ETH
    ///               2*1100*0.1   |  20*600*0.2 = 2620
    test.validate_total_risk(user_b, 2620);
}

#[test]
fn test_long_deleverage_after_funding_tick() {
    // Setup:
    let mut test = FlowTestExtendedTrait::new(fee_percentage: 1);
    let deleveraged_user = test.new_user();
    let deleverager_user = test.new_user();
    let other_user = test.new_user();

    test.process_deposit(test.deposit(deleveraged_user, 113));
    test.process_deposit(test.deposit(deleverager_user, 100_000));
    test.process_deposit(test.deposit(other_user, 100_000));

    let order_a = test.create_order_request(user: deleveraged_user, asset: ETH_ASSET, base: 2);
    let order_b = test.create_order_request(user: deleverager_user, asset: ETH_ASSET, base: -1);
    let order_c = test.create_order_request(user: other_user, asset: ETH_ASSET, base: -1);

    let (order_a, _) = test.trade(order_a, order_b);
    test.trade(order_a, order_c);

    //                                      TV                              TR               TV / TR
    //                     (COLLATERAL+SYNTHETIC*PRICE)          (|SYNTHETIC*PRICE*RISK|)
    //                   113 + 2 * -517(5 fee) + 2 * 512 = 103     2 * 512 * 0.1 = 102        1.0098
    test.validate_total_value(deleveraged_user, 103);
    test.validate_total_risk(deleveraged_user, 102);

    // Test:

    // Maximum funding tick in an hour is 15.
    test.hourly_funding_tick(array![(ETH_ASSET, 15)].span());
    test.hourly_funding_tick(array![(ETH_ASSET, 30)].span());
    test.hourly_funding_tick(array![(ETH_ASSET, 45)].span());
    test.hourly_funding_tick(array![(ETH_ASSET, 60)].span());
    test.hourly_funding_tick(array![(ETH_ASSET, 75)].span());
    test.hourly_funding_tick(array![(ETH_ASSET, 90)].span());
    test.hourly_funding_tick(array![(ETH_ASSET, 103)].span());

    //                                  TV                             TR                    TV / TR
    //                    (Previous TV - funding)           (|SYNTHETIC*PRICE*RISK|)
    //                      103 - 2 * 103 = -103              2 * 512 * 0.1 = 102            -1.0098
    test.validate_total_value(deleveraged_user, -103);
    test.validate_total_risk(deleveraged_user, 102);

    test.deleverage(:deleveraged_user, :deleverager_user, asset: ETH_ASSET, base: -1, quote: 564);

    //                                  TV                                       TR          TV / TR
    //                       (Previous TV + extra)           (|SYNTHETIC*PRICE*RISK|)
    //                          -103 + 52 = -51               1 * 512 * 0.1 = 51               -1
    test.validate_total_value(deleveraged_user, -51);
    test.validate_total_risk(deleveraged_user, 51);
}

#[test]
fn test_long_deleverage_after_price_tick() {
    // Setup:
    let mut test = FlowTestExtendedTrait::new(fee_percentage: 1);
    let deleveraged_user = test.new_user();
    let deleverager_user = test.new_user();

    test.process_deposit(test.deposit(deleveraged_user, 113));
    test.process_deposit(test.deposit(deleverager_user, 100_000));

    let order_a = test.create_order_request(user: deleveraged_user, asset: ETH_ASSET, base: 2);
    let order_b = test.create_order_request(user: deleverager_user, asset: ETH_ASSET, base: -2);

    test.trade(order_a, order_b);

    //                                      TV                              TR               TV / TR
    //                     (COLLATERAL+SYNTHETIC*PRICE)           (|SYNTHETIC*PRICE*RISK|)
    //                   113 + 2 * -517(5 fee) + 2 * 512 = 103     2 * 512 * 0.1 = 102        1.0098
    test.validate_total_value(deleveraged_user, 103);
    test.validate_total_risk(deleveraged_user, 102);

    // Test:

    test.price_tick(array![(ETH_ASSET, 512 - 93)].span());

    //                                      TV                               TR              TV / TR
    //                            (Previous TV - price diff)       (|SYNTHETIC*PRICE*RISK|)
    //                               103  - 2 * 93  = -83             1 * 419 * 0.1 = 41        1
    test.validate_total_value(deleveraged_user, -83);
    test.validate_total_risk(deleveraged_user, 83);

    test.deleverage(:deleveraged_user, :deleverager_user, asset: ETH_ASSET, base: -1, quote: 461);

    //                                      TV                           TR                  TV / TR
    //                            (Previous TV + extra)        (|SYNTHETIC*PRICE*RISK|)
    //                               -83  + 42 = -41              1 * 419 * 0.1 = 41            1
    test.validate_total_value(deleveraged_user, -41);
    test.validate_total_risk(deleveraged_user, 41);
}

#[test]
fn test_short_deleverage_after_funding_tick() {
    // Setup:
    let mut test = FlowTestExtendedTrait::new(fee_percentage: 1);
    let deleveraged_user = test.new_user();
    let deleverager_user = test.new_user();
    let other_user = test.new_user();

    test.process_deposit(test.deposit(deleveraged_user, 113));
    test.process_deposit(test.deposit(deleverager_user, 100_000));
    test.process_deposit(test.deposit(other_user, 100_000));

    let order_a = test.create_order_request(user: deleveraged_user, asset: ETH_ASSET, base: -2);
    let order_b = test.create_order_request(user: deleverager_user, asset: ETH_ASSET, base: 1);
    let order_c = test.create_order_request(user: other_user, asset: ETH_ASSET, base: 1);

    let (_, order_a) = test.trade(order_a, order_b);
    test.trade(order_a, order_c);

    //                                      TV                              TR               TV / TR
    //                     (COLLATERAL+SYNTHETIC*PRICE)          (|SYNTHETIC*PRICE*RISK|)
    //                   113 + 2 * +507(5 fee) - 2 * 512 = 103     2 * 512 * 0.1 = 102        1.0098
    test.validate_total_value(deleveraged_user, 103);
    test.validate_total_risk(deleveraged_user, 102);

    // Test:

    // Maximum funding tick in an hour is 15.
    test.hourly_funding_tick(array![(ETH_ASSET, -15)].span());
    test.hourly_funding_tick(array![(ETH_ASSET, -30)].span());
    test.hourly_funding_tick(array![(ETH_ASSET, -45)].span());
    test.hourly_funding_tick(array![(ETH_ASSET, -60)].span());
    test.hourly_funding_tick(array![(ETH_ASSET, -75)].span());
    test.hourly_funding_tick(array![(ETH_ASSET, -90)].span());
    test.hourly_funding_tick(array![(ETH_ASSET, -103)].span());

    //                                  TV                                       TR          TV / TR
    //                         Previous TV - funding)         (|SYNTHETIC*PRICE*RISK|)
    //                          103 - 2*103 = -103                1 * 512 * 0.1 = 51         -1.0098
    test.validate_total_value(deleveraged_user, -103);
    test.validate_total_risk(deleveraged_user, 102);

    test.deleverage(:deleveraged_user, :deleverager_user, asset: ETH_ASSET, base: 1, quote: -460);

    //                                  TV                                       TR          TV / TR
    //                       (Previous TV + extra)          (|SYNTHETIC*PRICE*RISK|)
    //                          -103 + 52 = -51               1 * 512 * 0.1 = 51               -1
    test.validate_total_value(deleveraged_user, -51);
    test.validate_total_risk(deleveraged_user, 51);
}

#[test]
fn test_short_deleverage_after_price_tick() {
    // Setup:
    let mut test = FlowTestExtendedTrait::new(fee_percentage: 1);
    let deleveraged_user = test.new_user();
    let deleverager_user = test.new_user();

    test.process_deposit(test.deposit(deleveraged_user, 113));
    test.process_deposit(test.deposit(deleverager_user, 100_000));

    let order_a = test.create_order_request(user: deleveraged_user, asset: ETH_ASSET, base: -2);
    let order_b = test.create_order_request(user: deleverager_user, asset: ETH_ASSET, base: 2);

    test.trade(order_a, order_b);

    //                                      TV                              TR               TV / TR
    //                     (COLLATERAL+SYNTHETIC*PRICE)           (|SYNTHETIC*PRICE*RISK|)
    //                   113 + 2 * -517(5 fee) + 2 * 512 = 103     2 * 512 * 0.1 = 102        1.0098
    test.validate_total_value(deleveraged_user, 103);
    test.validate_total_risk(deleveraged_user, 102);

    // Test:

    test.price_tick(array![(ETH_ASSET, 512 + 114)].span());

    //                                  TV                               TR                  TV / TR
    //                    (Previous TV - price diff)       (|SYNTHETIC*PRICE*RISK|)
    //                      103  - 2 * 114  = -125       2 * (512 + 114) * 0.1 =  125          -1
    test.validate_total_value(deleveraged_user, -125);
    test.validate_total_risk(deleveraged_user, 125);

    test.deleverage(:deleveraged_user, :deleverager_user, asset: ETH_ASSET, base: 1, quote: -563);

    //                                      TV                           TR                  TV / TR
    //                            (Previous TV + extra)        (|SYNTHETIC*PRICE*RISK|)
    //                               -125  + 63 = -62             1 * 626 * 0.1 = 62            1
    test.validate_total_value(deleveraged_user, -62);
    test.validate_total_risk(deleveraged_user, 62);
}

#[test]
fn test_long_liquidate_after_funding_tick() {
    // Setup:
    let mut test = FlowTestExtendedTrait::new(fee_percentage: 1);
    let liquidated_user = test.new_user();
    let liquidator_user = test.new_user();
    let other_user = test.new_user();

    test.process_deposit(test.deposit(liquidated_user, 113));
    test.process_deposit(test.deposit(liquidator_user, 100_000));
    test.process_deposit(test.deposit(other_user, 100_000));

    let order_a = test.create_order_request(user: liquidated_user, asset: ETH_ASSET, base: 2);
    let order_b = test.create_order_request(user: other_user, asset: ETH_ASSET, base: -2);

    test.trade(order_a, order_b);

    //                                      TV                              TR               TV / TR
    //                     (COLLATERAL+SYNTHETIC*PRICE)          (|SYNTHETIC*PRICE*RISK|)
    //                   113 + 2 * -517(5 fee) + 2 * 512 = 103     2 * 512 * 0.1 = 102        1.0098
    test.validate_total_value(liquidated_user, 103);
    test.validate_total_risk(liquidated_user, 102);

    // Test:

    // Maximum funding tick in an hour is 15.
    test.hourly_funding_tick(array![(ETH_ASSET, 15)].span());
    test.hourly_funding_tick(array![(ETH_ASSET, 26)].span());

    //                                  TV                             TR                    TV / TR
    //                    (Previous TV - funding)           (|SYNTHETIC*PRICE*RISK|)
    //                      103 - 2 * 26 = 51                 2 * 512 * 0.1 = 102              0.5
    test.validate_total_value(liquidated_user, 51);
    test.validate_total_risk(liquidated_user, 102);

    // Liquidator  wants to buy 21 lower than current price. By lowering the price, creating an
    // order then bringing the price back, we get an order with a lower price.
    test.price_tick(array![(ETH_ASSET, 512 - 21)].span());
    let order_c = test.create_order_request(user: liquidator_user, asset: ETH_ASSET, base: 1);
    test.price_tick(array![(ETH_ASSET, 512)].span());

    test.liquidate(:liquidated_user, liquidator_order: order_c);

    //                                  TV                                TR                 TV / TR
    //                       (Previous TV - loss - fee)       |SYNTHETIC*PRICE*RISK|)
    //                            51 - 21 - 4 = 26               1 * 512 * 0.1 = 51           0.51
    test.validate_total_value(liquidated_user, 26);
    test.validate_total_risk(liquidated_user, 51);
}

#[test]
fn test_long_liquidate_after_price_tick() {
    // Setup:
    let mut test = FlowTestExtendedTrait::new(fee_percentage: 1);
    let liquidated_user = test.new_user();
    let liquidator_user = test.new_user();
    let other_user = test.new_user();

    test.process_deposit(test.deposit(liquidated_user, 113));
    test.process_deposit(test.deposit(liquidator_user, 100_000));
    test.process_deposit(test.deposit(other_user, 100_000));

    let order_a = test.create_order_request(user: liquidated_user, asset: ETH_ASSET, base: 2);
    let order_b = test.create_order_request(user: other_user, asset: ETH_ASSET, base: -2);

    test.trade(order_a, order_b);

    //                                      TV                              TR               TV / TR
    //                     (COLLATERAL+SYNTHETIC*PRICE)          (|SYNTHETIC*PRICE*RISK|)
    //                   113 + 2 * -517(5 fee) + 2 * 512 = 103     2 * 512 * 0.1 = 102        1.0098
    test.validate_total_value(liquidated_user, 103);
    test.validate_total_risk(liquidated_user, 102);

    // Test:

    test.price_tick(array![(ETH_ASSET, 512 - 27)].span());

    //                                  TV                             TR                    TV / TR
    //                     (Previous TV - price diff)       (|SYNTHETIC*PRICE*RISK|)
    //                        103 - 2 * 27 = 49               2 * 485 * 0.1 = 97              0.505
    test.validate_total_value(liquidated_user, 49);
    test.validate_total_risk(liquidated_user, 97);

    // Liquidator  wants to buy 19 lower than current price. By lowering the price, creating an
    // order then bringing the price back, we get an order with a lower price.
    test.price_tick(array![(ETH_ASSET, 512 - 27 - 19)].span());
    let order_c = test.create_order_request(user: liquidator_user, asset: ETH_ASSET, base: 1);
    test.price_tick(array![(ETH_ASSET, 512 - 27)].span());

    test.liquidate(:liquidated_user, liquidator_order: order_c);

    //                                  TV                                TR                 TV / TR
    //                       (Previous TV - loss - fee)       |SYNTHETIC*PRICE*RISK|)
    //                            49 - 19 - 4 = 26               1 * 485 * 0.1 = 48           0.541
    test.validate_total_value(liquidated_user, 26);
    test.validate_total_risk(liquidated_user, 48);
}

#[test]
fn test_short_liquidate_after_funding_tick() {
    // Setup:
    let mut test = FlowTestExtendedTrait::new(fee_percentage: 1);
    let liquidated_user = test.new_user();
    let liquidator_user = test.new_user();
    let other_user = test.new_user();

    test.process_deposit(test.deposit(liquidated_user, 113));
    test.process_deposit(test.deposit(liquidator_user, 100_000));
    test.process_deposit(test.deposit(other_user, 100_000));

    let order_a = test.create_order_request(user: liquidated_user, asset: ETH_ASSET, base: -2);
    let order_b = test.create_order_request(user: other_user, asset: ETH_ASSET, base: 2);

    test.trade(order_a, order_b);

    //                                      TV                              TR               TV / TR
    //                     (COLLATERAL+SYNTHETIC*PRICE)          (|SYNTHETIC*PRICE*RISK|)
    //                   113 + 2 * -517(5 fee) + 2 * 512 = 103     2 * 512 * 0.1 = 102        1.0098
    test.validate_total_value(liquidated_user, 103);
    test.validate_total_risk(liquidated_user, 102);

    // Test:

    // Maximum funding tick in an hour is 15.
    test.hourly_funding_tick(array![(ETH_ASSET, -15)].span());
    test.hourly_funding_tick(array![(ETH_ASSET, -26)].span());

    //                                  TV                             TR                    TV / TR
    //                    (Previous TV - funding)           (|SYNTHETIC*PRICE*RISK|)
    //                      103 - 2 * 26 = 51                  2 * 512 * 0.1 = 102              0.5
    test.validate_total_value(liquidated_user, 51);
    test.validate_total_risk(liquidated_user, 102);

    // Liquidator  wants to sell 20 higher than current price. By rising the price, creating an
    // order then lowering the price back, we get an order with a higher price.
    test.price_tick(array![(ETH_ASSET, 512 + 20)].span());
    let order_c = test.create_order_request(user: liquidator_user, asset: ETH_ASSET, base: -1);
    test.price_tick(array![(ETH_ASSET, 512)].span());

    test.liquidate(:liquidated_user, liquidator_order: order_c);

    //                                  TV                                TR                 TV / TR
    //                       (Previous TV - loss - fee)       |SYNTHETIC*PRICE*RISK|)
    //                            51 - 20 - 5 = 26               1 * 512 * 0.1 = 51           0.51
    test.validate_total_value(liquidated_user, 26);
    test.validate_total_risk(liquidated_user, 51);
}


#[test]
fn test_short_liquidate_after_price_tick() {
    // Setup:
    let mut test = FlowTestExtendedTrait::new(fee_percentage: 1);
    let liquidated_user = test.new_user();
    let liquidator_user = test.new_user();
    let other_user = test.new_user();

    test.process_deposit(test.deposit(liquidated_user, 113));
    test.process_deposit(test.deposit(liquidator_user, 100_000));
    test.process_deposit(test.deposit(other_user, 100_000));

    let order_a = test.create_order_request(user: liquidated_user, asset: ETH_ASSET, base: -2);
    let order_b = test.create_order_request(user: other_user, asset: ETH_ASSET, base: 2);

    test.trade(order_a, order_b);

    //                                      TV                              TR               TV / TR
    //                     (COLLATERAL+SYNTHETIC*PRICE)          (|SYNTHETIC*PRICE*RISK|)
    //                   113 + 2 * -517(5 fee) + 2 * 512 = 103     2 * 512 * 0.1 = 102        1.0098
    test.validate_total_value(liquidated_user, 103);
    test.validate_total_risk(liquidated_user, 102);

    // Test:

    test.price_tick(array![(ETH_ASSET, 512 + 27)].span());

    //                                  TV                             TR                    TV / TR
    //                     (Previous TV - price diff)       (|SYNTHETIC*PRICE*RISK|)
    //                        103 - 2 * 27 = 49               2 * 539 * 0.1 = 107              0.45
    test.validate_total_value(liquidated_user, 49);
    test.validate_total_risk(liquidated_user, 107);

    // Liquidator  wants to sell 18 higher than current price. By rising the price, creating an
    // order then lowering the price back, we get an order with a higher price.
    test.price_tick(array![(ETH_ASSET, 512 + 27 + 18)].span());
    let order_c = test.create_order_request(user: liquidator_user, asset: ETH_ASSET, base: -1);
    test.price_tick(array![(ETH_ASSET, 512 + 27)].span());

    test.liquidate(:liquidated_user, liquidator_order: order_c);

    //                                  TV                                TR                 TV / TR
    //                       (Previous TV - loss - fee)       |SYNTHETIC*PRICE*RISK|)
    //                            49 - 18 - 5 = 26               1 * 539 * 0.1 = 53           0.541
    test.validate_total_value(liquidated_user, 26);
    test.validate_total_risk(liquidated_user, 53);
}
