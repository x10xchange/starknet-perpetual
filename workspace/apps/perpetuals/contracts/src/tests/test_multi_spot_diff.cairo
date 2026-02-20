use core::traits::{Default, Into};
#[cfg(test)]
use perpetuals::core::components::positions::Positions::InternalTrait as PositionsInternal;
use perpetuals::core::types::balance::Balance;
use perpetuals::core::types::position::MultiSpotPositionDiff;
use perpetuals::tests::constants::*;
use starknet::storage::StoragePointerReadAccess;
use crate::tests::test_utils::{
    PerpetualsInitConfig, User, create_token_state, init_position,
    setup_state_with_active_synthetic, setup_state_with_multiple_spot_assets,
    setup_state_with_pending_spot_asset, validate_asset_balance,
};

#[test]
fn test_apply_multi_spot_diff_happy_path() {
    let mut cfg: PerpetualsInitConfig = Default::default();
    let mut token_state = create_token_state();
    let mut state = setup_state_with_pending_spot_asset(@cfg, @token_state);

    // Create a user and a position
    let user: User = Default::default();
    init_position(@cfg, ref state, user);

    let position_id = user.position_id;
    let collateral_diff_val: i64 = 1000;
    let collateral_diff: Balance = collateral_diff_val.into();

    // cfg is owned, so these access the values directly
    let spot_asset_id = cfg.spot_cfg.collateral_id;
    let spot_asset_diff_val: i64 = 500;
    let spot_asset_diff: Balance = spot_asset_diff_val.into();

    let multi_spot_diff = MultiSpotPositionDiff {
        collateral_diff: collateral_diff,
        asset_diffs: array![(spot_asset_id, spot_asset_diff)].span(),
    };

    state.positions.apply_multi_spot_diff(position_id, multi_spot_diff);

    // Verify balances (collateral balance read directly as it's simple storage)
    let position = state.positions.get_position_snapshot(position_id);

    let expected_collateral = COLLATERAL_BALANCE_AMOUNT + 1000;
    assert(
        position.collateral_balance.read() == expected_collateral.into(),
        'Invalid collateral balance',
    );

    // Spot balance check using helper
    validate_asset_balance(ref state, position_id, spot_asset_id, spot_asset_diff);

    // Apply another diff (adding more)
    let spot_diff_2: i64 = 200;
    let col_diff_2: i64 = 100;

    let multi_spot_diff_2 = MultiSpotPositionDiff {
        collateral_diff: col_diff_2.into(),
        asset_diffs: array![(spot_asset_id, spot_diff_2.into())].span(),
    };
    state.positions.apply_multi_spot_diff(position_id, multi_spot_diff_2);

    let position_2 = state.positions.get_position_snapshot(position_id);
    assert(
        position_2.collateral_balance.read() == (expected_collateral + 100).into(),
        'Invalid col bal 2',
    );

    let expected_spot_2: i64 = 700;
    validate_asset_balance(ref state, position_id, spot_asset_id, expected_spot_2.into());

    // Apply negative diff (partial withdrawal)
    let spot_diff_3: i64 = -100;
    let col_diff_3: i64 = -50;

    let multi_spot_diff_3 = MultiSpotPositionDiff {
        collateral_diff: col_diff_3.into(),
        asset_diffs: array![(spot_asset_id, spot_diff_3.into())].span(),
    };
    state.positions.apply_multi_spot_diff(position_id, multi_spot_diff_3);

    let position_3 = state.positions.get_position_snapshot(position_id);
    assert(
        position_3.collateral_balance.read() == (expected_collateral + 100 - 50).into(),
        'Invalid col bal 3',
    );

    let expected_spot_3: i64 = 600;
    validate_asset_balance(ref state, position_id, spot_asset_id, expected_spot_3.into());
}

#[test]
#[should_panic(
    expected: "Spot Balance for asset: AssetId { value: 115908168817373063099305344695947534019542757008820723413990772101903177083 } has gone negative. now: Balance { value: -1 }, was: Balance { value: 0 }, position: PositionId { value: 100 }",
)]
fn test_apply_multi_spot_diff_negative_balance_panic() {
    let mut cfg: PerpetualsInitConfig = Default::default();
    let mut token_state = create_token_state();
    let mut state = setup_state_with_pending_spot_asset(@cfg, @token_state);

    let user: User = Default::default();
    init_position(@cfg, ref state, user);

    let position_id = user.position_id;
    let spot_asset_id = cfg.spot_cfg.collateral_id;

    // Try to withdraw more than we have (0 initially)
    let neg_one: i64 = -1;
    let multi_spot_diff = MultiSpotPositionDiff {
        collateral_diff: 0_i64.into(), asset_diffs: array![(spot_asset_id, neg_one.into())].span(),
    };

    state.positions.apply_multi_spot_diff(position_id, multi_spot_diff);
}

#[test]
#[should_panic(
    expected: "Asset: AssetId { value: 720515315941943725751128480342703114962297896757142150278960020243082094068 } is not a spot asset",
)]
fn test_apply_multi_spot_diff_synthetic_panic() {
    let mut cfg: PerpetualsInitConfig = Default::default();
    let mut token_state = create_token_state();
    // Setup with synthetic asset
    let mut state = setup_state_with_active_synthetic(@cfg, @token_state);

    let user: User = Default::default();
    init_position(@cfg, ref state, user);

    let position_id = user.position_id;
    let synthetic_id = cfg.synthetic_cfg.synthetic_id;

    let multi_spot_diff = MultiSpotPositionDiff {
        collateral_diff: 0_i64.into(), asset_diffs: array![(synthetic_id, 100_i64.into())].span(),
    };

    state.positions.apply_multi_spot_diff(position_id, multi_spot_diff);
}

#[test]
fn test_apply_multi_spot_diff_mixed_diffs_same_asset() {
    let mut cfg: PerpetualsInitConfig = Default::default();
    let mut token_state = create_token_state();
    let mut state = setup_state_with_pending_spot_asset(@cfg, @token_state);

    let user: User = Default::default();
    init_position(@cfg, ref state, user);

    let position_id = user.position_id;
    let spot_asset_id = cfg.spot_cfg.collateral_id;

    // 1. Initial funding
    let initial_diff = MultiSpotPositionDiff {
        collateral_diff: 0_i64.into(), asset_diffs: array![(spot_asset_id, 1000_i64.into())].span(),
    };
    state.positions.apply_multi_spot_diff(position_id, initial_diff);

    // 2. Apply a mix of positive and negative diffs
    let mixed_diffs = MultiSpotPositionDiff {
        collateral_diff: 50_i64.into(),
        asset_diffs: array![
            (spot_asset_id, 200_i64.into()), // +200 -> 1200
            (spot_asset_id, -500_i64.into()), // -500 -> 700
            (spot_asset_id, 150_i64.into()), // +150 -> 850
            (spot_asset_id, -50_i64.into()) // -50 -> 800
        ]
            .span(),
    };
    state.positions.apply_multi_spot_diff(position_id, mixed_diffs);

    // 3. Verify net balance is 800
    validate_asset_balance(ref state, position_id, spot_asset_id, 800_i64.into());
}

#[test]
fn test_apply_multi_spot_diff_multiple_assets_mixed() {
    let mut cfg: PerpetualsInitConfig = Default::default();
    let mut token_state = create_token_state();
    let mut state = setup_state_with_multiple_spot_assets(@cfg, @token_state);

    let user: User = Default::default();
    init_position(@cfg, ref state, user);

    let position_id = user.position_id;
    let spot_asset_id = cfg.spot_cfg.collateral_id;
    let vault_share_id = cfg.vault_share_cfg.collateral_id;

    // Initial funding for both assets
    let initial_diff = MultiSpotPositionDiff {
        collateral_diff: 0_i64.into(),
        asset_diffs: array![(spot_asset_id, 1000_i64.into()), (vault_share_id, 1000_i64.into())]
            .span(),
    };
    state.positions.apply_multi_spot_diff(position_id, initial_diff);

    // Apply mixed diffs across both assets
    let mixed_diffs = MultiSpotPositionDiff {
        collateral_diff: 100_i64.into(),
        asset_diffs: array![
            (spot_asset_id, 500_i64.into()), // 1000 + 500 = 1500
            (vault_share_id, -300_i64.into()), // 1000 - 300 = 700
            (spot_asset_id, -200_i64.into()), // 1500 - 200 = 1300
            (vault_share_id, 400_i64.into()) // 700 + 400 = 1100
        ]
            .span(),
    };
    state.positions.apply_multi_spot_diff(position_id, mixed_diffs);

    validate_asset_balance(ref state, position_id, spot_asset_id, 1300_i64.into());
    validate_asset_balance(ref state, position_id, vault_share_id, 1100_i64.into());
}
