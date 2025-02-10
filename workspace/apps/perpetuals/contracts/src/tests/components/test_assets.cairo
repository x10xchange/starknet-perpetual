use contracts_commons::test_utils::{TokenState, TokenTrait};
use perpetuals::core::components::assets::AssetsComponent::InternalTrait as AssetsInternal;
use perpetuals::core::components::assets::assets::AssetsComponent;
use perpetuals::core::core::Core;
use perpetuals::core::core::Core::SNIP12MetadataImpl;
use perpetuals::tests::constants::*;
use perpetuals::tests::test_utils::{PerpetualsInitConfig, generate_collateral};
use snforge_std::test_address;
use starknet::storage::{StorageMapWriteAccess, StoragePointerWriteAccess};

fn COMPONENT_STATE() -> AssetsComponent::ComponentState<Core::ContractState> {
    AssetsComponent::component_state_for_testing()
}

fn initialized_component_state() -> AssetsComponent::ComponentState<Core::ContractState> {
    let mut state = COMPONENT_STATE();
    state
}

fn setup_state(
    cfg: @PerpetualsInitConfig, token_state: @TokenState,
) -> AssetsComponent::ComponentState<Core::ContractState> {
    let mut state = initialized_component_state();
    state
        .initialize(
            max_price_interval: *cfg.max_price_interval,
            max_funding_interval: *cfg.max_funding_interval,
            max_funding_rate: *cfg.max_funding_rate,
            max_oracle_price_validity: *cfg.max_oracle_price_validity,
        );
    add_colateral(ref :state, :cfg, :token_state);
    // Synthetic asset configs.
    add_synthetic(ref :state, :cfg);
    // Fund the contract.
    (*token_state)
        .fund(recipient: test_address(), amount: CONTRACT_INIT_BALANCE.try_into().unwrap());

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
