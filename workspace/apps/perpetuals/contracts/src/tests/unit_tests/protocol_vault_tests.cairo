use core::byte_array::{ByteArray, ByteArrayTrait};
use core::num::traits::{Pow, Zero};
use openzeppelin::interfaces::erc4626::{IERC4626, IERC4626Dispatcher};
use openzeppelin::token::erc20::extensions::erc4626::ERC4626Component::AssetsManagementTrait;
use perpetuals::core::components::assets::interface::{
    IAssets, IAssetsDispatcher, IAssetsDispatcherTrait, IAssetsSafeDispatcher,
    IAssetsSafeDispatcherTrait,
};
use perpetuals::core::components::deposit::Deposit::deposit_hash;
use perpetuals::core::components::deposit::interface::{
    DepositStatus, IDeposit, IDepositDispatcher, IDepositDispatcherTrait, IDepositSafeDispatcher,
    IDepositSafeDispatcherTrait,
};
use perpetuals::core::components::operator_nonce::interface::IOperatorNonce;
use perpetuals::core::components::positions::Positions::{
    FEE_POSITION, INSURANCE_FUND_POSITION, InternalTrait as PositionsInternal,
};
use perpetuals::core::components::positions::errors::POSITION_DOESNT_EXIST;
use perpetuals::core::components::positions::interface::{
    IPositions, IPositionsDispatcher, IPositionsDispatcherTrait, IPositionsSafeDispatcher,
    IPositionsSafeDispatcherTrait,
};
use perpetuals::core::core::Core::SNIP12MetadataImpl;
use perpetuals::core::errors::WITHDRAW_EXPIRED;
use perpetuals::core::interface::{ICore, ICoreSafeDispatcher, ICoreSafeDispatcherTrait};
use perpetuals::core::types::asset::AssetStatus;
use perpetuals::core::types::funding::{FUNDING_SCALE, FundingIndex, FundingTick};
use perpetuals::core::types::order::Order;
use perpetuals::core::types::position::{POSITION_VERSION, PositionMutableTrait};
use perpetuals::core::types::price::{
    PRICE_SCALE, PriceTrait, SignedPrice, convert_oracle_to_perps_price,
};
use perpetuals::core::types::set_owner_account::SetOwnerAccountArgs;
use perpetuals::core::types::set_public_key::SetPublicKeyArgs;
use perpetuals::core::types::transfer::TransferArgs;
use perpetuals::core::types::withdraw::WithdrawArgs;
use perpetuals::tests::constants::*;
use perpetuals::tests::event_test_utils::{
    assert_add_oracle_event_with_expected, assert_add_synthetic_event_with_expected,
    assert_asset_activated_event_with_expected,
    assert_deactivate_synthetic_asset_event_with_expected, assert_deleverage_event_with_expected,
    assert_deposit_canceled_event_with_expected, assert_deposit_event_with_expected,
    assert_deposit_processed_event_with_expected, assert_funding_tick_event_with_expected,
    assert_liquidate_event_with_expected, assert_new_position_event_with_expected,
    assert_price_tick_event_with_expected, assert_remove_oracle_event_with_expected,
    assert_set_owner_account_event_with_expected, assert_set_public_key_event_with_expected,
    assert_set_public_key_request_event_with_expected, assert_trade_event_with_expected,
    assert_transfer_event_with_expected, assert_transfer_request_event_with_expected,
    assert_update_synthetic_quorum_event_with_expected, assert_withdraw_event_with_expected,
    assert_withdraw_request_event_with_expected,
};
use perpetuals::tests::test_utils::{
    Oracle, OracleTrait, PerpetualsInitConfig, User, UserTrait, add_synthetic_to_position,
    check_synthetic_asset, init_by_dispatcher, init_position, init_position_with_owner,
    initialized_contract_state, setup_state_with_active_asset, setup_state_with_pending_asset,
    setup_state_with_pending_vault_share, validate_asset_balance, validate_balance,
};
use snforge_std::cheatcodes::events::{EventSpyTrait, EventsFilterTrait};
use snforge_std::{start_cheat_block_timestamp_global, test_address};
use starknet::storage::{StoragePathEntry, StoragePointerReadAccess};
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
use crate::core::components::vault::protocol_vault::{IProtocolVault, ProtocolVault};
use crate::tests::event_test_utils::assert_add_spot_event_with_expected;

#[test]
#[feature("safe_dispatcher")]
fn test_protocol_vault() {
    // Setup:
    let cfg: PerpetualsInitConfig = Default::default();
    let token_state = cfg.collateral_cfg.token_cfg.deploy();
    let contract_address = init_by_dispatcher(cfg: @cfg, token_state: @token_state);

    let dispatcher = ICoreSafeDispatcher { contract_address };
    let asset_dispatcher = IAssetsDispatcher { contract_address };
    let deposit_dispatcher = IDepositDispatcher { contract_address };
    let position_dispatcher = IPositionsDispatcher { contract_address };

    let user_a: User = Default::default();
    let collateral_id = cfg.collateral_cfg.collateral_id;
    let synthetic_id_1 = SYNTHETIC_ASSET_ID_1();
    let synthetic_id_2 = SYNTHETIC_ASSET_ID_2();

    let risk_factor_first_tier_boundary = MAX_U128;
    let risk_factor_tier_size = 1;
    let risk_factor_tiers = array![10].span();
    let quorum = 1_u8;
    let resolution_factor = 2_000_000_000;

    let oracle_price: u128 = ORACLE_PRICE;
    let asset_name = 'ASSET_NAME';
    let oracle1_name = 'ORCL1';
    let oracle1 = Oracle { oracle_name: oracle1_name, asset_name, key_pair: KEY_PAIR_1() };
    let old_time: u64 = Time::now().into();
    let new_time = Time::now().add(delta: MAX_ORACLE_PRICE_VALIDITY);
    start_cheat_block_timestamp_global(block_timestamp: new_time.into());

    // Add synthetic assets.
    cheat_caller_address_once(:contract_address, caller_address: cfg.app_governor);
    asset_dispatcher
        .add_synthetic_asset(
            asset_id: synthetic_id_1,
            :risk_factor_tiers,
            :risk_factor_first_tier_boundary,
            :risk_factor_tier_size,
            :quorum,
            :resolution_factor,
        );

    cheat_caller_address_once(:contract_address, caller_address: cfg.app_governor);
    asset_dispatcher
        .add_synthetic_asset(
            asset_id: synthetic_id_2,
            :risk_factor_tiers,
            :risk_factor_first_tier_boundary,
            :risk_factor_tier_size,
            :quorum,
            :resolution_factor,
        );

    // Add to oracle.
    cheat_caller_address_once(:contract_address, caller_address: cfg.app_governor);
    asset_dispatcher
        .add_oracle_to_asset(
            asset_id: synthetic_id_1,
            oracle_public_key: oracle1.key_pair.public_key,
            oracle_name: oracle1_name,
            :asset_name,
        );

    cheat_caller_address_once(:contract_address, caller_address: cfg.app_governor);
    asset_dispatcher
        .add_oracle_to_asset(
            asset_id: synthetic_id_2,
            oracle_public_key: oracle1.key_pair.public_key,
            oracle_name: oracle1_name,
            :asset_name,
        );

    // Activate synthetic assets.
    cheat_caller_address_once(:contract_address, caller_address: cfg.operator);
    asset_dispatcher
        .price_tick(
            operator_nonce: 0,
            asset_id: synthetic_id_1,
            :oracle_price,
            signed_prices: [
                oracle1.get_signed_price(:oracle_price, timestamp: old_time.try_into().unwrap())
            ]
                .span(),
        );

    cheat_caller_address_once(:contract_address, caller_address: cfg.operator);
    asset_dispatcher
        .price_tick(
            operator_nonce: 1,
            asset_id: synthetic_id_2,
            :oracle_price,
            signed_prices: [
                oracle1.get_signed_price(:oracle_price, timestamp: old_time.try_into().unwrap())
            ]
                .span(),
        );

    // Add positions, so signatures can be checked.
    cheat_caller_address_once(:contract_address, caller_address: cfg.operator);
    position_dispatcher
        .new_position(
            operator_nonce: 2,
            position_id: POSITION_ID_1,
            owner_public_key: KEY_PAIR_1().public_key,
            owner_account: Zero::zero(),
            owner_protection_enabled: true,
        );

    cheat_caller_address_once(:contract_address, caller_address: cfg.operator);
    position_dispatcher
        .new_position(
            operator_nonce: 3,
            position_id: POSITION_ID_2,
            owner_public_key: KEY_PAIR_2().public_key,
            owner_account: Zero::zero(),
            owner_protection_enabled: true,
        );

    // Deposit money for users.
    let VAULT_DEPOSIT_AMOUNT = 1000_u64;
    token_state.fund(recipient: user_a.address, amount: USER_INIT_BALANCE.try_into().unwrap());
    token_state
        .approve(
            owner: user_a.address,
            spender: contract_address,
            amount: VAULT_DEPOSIT_AMOUNT.into() * cfg.collateral_cfg.quantum.into(),
        );

    cheat_caller_address_once(:contract_address, caller_address: user_a.address);
    deposit_dispatcher
        .deposit(
            asset_id: cfg.collateral_cfg.collateral_id,
            position_id: user_a.position_id,
            quantized_amount: VAULT_DEPOSIT_AMOUNT,
            salt: user_a.salt_counter,
        );

    cheat_caller_address_once(:contract_address, caller_address: cfg.operator);
    deposit_dispatcher
        .process_deposit(
            operator_nonce: 4,
            depositor: user_a.address,
            asset_id: cfg.collateral_cfg.collateral_id,
            position_id: user_a.position_id,
            quantized_amount: VAULT_DEPOSIT_AMOUNT,
            salt: user_a.salt_counter,
        );

    let mut state = ProtocolVault::contract_state_for_testing();
    ProtocolVault::constructor(
        ref state,
        name: "XTN_VAULT",
        symbol: "XTN",
        pnl_collateral_contract: token_state.address,
        perps_contract: contract_address,
        owning_position_id: user_a.position_id.value.into(),
        initial_supply: VAULT_DEPOSIT_AMOUNT.into(),
        recipient: user_a.address,
    );

    assert_eq!(state.get_owning_position_id(), user_a.position_id.value.into());

    let total_assets = state.total_assets();
    println!("Total assets in vault after init: {}", total_assets);

    //simulate perps contract approving a transfer
    token_state.approve(owner: contract_address, spender: test_address(), amount: 500_u128);
    cheat_caller_address_once(contract_address: test_address(), caller_address: contract_address);
    let shares_minted = state.deposit(assets: 500_u256, receiver: user_a.address);

    // as there is TV = VAULT_DEPOSIT_AMOUNT and share count = VAULT_DEPOSIT_AMOUNT
    // depositing 500 assets should mint 500 shares
    println!("Shares minted on deposit: {}", shares_minted);
    assert_eq!(shares_minted, 500_u256);
}
