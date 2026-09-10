//! Ethereum-side wrapping for secp256k1-signed user operations.
//!
//! Positions may be owned by either a STARK key or a secp256k1 key. In the secp256k1 case the
//! signer is an Ethereum wallet, which will not produce a raw ECDSA signature over an arbitrary
//! digest — MetaMask exposes `personal_sign` (EIP-191) and `eth_signTypedData_v4` (EIP-712) and
//! nothing else. We use EIP-712, because `bytes32` has exactly one encoding whereas EIP-191's
//! prefix depends on whether the client hands the wallet raw bytes or a hex string.
//!
//! The message being signed is *the same* SNIP-12 Poseidon hash the STARK path uses. It is carried
//! as the single field of a wrapper struct:
//!
//!     PerpsRequest(bytes32 requestHash)
//!
//! so everything the protocol keys on downstream — `approved_requests`, the fulfillment tracker,
//! every emitted `*_hash` — is untouched. Only the final input to signature verification differs.
//!
//! The EIP-712 domain deliberately contains only `name` and `version`. It omits both `chainId` and
//! `verifyingContract` so the wrapper is portable across the Starknet-to-EVM migration and does not
//! couple signing to an Ethereum wallet's active network. The wrapper therefore provides no chain
//! or deployment separation of its own; any required replay protection must come from the wrapped
//! request hash and protocol state. The current SNIP-12 request hash includes the Starknet chain
//! id.

use core::integer::u128_byte_reverse;
use core::keccak::compute_keccak_byte_array;
use starkware_utils::signature::stark::HashType;

/// keccak256("EIP712Domain(string name,string version)")
const DOMAIN_TYPE_HASH: u256 = 0xb03948446334eb9b2196d5eb166f69b9d49403eb4a12f36de8d3f9f3cb8e15c3;

/// keccak256("Perpetuals") — must track `constants::NAME`.
const NAME_HASH: u256 = 0x461e483ab48f972afc9aee07aaa1c12970bee3746628836b5d1fd10275ca210f;

/// keccak256("v0") — must track `constants::VERSION`.
const VERSION_HASH: u256 = 0x042d2d898454f584e9cded7d5fa57170aaeed0dd61e9c290d9b4f6e6933da157;

/// keccak256("PerpsRequest(bytes32 requestHash)")
const REQUEST_TYPE_HASH: u256 = 0x0634a6d29145c9086f1d98cf194c84aacd4da06b6b4ba1de64ceb1bf3a2e3aba;

/// hashStruct(EIP712Domain("Perpetuals", "v0")); reconstructed in the tests below.
const DOMAIN_SEPARATOR: u256 = 0x12b72fb1b17052d7f482c2353585056ac4d79329d91b8271b1c013622f2ba1f9;

/// Cairo's keccak returns the digest with its bytes reversed relative to Ethereum's convention.
/// Every digest that is compared against, or fed into, an Ethereum-produced value must go through
/// here — comparing two Cairo-side digests to each other would hide the mistake.
pub fn keccak_eth(ba: @ByteArray) -> u256 {
    let digest = compute_keccak_byte_array(ba);
    u256 { low: u128_byte_reverse(digest.high), high: u128_byte_reverse(digest.low) }
}

/// Appends `value` as 32 big-endian bytes, the EIP-712 encoding for every atomic type we use.
#[inline(never)]
fn append_word32(ref ba: ByteArray, value: u256) {
    ba.append_word(value.high.into(), 16);
    ba.append_word(value.low.into(), 16);
}

#[cfg(test)]
fn domain_separator() -> u256 {
    let mut encoded: ByteArray = "";
    append_word32(ref encoded, DOMAIN_TYPE_HASH);
    append_word32(ref encoded, NAME_HASH);
    append_word32(ref encoded, VERSION_HASH);
    keccak_eth(@encoded)
}

/// The digest an Ethereum wallet signs for `request_hash`, per EIP-712:
/// `keccak256(0x1901 ‖ domainSeparator ‖ hashStruct(PerpsRequest(request_hash)))`.
pub fn eip712_request_digest(request_hash: HashType) -> u256 {
    let mut encoded_struct: ByteArray = "";
    append_word32(ref encoded_struct, REQUEST_TYPE_HASH);
    append_word32(ref encoded_struct, request_hash.into());
    let struct_hash = keccak_eth(@encoded_struct);

    let mut encoded: ByteArray = "\x19\x01";
    append_word32(ref encoded, DOMAIN_SEPARATOR);
    append_word32(ref encoded, struct_hash);
    keccak_eth(@encoded)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Reference digests were produced independently in Python with `eth_utils.keccak`; see the
    /// investigation notes. Round-tripping Cairo against Cairo would pass even with the byte
    /// order flipped, so these must stay external vectors.
    const REQUEST_HASH: HashType =
        0x04c22f625c59651e1219c60d03055f11f5dc23959929de35861548d86c0bc4ec;

    #[test]
    fn test_keccak_eth_byte_order() {
        // keccak256("") — the canonical empty-input digest, in Ethereum byte order.
        let empty: ByteArray = "";
        assert_eq!(
            keccak_eth(@empty), 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470,
        );
    }

    #[test]
    fn test_domain_type_hashes() {
        let domain_type: ByteArray = "EIP712Domain(string name,string version)";
        assert_eq!(keccak_eth(@domain_type), DOMAIN_TYPE_HASH);

        let name: ByteArray = "Perpetuals";
        assert_eq!(keccak_eth(@name), NAME_HASH);

        let version: ByteArray = "v0";
        assert_eq!(keccak_eth(@version), VERSION_HASH);

        let request_type: ByteArray = "PerpsRequest(bytes32 requestHash)";
        assert_eq!(keccak_eth(@request_type), REQUEST_TYPE_HASH);
    }

    #[test]
    fn test_domain_separator_against_reference() {
        assert_eq!(
            domain_separator(), 0x12b72fb1b17052d7f482c2353585056ac4d79329d91b8271b1c013622f2ba1f9,
        );
    }

    #[test]
    fn test_request_digest_against_reference() {
        assert_eq!(
            eip712_request_digest(REQUEST_HASH),
            0xa53e1026a442ebe85be03f8611b6b22f484b04efcd5997b8955a7f5ccdb4871f,
        );
    }
}
