use perpetuals::core::constants::{TREASURY_SWEEP_RECIPIENT, TREASURY_SWEEP_TOKENS};
use perpetuals::core::core::Core;
use perpetuals::core::events::TreasurySwept;
use perpetuals::core::interface::{ICoreDispatcher, ICoreDispatcherTrait};
use perpetuals::tests::flow_tests::infra::{FlowTestBase, FlowTestBaseTrait};
use perpetuals::tests::flow_tests::perps_tests_facade::PerpsTestsFacadeTrait;
use snforge_std::cheatcodes::events::EventSpyAssertionsTrait;
use snforge_std::{ContractClassTrait, DeclareResultTrait, Token, TokenTrait};
use starknet::ContractAddress;
use starkware_utils_testing::test_utils::{
    TokenState, TokenTrait as TestTokenTrait, cheat_caller_address_once,
};

const USDC_AMOUNT: u128 = 1_000_000_000;
const USDT_AMOUNT: u128 = 2_000_000_000;
const ETH_AMOUNT: u128 = 3_000_000_000_000_000_000;
const WBTC_AMOUNT: u128 = 400_000_000;

fn RECIPIENT() -> ContractAddress {
    TREASURY_SWEEP_RECIPIENT.try_into().unwrap()
}

fn USDC() -> ContractAddress {
    (*TREASURY_SWEEP_TOKENS.span()[0]).try_into().unwrap()
}

fn USDT() -> ContractAddress {
    (*TREASURY_SWEEP_TOKENS.span()[1]).try_into().unwrap()
}

fn ETH() -> ContractAddress {
    (*TREASURY_SWEEP_TOKENS.span()[2]).try_into().unwrap()
}

fn WBTC() -> ContractAddress {
    (*TREASURY_SWEEP_TOKENS.span()[3]).try_into().unwrap()
}

fn token(state: @FlowTestBase, address: ContractAddress) -> TokenState {
    TokenState { address, owner: *state.facade.token_state.owner }
}

/// Deploys a mock ERC20 at the hardcoded mainnet `address`, minting `amount` to `holder`.
fn deploy_token_at(address: ContractAddress, holder: ContractAddress, amount: u128) {
    let mut calldata = array![];
    let name: ByteArray = "TOKEN";
    let symbol: ByteArray = "TKN";
    name.serialize(ref calldata);
    symbol.serialize(ref calldata);
    6_u8.serialize(ref calldata);
    let initial_supply: u256 = amount.into();
    initial_supply.serialize(ref calldata);
    holder.serialize(ref calldata);
    let erc20 = snforge_std::declare("DualCaseERC20Mock").unwrap().contract_class();
    erc20.deploy_at(@calldata, address).unwrap();
}

/// Deploys the swept tokens with the given treasury balances. ETH is predeployed by snforge at its
/// mainnet address, so only its balance is set.
fn setup(usdc: u128, usdt: u128, eth: u128, wbtc: u128) -> FlowTestBase {
    let state: FlowTestBase = FlowTestBaseTrait::new();
    let treasury = state.facade.treasury_address;
    assert_eq!(Token::ETH.contract_address(), ETH());
    deploy_token_at(USDC(), treasury, usdc);
    deploy_token_at(USDT(), treasury, usdt);
    deploy_token_at(WBTC(), treasury, wbtc);
    snforge_std::set_balance(target: treasury, new_balance: eth.into(), token: Token::ETH);
    state
}

/// Lifts the treasury protection limit to 100% for every swept token, as ops do before the sweep.
fn raise_protection_limits(ref state: FlowTestBase) {
    for token_address in TREASURY_SWEEP_TOKENS.span() {
        let token_address: ContractAddress = (*token_address).try_into().unwrap();
        state.facade.set_treasury_protection_percent_for_token(:token_address, percent: 100);
    }
}

fn sweep_as(ref state: FlowTestBase, caller: ContractAddress, amount: u256) {
    let perpetuals = state.facade.perpetuals_contract;
    cheat_caller_address_once(contract_address: perpetuals, caller_address: caller);
    ICoreDispatcher { contract_address: perpetuals }.sweep_treasury(:amount);
}

/// Sweeps `amount` of each token as the upgrade governor.
fn sweep_amount(ref state: FlowTestBase, amount: u256) {
    let governor = state.facade.governance_admin;
    sweep_as(ref state, governor, :amount);
}

/// Sweeps the full balance of each token as the upgrade governor.
fn sweep(ref state: FlowTestBase) {
    sweep_amount(ref state, amount: 0);
}

fn swept_event(
    state: @FlowTestBase, token_address: ContractAddress, amount: u128,
) -> (ContractAddress, Core::Event) {
    (
        *state.facade.perpetuals_contract,
        Core::Event::TreasurySwept(
            TreasurySwept { token_address, recipient: RECIPIENT(), amount: amount.into() },
        ),
    )
}

#[test]
fn test_sweep_treasury_moves_all_balances() {
    let mut state = setup(USDC_AMOUNT, USDT_AMOUNT, ETH_AMOUNT, WBTC_AMOUNT);
    raise_protection_limits(ref state);
    let treasury = state.facade.treasury_address;
    let perpetuals = state.facade.perpetuals_contract;
    // Tokens held by Core itself (e.g. pending deposits) are not swept.
    snforge_std::set_balance(target: perpetuals, new_balance: 7, token: Token::ETH);

    sweep(ref state);

    let expected = array![
        (USDC(), USDC_AMOUNT), (USDT(), USDT_AMOUNT), (ETH(), ETH_AMOUNT), (WBTC(), WBTC_AMOUNT),
    ];
    let mut events = array![];
    for (address, amount) in expected {
        let token_state = token(@state, address);
        assert_eq!(token_state.balance_of(RECIPIENT()), amount);
        assert_eq!(token_state.balance_of(treasury), 0);
        events.append(swept_event(@state, address, amount));
    }
    assert_eq!(token(@state, ETH()).balance_of(perpetuals), 7);
    state.facade.event_info.assert_emitted(@events);
}

#[test]
fn test_sweep_treasury_skips_zero_balances() {
    let mut state = setup(USDC_AMOUNT, 0, ETH_AMOUNT, 0);
    raise_protection_limits(ref state);

    sweep(ref state);

    assert_eq!(token(@state, USDC()).balance_of(RECIPIENT()), USDC_AMOUNT);
    assert_eq!(token(@state, ETH()).balance_of(RECIPIENT()), ETH_AMOUNT);
    assert_eq!(token(@state, USDT()).balance_of(RECIPIENT()), 0);
    assert_eq!(token(@state, WBTC()).balance_of(RECIPIENT()), 0);
    let swept = array![
        swept_event(@state, USDC(), USDC_AMOUNT), swept_event(@state, ETH(), ETH_AMOUNT),
    ];
    state.facade.event_info.assert_emitted(@swept);
    let skipped = array![swept_event(@state, USDT(), 0), swept_event(@state, WBTC(), 0)];
    state.facade.event_info.assert_not_emitted(@skipped);
}

#[test]
fn test_sweep_treasury_twice_moves_nothing_more() {
    let mut state = setup(USDC_AMOUNT, USDT_AMOUNT, ETH_AMOUNT, WBTC_AMOUNT);
    raise_protection_limits(ref state);

    sweep(ref state);
    sweep(ref state);

    assert_eq!(token(@state, USDC()).balance_of(RECIPIENT()), USDC_AMOUNT);
    assert_eq!(token(@state, USDT()).balance_of(RECIPIENT()), USDT_AMOUNT);
    assert_eq!(token(@state, ETH()).balance_of(RECIPIENT()), ETH_AMOUNT);
    assert_eq!(token(@state, WBTC()).balance_of(RECIPIENT()), WBTC_AMOUNT);
}

#[test]
#[should_panic(expected: "ONLY_UPGRADE_GOVERNOR")]
fn test_sweep_treasury_only_upgrade_governor() {
    let mut state = setup(USDC_AMOUNT, USDT_AMOUNT, ETH_AMOUNT, WBTC_AMOUNT);
    raise_protection_limits(ref state);
    let app_governor = state.facade.app_governor;

    sweep_as(ref state, app_governor, amount: 0);
}

#[test]
fn test_sweep_treasury_test_amount() {
    let mut state = setup(USDC_AMOUNT, USDT_AMOUNT, ETH_AMOUNT, WBTC_AMOUNT);
    raise_protection_limits(ref state);
    let treasury = state.facade.treasury_address;
    let test_amount: u128 = 100;

    sweep_amount(ref state, amount: test_amount.into());

    // The raw amount is sent as-is for every token, regardless of its decimals.
    let balances = array![
        (USDC(), USDC_AMOUNT), (USDT(), USDT_AMOUNT), (ETH(), ETH_AMOUNT), (WBTC(), WBTC_AMOUNT),
    ];
    let mut events = array![];
    for (address, balance) in balances {
        let token_state = token(@state, address);
        assert_eq!(token_state.balance_of(RECIPIENT()), test_amount);
        assert_eq!(token_state.balance_of(treasury), balance - test_amount);
        events.append(swept_event(@state, address, test_amount));
    }
    state.facade.event_info.assert_emitted(@events);

    // A follow-up full sweep moves the rest.
    sweep(ref state);
    assert_eq!(token(@state, USDC()).balance_of(RECIPIENT()), USDC_AMOUNT);
    assert_eq!(token(@state, ETH()).balance_of(RECIPIENT()), ETH_AMOUNT);
    assert_eq!(token(@state, WBTC()).balance_of(treasury), 0);
}

#[test]
fn test_sweep_treasury_amount_capped_at_balance() {
    // wBTC holds less than the requested amount and USDT holds nothing.
    let mut state = setup(USDC_AMOUNT, 0, ETH_AMOUNT, 50);
    raise_protection_limits(ref state);
    let test_amount: u128 = 1_000;

    sweep_amount(ref state, amount: test_amount.into());

    assert_eq!(token(@state, USDC()).balance_of(RECIPIENT()), test_amount);
    assert_eq!(token(@state, ETH()).balance_of(RECIPIENT()), test_amount);
    assert_eq!(token(@state, WBTC()).balance_of(RECIPIENT()), 50);
    assert_eq!(token(@state, USDT()).balance_of(RECIPIENT()), 0);
    assert_eq!(token(@state, WBTC()).balance_of(state.facade.treasury_address), 0);
}

#[test]
#[should_panic(expected: "Treasury Protection Limit Exceeded")]
fn test_sweep_treasury_requires_raised_protection_limit() {
    let mut state = setup(USDC_AMOUNT, USDT_AMOUNT, ETH_AMOUNT, WBTC_AMOUNT);

    sweep(ref state);
}
