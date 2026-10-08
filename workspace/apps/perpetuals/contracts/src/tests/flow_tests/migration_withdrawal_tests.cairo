use perpetuals::core::components::assets::interface::{IAssetsDispatcher, IAssetsDispatcherTrait};
use perpetuals::core::components::operator_nonce::interface::{
    IOperatorNonceDispatcher, IOperatorNonceDispatcherTrait,
};
use perpetuals::core::components::snip::SNIP12MetadataImpl;
use perpetuals::core::constants::MIGRATION_WITHDRAWAL_RECIPIENT;
use perpetuals::core::interface::{ICoreDispatcher, ICoreDispatcherTrait};
use perpetuals::core::types::asset::AssetId;
use perpetuals::core::types::withdraw::WithdrawArgs;
use perpetuals::tests::event_test_utils::assert_withdraw_event_with_expected;
use perpetuals::tests::flow_tests::infra::{FlowTestBase, FlowTestBaseTrait};
use perpetuals::tests::flow_tests::perps_tests_facade::*;
use snforge_std::cheatcodes::events::{EventSpyTrait, EventsFilterTrait};
use snforge_std::{TokenTrait, start_cheat_block_timestamp_global};
use starknet::ContractAddress;
use starkware_utils::components::request_approvals::interface::{
    IRequestApprovalsDispatcher, IRequestApprovalsDispatcherTrait, RequestStatus,
};
use starkware_utils::constants::MAX_U128;
use starkware_utils::hash::message_hash::OffchainMessageHash;
use starkware_utils::time::time::{Time, Timestamp};
use starkware_utils_testing::test_utils::{TokenState, TokenTrait as TestTokenTrait};

const DEPOSIT_AMOUNT: u64 = 100_000;
const WITHDRAW_AMOUNT: u64 = 15_000;

fn MIGRATION_RECIPIENT() -> ContractAddress {
    MIGRATION_WITHDRAWAL_RECIPIENT.try_into().unwrap()
}

fn perps(state: @FlowTestBase) -> ICoreDispatcher {
    ICoreDispatcher { contract_address: *state.facade.perpetuals_contract }
}

fn nonce(state: @FlowTestBase) -> u64 {
    IOperatorNonceDispatcher { contract_address: *state.facade.perpetuals_contract }
        .get_operator_nonce()
}

fn request_status(state: @FlowTestBase, request_hash: felt252) -> RequestStatus {
    IRequestApprovalsDispatcher { contract_address: *state.facade.perpetuals_contract }
        .get_request_status(request_hash)
}

fn expiration() -> Timestamp {
    Time::now().add(Time::seconds(10))
}

fn withdraw_hash(user: User, args: WithdrawArgs) -> felt252 {
    args.get_message_hash(public_key: user.account.key_pair.public_key)
}

/// The operator executes `withdraw` for `args` without any prior `withdraw_request`.
fn operator_withdraw(ref state: FlowTestBase, args: WithdrawArgs) {
    let operator_nonce = nonce(@state);
    state.facade.operator.set_as_caller(state.facade.perpetuals_contract);
    perps(@state)
        .withdraw(
            :operator_nonce,
            collateral_id: args.collateral_id,
            recipient: args.recipient,
            position_id: args.position_id,
            amount: args.amount,
            expiration: args.expiration,
            salt: args.salt,
            interest_amount: 0,
        );
}

fn setup_funded_user() -> (FlowTestBase, User) {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let user = state.new_user_with_position();
    let deposit_info = state
        .facade
        .deposit(
            depositor: user.account,
            position_id: user.position_id,
            quantized_amount: DEPOSIT_AMOUNT,
        );
    state.facade.process_deposit(:deposit_info);
    (state, user)
}

fn base_collateral_args(
    state: @FlowTestBase, user: User, recipient: ContractAddress, salt: felt252,
) -> WithdrawArgs {
    WithdrawArgs {
        recipient,
        position_id: user.position_id,
        collateral_id: *state.facade.collateral_id,
        amount: WITHDRAW_AMOUNT,
        expiration: expiration(),
        salt,
    }
}

#[test]
fn test_migration_withdrawal_to_whitelisted_recipient_without_request() {
    let (mut state, user) = setup_funded_user();
    let args = base_collateral_args(@state, user, MIGRATION_RECIPIENT(), salt: 1);
    let request_hash = withdraw_hash(user, args);
    assert_eq!(request_status(@state, request_hash), RequestStatus::NOT_REGISTERED);

    let token_state = state.facade.token_state;
    let recipient_balance_before = token_state.balance_of(MIGRATION_RECIPIENT());
    let treasury_balance_before = token_state.balance_of(state.facade.treasury_address);
    let collateral_before = state.facade.get_position_collateral_balance(user.position_id);

    operator_withdraw(ref state, args);

    let unquantized_amount = (WITHDRAW_AMOUNT * state.facade.collateral_quantum).into();
    assert_eq!(
        token_state.balance_of(MIGRATION_RECIPIENT()),
        recipient_balance_before + unquantized_amount,
    );
    assert_eq!(
        token_state.balance_of(state.facade.treasury_address),
        treasury_balance_before - unquantized_amount,
    );
    state
        .facade
        .validate_collateral_balance(
            position_id: user.position_id,
            expected_balance: collateral_before - WITHDRAW_AMOUNT.into(),
        );
    // The request is recorded as processed exactly like a signed withdrawal.
    assert_eq!(request_status(@state, request_hash), RequestStatus::PROCESSED);

    let events = state
        .facade
        .event_info
        .get_events()
        .emitted_by(state.facade.perpetuals_contract)
        .events;
    assert_withdraw_event_with_expected(
        spied_event: events[events.len() - 1],
        position_id: user.position_id,
        recipient: MIGRATION_RECIPIENT(),
        collateral_id: state.facade.collateral_id,
        token_address: token_state.address,
        amount: WITHDRAW_AMOUNT,
        expiration: args.expiration,
        withdraw_request_hash: request_hash,
        salt: args.salt,
        interest_amount: 0,
    );
}

#[test]
#[should_panic(expected: 'REQUEST_ALREADY_PROCESSED')]
fn test_migration_withdrawal_cannot_be_replayed() {
    let (mut state, user) = setup_funded_user();
    let args = base_collateral_args(@state, user, MIGRATION_RECIPIENT(), salt: 1);

    operator_withdraw(ref state, args);
    operator_withdraw(ref state, args);
}

#[test]
fn test_migration_withdrawal_with_different_salts() {
    let (mut state, user) = setup_funded_user();
    let collateral_before = state.facade.get_position_collateral_balance(user.position_id);

    operator_withdraw(
        ref state, base_collateral_args(@state, user, MIGRATION_RECIPIENT(), salt: 1),
    );
    operator_withdraw(
        ref state, base_collateral_args(@state, user, MIGRATION_RECIPIENT(), salt: 2),
    );

    state
        .facade
        .validate_collateral_balance(
            position_id: user.position_id,
            expected_balance: collateral_before - (2 * WITHDRAW_AMOUNT).into(),
        );
}

#[test]
fn test_migration_withdrawal_with_pending_signed_request() {
    let (mut state, user) = setup_funded_user();
    let args = base_collateral_args(@state, user, MIGRATION_RECIPIENT(), salt: 1);
    let request_hash = withdraw_hash(user, args);

    // The user has already signed a request for the very same withdrawal.
    let signature = user.account.sign_message(message: request_hash);
    user.set_as_caller(state.facade.perpetuals_contract);
    perps(@state)
        .withdraw_request(
            :signature,
            collateral_id: args.collateral_id,
            recipient: args.recipient,
            position_id: args.position_id,
            amount: args.amount,
            expiration: args.expiration,
            salt: args.salt,
        );
    assert_eq!(request_status(@state, request_hash), RequestStatus::PENDING);

    operator_withdraw(ref state, args);
    assert_eq!(request_status(@state, request_hash), RequestStatus::PROCESSED);
}

#[test]
#[should_panic(expected: 'REQUEST_NOT_REGISTERED')]
fn test_withdrawal_without_request_to_other_recipient_fails() {
    let (mut state, user) = setup_funded_user();

    // Any recipient other than the whitelisted one still needs the signed request.
    operator_withdraw(ref state, base_collateral_args(@state, user, user.account.address, salt: 1));
}

#[test]
#[should_panic(expected: 'SIGNED_TX_EXPIRED')]
fn test_migration_withdrawal_still_validates_expiration() {
    let (mut state, user) = setup_funded_user();
    let args = base_collateral_args(@state, user, MIGRATION_RECIPIENT(), salt: 1);
    start_cheat_block_timestamp_global(block_timestamp: args.expiration.seconds + 1);

    operator_withdraw(ref state, args);
}

#[test]
#[should_panic(expected: "POSITION_NOT_HEALTHY_NOR_HEALTHIER")]
fn test_migration_withdrawal_still_validates_position_health() {
    let (mut state, user) = setup_funded_user();
    let mut args = base_collateral_args(@state, user, MIGRATION_RECIPIENT(), salt: 1);
    args.amount = DEPOSIT_AMOUNT + 1;

    operator_withdraw(ref state, args);
}

#[test]
fn test_migration_withdrawal_of_spot_collateral() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let token = snforge_std::Token::STRK;
    let erc20_contract_address = token.contract_address();
    let asset_info = AssetInfoTrait::new_collateral(
        asset_name: 'COL',
        risk_factor_data: RiskFactorTiers {
            tiers: array![10].span(), first_tier_boundary: MAX_U128, tier_size: 1,
        },
        oracles_len: 1,
        :erc20_contract_address,
    );
    let asset_id: AssetId = asset_info.asset_id;
    state.facade.add_active_collateral(asset_info: @asset_info, initial_price: 100);

    let user = state.new_user_with_position();
    snforge_std::set_balance(target: user.account.address, new_balance: 5_000_000, :token);
    let deposit_info = state
        .facade
        .deposit_spot(
            depositor: user.account,
            :asset_id,
            position_id: user.position_id,
            quantized_amount: DEPOSIT_AMOUNT,
        );
    state.facade.process_deposit(:deposit_info);
    state.facade.set_treasury_protection_percent_for_token(erc20_contract_address, 100);

    let args = WithdrawArgs {
        recipient: MIGRATION_RECIPIENT(),
        position_id: user.position_id,
        collateral_id: asset_id,
        amount: WITHDRAW_AMOUNT,
        expiration: expiration(),
        salt: 1,
    };
    let request_hash = withdraw_hash(user, args);
    let token_state = TokenState {
        address: erc20_contract_address, owner: state.facade.token_state.owner,
    };
    let recipient_balance_before = token_state.balance_of(MIGRATION_RECIPIENT());
    let asset_balance_before = state.facade.get_position_asset_balance(user.position_id, asset_id);

    operator_withdraw(ref state, args);

    let quantum = IAssetsDispatcher { contract_address: state.facade.perpetuals_contract }
        .get_asset_config(:asset_id)
        .quantum;
    assert_eq!(
        token_state.balance_of(MIGRATION_RECIPIENT()),
        recipient_balance_before + (WITHDRAW_AMOUNT * quantum).into(),
    );
    state
        .facade
        .validate_asset_balance(
            position_id: user.position_id,
            :asset_id,
            expected_balance: asset_balance_before - WITHDRAW_AMOUNT.into(),
        );
    assert_eq!(request_status(@state, request_hash), RequestStatus::PROCESSED);
}
