use contracts_commons::types::time::time::Timestamp;
use contracts_commons::types::{PublicKey, Signature};
use perpetuals::core::types::PositionId;
use perpetuals::core::types::asset::AssetId;
use perpetuals::core::types::funding::FundingTick;
use perpetuals::core::types::order::Order;
use perpetuals::core::types::price::SignedPrice;
use starknet::ContractAddress;


#[starknet::interface]
pub trait ICore<TContractState> {
    // Position Flows
    fn new_position(
        ref self: TContractState,
        operator_nonce: u64,
        position_id: PositionId,
        owner_public_key: PublicKey,
        owner_account: ContractAddress,
    );
    fn set_owner_account(
        ref self: TContractState,
        operator_nonce: u64,
        signature: Signature,
        position_id: PositionId,
        public_key: PublicKey,
        new_account_owner: ContractAddress,
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
    fn process_deposit(
        ref self: TContractState,
        operator_nonce: u64,
        depositor: ContractAddress,
        position_id: PositionId,
        collateral_id: AssetId,
        amount: u128,
        salt: felt252,
    );
    fn withdraw_request(
        ref self: TContractState,
        signature: Signature,
        recipient: ContractAddress,
        position_id: PositionId,
        collateral_id: AssetId,
        amount: u64,
        expiration: Timestamp,
        salt: felt252,
    );
    fn withdraw(
        ref self: TContractState,
        operator_nonce: u64,
        recipient: ContractAddress,
        position_id: PositionId,
        collateral_id: AssetId,
        amount: u64,
        expiration: Timestamp,
        salt: felt252,
    );
    fn transfer_request(
        ref self: TContractState,
        signature: Signature,
        recipient: PositionId,
        position_id: PositionId,
        collateral_id: AssetId,
        amount: u64,
        expiration: Timestamp,
        salt: felt252,
    );
    fn transfer(
        ref self: TContractState,
        operator_nonce: u64,
        recipient: PositionId,
        position_id: PositionId,
        collateral_id: AssetId,
        amount: u64,
        expiration: Timestamp,
        salt: felt252,
    );
    fn trade(
        ref self: TContractState,
        operator_nonce: u64,
        signature_a: Signature,
        signature_b: Signature,
        order_a: Order,
        order_b: Order,
        actual_amount_base_a: i64,
        actual_amount_quote_a: i64,
        actual_fee_a: u64,
        actual_fee_b: u64,
    );
    fn liquidate(
        ref self: TContractState,
        operator_nonce: u64,
        liquidator_signature: Signature,
        liquidated_position_id: PositionId,
        liquidator_order: Order,
        actual_amount_base_liquidated: i64,
        actual_amount_quote_liquidated: i64,
        actual_liquidator_fee: u64,
        fee_asset_id: AssetId,
        fee_amount: u64,
    );
    fn deleverage(
        ref self: TContractState,
        operator_nonce: u64,
        deleveraged_position: PositionId,
        deleverager_position: PositionId,
        deleveraged_base_asset_id: AssetId,
        deleveraged_base_amount: i64,
        deleveraged_quote_asset_id: AssetId,
        deleveraged_quote_amount: i64,
    );
    // Asset Flows
    fn register_collateral(
        ref self: TContractState, asset_id: AssetId, token_address: ContractAddress, quantum: u64,
    );
    fn add_synthetic_asset(
        ref self: TContractState, asset_id: AssetId, risk_factor: u8, quorum: u8, resolution: u64,
    );
    fn deactivate_synthetic(ref self: TContractState, synthetic_id: AssetId);
    fn add_oracle_to_asset(
        ref self: TContractState,
        asset_id: AssetId,
        oracle_public_key: PublicKey,
        oracle_name: felt252,
        asset_name: felt252,
    );
    fn remove_oracle_from_asset(
        ref self: TContractState, asset_id: AssetId, oracle_public_key: PublicKey,
    );
    fn update_synthetic_quorum(ref self: TContractState, synthetic_id: AssetId, quorum: u8);
    // Ticks
    fn funding_tick(
        ref self: TContractState, operator_nonce: u64, funding_ticks: Span<FundingTick>,
    );
    fn price_tick(
        ref self: TContractState,
        operator_nonce: u64,
        asset_id: AssetId,
        price: u128,
        signed_prices: Span<SignedPrice>,
    );
}
