use core::byte_array::{ByteArray, ByteArrayTrait};
use core::num::traits::{Pow, Zero};
use openzeppelin::interfaces::erc20::{IERC20, IERC20Dispatcher};
use openzeppelin::interfaces::erc4626::{IERC4626, IERC4626Dispatcher};
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
use perpetuals::core::types::position::{POSITION_VERSION, PositionId, PositionMutableTrait};
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
    Deployable, TokenState, TokenTrait, assert_panic_with_error, assert_panic_with_felt_error,
    cheat_caller_address_once,
};
use crate::core::components::vault::protocol_vault::{IProtocolVault, ProtocolVault};
use crate::tests::event_test_utils::assert_add_spot_event_with_expected;


#[test]
#[feature("safe_dispatcher")]
fn test_protocol_vault() {
    // Setup:
    let cfg: PerpetualsInitConfig = Default::default();
    let usdc_token_state = cfg.collateral_cfg.token_cfg.deploy();
    let perps_contract_address = init_by_dispatcher(cfg: @cfg, token_state: @usdc_token_state);

    let dispatcher = ICoreSafeDispatcher { contract_address: perps_contract_address };
    let asset_dispatcher = IAssetsDispatcher { contract_address: perps_contract_address };
    let deposit_dispatcher = IDepositDispatcher { contract_address: perps_contract_address };
    let position_dispatcher = IPositionsDispatcher { contract_address: perps_contract_address };

    let vault_user: User = Default::default();
    let depositing_user = UserTrait::new(
        position_id: PositionId { value: 21 }, key_pair: KEY_PAIR_1(),
    );

    // let collateral_id = cfg.collateral_cfg.collateral_id;
    // let synthetic_id_1 = SYNTHETIC_ASSET_ID_1();
    // let synthetic_id_2 = SYNTHETIC_ASSET_ID_2();

    // let risk_factor_first_tier_boundary = MAX_U128;
    // let risk_factor_tier_size = 1;
    // let risk_factor_tiers = array![10].span();
    // let quorum = 1_u8;
    // let resolution_factor = 2_000_000_000;

    // let oracle_price: u128 = ORACLE_PRICE;
    // let asset_name = 'ASSET_NAME';
    // let oracle1_name = 'ORCL1';
    // let oracle1 = Oracle { oracle_name: oracle1_name, asset_name, key_pair: KEY_PAIR_1() };
    // let old_time: u64 = Time::now().into();
    // let new_time = Time::now().add(delta: MAX_ORACLE_PRICE_VALIDITY);
    // start_cheat_block_timestamp_global(block_timestamp: new_time.into());

    // // Add synthetic assets.
    // cheat_caller_address_once(
    //     contract_address: perps_contract_address, caller_address: cfg.app_governor,
    // );
    // asset_dispatcher
    //     .add_synthetic_asset(
    //         asset_id: synthetic_id_1,
    //         :risk_factor_tiers,
    //         :risk_factor_first_tier_boundary,
    //         :risk_factor_tier_size,
    //         :quorum,
    //         :resolution_factor,
    //     );

    // cheat_caller_address_once(
    //     contract_address: perps_contract_address, caller_address: cfg.app_governor,
    // );
    // asset_dispatcher
    //     .add_synthetic_asset(
    //         asset_id: synthetic_id_2,
    //         :risk_factor_tiers,
    //         :risk_factor_first_tier_boundary,
    //         :risk_factor_tier_size,
    //         :quorum,
    //         :resolution_factor,
    //     );

    // Add to oracle.
    // cheat_caller_address_once(
    //     contract_address: perps_contract_address, caller_address: cfg.app_governor,
    // );
    // asset_dispatcher
    //     .add_oracle_to_asset(
    //         asset_id: synthetic_id_1,
    //         oracle_public_key: oracle1.key_pair.public_key,
    //         oracle_name: oracle1_name,
    //         :asset_name,
    //     );

    // cheat_caller_address_once(
    //     contract_address: perps_contract_address, caller_address: cfg.app_governor,
    // );
    // asset_dispatcher
    //     .add_oracle_to_asset(
    //         asset_id: synthetic_id_2,
    //         oracle_public_key: oracle1.key_pair.public_key,
    //         oracle_name: oracle1_name,
    //         :asset_name,
    //     );

    // Activate synthetic assets.
    // cheat_caller_address_once(
    //     contract_address: perps_contract_address, caller_address: cfg.operator,
    // );
    // asset_dispatcher
    //     .price_tick(
    //         operator_nonce: 0,
    //         asset_id: synthetic_id_1,
    //         :oracle_price,
    //         signed_prices: [
    //             oracle1.get_signed_price(:oracle_price, timestamp: old_time.try_into().unwrap())
    //         ]
    //             .span(),
    //     );

    // cheat_caller_address_once(
    //     contract_address: perps_contract_address, caller_address: cfg.operator,
    // );
    // asset_dispatcher
    //     .price_tick(
    //         operator_nonce: 1,
    //         asset_id: synthetic_id_2,
    //         :oracle_price,
    //         signed_prices: [
    //             oracle1.get_signed_price(:oracle_price, timestamp: old_time.try_into().unwrap())
    //         ]
    //             .span(),
    //     );

    // Add positions, so signatures can be checked.
    cheat_caller_address_once(
        contract_address: perps_contract_address, caller_address: cfg.operator,
    );
    position_dispatcher
        .new_position(
            operator_nonce: 0,
            position_id: vault_user.position_id,
            owner_public_key: vault_user.get_public_key(),
            owner_account: Zero::zero(),
            owner_protection_enabled: true,
        );

    cheat_caller_address_once(
        contract_address: perps_contract_address, caller_address: cfg.operator,
    );
    position_dispatcher
        .new_position(
            operator_nonce: 1,
            position_id: depositing_user.position_id,
            owner_public_key: depositing_user.get_public_key(),
            owner_account: Zero::zero(),
            owner_protection_enabled: true,
        );

    // Deposit money for users.
    let VAULT_DEPOSIT_AMOUNT = 1000_u64;
    usdc_token_state
        .fund(recipient: vault_user.address, amount: USER_INIT_BALANCE.try_into().unwrap());
    usdc_token_state
        .approve(
            owner: vault_user.address,
            spender: perps_contract_address,
            amount: VAULT_DEPOSIT_AMOUNT.into() * cfg.collateral_cfg.quantum.into(),
        );

    usdc_token_state
        .fund(recipient: depositing_user.address, amount: USER_INIT_BALANCE.try_into().unwrap());
    usdc_token_state
        .approve(
            owner: depositing_user.address,
            spender: perps_contract_address,
            amount: VAULT_DEPOSIT_AMOUNT.into() * cfg.collateral_cfg.quantum.into(),
        );
    // deposit into vault
    cheat_caller_address_once(
        contract_address: perps_contract_address, caller_address: vault_user.address,
    );
    deposit_dispatcher
        .deposit(
            asset_id: cfg.collateral_cfg.collateral_id,
            position_id: vault_user.position_id,
            quantized_amount: VAULT_DEPOSIT_AMOUNT,
            salt: vault_user.salt_counter,
        );
    cheat_caller_address_once(
        contract_address: perps_contract_address, caller_address: cfg.operator,
    );
    deposit_dispatcher
        .process_deposit(
            operator_nonce: 2,
            depositor: vault_user.address,
            asset_id: cfg.collateral_cfg.collateral_id,
            position_id: vault_user.position_id,
            quantized_amount: VAULT_DEPOSIT_AMOUNT,
            salt: vault_user.salt_counter,
        );

    // deposit into user position
    cheat_caller_address_once(
        contract_address: perps_contract_address, caller_address: depositing_user.address,
    );
    deposit_dispatcher
        .deposit(
            asset_id: cfg.collateral_cfg.collateral_id,
            position_id: depositing_user.position_id,
            quantized_amount: VAULT_DEPOSIT_AMOUNT,
            salt: depositing_user.salt_counter,
        );

    cheat_caller_address_once(
        contract_address: perps_contract_address, caller_address: cfg.operator,
    );
    deposit_dispatcher
        .process_deposit(
            operator_nonce: 3,
            depositor: depositing_user.address,
            asset_id: cfg.collateral_cfg.collateral_id,
            position_id: depositing_user.position_id,
            quantized_amount: VAULT_DEPOSIT_AMOUNT,
            salt: depositing_user.salt_counter,
        );

    let mut state = ProtocolVault::contract_state_for_testing();
    ProtocolVault::constructor(
        ref state,
        name: "XTN_VAULT",
        symbol: "XTN",
        pnl_collateral_contract: usdc_token_state.address,
        perps_contract: perps_contract_address,
        owning_position_id: vault_user.position_id.value.into(),
        initial_supply: VAULT_DEPOSIT_AMOUNT.into(),
        recipient: vault_user.address,
    );

    //state setup complete
    // check owning vault is set correctly
    assert_eq!(state.get_owning_position_id(), vault_user.position_id.value.into());

    //check total assets == TV of vault position
    let total_assets = state.total_assets();
    let tv_tr_of_vault = position_dispatcher.get_position_tv_tr(vault_user.position_id);
    assert_eq!(total_assets, tv_tr_of_vault.total_value.abs().into());

    let balance_of_perps_contract_before = usdc_token_state
        .balance_of(account: perps_contract_address);

    //simulate perps contract approving a transfer
    usdc_token_state
        .approve(owner: perps_contract_address, spender: test_address(), amount: 500_u128);
    cheat_caller_address_once(
        contract_address: test_address(), caller_address: perps_contract_address,
    );
    //simulate the perps contract calling deposit
    let shares_minted = state.deposit(assets: 500_u256, receiver: perps_contract_address);

    // as there is TV = VAULT_DEPOSIT_AMOUNT and share count = VAULT_DEPOSIT_AMOUNT
    // depositing 500 assets should mint 500 shares
    println!("Shares minted on deposit: {}", shares_minted);
    assert_eq!(shares_minted, 500_u256);

    let balance_of_perps_contract_after = usdc_token_state
        .balance_of(account: perps_contract_address);

    // the vault should send back the same amount of tokens it received
    assert_eq!(balance_of_perps_contract_before, balance_of_perps_contract_after);

    //the perps contract should receive the minted shares
    let balance_of_vault_shares = state.balance_of(perps_contract_address);
    assert_eq!(balance_of_vault_shares, shares_minted);
}
