use perpetuals::core::types::funding::{FUNDING_SCALE, FundingIndex, FundingTick};
use perpetuals::tests::constants::*;
use perpetuals::tests::flow_tests::infra::*;
use perpetuals::tests::flow_tests::perps_tests_facade::*;
use perpetuals::tests::test_utils::{deploy_account, init_by_dispatcher};
use starkware_utils::constants::MAX_U128;


// #[derive(Drop)]
// pub struct DeployedVault {
//     pub contract_address: ContractAddress,
//     pub erc20: IERC20Dispatcher,
//     pub erc4626: IERC4626Dispatcher,
//     pub protocol_vault: IProtocolVaultDispatcher,
// }

// pub fn deploy_protocol_vault_with_dispatcher(
//     perps_address: ContractAddress,
//     vault_position_id: PositionId,
//     usdc_token_state: TokenState,
//     initial_receiver: ContractAddress,
// ) -> DeployedVault {
//     let owning_account = deploy_account(StarkCurveKeyPairImpl::generate());
//     usdc_token_state.fund(owning_account, 1_000_000_000_u128);
//     let mut calldata = ArrayTrait::new();
//     let name: ByteArray = "Perpetuals Protocol Vault";
//     let symbol: ByteArray = "PPV";
//     name.serialize(ref calldata);
//     symbol.serialize(ref calldata);
//     usdc_token_state.address.serialize(ref calldata);
//     perps_address.serialize(ref calldata);
//     vault_position_id.value.serialize(ref calldata);
//     initial_receiver.serialize(ref calldata);
//     let contract = snforge_std::declare("ProtocolVault").unwrap().contract_class();
//     let (contract_address, _) = contract.deploy(@calldata).unwrap();
//     let erc20 = IERC20Dispatcher { contract_address: contract_address };
//     let erc4626 = IERC4626Dispatcher { contract_address: contract_address };
//     let protocol_vault = IProtocolVaultDispatcher { contract_address: contract_address };
//     DeployedVault { contract_address: contract_address, erc20, erc4626, protocol_vault }
// }

#[test]
fn test_protocol_vault_deposit_into_vault() {
    let mut state: FlowTestBase = FlowTestBaseTrait::new();
    let vault_user = state.new_user_with_position();
    let depositing_user = state.new_user_with_position();
    let deposit_info = state.facade.deposit(vault_user.account, vault_user.position_id, 5000_u64);
    state.facade.process_deposit(deposit_info);
    
    state.facade.register_vault_share_spot_asset(vault_user.position_id);
}
