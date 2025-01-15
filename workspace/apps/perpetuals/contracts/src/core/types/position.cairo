use contracts_commons::message_hash::OffchainMessageHash;
use core::num::traits::Zero;
use openzeppelin::account::utils::is_valid_stark_signature;
use perpetuals::core::errors::INVALID_STARK_SIGNATURE;
use perpetuals::core::types::Signature;
use perpetuals::core::types::asset::AssetId;
use perpetuals::core::types::asset::collateral::CollateralAsset;
use perpetuals::core::types::asset::synthetic::SyntheticAsset;
use starknet::ContractAddress;
use starknet::storage::{Map, Mutable, StoragePath, StoragePointerReadAccess};


#[starknet::storage_node]
pub struct Position {
    version: u8,
    pub owner_account: ContractAddress,
    pub owner_public_key: felt252,
    pub collateral_assets_head: Option<AssetId>,
    pub collateral_assets: Map<AssetId, CollateralAsset>,
    pub synthetic_assets_head: Option<AssetId>,
    pub synthetic_assets: Map<AssetId, SyntheticAsset>,
}


#[generate_trait]
pub impl PositionImpl of PositionTrait {
    fn _validate_stark_signature(
        self: @StoragePath<Mutable<Position>>, msg_hash: felt252, signature: Signature,
    ) {
        assert(
            is_valid_stark_signature(
                :msg_hash, public_key: self.owner_public_key.read(), :signature,
            ),
            INVALID_STARK_SIGNATURE,
        );
    }

    fn _generate_message_hash_with_public_key<
        T, +OffchainMessageHash<T, ContractAddress>, +OffchainMessageHash<T, felt252>, +Drop<T>,
    >(
        self: @StoragePath<Mutable<Position>>, message: T,
    ) -> felt252 {
        message.get_message_hash(signer: self.owner_public_key.read())
    }

    fn _generate_message_hash_with_owner_account_or_public_key<
        T, +OffchainMessageHash<T, ContractAddress>, +OffchainMessageHash<T, felt252>, +Drop<T>,
    >(
        self: @StoragePath<Mutable<Position>>, message: T,
    ) -> felt252 {
        let signer = self.owner_account.read();
        if signer.is_non_zero() {
            message.get_message_hash(:signer)
        } else {
            message.get_message_hash(signer: self.owner_public_key.read())
        }
    }
}
