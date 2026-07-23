use core::hash::{HashStateExTrait, HashStateTrait};
use core::keccak::{compute_keccak_byte_array, keccak_u256s_be_inputs};
use core::poseidon::PoseidonTrait;
use openzeppelin::utils::snip12::StructHash;
use perpetuals::core::types::position::PositionId;
use starknet::EthAddress;
use starkware_utils::math::utils::u256_reverse_endian;
use starkware_utils::signature::stark::HashType;
use starkware_utils::time::time::Timestamp;

/// Co-signed by the position's STARK owner key (SNIP-12) and the EVM account (EIP-712).
#[derive(Copy, Drop, Serde)]
pub struct SetEvmAccountArgs {
    pub position_id: PositionId,
    pub new_evm_account: EthAddress,
    pub expiration: Timestamp,
}

pub impl SetEvmAccountStructHash of StructHash<SetEvmAccountArgs> {
    fn hash_struct(self: @SetEvmAccountArgs) -> HashType {
        let type_hash = selector!(
            "\"SetEvmAccountArgs\"(\"position_id\":\"PositionId\",\"new_evm_account\":\"felt\",\"expiration\":\"Timestamp\")\"PositionId\"(\"value\":\"u32\")\"Timestamp\"(\"seconds\":\"u64\")",
        );
        let evm_felt: felt252 = (*self.new_evm_account).into();
        PoseidonTrait::new()
            .update_with(type_hash)
            .update_with(*self.position_id)
            .update_with(evm_felt)
            .update_with(*self.expiration)
            .finalize()
    }
}

// Domain = name + version only (no chainId / verifyingContract) so any EVM wallet can sign via
// eth_signTypedData_v4. Constants are computed off-chain and checked against on-chain keccak in
// the tests below.
pub const SET_EVM_ACCOUNT_TYPE_HASH: u256 =
    0x94114db3661181f4bb5fb20fea10b7830b850cbfd64d7789a9191e79d9150484;
pub const EIP712_DOMAIN_SEPARATOR: u256 =
    0x12b72fb1b17052d7f482c2353585056ac4d79329d91b8271b1c013622f2ba1f9;

// Cairo keccak returns little-endian; `u256_reverse_endian` converts to the big-endian form
// EIP-712 / verify_eth_signature expect.
pub fn set_evm_account_eip712_digest(
    position_id: PositionId, new_evm_account: EthAddress, expiration: Timestamp,
) -> u256 {
    let pid_u256: u256 = position_id.value.into();
    let addr_felt: felt252 = new_evm_account.into();
    let addr_u256: u256 = addr_felt.into();
    let exp_u256: u256 = expiration.seconds.into();
    let struct_hash = u256_reverse_endian(
        keccak_u256s_be_inputs(
            array![SET_EVM_ACCOUNT_TYPE_HASH, pid_u256, addr_u256, exp_u256].span(),
        ),
    );
    let mut envelope: ByteArray = "";
    envelope.append_byte(0x19);
    envelope.append_byte(0x01);
    envelope.append_word(EIP712_DOMAIN_SEPARATOR.high.into(), 16);
    envelope.append_word(EIP712_DOMAIN_SEPARATOR.low.into(), 16);
    envelope.append_word(struct_hash.high.into(), 16);
    envelope.append_word(struct_hash.low.into(), 16);
    u256_reverse_endian(compute_keccak_byte_array(@envelope))
}

#[cfg(test)]
mod tests {
    use core::keccak::{compute_keccak_byte_array, keccak_u256s_be_inputs};
    use starkware_utils::math::utils::u256_reverse_endian;
    use super::{EIP712_DOMAIN_SEPARATOR, SET_EVM_ACCOUNT_TYPE_HASH};

    fn keccak_be(input: ByteArray) -> u256 {
        u256_reverse_endian(compute_keccak_byte_array(@input))
    }

    #[test]
    fn test_eip712_type_hash_matches_string() {
        let expected = keccak_be(
            "SetEvmAccount(uint32 positionId,address newEvmAccount,uint64 expiration)",
        );
        assert!(expected == SET_EVM_ACCOUNT_TYPE_HASH);
    }

    /// Each domain component plus the composed separator.
    #[test]
    fn test_eip712_domain_separator_matches() {
        let domain_typehash = keccak_be("EIP712Domain(string name,string version)");
        assert!(
            domain_typehash == 0xb03948446334eb9b2196d5eb166f69b9d49403eb4a12f36de8d3f9f3cb8e15c3,
        );

        let name_hash = keccak_be("Perpetuals");
        assert!(name_hash == 0x461e483ab48f972afc9aee07aaa1c12970bee3746628836b5d1fd10275ca210f);

        let version_hash = keccak_be("v0");
        assert!(version_hash == 0x042d2d898454f584e9cded7d5fa57170aaeed0dd61e9c290d9b4f6e6933da157);

        let domain_separator = u256_reverse_endian(
            keccak_u256s_be_inputs(array![domain_typehash, name_hash, version_hash].span()),
        );
        assert!(domain_separator == EIP712_DOMAIN_SEPARATOR);
    }
}
