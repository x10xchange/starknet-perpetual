use perpetuals::core::types::position::{PositionData, PositionId};
use perpetuals::core::value_risk_calculator::PositionTVTR;
use starknet::secp256_trait::Signature as EvmSignature;
use starknet::{ContractAddress, EthAddress};
use starkware_utils::signature::stark::{PublicKey, Signature};
use starkware_utils::time::time::Timestamp;

#[starknet::interface]
pub trait IPositions<TContractState> {
    fn get_position_assets(self: @TContractState, position_id: PositionId) -> PositionData;
    fn get_position_tv_tr(self: @TContractState, position_id: PositionId) -> PositionTVTR;
    fn is_deleveragable(self: @TContractState, position_id: PositionId) -> bool;
    fn is_healthy(self: @TContractState, position_id: PositionId) -> bool;
    fn is_liquidatable(self: @TContractState, position_id: PositionId) -> bool;
    // Position Flows
    fn new_position(
        ref self: TContractState,
        operator_nonce: u64,
        position_id: PositionId,
        owner_public_key: PublicKey,
        owner_account: ContractAddress,
        owner_protection_enabled: bool,
    );
    fn set_owner_account_request(
        ref self: TContractState,
        signature: Signature,
        position_id: PositionId,
        new_owner_account: ContractAddress,
        expiration: Timestamp,
    );
    fn set_owner_account(
        ref self: TContractState,
        operator_nonce: u64,
        position_id: PositionId,
        new_owner_account: ContractAddress,
        expiration: Timestamp,
    );
    fn set_public_key_request(
        ref self: TContractState,
        signature: Signature,
        position_id: PositionId,
        new_public_key: PublicKey,
        expiration: Timestamp,
    );
    fn set_public_key(
        ref self: TContractState,
        operator_nonce: u64,
        position_id: PositionId,
        new_public_key: PublicKey,
        expiration: Timestamp,
    );
    fn enable_owner_protection(
        ref self: TContractState,
        operator_nonce: u64,
        position_id: PositionId,
        signature: Signature,
    );
    /// Attaches an EVM address to the position. Requires signatures from BOTH the existing
    /// STARK owner public key and the new EVM account, both over the same logical message
    /// (position_id, new_evm_account) — STARK side hashes with Poseidon, EVM side with keccak.
    /// Set-once: fails if the position already has an evm account.
    fn set_evm_account(
        ref self: TContractState,
        position_id: PositionId,
        new_evm_account: EthAddress,
        stark_signature: Signature,
        evm_signature: EvmSignature,
    );
    /// Opt-in protection: when enabled, all withdrawals from this position must be routed
    /// back to the position's owner_account. Defense against STARK-key compromise where the
    /// attacker has the trade key but not the L2 wallet. Only settable when owner_account is
    /// configured; gated by caller == owner_account.
    fn set_owner_only_withdrawal(ref self: TContractState, position_id: PositionId, enabled: bool);
}
