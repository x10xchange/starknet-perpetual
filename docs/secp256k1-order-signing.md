# secp256k1 `Order` hashing and signing

This document specifies how an external client must hash and sign a perpetual `Order` for a
position whose owner key is a secp256k1 Ethereum address.

The scheme has two layers:

1. Hash the `Order` using the protocol's existing SNIP-12/Poseidon scheme. This produces
   `requestHash`.
2. Put that hash in `PerpsRequest(bytes32 requestHash)` and sign it using EIP-712/secp256k1.

Do not sign the order struct hash or SNIP-12 request hash directly with secp256k1. Do not apply an
Ethereum `personal_sign` prefix. The signature verified by the contract is over the final EIP-712
digest.

This document describes the implementation at the time it was written. Its source of truth is:

- [`Order` and its SNIP-12 type hash](../workspace/apps/perpetuals/contracts/src/core/types/order.cairo)
- [SNIP-12 message hashing](../workspace/apps/perpetuals/contracts/src/core/utils.cairo)
- [EIP-712 wrapping](../workspace/apps/perpetuals/contracts/src/core/eip712.cairo)
- [secp256k1 signature serialization](../workspace/apps/perpetuals/contracts/src/tests/signers.cairo)

Relevant standards and reference libraries:

- [SNIP-12](https://github.com/starknet-io/SNIPs/blob/main/SNIPS/snip-12.md)
- [EIP-712](https://eips.ethereum.org/EIPS/eip-712)
- [`@scure/starknet`](https://github.com/paulmillr/scure-starknet)
- [viem `signTypedData`](https://viem.sh/docs/accounts/local/signTypedData)

## Important conventions

### Position owner key

For a secp256k1 position:

- `owner_key_type` is `1` (`SECP256K1`) when the position is created or its key is rotated.
- `owner_public_key` contains the 20-byte Ethereum address interpreted as an unsigned felt. It does
  not contain the full compressed or uncompressed secp256k1 public key.
- The same Ethereum address is the `public_key`/signer value inside the SNIP-12 message hash.
- `owner_key_type` is position metadata and is not a field of `Order`; it is not included in the
  order hash.

### Felt and byte encoding

The Starknet field prime is:

```text
p = 2^251 + 17 * 2^192 + 1
  = 0x800000000000011000000000000000000000000000000000000000000000001
```

Unsigned fields are hashed as their ordinary non-negative felt value. A signed `i64` is converted
to a felt as follows:

```text
felt(x) = x       if x >= 0
felt(x) = p + x   if x < 0
```

This is field-prime encoding, not 64-bit two's-complement encoding.

Short strings such as `Perpetuals` and `SN_MAIN` are interpreted as big-endian ASCII integers:

```text
'Perpetuals'       = 0x50657270657475616c73
'v0'               = 0x7630
'SN_MAIN'          = 0x534e5f4d41494e
'SN_SEPOLIA'       = 0x534e5f5345504f4c4941
'StarkNet Message' = 0x537461726b4e6574204d657373616765
```

All Poseidon operations below mean Starknet's Poseidon hash-many/sponge operation. Do not replace
it with Pedersen, a pairwise Poseidon fold, or a Poseidon implementation configured for another
field or parameter set.

When a felt is placed in EIP-712 `bytes32`, encode it as exactly 32 bytes, unsigned, big-endian and
left-padded with zero bytes.

## Step 1: hash the `Order`

The Cairo struct is logically:

```text
Order {
    position_id: u32,
    base_asset_id: felt,
    base_amount: i64,
    quote_asset_id: felt,
    quote_amount: i64,
    fee_asset_id: felt,
    fee_amount: u64,
    expiration: u64,
    salt: felt,
}
```

`PositionId`, `AssetId`, and `Timestamp` are single-field Cairo wrappers. Their values are flattened
into the Poseidon input in field order; they do not add another hash layer.

The exact pinned order type hash is:

```text
ORDER_TYPE_HASH =
0x036da8d51815527cabfaa9c982f564c80fa7429616739306036f1f9b608dd112
```

It is Starknet Keccak (Keccak-256 masked to 250 bits) of this exact string:

```text
"Order"("position_id":"felt","base_asset_id":"AssetId","base_amount":"i64","quote_asset_id":"AssetId","quote_amount":"i64","fee_asset_id":"AssetId","fee_amount":"u64","expiration":"Timestamp","salt":"felt")"PositionId"("value":"u32")"AssetId"("value":"felt")"Timestamp"("seconds":"u64")
```

Use the pinned constant. In particular, do not change `"position_id":"felt"` to
`"position_id":"PositionId"` or reorder the dependency definitions, even if another SNIP-12
encoder would canonicalize the schema differently.

The order struct hash is:

```text
orderStructHash = poseidonHashMany([
    ORDER_TYPE_HASH,
    position_id,
    base_asset_id,
    felt(base_amount),
    quote_asset_id,
    felt(quote_amount),
    fee_asset_id,
    fee_amount,
    expiration,
    salt,
])
```

## Step 2: build the SNIP-12 request hash

The current Starknet SNIP-12 domain is:

```text
name     = 'Perpetuals'
version  = 'v0'
chain_id = the Starknet chain on which the order will be submitted
revision = 1
```

Its type hash is:

```text
STARKNET_DOMAIN_TYPE_HASH =
0x01ff2f602e42168014d405a94f75e8a93d640751d71d16311266e140d8b0a210
```

Calculate:

```text
snip12DomainHash = poseidonHashMany([
    STARKNET_DOMAIN_TYPE_HASH,
    shortString('Perpetuals'),
    shortString('v0'),
    chain_id,
    1,
])

requestHash = poseidonHashMany([
    shortString('StarkNet Message'),
    snip12DomainHash,
    ownerEthereumAddress,
    orderStructHash,
])
```

`ownerEthereumAddress` is the numeric value of the 20-byte address stored on the position. Using a
full secp256k1 public key, a Stark public key, an account contract address, or the Core contract
address here will produce the wrong hash.

Although the outer EIP-712 domain below has no chain ID, the SNIP-12 `requestHash` does. An order
hashed for `SN_MAIN` will not verify on `SN_SEPOLIA`, and vice versa.

## Step 3: wrap `requestHash` in EIP-712

The exact EIP-712 data is:

```text
EIP712Domain(string name,string version)
PerpsRequest(bytes32 requestHash)

domain.name       = "Perpetuals"
domain.version    = "v0"
message.requestHash = bytes32(requestHash)
```

The domain intentionally contains neither `chainId` nor `verifyingContract`. Do not add either
field, and do not add empty or zero-valued versions of them. The domain type itself must contain
only `name` and `version`.

The constants are:

```text
keccak256("EIP712Domain(string name,string version)")
  = 0xb03948446334eb9b2196d5eb166f69b9d49403eb4a12f36de8d3f9f3cb8e15c3

keccak256("Perpetuals")
  = 0x461e483ab48f972afc9aee07aaa1c12970bee3746628836b5d1fd10275ca210f

keccak256("v0")
  = 0x042d2d898454f584e9cded7d5fa57170aaeed0dd61e9c290d9b4f6e6933da157

keccak256("PerpsRequest(bytes32 requestHash)")
  = 0x0634a6d29145c9086f1d98cf194c84aacd4da06b6b4ba1de64ceb1bf3a2e3aba

domainSeparator
  = keccak256(domainTypeHash || nameHash || versionHash)
  = 0x12b72fb1b17052d7f482c2353585056ac4d79329d91b8271b1c013622f2ba1f9
```

Each `||` operand in the domain and struct encodings is one 32-byte word. Calculate the final
digest as:

```text
requestStructHash = keccak256(
    requestTypeHash || bytes32(requestHash)
)

eip712Digest = keccak256(
    0x1901 || domainSeparator || requestStructHash
)
```

Ask the wallet to sign the typed data. Do not ask it to sign `eip712Digest` as a normal message,
because that would add the EIP-191 `personal_sign` prefix and hash it again.

Raw JSON-RPC typed data has this shape:

```json
{
  "types": {
    "EIP712Domain": [
      { "name": "name", "type": "string" },
      { "name": "version", "type": "string" }
    ],
    "PerpsRequest": [{ "name": "requestHash", "type": "bytes32" }]
  },
  "primaryType": "PerpsRequest",
  "domain": {
    "name": "Perpetuals",
    "version": "v0"
  },
  "message": {
    "requestHash": "0x...exactly 64 hex digits..."
  }
}
```

## Step 4: serialize the signature for Cairo

The wallet normally returns a 65-byte signature:

```text
r (32 bytes) || s (32 bytes) || v (1 byte)
```

Normalize the recovery value to `y_parity`:

```text
y_parity = v       if v is 0 or 1
y_parity = v - 27  if v is 27 or 28
```

Reject any other value. The verifier requires a low-`s` secp256k1 signature. Standard Ethereum
wallet libraries normally produce one, but an implementation accepting externally supplied
signatures should enforce `s <= secp256k1_n / 2`.

Serialize the signature as these five Cairo felts:

```text
[
    r & (2^128 - 1),
    r >> 128,
    s & (2^128 - 1),
    s >> 128,
    y_parity,
]
```

The order is low limb first. When calling through a Starknet SDK, pass this as a five-element
array/span and let the SDK add the Cairo array length. Do not pass Ethereum's `v` value `27` or `28`
directly as the fifth felt.

## Complete golden vector

The private key below is public test data. Never use it for real funds.

The sample asset IDs are illustrative; this vector is intended to test hashing and signing and is
not necessarily executable against a deployed market.

### Key and order

```text
secp256k1 private key:
0x9a8b7c6d5e4f30211122334455667788990011223344556677889900aabbccdd

Ethereum address:
0x791F8294Add8396e4A7Bb6338700ce6247647a72

Starknet chain ID:
'SN_MAIN' = 0x534e5f4d41494e
```

| Order field      |        Logical value |                                             Felt passed to Poseidon |
| ---------------- | -------------------: | ------------------------------------------------------------------: |
| `position_id`    |             `123456` |                                                           `0x1e240` |
| `base_asset_id`  |     ASCII `BTC-PERP` |                                                `0x4254432d50455250` |
| `base_amount`    |           `25000000` |                                                         `0x17d7840` |
| `quote_asset_id` |         ASCII `USDC` |                                                        `0x55534443` |
| `quote_amount`   |        `-1250000000` | `0x800000000000010ffffffffffffffffffffffffffffffffffffffffb57e8381` |
| `fee_asset_id`   |         ASCII `USDC` |                                                        `0x55534443` |
| `fee_amount`     |            `2500000` |                                                          `0x2625a0` |
| `expiration`     |         `1893456000` |                                                        `0x70dbd880` |
| `salt`           | `0x0123456789abcdef` |                                                `0x0123456789abcdef` |

The exact first Poseidon input is:

```text
[
  0x36da8d51815527cabfaa9c982f564c80fa7429616739306036f1f9b608dd112,
  0x1e240,
  0x4254432d50455250,
  0x17d7840,
  0x55534443,
  0x800000000000010ffffffffffffffffffffffffffffffffffffffffb57e8381,
  0x55534443,
  0x2625a0,
  0x70dbd880,
  0x123456789abcdef
]
```

Expected intermediate hashes, shown as fixed-width 32-byte values:

```text
snip12DomainHash =
0x038d7910d4785470e8138ba27e6130abe78124c7f39b2af4c28a5a426e631b79

orderStructHash =
0x04fef85a257541351c448169d1e249efce862fd8a3593d13cc6a1f107a016735

requestHash =
0x0432f8b0fb99d342f271fd3a963e723ca3091a65ec9ad78e7941a3712c06cefd
```

The EIP-712 message for this vector is:

```json
{
  "types": {
    "EIP712Domain": [
      { "name": "name", "type": "string" },
      { "name": "version", "type": "string" }
    ],
    "PerpsRequest": [{ "name": "requestHash", "type": "bytes32" }]
  },
  "primaryType": "PerpsRequest",
  "domain": {
    "name": "Perpetuals",
    "version": "v0"
  },
  "message": {
    "requestHash": "0x0432f8b0fb99d342f271fd3a963e723ca3091a65ec9ad78e7941a3712c06cefd"
  }
}
```

Expected EIP-712 intermediates:

```text
requestStructHash =
0x1ee3d7d751390e32bc54aa3f14437ed5d457a3087dbab6d2b81fffebbe5cd3f2

eip712Digest =
0xec681621326678635e858453847fa30741e35669cfe356dc57f5761115f3f9f2
```

Expected 65-byte Ethereum signature (`r || s || v`):

```text
0xdcbd1f2f2fe383ccf23f7dbadae62c6a5effd6a8f128d505eaca8d1aa672b2eb32915f551d952833e326e36d52acc384aefe7588671f27b84653a4a90831f1f11b
```

All hash values must match exactly. A valid ECDSA implementation may produce a different signature
because the signing nonce is not unique. The signature above is the deterministic result produced
by viem and Foundry for this key and digest; another result is compatible if it is low-`s`, verifies
against the same digest, and recovers the expected Ethereum address.

Split values:

```text
r = 0xdcbd1f2f2fe383ccf23f7dbadae62c6a5effd6a8f128d505eaca8d1aa672b2eb
s = 0x32915f551d952833e326e36d52acc384aefe7588671f27b84653a4a90831f1f1
v = 0x1b = 27
y_parity = 0
```

Expected Cairo signature array:

```text
[
  0x5effd6a8f128d505eaca8d1aa672b2eb,
  0xdcbd1f2f2fe383ccf23f7dbadae62c6a,
  0xaefe7588671f27b84653a4a90831f1f1,
  0x32915f551d952833e326e36d52acc384,
  0x0
]
```

## Runnable TypeScript reference

Install the two dependencies and pin versions in production:

```bash
npm install @scure/starknet viem
```

The following program reproduces every golden value and demonstrates local signing. For a browser
wallet, construct the same `typedData` object and pass it to the wallet client's
`signTypedData`/`eth_signTypedData_v4` method instead of using the test private key.

```typescript
import assert from "node:assert/strict";
import { poseidonHashMany } from "@scure/starknet";
import { hashTypedData, type Hex } from "viem";
import { privateKeyToAccount } from "viem/accounts";

const FELT_PRIME = (1n << 251n) + 17n * (1n << 192n) + 1n;
const MASK_128 = (1n << 128n) - 1n;
const SECP256K1_N =
  0xfffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141n;

const ORDER_TYPE_HASH =
  0x36da8d51815527cabfaa9c982f564c80fa7429616739306036f1f9b608dd112n;
const STARKNET_DOMAIN_TYPE_HASH =
  0x1ff2f602e42168014d405a94f75e8a93d640751d71d16311266e140d8b0a210n;

function shortString(value: string): bigint {
  const bytes = new TextEncoder().encode(value);
  if (bytes.length > 31) throw new Error("short string exceeds 31 bytes");

  let result = 0n;
  for (const byte of bytes) result = (result << 8n) | BigInt(byte);
  return result;
}

function signedI64ToFelt(value: bigint): bigint {
  const min = -(1n << 63n);
  const max = (1n << 63n) - 1n;
  if (value < min || value > max) throw new Error("value is outside i64 range");
  return value < 0n ? FELT_PRIME + value : value;
}

function bytes32(value: bigint): Hex {
  if (value < 0n || value >= 1n << 256n)
    throw new Error("value is outside bytes32 range");
  return `0x${value.toString(16).padStart(64, "0")}` as Hex;
}

function cairoSignature(signature: Hex): bigint[] {
  const raw = signature.slice(2);
  if (raw.length !== 130)
    throw new Error("expected a 65-byte r || s || v signature");

  const r = BigInt(`0x${raw.slice(0, 64)}`);
  const s = BigInt(`0x${raw.slice(64, 128)}`);
  const v = Number.parseInt(raw.slice(128, 130), 16);
  const yParity = v >= 27 ? v - 27 : v;

  if (yParity !== 0 && yParity !== 1) throw new Error("invalid recovery value");
  if (s > SECP256K1_N / 2n) throw new Error("high-s signature is not accepted");

  return [r & MASK_128, r >> 128n, s & MASK_128, s >> 128n, BigInt(yParity)];
}

const privateKey =
  "0x9a8b7c6d5e4f30211122334455667788990011223344556677889900aabbccdd" as Hex;
const account = privateKeyToAccount(privateKey);

const order = {
  positionId: 123456n,
  baseAssetId: 0x4254432d50455250n,
  baseAmount: 25_000_000n,
  quoteAssetId: 0x55534443n,
  quoteAmount: -1_250_000_000n,
  feeAssetId: 0x55534443n,
  feeAmount: 2_500_000n,
  expiration: 1_893_456_000n,
  salt: 0x0123456789abcdefn,
};

const orderStructHash = poseidonHashMany([
  ORDER_TYPE_HASH,
  order.positionId,
  order.baseAssetId,
  signedI64ToFelt(order.baseAmount),
  order.quoteAssetId,
  signedI64ToFelt(order.quoteAmount),
  order.feeAssetId,
  order.feeAmount,
  order.expiration,
  order.salt,
]);

const snip12DomainHash = poseidonHashMany([
  STARKNET_DOMAIN_TYPE_HASH,
  shortString("Perpetuals"),
  shortString("v0"),
  shortString("SN_MAIN"),
  1n,
]);

const ownerEthereumAddress = BigInt(account.address);
const requestHash = poseidonHashMany([
  shortString("StarkNet Message"),
  snip12DomainHash,
  ownerEthereumAddress,
  orderStructHash,
]);

const typedData = {
  domain: {
    name: "Perpetuals",
    version: "v0",
  },
  types: {
    PerpsRequest: [{ name: "requestHash", type: "bytes32" }],
  },
  primaryType: "PerpsRequest",
  message: {
    requestHash: bytes32(requestHash),
  },
} as const;

const eip712Digest = hashTypedData(typedData);
const signature = await account.signTypedData(typedData);
const serialized = cairoSignature(signature);

assert.equal(account.address, "0x791F8294Add8396e4A7Bb6338700ce6247647a72");
assert.equal(
  bytes32(snip12DomainHash),
  "0x038d7910d4785470e8138ba27e6130abe78124c7f39b2af4c28a5a426e631b79",
);
assert.equal(
  bytes32(orderStructHash),
  "0x04fef85a257541351c448169d1e249efce862fd8a3593d13cc6a1f107a016735",
);
assert.equal(
  bytes32(requestHash),
  "0x0432f8b0fb99d342f271fd3a963e723ca3091a65ec9ad78e7941a3712c06cefd",
);
assert.equal(
  eip712Digest,
  "0xec681621326678635e858453847fa30741e35669cfe356dc57f5761115f3f9f2",
);
assert.equal(
  signature,
  "0xdcbd1f2f2fe383ccf23f7dbadae62c6a5effd6a8f128d505eaca8d1aa672b2eb32915f551d952833e326e36d52acc384aefe7588671f27b84653a4a90831f1f11b",
);
assert.deepEqual(serialized, [
  0x5effd6a8f128d505eaca8d1aa672b2ebn,
  0xdcbd1f2f2fe383ccf23f7dbadae62c6an,
  0xaefe7588671f27b84653a4a90831f1f1n,
  0x32915f551d952833e326e36d52acc384n,
  0n,
]);

console.log({
  owner: account.address,
  snip12DomainHash: bytes32(snip12DomainHash),
  orderStructHash: bytes32(orderStructHash),
  requestHash: bytes32(requestHash),
  eip712Digest,
  signature,
  cairoSignature: serialized.map((value) => `0x${value.toString(16)}`),
});
```

## Integration checklist

An implementation is compatible when it can reproduce all of the following independently:

1. The negative `quote_amount` felt.
2. `orderStructHash` from the ten-element order Poseidon input.
3. `snip12DomainHash` for the target Starknet chain.
4. `requestHash` using the owner's Ethereum address.
5. The EIP-712 domain separator and `requestStructHash`.
6. The final EIP-712 digest.
7. Recovery of the expected Ethereum address from the signature.
8. The five-felt Cairo signature serialization.

## Security and replay notes

- The wallet-visible EIP-712 message contains an opaque `requestHash`, not the individual order
  fields. A client should display and validate the decoded order separately before requesting a
  signature.
- The EIP-712 domain deliberately provides no chain or deployment separation. The current inner
  SNIP-12 hash provides Starknet chain separation, but it does not identify a specific Core
  deployment.
- The order's `salt`, `expiration`, position ownership, and protocol fulfillment state are part of
  the protocol's replay controls. Use a fresh unpredictable salt for every order.
- Hash every integer from its exact quantized protocol value. Do not hash decimal display values or
  JavaScript `number` values that may have lost precision; use `bigint` or an arbitrary-precision
  integer type throughout.
- Ethereum addresses are case-insensitive numeric values. Checksum casing does not affect either
  hash.
