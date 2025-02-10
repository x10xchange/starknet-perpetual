use contracts_commons::test_utils::TokenState;
use perpetuals::core::components::assets::assets::AssetsComponent;
use perpetuals::core::core::Core;
use perpetuals::core::core::Core::SNIP12MetadataImpl;
use perpetuals::tests::constants::*;
use perpetuals::tests::test_utils::{PerpetualsInitConfig, generate_collateral};
use starknet::storage::{StorageMapWriteAccess, StoragePointerWriteAccess};

fn COMPONENT_STATE() -> AssetsComponent::ComponentState<Core::ContractState> {
    AssetsComponent::component_state_for_testing()
}

fn initialized_component_state() -> AssetsComponent::ComponentState<Core::ContractState> {
    let mut state = COMPONENT_STATE();
    state
}


fn add_colateral(
    ref state: AssetsComponent::ComponentState<Core::ContractState>,
    cfg: @PerpetualsInitConfig,
    token_state: @TokenState,
) {
    let (collateral_config, mut collateral_timely_data) = generate_collateral(
        cfg.collateral_cfg, :token_state,
    );
    state
        .collateral_config
        .write(*cfg.collateral_cfg.collateral_id, Option::Some(collateral_config));
    state.collateral_timely_data.write(*cfg.collateral_cfg.collateral_id, collateral_timely_data);
    state.collateral_timely_data_head.write(Option::Some(*cfg.collateral_cfg.collateral_id));
}

fn add_synthetic(
    ref state: AssetsComponent::ComponentState<Core::ContractState>, cfg: @PerpetualsInitConfig,
) {
    state.synthetic_timely_data.write(*cfg.synthetic_cfg.synthetic_id, SYNTHETIC_TIMELY_DATA());
    state.synthetic_timely_data_head.write(Option::Some(*cfg.synthetic_cfg.synthetic_id));
    state.synthetic_config.write(*cfg.synthetic_cfg.synthetic_id, Option::Some(SYNTHETIC_CONFIG()));
}

fn add_synthetic_pending(
    ref state: AssetsComponent::ComponentState<Core::ContractState>, cfg: @PerpetualsInitConfig,
) {
    state.synthetic_timely_data.write(*cfg.synthetic_cfg.synthetic_id, SYNTHETIC_TIMELY_DATA());
    state.synthetic_timely_data_head.write(Option::Some(*cfg.synthetic_cfg.synthetic_id));
    state
        .synthetic_config
        .write(*cfg.synthetic_cfg.synthetic_id, Option::Some(SYNTHETIC_PENDING_CONFIG()));
}
