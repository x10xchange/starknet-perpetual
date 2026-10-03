use core::num::traits::Zero;
use perpetuals::core::components::operator_nonce::interface::IOperatorNonce;
use perpetuals::core::components::positions::Positions::InternalTrait as PositionsInternal;
use perpetuals::core::components::positions::interface::IPositions;
use perpetuals::core::core::Core;
use perpetuals::core::interface::ICore;
use perpetuals::core::types::asset::AssetStatus;
use perpetuals::core::types::asset::synthetic::AssetType;
use perpetuals::core::types::funding::FundingIndex;
use perpetuals::core::types::position::PositionId;
use perpetuals::core::types::price::PRICE_SCALE;
use perpetuals::tests::test_utils::{
    PerpetualsInitConfig, User, init_position_with_spot_asset_balance,
    setup_state_with_pending_spot_asset,
};
use snforge_std::{start_cheat_block_timestamp_global, test_address};
use starknet::storage::{
    StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
    StoragePointerWriteAccess,
};
use starkware_utils::storage::iterable_map::{IterableMapReadAccessImpl, IterableMapWriteAccessImpl};
use starkware_utils::time::time::{Time, Timestamp};
use starkware_utils_testing::test_utils::{Deployable, cheat_caller_address_once};

fn setup(price: u64) -> (Core::ContractState, PerpetualsInitConfig, PositionId) {
    let mut cfg: PerpetualsInitConfig = Default::default();
    cfg.spot_cfg.resolution_factor = 1_000_000;
    let token = cfg.collateral_cfg.token_cfg.deploy();
    let mut state = setup_state_with_pending_spot_asset(@cfg, @token);
    let asset = cfg.spot_cfg.collateral_id;
    let mut config = state.assets.asset_config.read(asset).unwrap();
    config.status = AssetStatus::ACTIVE;
    state.assets.asset_config.write(asset, Option::Some(config));
    let mut timely = state.assets.timely_data.read(asset).unwrap();
    timely.price = price.into();
    timely.last_price_update = Time::now();
    state.assets.timely_data.write(asset, timely);
    let user: User = Default::default();
    let position_id = user.position_id;
    init_position_with_spot_asset_balance(@cfg, ref state, user, asset, 100_i64.into());
    let position = state.positions.get_position_mut(position_id);
    position.collateral_balance.write(200_i64.into());
    (state, cfg, position_id)
}

fn swap(
    ref state: Core::ContractState,
    cfg: @PerpetualsInitConfig,
    position_id: PositionId,
    amount: u64,
) {
    cheat_caller_address_once(test_address(), *cfg.operator);
    let nonce = state.get_operator_nonce();
    state.enforced_stable_coin_swap(nonce, position_id, *cfg.spot_cfg.collateral_id, amount);
}

#[test]
fn test_enforced_stable_coin_swap_preserves_checkpoints_and_owner() {
    let (mut state, cfg, position_id) = setup(PRICE_SCALE - 1);
    let asset = cfg.spot_cfg.collateral_id;
    let position = state.positions.get_position_mut(position_id);
    position.last_interest_applied_time.write(Timestamp { seconds: 17 });
    let owner = position.owner_public_key.read();
    let mut source = position.asset_balances.read(asset).unwrap();
    source.funding_index = FundingIndex { value: 123 };
    position.asset_balances.write(asset, source);
    let nonce = state.get_operator_nonce();
    swap(ref state, @cfg, position_id, 40);
    let position = state.positions.get_position_snapshot(position_id);
    assert!(position.collateral_balance.read() == 240_i64.into());
    let source = position.asset_balances.read(asset).unwrap();
    assert!(source.balance == 60_i64.into());
    assert!(source.funding_index == FundingIndex { value: 123 });
    assert!(position.last_interest_applied_time.read().seconds == 17);
    assert!(position.owner_public_key.read() == owner);
    assert!(state.get_operator_nonce() == nonce + 1);
    swap(ref state, @cfg, position_id, 60);
    let position = state.positions.get_position_snapshot(position_id);
    assert!(position.collateral_balance.read() == 300_i64.into());
    assert!(position.asset_balances.read(asset).unwrap().balance.is_zero());
}

#[test]
fn test_enforced_stable_coin_swap_accepts_unhealthy_position() {
    let (mut state, cfg, position_id) = setup(PRICE_SCALE / 2);
    state.positions.get_position_mut(position_id).collateral_balance.write((-200_i64).into());
    assert!(state.positions.is_deleveragable(position_id));
    swap(ref state, @cfg, position_id, 100);
    assert!(
        state
            .positions
            .get_position_snapshot(position_id)
            .collateral_balance
            .read() == (-100_i64)
            .into(),
    );
    assert!(state.positions.is_deleveragable(position_id));
}

#[test]
#[should_panic(expected: 'SWAP_PRICE_NOT_BELOW_USDC')]
fn test_enforced_stable_coin_swap_rejects_parity() {
    let (mut state, cfg, position_id) = setup(PRICE_SCALE);
    swap(ref state, @cfg, position_id, 100);
}

#[test]
#[should_panic(expected: 'SWAP_PRICE_NOT_BELOW_USDC')]
fn test_enforced_stable_coin_swap_rejects_price_above_parity() {
    let (mut state, cfg, position_id) = setup(PRICE_SCALE + 1);
    swap(ref state, @cfg, position_id, 100);
}

#[test]
#[should_panic(expected: 'SWAP_RESOLUTION_MISMATCH')]
fn test_enforced_stable_coin_swap_rejects_different_units() {
    let (mut state, cfg, position_id) = setup(PRICE_SCALE / 2);
    let asset = cfg.spot_cfg.collateral_id;
    let mut config = state.assets.asset_config.read(asset).unwrap();
    config.resolution_factor = 1_000_000_000;
    state.assets.asset_config.write(asset, Option::Some(config));
    swap(ref state, @cfg, position_id, 100);
}

#[test]
#[should_panic(expected: 'SWAP_ASSET_NOT_SPOT')]
fn test_enforced_stable_coin_swap_rejects_synthetic() {
    let (mut state, cfg, position_id) = setup(PRICE_SCALE / 2);
    let asset = cfg.spot_cfg.collateral_id;
    let mut config = state.assets.asset_config.read(asset).unwrap();
    config.asset_type = AssetType::SYNTHETIC;
    state.assets.asset_config.write(asset, Option::Some(config));
    swap(ref state, @cfg, position_id, 100);
}

#[test]
#[should_panic(expected: 'SWAP_ASSET_NOT_SPOT')]
fn test_enforced_stable_coin_swap_rejects_vault_shares() {
    let (mut state, cfg, position_id) = setup(PRICE_SCALE / 2);
    let asset = cfg.spot_cfg.collateral_id;
    let mut config = state.assets.asset_config.read(asset).unwrap();
    config.asset_type = AssetType::VAULT_SHARE_COLLATERAL;
    state.assets.asset_config.write(asset, Option::Some(config));
    swap(ref state, @cfg, position_id, 100);
}

#[test]
#[should_panic(expected: 'INVALID_ZERO_AMOUNT')]
fn test_enforced_stable_coin_swap_rejects_zero_amount() {
    let (mut state, cfg, position_id) = setup(PRICE_SCALE / 2);
    swap(ref state, @cfg, position_id, 0);
}

#[test]
#[should_panic(expected: 'INSUFFICIENT_SWAP_BALANCE')]
fn test_enforced_stable_coin_swap_rejects_overdraw() {
    let (mut state, cfg, position_id) = setup(PRICE_SCALE / 2);
    swap(ref state, @cfg, position_id, 101);
}

#[test]
#[should_panic(expected: 'AMOUNT_OVERFLOW')]
fn test_enforced_stable_coin_swap_rejects_amount_overflow() {
    let (mut state, cfg, position_id) = setup(PRICE_SCALE / 2);
    swap(ref state, @cfg, position_id, 0x8000000000000000);
}

#[test]
#[should_panic]
fn test_enforced_stable_coin_swap_rejects_collateral_overflow() {
    let (mut state, cfg, position_id) = setup(PRICE_SCALE / 2);
    state
        .positions
        .get_position_mut(position_id)
        .collateral_balance
        .write(0x7fffffffffffffff_i64.into());
    swap(ref state, @cfg, position_id, 1);
}

#[test]
#[should_panic(expected: 'POSITION_DOESNT_EXIST')]
fn test_enforced_stable_coin_swap_rejects_missing_position() {
    let (mut state, cfg, _) = setup(PRICE_SCALE / 2);
    swap(ref state, @cfg, PositionId { value: 999999 }, 100);
}

#[test]
#[should_panic(expected: 'INACTIVE_ASSET')]
fn test_enforced_stable_coin_swap_rejects_inactive_asset() {
    let (mut state, cfg, position_id) = setup(PRICE_SCALE / 2);
    let asset = cfg.spot_cfg.collateral_id;
    let mut config = state.assets.asset_config.read(asset).unwrap();
    config.status = AssetStatus::INACTIVE;
    state.assets.asset_config.write(asset, Option::Some(config));
    swap(ref state, @cfg, position_id, 100);
}

#[test]
#[should_panic(expected: 'SYNTHETIC_EXPIRED_PRICE')]
fn test_enforced_stable_coin_swap_rejects_stale_price() {
    let (mut state, cfg, position_id) = setup(PRICE_SCALE / 2);
    let now = Time::now().seconds + cfg.max_price_interval.seconds + 1;
    start_cheat_block_timestamp_global(now);
    state.assets.last_funding_tick.write(Timestamp { seconds: now });
    swap(ref state, @cfg, position_id, 100);
}
