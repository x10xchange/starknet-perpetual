use openzeppelin::interfaces::erc20::IERC20DispatcherTrait;
use perpetuals::tests::constants::*;
use perpetuals::tests::flow_tests::infra::*;
use perpetuals::tests::flow_tests::perps_tests_facade::*;
use perpetuals::tests::test_utils::assert_with_error;
use snforge_std::start_cheat_block_timestamp_global;
use starkware_utils::time::time::Time;


#[test]
fn test_deposit_into_protocol_vault_same_position() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let vault_user = state.new_user_with_position();
    let depositing_user = state.new_user_with_position();
    let vault_init_deposit = state
        .facade
        .deposit(vault_user.account, vault_user.position_id, 5000_u64);
    state.facade.process_deposit(vault_init_deposit);

    state
        .facade
        .process_deposit(
            state.facade.deposit(depositing_user.account, depositing_user.position_id, 1000_u64),
        );

    let vault_config = state.facade.register_vault_share_spot_asset(vault_user.position_id);

    state
        .facade
        .deposit_into_vault(
            vault: vault_config, amount: 1000, :depositing_user, receiving_user: depositing_user,
        );
}
