use perpetuals::tests::flow_tests::flow_tests_infra::*;

#[test]
fn flow_test_deposit_and_withdraw() {
    let mut flow_test_state = FlowTestTrait::init();
    flow_test_state.setup(synthetics: array![].span());
    let user = flow_test_state.new_user(register_address: false);
    let deposit_info = flow_test_state.deposit(:user, quantized_amount: 100);
    flow_test_state.process_deposit(:deposit_info);
    flow_test_state.self_request_and_withdraw(:user, amount: 50);
    // TODO: check balance
}
