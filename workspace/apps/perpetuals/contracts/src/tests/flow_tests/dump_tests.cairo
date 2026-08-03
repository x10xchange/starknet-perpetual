//! Tests for the state-export ("dump") surface: `IDump` on `Core` and
//! `IDump` + `IDumpExtra` on the storage-compatible `DumpCore`
//! class swapped in via `replace_to`.
//!
//! Coverage:
//! - Raw storage addresses of Core's contract-level fields are unchanged by
//!   hosting them in the shared `CoreFieldsComponent` (they must stay at
//!   `sn_keccak(<member_name>)`, the addresses of the deployed contract).
//! - Full round trip: populate a live Core through normal entrypoints,
//!   `replace_to` DumpCore, export everything, assert every exported
//!   value, `replace_to` back to Core, and verify trading still works.
//! - Deactivated synthetics stay in `export_assets` (they are enumerated from
//!   `timely_data`, which deactivation does not touch).

use core::num::traits::Zero;
use perpetuals::core::components::assets::assets_manager::{
    IAssetsExternalDispatcher, IAssetsExternalDispatcherTrait,
};
use perpetuals::core::components::assets::interface::{
    AssetDump, IAssetsDispatcher, IAssetsDispatcherTrait,
};
use perpetuals::core::components::deposit::deposit_manager::deposit_hash;
use perpetuals::core::components::deposit::interface::{
    DepositStatus, IDepositDispatcher, IDepositDispatcherTrait,
};
use perpetuals::core::components::exchange_time::interface::{
    IExchangeTimeDispatcher, IExchangeTimeDispatcherTrait,
};
use perpetuals::core::components::external_components::interface::{
    EXTERNAL_COMPONENT_ASSETS, EXTERNAL_COMPONENT_VAULT,
};
use perpetuals::core::components::operator_nonce::interface::{
    IOperatorNonceDispatcher, IOperatorNonceDispatcherTrait,
};
use perpetuals::core::components::positions::interface::PositionDump;
use perpetuals::core::dump::{
    IDumpDispatcher, IDumpDispatcherTrait, IDumpExtraDispatcher, IDumpExtraDispatcherTrait, KeySets,
};
use perpetuals::core::interface::{ICoreDispatcher, ICoreDispatcherTrait};
use perpetuals::core::types::asset::{AssetId, AssetStatus};
use perpetuals::core::types::position::PositionId;
use perpetuals::tests::constants::{
    CANCEL_DELAY, COLLATERAL_ASSET_ID, COLLATERAL_QUANTUM, FORCED_ACTION_TIMELOCK,
    MAX_FUNDING_INTERVAL, MAX_FUNDING_RATE, MAX_INTEREST_RATE_PER_SEC, MAX_ORACLE_PRICE_VALIDITY,
    MAX_PRICE_INTERVAL, PREMIUM_COST,
};
use perpetuals::tests::flow_tests::infra::*;
use perpetuals::tests::flow_tests::perps_tests_facade::*;
use snforge_std::DeclareResultTrait;
use snforge_std::signature::stark_curve::StarkCurveKeyPairImpl;
use starknet::class_hash::ClassHash;
use starkware_utils::components::replaceability::interface::{
    IReplaceableDispatcher, IReplaceableDispatcherTrait, ImplementationData,
};
use starkware_utils::constants::HOUR;
use starkware_utils_testing::test_utils::cheat_caller_address_once;

/// Swaps the class of the live perpetuals contract (upgrade delay is 0 in
/// tests, so add + replace happen back to back).
fn replace_contract_class(facade: @PerpsTestsFacade, class_hash: ClassHash) {
    let contract_address = *facade.perpetuals_contract;
    let implementation_data = ImplementationData {
        impl_hash: class_hash, eic_data: Option::None, final: false,
    };
    let replaceable = IReplaceableDispatcher { contract_address };
    cheat_caller_address_once(:contract_address, caller_address: *facade.governance_admin);
    replaceable.add_new_implementation(:implementation_data);
    cheat_caller_address_once(:contract_address, caller_address: *facade.governance_admin);
    replaceable.replace_to(:implementation_data);
}

fn declared_class_hash(contract_name: ByteArray) -> ClassHash {
    *snforge_std::declare(contract_name).unwrap().contract_class().class_hash
}

fn find_asset_dump(assets: @Array<AssetDump>, asset_id: AssetId) -> @AssetDump {
    let mut i = 0;
    loop {
        assert!(i < assets.len(), "asset id not found in dump");
        if *assets.at(i).asset_id == asset_id {
            break assets.at(i);
        }
        i += 1;
    }
}

fn find_position_dump(positions: @Array<PositionDump>, position_id: PositionId) -> @PositionDump {
    let mut i = 0;
    loop {
        assert!(i < positions.len(), "position id not found in dump");
        if *positions.at(i).position_id == position_id {
            break positions.at(i);
        }
        i += 1;
    }
}

/// Raw asset balance (`(AssetId, AssetBalance)` entry) of a position dump.
fn dumped_asset_balance(dump: @PositionDump, asset_id: AssetId) -> i64 {
    let mut i = 0;
    loop {
        assert!(i < dump.asset_balances.len(), "asset balance not found in dump");
        let (id, asset_balance) = dump.asset_balances.at(i);
        if *id == asset_id {
            break (*asset_balance.balance).into();
        }
        i += 1;
    }
}

/// Finding 1 evidence: Core's contract-level fields moved into the shared
/// `CoreFieldsComponent`, and because `#[substorage(v0)]` flattens component
/// members to `sn_keccak(<member_name>)`, their raw storage addresses must be
/// EXACTLY the ones the deployed contract already uses. Reads the slots by
/// their pre-refactor addresses and asserts the values written through normal
/// entrypoints are there.
#[test]
fn test_core_fields_storage_addresses_unchanged() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let contract_address = state.facade.perpetuals_contract;

    // Set the one scalar the constructor leaves at default.
    cheat_caller_address_once(:contract_address, caller_address: state.facade.app_governor);
    ICoreDispatcher { contract_address }.enable_escape_hatch();

    let timelock = snforge_std::load(contract_address, selector!("forced_action_timelock"), 1);
    assert_eq!(*timelock.at(0), FORCED_ACTION_TIMELOCK.into());

    let premium_cost = snforge_std::load(contract_address, selector!("premium_cost"), 1);
    assert_eq!(*premium_cost.at(0), PREMIUM_COST.into());

    let enabled = snforge_std::load(contract_address, selector!("forced_actions_enabled"), 1);
    assert_eq!(*enabled.at(0), 1);

    let treasury = snforge_std::load(contract_address, selector!("treasury"), 1);
    assert_eq!(*treasury.at(0), state.facade.treasury_address.into());
}

/// Finding 1 round trip: populate non-trivial state through normal
/// entrypoints, `replace_to` DumpCore, export everything, assert every
/// exported value against what was written (reading live getters before the
/// swap where they exist), then `replace_to` back to the Core class and check
/// a normal trade still settles.
#[test]
fn test_dump_core_round_trip() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let contract_address = state.facade.perpetuals_contract;
    let risk_factor_data = RiskFactorTiers {
        tiers: array![100, 200, 500].span(), first_tier_boundary: 10_000, tier_size: 10_000,
    };

    // --- Populate state through normal entrypoints. ---
    let btc_info = AssetInfoTrait::new(asset_name: 'BTC_MIG', :risk_factor_data, oracles_len: 1);
    let eth_info = AssetInfoTrait::new(asset_name: 'ETH_MIG', :risk_factor_data, oracles_len: 1);
    state.facade.add_active_synthetic(synthetic_info: @btc_info, initial_price: 100);
    state.facade.add_active_synthetic(synthetic_info: @eth_info, initial_price: 50);

    let user_a = state.new_user_with_position();
    let user_b = state.new_user_with_position();
    let vault_user = state.new_user_with_position();

    // A REGISTERED (unprocessed) deposit. First `generate_salt` call in this
    // facade instance, so the salt is 1; the hash-vs-live-status assertion
    // below fails loudly if that ever changes.
    let pending_deposit_amount = 500;
    state
        .facade
        .deposit(
            depositor: user_a.account,
            position_id: user_a.position_id,
            quantized_amount: pending_deposit_amount,
        );
    let pending_deposit_hash = deposit_hash(
        token_address: state.facade.token_state.address,
        depositor: user_a.account.address,
        position_id: user_a.position_id,
        quantized_amount: pending_deposit_amount,
        salt: 1,
    );
    let live_pending_status = IDepositDispatcher { contract_address }
        .get_deposit_status(deposit_hash: pending_deposit_hash);
    assert!(
        live_pending_status != DepositStatus::NOT_REGISTERED,
        "pending deposit not found under the computed hash",
    );

    // Processed deposits + trades in both synthetics -> positions with
    // multiple asset balances each.
    let deposit_a = state
        .facade
        .deposit(
            depositor: user_a.account, position_id: user_a.position_id, quantized_amount: 10_000,
        );
    state.facade.process_deposit(deposit_info: deposit_a);
    let deposit_b = state
        .facade
        .deposit(
            depositor: user_b.account, position_id: user_b.position_id, quantized_amount: 20_000,
        );
    state.facade.process_deposit(deposit_info: deposit_b);

    let order_a = state
        .facade
        .create_order(
            user: user_a,
            base_amount: 10,
            base_asset_id: btc_info.asset_id,
            quote_amount: -1_000,
            fee_amount: 1,
        );
    let order_b = state
        .facade
        .create_order(
            user: user_b,
            base_amount: -10,
            base_asset_id: btc_info.asset_id,
            quote_amount: 1_000,
            fee_amount: 1,
        );
    state
        .facade
        .trade(
            order_info_a: order_a,
            order_info_b: order_b,
            base: 10,
            quote: -1_000,
            fee_a: 0,
            fee_b: 0,
        );

    let order_a = state
        .facade
        .create_order(
            user: user_a,
            base_amount: 5,
            base_asset_id: eth_info.asset_id,
            quote_amount: -250,
            fee_amount: 1,
        );
    let order_b = state
        .facade
        .create_order(
            user: user_b,
            base_amount: -5,
            base_asset_id: eth_info.asset_id,
            quote_amount: 250,
            fee_amount: 1,
        );
    state
        .facade
        .trade(
            order_info_a: order_a, order_info_b: order_b, base: 5, quote: -250, fee_a: 0, fee_b: 0,
        );

    // Non-default `interest_divergence` (and exchange-time values). The
    // amount must stay under the per-position rate cap:
    // balance * time * MAX_INTEREST_RATE_PER_SEC / 2^32 ≈ 8 for one hour.
    state.facade.advance_time(seconds: HOUR);
    let interest_amount: i64 = 4;
    state
        .facade
        .apply_interests(
            position_interest_amounts: array![(user_a.position_id, interest_amount)].span(),
        );

    // A vault (its position must hold positive assets before conversion).
    let vault_init_deposit = state
        .facade
        .deposit(
            depositor: vault_user.account,
            position_id: vault_user.position_id,
            quantized_amount: 5_000,
        );
    state.facade.process_deposit(deposit_info: vault_init_deposit);
    let vault_state = state
        .facade
        .register_vault_share_spot_asset(position_vault: vault_user, asset_name: 'VLT_MIG');

    // An extra oracle whose key is known to the test, for the keyed export.
    let oracle_key_pair = StarkCurveKeyPairImpl::from_secret_key('MIG_ORACLE');
    cheat_caller_address_once(:contract_address, caller_address: state.facade.app_governor);
    IAssetsExternalDispatcher { contract_address }
        .add_oracle_to_asset(btc_info.asset_id, oracle_key_pair.public_key, 'MO', 'BTC_MIG');

    // Non-default `forced_actions_enabled`.
    cheat_caller_address_once(:contract_address, caller_address: state.facade.app_governor);
    ICoreDispatcher { contract_address }.enable_escape_hatch();

    // --- Record expectations from live getters before the swap. ---
    state.facade.operator.set_as_caller(contract_address);
    let expected_nonce = IOperatorNonceDispatcher { contract_address }.get_operator_nonce();
    let exchange_time_dispatcher = IExchangeTimeDispatcher { contract_address };
    let expected_exchange_time = exchange_time_dispatcher.get_exchange_time();
    let expected_last_update = exchange_time_dispatcher.get_time_of_last_update();
    let assets_dispatcher = IAssetsDispatcher { contract_address };
    let expected_num_active = assets_dispatcher.get_num_of_active_synthetic_assets();
    let expected_last_price_validation = assets_dispatcher.get_last_price_validation();
    let expected_last_funding_tick = assets_dispatcher.get_last_funding_tick();
    let live_btc_config = assets_dispatcher.get_asset_config(asset_id: btc_info.asset_id);
    let live_btc_timely = assets_dispatcher.get_timely_data(asset_id: btc_info.asset_id);
    let live_btc_tiers = assets_dispatcher.get_risk_factor_tiers(asset_id: btc_info.asset_id);

    // --- Swap in DumpCore and export. ---
    let core_class_hash = declared_class_hash("Core");
    let dump_class_hash = declared_class_hash("DumpCore");
    replace_contract_class(facade: @state.facade, class_hash: dump_class_hash);

    let dump = IDumpDispatcher { contract_address };
    let dump_extra = IDumpExtraDispatcher { contract_address };

    // Core scalars: all four non-default, asserted individually (these are the
    // fields with no shared definition before CoreFieldsComponent).
    let scalars = dump.export_core_scalars();
    assert_eq!(scalars.forced_action_timelock.seconds, FORCED_ACTION_TIMELOCK);
    assert_eq!(scalars.premium_cost, PREMIUM_COST);
    assert!(scalars.forced_actions_enabled);
    assert_eq!(scalars.interest_divergence, interest_amount);

    // Config plane.
    let config = dump_extra.export_config();
    assert_eq!(config.operator_nonce, expected_nonce);
    assert_eq!(config.exchange_time, expected_exchange_time);
    assert_eq!(config.last_time_of_exchange_time_update, expected_last_update);
    assert!(!config.paused);
    assert_eq!(config.deposit_cancel_delay, CANCEL_DELAY);
    assert_eq!(config.max_interest_rate_per_sec, MAX_INTEREST_RATE_PER_SEC);
    assert_eq!(config.treasury_address, state.facade.treasury_address);
    assert_eq!(config.core.forced_action_timelock.seconds, FORCED_ACTION_TIMELOCK);
    assert_eq!(config.core.premium_cost, PREMIUM_COST);
    assert!(config.core.forced_actions_enabled);
    assert_eq!(config.core.interest_divergence, interest_amount);

    // Assets component scalars.
    let assets_dump = config.assets;
    assert_eq!(assets_dump.max_funding_rate, MAX_FUNDING_RATE);
    assert_eq!(assets_dump.max_price_interval, MAX_PRICE_INTERVAL);
    assert_eq!(assets_dump.max_funding_interval, MAX_FUNDING_INTERVAL);
    assert_eq!(assets_dump.max_oracle_price_validity, MAX_ORACLE_PRICE_VALIDITY);
    assert_eq!(assets_dump.last_price_validation, expected_last_price_validation);
    assert_eq!(assets_dump.last_funding_tick, expected_last_funding_tick);
    assert_eq!(assets_dump.collateral_token_address, state.facade.token_state.address);
    assert_eq!(assets_dump.collateral_quantum, COLLATERAL_QUANTUM);
    assert_eq!(assets_dump.collateral_id, Option::Some(COLLATERAL_ASSET_ID()));
    assert_eq!(assets_dump.num_of_active_synthetic_assets, expected_num_active);
    assert!(assets_dump.risk_factor_request_hash.is_zero());

    // Per-asset dumps: both synthetics and the vault-share asset enumerated.
    assert_eq!(assets_dump.assets.len(), 3);
    let btc_dump = find_asset_dump(assets: @assets_dump.assets, asset_id: btc_info.asset_id);
    let btc_dump_config = (*btc_dump.config).expect('BTC config missing from dump');
    assert_eq!(btc_dump_config.status, live_btc_config.status);
    assert_eq!(btc_dump_config.quorum, live_btc_config.quorum);
    assert_eq!(btc_dump_config.resolution_factor, live_btc_config.resolution_factor);
    assert_eq!(btc_dump_config.asset_type, live_btc_config.asset_type);
    assert_eq!(*btc_dump.timely_data.price, live_btc_timely.price);
    assert_eq!(*btc_dump.timely_data.last_price_update, live_btc_timely.last_price_update);
    assert_eq!(*btc_dump.timely_data.funding_index, live_btc_timely.funding_index);
    assert!(btc_dump.risk_factor_tiers.span() == live_btc_tiers);
    find_asset_dump(assets: @assets_dump.assets, asset_id: eth_info.asset_id);
    find_asset_dump(assets: @assets_dump.assets, asset_id: vault_state.asset_id);

    // External component registry: fixed key set, one entry per component.
    assert_eq!(config.external_components.len(), 8);
    let mut vault_entry_checked = false;
    let mut assets_entry_checked = false;
    for entry in config.external_components.span() {
        if *entry.component_type == EXTERNAL_COMPONENT_VAULT {
            assert_eq!(*entry.registered_class_hash, declared_class_hash("VaultsManager"));
            assert_eq!(*entry.implementation, declared_class_hash("VaultsManager"));
            vault_entry_checked = true;
        }
        if *entry.component_type == EXTERNAL_COMPONENT_ASSETS {
            assert_eq!(*entry.registered_class_hash, declared_class_hash("AssetsManager"));
            assert_eq!(*entry.implementation, declared_class_hash("AssetsManager"));
            assets_entry_checked = true;
        }
    }
    assert!(vault_entry_checked && assets_entry_checked);

    // Positions: raw storage dumps.
    let positions = dump
        .export_positions(position_ids: array![user_a.position_id, user_b.position_id]);
    assert_eq!(positions.len(), 2);
    let dump_a = find_position_dump(positions: @positions, position_id: user_a.position_id);
    assert_eq!(*dump_a.version, 1);
    assert_eq!(*dump_a.owner_account, Option::Some(user_a.account.address));
    assert_eq!(*dump_a.owner_public_key, user_a.account.key_pair.public_key);
    assert!(*dump_a.owner_protection_enabled);
    // 10_000 deposited - 1_000 BTC quote - 250 ETH quote + 4 interest.
    assert_eq!((*dump_a.collateral_balance).into(), 8_754_i64);
    assert_eq!(*dump_a.last_interest_applied_time, expected_exchange_time);
    assert_eq!(dump_a.asset_balances.len(), 2);
    assert_eq!(dumped_asset_balance(dump: dump_a, asset_id: btc_info.asset_id), 10);
    assert_eq!(dumped_asset_balance(dump: dump_a, asset_id: eth_info.asset_id), 5);

    let dump_b = find_position_dump(positions: @positions, position_id: user_b.position_id);
    assert_eq!(*dump_b.owner_public_key, user_b.account.key_pair.public_key);
    assert_eq!((*dump_b.collateral_balance).into(), 21_250_i64);
    assert_eq!(dumped_asset_balance(dump: dump_b, asset_id: btc_info.asset_id), -10);
    assert_eq!(dumped_asset_balance(dump: dump_b, asset_id: eth_info.asset_id), -5);

    // Keyed maps.
    let keyed = dump_extra
        .export_keyed(
            keys: KeySets {
                deposit_hashes: array![pending_deposit_hash],
                fulfillment_hashes: array![],
                oracle_entries: array![(btc_info.asset_id, oracle_key_pair.public_key)],
                vault_asset_ids: array![vault_state.asset_id],
                vault_position_ids: array![vault_state.position_id],
                vault_limit_override_position_ids: array![vault_state.position_id],
                deposit_limit_tokens: array![state.facade.token_state.address],
            },
        );
    assert_eq!(keyed.deposit_statuses.len(), 1);
    assert_eq!(keyed.deposit_statuses.at(0), @live_pending_status);
    assert_eq!(keyed.fulfillments.len(), 0);
    assert_eq!(keyed.oracle_values.len(), 1);
    assert!((*keyed.oracle_values.at(0)).is_non_zero());
    assert_eq!(keyed.vaults_by_asset.len(), 1);
    let vault_by_asset = *keyed.vaults_by_asset.at(0);
    assert_eq!(vault_by_asset.asset_id, vault_state.asset_id);
    assert_eq!(vault_by_asset.position_id, vault_state.position_id.value);
    assert_eq!(keyed.vaults_by_position.at(0), @vault_by_asset);
    assert_eq!(*keyed.vault_limit_overrides.at(0), 0);
    assert_eq!(*keyed.max_deposits.at(0), Option::None);

    // --- Swap back to Core and verify normal operation resumes. ---
    replace_contract_class(facade: @state.facade, class_hash: core_class_hash);

    let order_a = state
        .facade
        .create_order(
            user: user_a,
            base_amount: -5,
            base_asset_id: btc_info.asset_id,
            quote_amount: 500,
            fee_amount: 1,
        );
    let order_b = state
        .facade
        .create_order(
            user: user_b,
            base_amount: 5,
            base_asset_id: btc_info.asset_id,
            quote_amount: -500,
            fee_amount: 1,
        );
    state
        .facade
        .trade(
            order_info_a: order_a, order_info_b: order_b, base: -5, quote: 500, fee_a: 0, fee_b: 0,
        );
    state.facade.validate_collateral_balance(user_a.position_id, 9_254_i64.into());
}

/// Finding 4: `export_assets` enumerates asset ids from the `timely_data`
/// map. Deactivation must NOT remove an asset from the dump — positions may
/// still hold balances in it. Also pins the invariant that every enumerated
/// asset has a populated config (`AssetDump.config` of `None` means
/// "enumerated but unconfigured" and is currently unreachable).
#[test]
fn test_export_assets_includes_deactivated_synthetic() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let contract_address = state.facade.perpetuals_contract;
    let risk_factor_data = RiskFactorTiers {
        tiers: array![100, 200, 500].span(), first_tier_boundary: 10_000, tier_size: 10_000,
    };

    let btc_info = AssetInfoTrait::new(asset_name: 'BTC_MIG', :risk_factor_data, oracles_len: 1);
    let eth_info = AssetInfoTrait::new(asset_name: 'ETH_MIG', :risk_factor_data, oracles_len: 1);
    state.facade.add_active_synthetic(synthetic_info: @btc_info, initial_price: 100);
    state.facade.add_active_synthetic(synthetic_info: @eth_info, initial_price: 50);

    // Give a position a balance in the asset about to be deactivated.
    let user_a = state.new_user_with_position();
    let user_b = state.new_user_with_position();
    let deposit_a = state
        .facade
        .deposit(
            depositor: user_a.account, position_id: user_a.position_id, quantized_amount: 10_000,
        );
    state.facade.process_deposit(deposit_info: deposit_a);
    let deposit_b = state
        .facade
        .deposit(
            depositor: user_b.account, position_id: user_b.position_id, quantized_amount: 20_000,
        );
    state.facade.process_deposit(deposit_info: deposit_b);
    let order_a = state
        .facade
        .create_order(
            user: user_a,
            base_amount: 10,
            base_asset_id: btc_info.asset_id,
            quote_amount: -1_000,
            fee_amount: 1,
        );
    let order_b = state
        .facade
        .create_order(
            user: user_b,
            base_amount: -10,
            base_asset_id: btc_info.asset_id,
            quote_amount: 1_000,
            fee_amount: 1,
        );
    state
        .facade
        .trade(
            order_info_a: order_a,
            order_info_b: order_b,
            base: 10,
            quote: -1_000,
            fee_a: 0,
            fee_b: 0,
        );

    state.facade.deactivate_synthetic(synthetic_id: btc_info.asset_id);
    let expected_num_active = IAssetsDispatcher { contract_address }
        .get_num_of_active_synthetic_assets();
    assert_eq!(expected_num_active, 1);

    replace_contract_class(facade: @state.facade, class_hash: declared_class_hash("DumpCore"));

    let config = IDumpExtraDispatcher { contract_address }.export_config();
    let assets_dump = config.assets;
    assert_eq!(assets_dump.num_of_active_synthetic_assets, expected_num_active);
    assert_eq!(assets_dump.assets.len(), 2);

    // The deactivated synthetic is still enumerated, with its full record.
    let btc_dump = find_asset_dump(assets: @assets_dump.assets, asset_id: btc_info.asset_id);
    let btc_dump_config = (*btc_dump.config).expect('BTC config missing from dump');
    assert_eq!(btc_dump_config.status, AssetStatus::INACTIVE);
    assert_eq!(btc_dump.risk_factor_tiers.len(), 3);
    assert!((*btc_dump.timely_data.price).is_non_zero());

    // Invariant: every enumerated asset has a populated config. If a future
    // assets-manager change makes config-less enumeration reachable, this
    // makes the gap visible.
    for asset in assets_dump.assets.span() {
        assert!(asset.config.is_some(), "enumerated asset without config");
    }

    // The position still holds a balance in the deactivated asset — the
    // reason dropping it from the dump would corrupt a replica built from it.
    let positions = IDumpDispatcher { contract_address }
        .export_positions(position_ids: array![user_a.position_id]);
    assert_eq!(dumped_asset_balance(dump: positions.at(0), asset_id: btc_info.asset_id), 10);
}
