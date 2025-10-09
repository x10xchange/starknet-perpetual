use perpetuals::core::components::operator_nonce::interface::IOperatorNonce;

use perpetuals::core::core::Core::SNIP12MetadataImpl;
use perpetuals::core::interface::ICore;
use perpetuals::core::types::transfer::TransferArgs;
use perpetuals::tests::constants::*;
// use perpetuals::tests::event_test_utils::{
//     assert_add_oracle_event_with_expected, assert_add_synthetic_event_with_expected,
//     assert_asset_activated_event_with_expected,
//     assert_deactivate_synthetic_asset_event_with_expected, assert_deleverage_event_with_expected,
//     assert_deposit_canceled_event_with_expected, assert_deposit_event_with_expected,
//     assert_deposit_processed_event_with_expected, assert_funding_tick_event_with_expected,
//     assert_liquidate_event_with_expected, assert_new_position_event_with_expected,
//     assert_price_tick_event_with_expected, assert_remove_oracle_event_with_expected,
//     assert_set_owner_account_event_with_expected, assert_set_public_key_event_with_expected,
//     assert_set_public_key_request_event_with_expected, assert_trade_event_with_expected,
//     assert_transfer_event_with_expected, assert_transfer_request_event_with_expected,
//     assert_update_synthetic_quorum_event_with_expected, assert_withdraw_event_with_expected,
//     assert_withdraw_request_event_with_expected,
// };
use perpetuals::tests::test_utils::{
    PerpetualsInitConfig, User, UserTrait,
    deposit_vault_share, init_position,
    init_position_zero_collateral,
    send_price_tick_for_vault_share,
    setup_state_with_pending_vault_share, validate_asset_balance,
};
use snforge_std::{test_address};
use starkware_utils::components::replaceability::interface::IReplaceable;
use starkware_utils::components::request_approvals::interface::{IRequestApprovals, RequestStatus};
use starkware_utils::components::roles::interface::IRoles;
use starkware_utils::constants::{HOUR, MAX_U128};
use starkware_utils::hash::message_hash::OffchainMessageHash;
use starkware_utils::math::abs::Abs;
use starkware_utils::storage::iterable_map::*;
use starkware_utils::time::time::{Time, Timestamp};
use starkware_utils_testing::test_utils::{
    Deployable, TokenTrait, assert_panic_with_error, assert_panic_with_felt_error,
    cheat_caller_address_once,
};
use crate::core::types::position::PositionId;


#[test]
fn test_successful_transfer_of_vault_share() {
    let cfg: PerpetualsInitConfig = Default::default();
    let mut state = setup_state_with_pending_vault_share(
        cfg: @cfg, token_state: @cfg.collateral_cfg.token_cfg.deploy(),
    );
    send_price_tick_for_vault_share(ref :state, cfg: @cfg, price: 12);
    let user1: User = UserTrait::new(position_id: POSITION_ID_1, key_pair: KEY_PAIR_1());
    let user2: User = UserTrait::new(position_id: POSITION_ID_2, key_pair: KEY_PAIR_1());
    init_position(cfg: @cfg, ref :state, user: user1);
    init_position(cfg: @cfg, ref :state, user: user2);

    deposit_vault_share(ref :state, cfg: @cfg, user: user1, number_of_shares: 2);

    validate_asset_balance(
        ref :state,
        position_id: user1.position_id,
        asset_id: cfg.vault_share_cfg.collateral_id,
        expected_balance: (2_u64 * cfg.vault_share_cfg.resolution_factor).into(),
    );

    validate_asset_balance(
        ref :state,
        position_id: user2.position_id,
        asset_id: cfg.vault_share_cfg.collateral_id,
        expected_balance: 0_u64.into(),
    );

    let transfer_amount = 1_u64 * cfg.vault_share_cfg.resolution_factor;

    let expiration = Time::now().add(delta: Time::days(1));
    let collateral_id = cfg.vault_share_cfg.collateral_id;
    let operator_nonce = state.get_operator_nonce();

    let transfer_args = TransferArgs {
        position_id: user1.position_id,
        recipient: user2.position_id,
        salt: 1234,
        expiration: expiration,
        collateral_id,
        amount: transfer_amount,
    };

    let msg_hash = transfer_args.get_message_hash(user1.get_public_key());
    let sender_signature = user1.sign_message(msg_hash);

    // Test:
    cheat_caller_address_once(contract_address: test_address(), caller_address: user1.address);
    state
        .transfer_request(
            signature: sender_signature,
            asset_id: collateral_id,
            recipient: transfer_args.recipient,
            position_id: transfer_args.position_id,
            amount: transfer_args.amount,
            expiration: transfer_args.expiration,
            salt: transfer_args.salt,
        );
    cheat_caller_address_once(contract_address: test_address(), caller_address: cfg.operator);
    state
        .transfer(
            :operator_nonce,
            asset_id: collateral_id,
            recipient: transfer_args.recipient,
            position_id: transfer_args.position_id,
            amount: transfer_args.amount,
            expiration: transfer_args.expiration,
            salt: transfer_args.salt,
        );

    validate_asset_balance(
        ref :state,
        position_id: user1.position_id,
        asset_id: cfg.vault_share_cfg.collateral_id,
        expected_balance: (1_u64 * cfg.vault_share_cfg.resolution_factor).into(),
    );

    validate_asset_balance(
        ref :state,
        position_id: user2.position_id,
        asset_id: cfg.vault_share_cfg.collateral_id,
        expected_balance: (1_u64 * cfg.vault_share_cfg.resolution_factor).into(),
    );
}


#[test]
#[should_panic(
    expected: "POSITION_NOT_HEALTHY_NOR_HEALTHIER position_id: PositionId { value: 22 } TV before 24000000, TR before 240000, TV after -24000000, TR after 240000",
)]
fn test_unsuccessful_transfer_of_vault_share_not_enough_balance() {
    let cfg: PerpetualsInitConfig = Default::default();
    let mut state = setup_state_with_pending_vault_share(
        cfg: @cfg, token_state: @cfg.collateral_cfg.token_cfg.deploy(),
    );
    send_price_tick_for_vault_share(ref :state, cfg: @cfg, price: 12);
    let user1: User = UserTrait::new(position_id: PositionId { value: 22 }, key_pair: KEY_PAIR_1());
    let user2: User = UserTrait::new(position_id: POSITION_ID_2, key_pair: KEY_PAIR_1());
    init_position_zero_collateral(cfg: @cfg, ref :state, user: user1);
    init_position_zero_collateral(cfg: @cfg, ref :state, user: user2);

    deposit_vault_share(ref :state, cfg: @cfg, user: user1, number_of_shares: 2);

    validate_asset_balance(
        ref :state,
        position_id: user1.position_id,
        asset_id: cfg.vault_share_cfg.collateral_id,
        expected_balance: (2_u64 * cfg.vault_share_cfg.resolution_factor).into(),
    );

    validate_asset_balance(
        ref :state,
        position_id: user2.position_id,
        asset_id: cfg.vault_share_cfg.collateral_id,
        expected_balance: 0_u64.into(),
    );

    let transfer_amount = 4_u64 * cfg.vault_share_cfg.resolution_factor;

    let expiration = Time::now().add(delta: Time::days(1));
    let collateral_id = cfg.vault_share_cfg.collateral_id;
    let operator_nonce = state.get_operator_nonce();

    let transfer_args = TransferArgs {
        position_id: user1.position_id,
        recipient: user2.position_id,
        salt: 1234,
        expiration: expiration,
        collateral_id,
        amount: transfer_amount,
    };

    let msg_hash = transfer_args.get_message_hash(user1.get_public_key());
    let sender_signature = user1.sign_message(msg_hash);

    // Test:
    cheat_caller_address_once(contract_address: test_address(), caller_address: user1.address);
    state
        .transfer_request(
            signature: sender_signature,
            asset_id: collateral_id,
            recipient: transfer_args.recipient,
            position_id: transfer_args.position_id,
            amount: transfer_args.amount,
            expiration: transfer_args.expiration,
            salt: transfer_args.salt,
        );
    cheat_caller_address_once(contract_address: test_address(), caller_address: cfg.operator);
    state
        .transfer(
            :operator_nonce,
            asset_id: collateral_id,
            recipient: transfer_args.recipient,
            position_id: transfer_args.position_id,
            amount: transfer_args.amount,
            expiration: transfer_args.expiration,
            salt: transfer_args.salt,
        );
}
