use core::byte_array::ByteArrayTrait;
use core::hash::{HashStateExTrait, HashStateTrait};
use core::num::traits::{Pow, Zero};
use core::poseidon::PoseidonTrait;
use openzeppelin::interfaces::erc20::{IERC20, IERC20Dispatcher, IERC20DispatcherTrait};
use openzeppelin::interfaces::erc4626::{IERC4626, IERC4626Dispatcher, IERC4626DispatcherTrait};
use openzeppelin::presets::interfaces::{
    AccountUpgradeableABIDispatcher, AccountUpgradeableABIDispatcherTrait,
};
use openzeppelin_testing::deployment::declare_and_deploy;
use openzeppelin_testing::signing::StarkKeyPair;
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
use perpetuals::core::core::Core;
use perpetuals::core::core::Core::{InternalCoreFunctions, SNIP12MetadataImpl};
use perpetuals::core::errors::WITHDRAW_EXPIRED;
use perpetuals::core::interface::{ICore, ICoreSafeDispatcher, ICoreSafeDispatcherTrait};
use perpetuals::core::types::asset::{AssetId, AssetStatus};
use perpetuals::core::types::balance::Balance;
use perpetuals::core::types::funding::{FUNDING_SCALE, FundingIndex, FundingTick};
use perpetuals::core::types::order::Order;
use perpetuals::core::types::position::{
    POSITION_VERSION, PositionDiff, PositionId, PositionMutableTrait,
};
use perpetuals::core::types::price::{
    PRICE_SCALE, Price, PriceTrait, SignedPrice, convert_oracle_to_perps_price,
};
use perpetuals::core::types::risk_factor::{RiskFactor, RiskFactorTrait};
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
    check_synthetic_asset, deploy_account, init_by_dispatcher, init_position,
    init_position_with_owner, initialized_contract_state, setup_state_with_active_asset,
    setup_state_with_pending_asset, setup_state_with_pending_vault_share, validate_asset_balance,
    validate_balance,
};
use snforge_std::cheatcodes::events::{EventSpyTrait, EventsFilterTrait};
use snforge_std::signature::stark_curve::{StarkCurveKeyPairImpl, StarkCurveSignerImpl};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, start_cheat_block_timestamp_global, test_address,
};
use starknet::ContractAddress;
use starknet::storage::{
    StorageMapReadAccess, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess,
};
use starkware_utils::components::replaceability::interface::IReplaceable;
use starkware_utils::components::request_approvals::interface::{IRequestApprovals, RequestStatus};
use starkware_utils::components::roles::interface::{
    IRoles, IRolesDispatcher, IRolesDispatcherTrait,
};
use starkware_utils::constants::{HOUR, MAX_U128, TWO_POW_32, TWO_POW_40};
use starkware_utils::hash::message_hash::OffchainMessageHash;
use starkware_utils::math::abs::Abs;
use starkware_utils::signature::stark::Signature;
use starkware_utils::storage::iterable_map::*;
use starkware_utils::time::time::{Time, TimeDelta, Timestamp};
use starkware_utils_testing::test_utils::{
    Deployable, TokenConfig, TokenState, TokenTrait, assert_panic_with_error,
    assert_panic_with_felt_error, cheat_caller_address_once,
};
use crate::core::components::vault::protocol_vault::{
    IProtocolVault, IProtocolVaultDispatcher, IProtocolVaultDispatcherTrait, ProtocolVault,
};
use crate::tests::event_test_utils::assert_add_spot_event_with_expected;


#[derive(Drop)]
pub struct DeployedVault {
    pub contract_address: ContractAddress,
    pub erc20: IERC20Dispatcher,
    pub erc4626: IERC4626Dispatcher,
    pub protocol_vault: IProtocolVaultDispatcher,
}

pub fn deploy_protocol_vault_with_dispatcher(
    perps_address: ContractAddress,
    vault_position_id: PositionId,
    usdc_token_state: TokenState,
    initial_receiver: ContractAddress,
) -> DeployedVault {
    let owning_account = deploy_account(StarkCurveKeyPairImpl::generate());
    usdc_token_state.fund(owning_account, 1_000_000_000_u128);
    let mut calldata = ArrayTrait::new();
    let name: ByteArray = "Perpetuals Protocol Vault";
    let symbol: ByteArray = "PPV";
    name.serialize(ref calldata);
    symbol.serialize(ref calldata);
    usdc_token_state.address.serialize(ref calldata);
    perps_address.serialize(ref calldata);
    vault_position_id.value.serialize(ref calldata);
    initial_receiver.serialize(ref calldata);
    let contract = snforge_std::declare("ProtocolVault").unwrap().contract_class();
    let (contract_address, _) = contract.deploy(@calldata).unwrap();
    let erc20 = IERC20Dispatcher { contract_address: contract_address };
    let erc4626 = IERC4626Dispatcher { contract_address: contract_address };
    let protocol_vault = IProtocolVaultDispatcher { contract_address: contract_address };
    DeployedVault { contract_address: contract_address, erc20, erc4626, protocol_vault }
}

#[test]
#[feature("safe_dispatcher")]
fn test_protocol_vault_initialisation_logic() {
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

    let deployed_vault = deploy_protocol_vault_with_dispatcher(
        perps_address: perps_contract_address,
        vault_position_id: vault_user.position_id,
        usdc_token_state: usdc_token_state,
        initial_receiver: vault_user.address,
    );

    //state setup complete
    // check owning vault is set correctly
    assert_eq!(
        deployed_vault.protocol_vault.get_owning_position_id(), vault_user.position_id.value.into(),
    );

    //check total assets == TV of vault position
    let total_assets = deployed_vault.erc4626.total_assets();
    let tv_tr_of_vault = position_dispatcher.get_position_tv_tr(vault_user.position_id);
    assert_eq!(total_assets, tv_tr_of_vault.total_value.abs().into());

    let balance_of_perps_contract_before = usdc_token_state
        .balance_of(account: perps_contract_address);

    //simulate perps contract approving a transfer
    usdc_token_state
        .approve(
            owner: perps_contract_address,
            spender: deployed_vault.contract_address,
            amount: 500_u128,
        );
    cheat_caller_address_once(
        contract_address: deployed_vault.contract_address, caller_address: perps_contract_address,
    );
    //simulate the perps contract calling deposit
    let shares_minted = deployed_vault
        .erc4626
        .deposit(assets: 500_u256, receiver: perps_contract_address);

    // as there is TV = VAULT_DEPOSIT_AMOUNT and share count = VAULT_DEPOSIT_AMOUNT
    // depositing 500 assets should mint 500 shares
    println!("Shares minted on deposit: {}", shares_minted);
    assert_eq!(shares_minted, 500_u256);

    let balance_of_perps_contract_after = usdc_token_state
        .balance_of(account: perps_contract_address);

    // the vault should send back the same amount of tokens it received
    assert_eq!(balance_of_perps_contract_before, balance_of_perps_contract_after);

    //the perps contract should receive the minted shares
    let balance_of_vault_shares = deployed_vault.erc20.balance_of(perps_contract_address);
    assert_eq!(balance_of_vault_shares, shares_minted);
}


#[test]
#[feature("safe_dispatcher")]
#[should_panic(expected: 'Result::unwrap failed.')]
fn test_protocol_vault_fails_when_position_does_not_exist() {
    // Setup:
    let cfg: PerpetualsInitConfig = Default::default();
    let usdc_token_state = cfg.collateral_cfg.token_cfg.deploy();
    let perps_contract_address = init_by_dispatcher(cfg: @cfg, token_state: @usdc_token_state);
    let vault_user: User = Default::default();

    deploy_protocol_vault_with_dispatcher(
        perps_address: perps_contract_address,
        vault_position_id: vault_user.position_id,
        usdc_token_state: usdc_token_state,
        initial_receiver: vault_user.address,
    );
}

#[test]
#[feature("safe_dispatcher")]
#[should_panic(expected: 'Result::unwrap failed.')]
fn test_protocol_vault_fails_when_position_has_zero_tv() {
    // Setup:
    let cfg: PerpetualsInitConfig = Default::default();
    let usdc_token_state = cfg.collateral_cfg.token_cfg.deploy();
    let perps_contract_address = init_by_dispatcher(cfg: @cfg, token_state: @usdc_token_state);
    let vault_user: User = Default::default();
    let position_dispatcher = IPositionsDispatcher { contract_address: perps_contract_address };

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

    deploy_protocol_vault_with_dispatcher(
        perps_address: perps_contract_address,
        vault_position_id: vault_user.position_id,
        usdc_token_state: usdc_token_state,
        initial_receiver: vault_user.address,
    );
}
