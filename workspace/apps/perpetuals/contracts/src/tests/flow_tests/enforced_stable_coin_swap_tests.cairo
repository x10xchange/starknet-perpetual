use perpetuals::core::components::assets::interface::{IAssetsDispatcher, IAssetsDispatcherTrait};
use perpetuals::core::components::operator_nonce::interface::{
    IOperatorNonceDispatcher, IOperatorNonceDispatcherTrait,
};
use perpetuals::core::events::EnforcedStableCoinSwap;
use perpetuals::core::types::price::PRICE_SCALE;
use perpetuals::tests::flow_tests::infra::{FlowTestBase, FlowTestBaseTrait};
use perpetuals::tests::flow_tests::perps_tests_facade::*;
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, EventSpyTrait, EventsFilterTrait, TokenTrait, declare,
    spy_events, stop_cheat_caller_address,
};
use starkware_utils::constants::MAX_U128;
use starkware_utils_testing::test_utils::{
    TokenState, TokenTrait as TestTokenTrait, assert_expected_event_emitted,
};

// Foundry 0.55 does not roll back a failed call made directly by a test.
// Catch inside a contract so this exercises Starknet's nested-call rollback.
#[starknet::interface]
trait ISwapTestCaller<TContractState> {
    fn try_swap(
        self: @TContractState,
        target: starknet::ContractAddress,
        operator_nonce: u64,
        position_id: perpetuals::core::types::position::PositionId,
        from_asset_id: perpetuals::core::types::asset::AssetId,
        amount: u64,
    ) -> bool;
}

#[starknet::contract]
mod SwapTestCaller {
    use perpetuals::core::interface::{ICoreSafeDispatcher, ICoreSafeDispatcherTrait};
    use perpetuals::core::types::asset::AssetId;
    use perpetuals::core::types::position::PositionId;
    use starknet::ContractAddress;
    #[storage]
    struct Storage {}
    #[abi(embed_v0)]
    impl Caller of super::ISwapTestCaller<ContractState> {
        #[feature("safe_dispatcher")]
        fn try_swap(
            self: @ContractState,
            target: ContractAddress,
            operator_nonce: u64,
            position_id: PositionId,
            from_asset_id: AssetId,
            amount: u64,
        ) -> bool {
            ICoreSafeDispatcher { contract_address: target }
                .enforced_stable_coin_swap(operator_nonce, position_id, from_asset_id, amount)
                .is_ok()
        }
    }
}

fn nonce(state: @FlowTestBase) -> u64 {
    IOperatorNonceDispatcher { contract_address: *state.facade.perpetuals_contract }
        .get_operator_nonce()
}

fn setup() -> (FlowTestBase, User, AssetInfo) {
    let mut state = FlowTestBaseTrait::new();
    let token = snforge_std::Token::STRK;
    let asset_info = AssetInfoTrait::new_collateral_with_resolution(
        asset_name: 'USDT',
        risk_factor_data: RiskFactorTiers {
            tiers: array![100].span(), first_tier_boundary: MAX_U128, tier_size: 1,
        },
        oracles_len: 1,
        resolution: 1_000_000,
        erc20_contract_address: token.contract_address(),
        quantum: 1,
    );
    state.facade.add_active_collateral(@asset_info, 1);
    // Fresh, signed oracle price of $0.50. The conversion itself still pays $1.
    let oracle_price: u128 = 500_000_000_000_000_000;
    let operator_nonce = nonce(@state);
    state.facade.operator.set_as_caller(state.facade.perpetuals_contract);
    IAssetsDispatcher { contract_address: state.facade.perpetuals_contract }
        .price_tick(
            operator_nonce, asset_info.asset_id, oracle_price, asset_info.sign_price(oracle_price),
        );
    let user = state.new_user_with_position();
    snforge_std::set_balance(user.account.address, 10_000_000, token);
    let deposit = state
        .facade
        .deposit_spot(user.account, asset_info.asset_id, user.position_id, 100);
    state.facade.process_deposit(deposit);
    let deposit = state.facade.deposit(user.account, user.position_id, 200);
    state.facade.process_deposit(deposit);
    (state, user, asset_info)
}

#[test]
fn test_enforced_stable_coin_swap_abi_event_and_atomic_failures() {
    let (mut state, user, asset) = setup();
    let contract_address = state.facade.perpetuals_contract;
    let caller = declare("SwapTestCaller").unwrap().contract_class();
    let (caller_address, _) = caller.deploy(@array![]).unwrap();
    let dispatcher = ISwapTestCallerDispatcher { contract_address: caller_address };
    let original_nonce = nonce(@state);
    let token = TokenState {
        address: asset.erc20_contract_address, owner: state.facade.token_state.owner,
    };
    let treasury_usdc = state.facade.token_state.balance_of(state.facade.treasury_address);
    let treasury_usdt = token.balance_of(state.facade.treasury_address);
    let contract_usdc = state.facade.token_state.balance_of(contract_address);
    let contract_usdt = token.balance_of(contract_address);
    let mut spy = spy_events();

    state.facade.operator.set_as_caller(contract_address);
    assert!(
        !dispatcher
            .try_swap(contract_address, original_nonce, user.position_id, asset.asset_id, 101),
    );
    assert!(nonce(@state) == original_nonce);
    assert!(
        state.facade.get_position_asset_balance(user.position_id, asset.asset_id) == 100_i64.into(),
    );
    assert!(state.facade.get_position_collateral_balance(user.position_id) == 200_i64.into());
    assert!(spy.get_events().emitted_by(contract_address).events.is_empty());

    state.facade.operator.set_as_caller(contract_address);
    assert!(
        !dispatcher
            .try_swap(contract_address, original_nonce + 1, user.position_id, asset.asset_id, 40),
    );
    assert!(nonce(@state) == original_nonce);
    stop_cheat_caller_address(contract_address);
    assert!(
        !dispatcher
            .try_swap(contract_address, original_nonce, user.position_id, asset.asset_id, 40),
    );
    assert!(nonce(@state) == original_nonce);

    state.facade.operator.set_as_caller(contract_address);
    assert!(
        dispatcher.try_swap(contract_address, original_nonce, user.position_id, asset.asset_id, 40),
    );
    assert!(nonce(@state) == original_nonce + 1);
    assert!(
        state.facade.get_position_asset_balance(user.position_id, asset.asset_id) == 60_i64.into(),
    );
    assert!(state.facade.get_position_collateral_balance(user.position_id) == 240_i64.into());
    let events = spy.get_events().emitted_by(contract_address).events;
    assert!(events.len() == 1);
    assert_expected_event_emitted(
        events[0],
        EnforcedStableCoinSwap {
            position_id: user.position_id,
            from_asset_id: asset.asset_id,
            to_asset_id: state.facade.collateral_id,
            amount: 40,
            price: (PRICE_SCALE / 2).into(),
        },
        @selector!("EnforcedStableCoinSwap"),
        "EnforcedStableCoinSwap",
    );

    state.facade.operator.set_as_caller(contract_address);
    assert!(
        !dispatcher
            .try_swap(contract_address, original_nonce, user.position_id, asset.asset_id, 40),
    );
    assert!(nonce(@state) == original_nonce + 1);
    state.facade.operator.set_as_caller(contract_address);
    assert!(
        dispatcher
            .try_swap(contract_address, original_nonce + 1, user.position_id, asset.asset_id, 60),
    );
    assert!(
        state.facade.get_position_asset_balance(user.position_id, asset.asset_id) == 0_i64.into(),
    );
    assert!(state.facade.get_position_collateral_balance(user.position_id) == 300_i64.into());
    state.facade.validate_total_value(user.position_id, 300);
    state.facade.validate_total_risk(user.position_id, 0);
    assert!(state.facade.token_state.balance_of(state.facade.treasury_address) == treasury_usdc);
    assert!(token.balance_of(state.facade.treasury_address) == treasury_usdt);
    assert!(state.facade.token_state.balance_of(contract_address) == contract_usdc);
    assert!(token.balance_of(contract_address) == contract_usdt);
}
