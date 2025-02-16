# Perpetuals \- Specs

<details>
    <summary><strong style="font-size: 1.5em;">Table of contents</strong></summary>

- # Table of contents
- [Core contract](#core-contract)
    - [Value risk calculator](#value-risk-calculator)
        - [Total Value (TV) and Total Risk (TR)](#total-value-\(tv\)-and-total-risk-\(tr\))
        - [Structs](#structs)
            - [PositionTVTR](#positiontvtr)
            - [PositionTVTRChange](#positiontvtrchange)
            - [PositionState](#positionstate)
            - [Deleveragable](#deleveragable)
            - [Liquidatable](#liquidatable)
            - [Healthy](#healthy)
            - [ChangeEffects](#changeeffects)
            - [Is Healthier](#is-healthier)
            - [Is Fair Deleverage](#is-fair-deleverage)
            - [PositionChangeResult](#positionchangeresult)
        - [Functions](#functions)
            - [Evaluate Position Change](#evaluate-position-change)
                - [Description](#description)
                - [Logic](#logic)
    - [Structs](#structs-1)
        - [Signature](#signature)
        - [PublicKey](#publickey)
        - [HashType](#hashtype)
        - [AssetId](#assetid)
        - [AssetEntry](#assetentry)
        - [PositionData](#positiondata)
        - [AssetDiffEntry](#assetdiffentry)
        - [PositionDiff](#positiondiff)
        - [PositionId](#positionid)
        - [FundingIndex](#fundingindex)
        - [Balance](#balance)
        - [Price](#price)
        - [Timestamp](#timestamp)
        - [TimeDelta](#timedelta)
        - [FundingTick](#fundingtick)
        - [PriceTick](#pricetick)
        - [FixedTwoDecimal](#fixedtwodecimal)
        - [Position](#position)
        - [CollateralAsset](#collateralasset)
        - [SyntheticAsset](#syntheticasset)
        - [CollateralConfig](#assetstatus)
        - [SyntheticConfig](#syntheticconfig)
        - [CollateralTimelyData](#collateraltimelydata)
        - [SyntheticTimelyData](#synthetictimelydata)
    - [Get Message Hash](#get-message-hash)
        - [WithdrawArgs](#withdrawargs)
        - [TransferArgs](#transferargs)
        - [SetPublicKeyArgs](#setpublickeyargs)
        - [SetOwnerAccountArgs](#setowneraccountargs)
        - [Order](#order)
    - [Components](#components)
        - [Assets](#assets)
        - [Deposit](#deposit)
        - [Nonce](#nonce)
        - [Pausable](#pausable)
        - [Replaceability](#replaceability)
        - [Requests](#requests)
        - [Roles](#roles)
        - [Positions](#positions)
    - [Storage](#storage)
    - [Validations](#validations)
        - [Pause](#pause)
        - [Position](#position-1)
        - [Operator Nonce](#operator-nonce)
        - [Signature](#signature-1)
        - [Caller validation](#caller-validation)
        - [Public key signature](#public-key-signature)
        - [Expiration](#expiration)
        - [Requests](#requests-1)
        - [Funding](#funding)
        - [Price](#price-1)
        - [Amount](#amount)
        - [Asset](#asset)
        - [Fulfillment](#fulfillment)
        - [Fundamental](#fundamental)
    - [Errors](#errors)
    - [Events](#events)
        - [NewPosition](#newposition)
        - [Deposit](#deposit-1)
        - [DepositCanceled](#depositcanceled)
        - [DepositProcessed](#depositprocessed)
        - [WithdrawRequest](#withdrawrequest)
        - [Withdraw](#withdraw)
        - [Trade](#trade)
        - [Liquidate](#liquidate)
        - [Deleverage](#deleverage)
        - [TransferRequest](#transferrequest)
        - [Transfer](#transfer)
        - [SetOwnerAccount](#setowneraccount)
        - [SetPublicKeyRequest](#setpublickeyrequest)
        - [SetPublicKey](#setpublickey)
        - [FundingTick](#fundingtick-1)
        - [PriceTick](#pricetick-1)
        - [AssetActivated](#assetactivated)
        - [AddSynthetic](#addsynthetic)
        - [DeactivateSyntheticAsset](#deactivatesyntheticasset)
        - [UpdateOracleQuorum](#updateoraclequorum)
        - [RemoveOracle](#removeoracle)
        - [AddOracle](#addoracle)
        - [RegisterCollateral](#registercollateral)
    - [Constructor](#constructor)
    - [Public Functions](#public-functions)
        - [New Position](#new-position)
        - [Deposit](#deposit-2)
        - [Process Deposit](#process-deposit)
        - [Cancel Pending Deposit](#cancel-pending-deposit)
        - [Withdraw Request](#withdraw-request)
        - [Withdraw](#withdraw-1)
        - [Transfer Request](#transfer-request)
        - [Trade](#trade-1)
        - [Liquidate](#liquidate-1)
        - [Deleverage](#deleverage-1)
        - [Set Owner Account](#set-owner-account)
        - [Set Public Key Request](#set-public-key-request)
        - [Set Public Key](#set-public-key)
        - [Funding Tick](#funding-tick)
        - [Add Oracle To Asset](#add-oracle-to-asset)
        - [Remove Oracle](#remove-oracle)
        - [Update Synthetic Quorum](#update-synthetic-quorum)
        - [Price Tick](#price-tick)
        - [Register Collateral](#register-collateral)
        - [Add Synthetic](#add-synthetic)
        - [Deactivate Synthetic](#deactivate-synthetic)
</details>

# Core contract

## Value risk calculator

### Total Value (TV) and Total Risk (TR)
<img src="../assets/tv-tr-example.png" alt="tv tr example" />

[Same as in StarkEx](https://docs.starkware.co/starkex/perpetual/perpetual_overview.html#total_value_total_risk)

The *total value* of a position is the sum of the value of the position’s collateral and synthetic assets, expressed in the collateral currency.   
The *total risk* is a measurement that includes the total value of all synthetic assets in a position, and also takes into account a predetermined *risk factor* for each synthetic asset. As the risk factor increases, so does the total risk.  
Example:

## Structs

### PositionTVTR

```rust
pub struct PositionTVTR {
    pub total_value: i128,
    pub total_risk: u128,
}

```

### PositionTVTRChange

```rust
pub struct PositionTVTRChange {
    pub before: PositionTVTR,
    pub after: PositionTVTR,
}
```

### PositionState

```rustrust
pub enum PositionState {
    Healthy,
    Liquidatable,
    Deleveragable,
}
```

### Deleveragable

A position is in deleveragable state when:  
$TV < 0$

### Liquidatable

A position is in liquidatable state when:  
$|TV| < TR$

### Healthy

A position is in a healthy state when:  
$|TV| \geq TR$

### ChangeEffects

```rust
pub struct ChangeEffects {
    pub is_healthier: bool,
    pub is_fair_deleverage: bool,
}
```

### Is Healthier

1. $(\frac{TV}{TR})_{new}\leq(\frac{TV}{TR})_{old}$

   **AND**  
2. $TR_{new}<TR_{old}$

### Is Fair Deleverage

1. $\frac{TV_{new}-1USDC}{TR_{new}}<\frac{TV}{TR}_{old}\leq\frac{TV}{TR}_{new}$

Deleveragerer should be healthy or healthier.  
Deleveragree should be (healthy or healthier) **and** is fair deleverage 

### PositionChangeResult

```rust
pub struct PositionChangeResult {
    pub position_state_before_change: PositionState,
    pub position_state_after_change: PositionState,
    pub change_effects: Option<ChangeEffects>,
}
```

## Functions

### Evaluate Position Change

#### Description

```rust
fn evaluate_position_change(
self: @ContractState, position: PositionData, position_diff: PositionDiff,
) -> PositionChangeResult
```

#### Logic

1. Initialize total\_value\_before \= 0  
2. Initialize total\_risk\_before \= 0  
3. Iterate over `position.asset_entries`:  
   1. total\_value\_before+= asset\_price\*asset\_balance  
   2. total\_risk\_before+= asset\_price\*asset\_balance\*asset\_risk\_factor  
4. Initialize total\_value\_after \= total\_value\_before  
5. Initialize total\_risk\_after \= total\_risk\_before  
6. Iterate over `position_diff`:  
   1. total\_value\_after \+= price\*balance\_after \- price\*balance\_before  
   2. total\_risk\_after \+= risk\_factor \* (price\*balance\_after \- price\*balance\_before)  
7. Return the [`PositionChangeResult`](#positionchangeresult) according to the Total Risk and Total Value.

## Structs 

### Signature

```rust
pub type Signature = Span<felt252>;
```

### PublicKey

```rust
pub type PublicKey = felt252;
```

### HashType

```rust
pub type HashType = felt252;
```

### AssetId

```rust
pub struct AssetId { 
pub value: felt252,
}
```

### AssetEntry

```rust
pub struct AssetEntry {
    pub id: AssetId,
    pub balance: Balance,
    pub price: Price,
}
```

### PositionData

```rust
pub struct PositionData {
    pub asset_entries: Span<AssetEntry>,
}
```

### AssetDiffEntry

```rust
pub struct AssetDiffEntry {
    pub id: AssetId,
    pub before: Balance,
    pub after: Balance,
    pub price: Price,
}
```

### PositionDiff

```rust
pub type PositionDiff = Span<AssetDiffEntry>;
```

### PositionId 

```rust
struct PositionId { 
value: u32,
}
```

### FundingIndex 

```rust
pub struct FundingIndex {
/// Signed 64-bit fixed-point number:
/// 1 sign bit, 31-bits integer part, 32-bits fractional part.
pub value: i64 
}
```

### Balance

```rust
pub struct Balance { 
pub value: i64 
}
```

### Price

```rust
pub struct Price {
	// Unsigned 28-bit fixed point decimal percision.
// 28-bit for the integer part and 28-bit for the fractional part.
pub value: u64 
}
```

### Timestamp

```rust
pub struct Timestamp { 
pub seconds: u64 
}
```

### TimeDelta

```rust
pub struct TimeDelta { 
pub seconds: u64 
}
```

### FundingTick

```rust
pub struct FundingTick {
	asset_id: AssetId,
	funding_index: FundingIndex
}
```

### PriceTick 

```rust
pub struct PriceTick {
	signature: Signature,
	signer_public_key: felt252,
	timestamp: u32,
	price: u128,
}
```

### FixedTwoDecimal 

```rust
// Fixed-point decimal with 2 decimal places. 
// Example: 0.75 is represented as 75.
pub struct FixedTwoDecimal { 
    pub value: u8 // Stores number * 100
}
```

### Position

```rust
#[starknet::storage_node]
struct Position {
    version: u8,
    owner_account: ContractAddress,
    owner_public_key: felt252,
    collateral_assets_head: Option<AssetId>,
    collateral_assets: Map<AssetId, CollateralAsset>,
    synthetic_assets_head: Option<AssetId>,
    synthetic_assets: Map<AssetId, SyntheticAsset>,
}
```

### CollateralAsset

```rust
struct CollateralAsset {
    pub version: u8,
    pub balance: Balance,
    pub next: Option<AssetId>,
}
```

### SyntheticAsset

```rust
struct SyntheticAsset {
    pub version: u8,
    pub balance: Balance,
    pub funding_index: FundingIndex,
    pub next: Option<AssetId>,
}
```

### AssetStatus

```rust
pub enum AssetStatus {
    PENDING,
    ACTIVATED,
    DEACTIVATED,
}

impl AssetStatusPacking of StorePacking<AssetStatus, u8> {
    fn pack(value: AssetStatus) -> u8 {
        match value {
            AssetStatus::PENDING => 0,
            AssetStatus::ACTIVATED => 1,
            AssetStatus::DEACTIVATED => 2,
        }
    }

    fn unpack(value: u8) -> AssetStatus {
        match value {
            0 => AssetStatus::PENDING,
            1 => AssetStatus::ACTIVATED,
            2 => AssetStatus::DEACTIVATED,
            _ => panic_with_felt252(INVALID_STATUS),
        }
    }
}

```

### CollateralConfig

```rust
struct CollateralConfig {
    pub version: u8,
    // Collateral ERC20 contract address
    pub address: ContractAddress,
    // Configurable.
    pub status: AssetStatus,
    pub quantum: u64,
    pub risk_factor: FixedTwoDecimal,
    // Number of oracles that need to sign on the price to accept it.
    pub quorum: u8,
}
```

### SyntheticConfig

```rust
struct SyntheticConfig {
    pub version: u8,
    // Configurable
    pub status: AssetStatus,
    // Resolution is the total number of the smallest part of a synthetic.
    pub resolution: u64,
    // Number of oracles that need to sign on the price to accept it.
    pub quorum: u8,
}
```

### CollateralTimelyData 

```rust
struct CollateralTimelyData {
	pub version: u8,
    pub price: Price,
    pub last_price_update: Timestamp,
    pub next: Option<AssetId>,
}
```

### SyntheticTimelyData

```rust 
struct SyntheticTimelyData {
	pub version: u8,
    pub price: Price,
    pub last_price_update: Timestamp,
    pub funding_index: FundingIndex,
    pub next: Option<AssetId>,
}
```

## Get Message Hash 

Hash on the following args are done according to [SNIP-12](https://github.com/starknet-io/SNIPs/blob/main/SNIPS/snip-12.md).

```rust
pub(crate) impl OffchainMessageHashImpl<
    T, +StructHash<T>, impl metadata: SNIP12Metadata,
> of OffchainMessageHash<T> {
    fn get_message_hash(self: @T, public_key: PublicKey) -> HashType {
        let domain = StarknetDomain {
            name: metadata::name(),
            version: metadata::version(),
            chain_id: get_tx_info().unbox().chain_id,
            revision: '1',
        };
        let mut state = PoseidonTrait::new();
        state = state.update_with('StarkNet Message');
        state = state.update_with(domain.hash_struct());
        state = state.update_with(public_key);
        state = state.update_with(self.hash_struct());
        state.finalize()
    }
}
```

The `hash_struct()` is the following:

```rust
fn hash_struct(self: @TYPE) -> HashType {
    let hash_state = PoseidonTrait::new();
    hash_state.update_with(TYPE_HASH).update_with(*self).finalize()
}

```

The `StarknetDomain` values are:  
 

```rust
const NAME: felt252 = 'Perpetuals';
const VERSION: felt252 = 'v0';
```

And the `StarknetDomain` type hash is:  

```rust
// selector!(
//   "\"StarknetDomain\"(
//    \"name\":\"shortstring\",
//    \"version\":\"shortstring\",
//    \"chainId\":\"shortstring\",
//    \"revision\":\"shortstring\"
//   )"
// );
pub const STARKNET_DOMAIN_TYPE_HASH: HashType =
    0x1ff2f602e42168014d405a94f75e8a93d640751d71d16311266e140d8b0a210;

```

The public key is the position public key.

### WithdrawArgs
```rust
pub struct WithdrawArgs {
    pub recipient: ContractAddress,
    pub position_id: PositionId,
    pub collateral_id: AssetId,
    pub amount: u64,
    pub expiration: Timestamp,
    pub salt: felt252,
}

/// selector!(
///   "\"WithdrawArgs\"(
///    \"recipient\":\"ContractAddress\",
///    \"position_id\":\"PositionId\",
///    \"collateral_id\":\"AssetId\",
///    \"amount\":\"u64\",
///    \"expiration\":\"Timestamp\"
///    \"salt\":\"felt\",
///    )
///    \"PositionId\"(
///    \"value\":\"felt\"
///    )"
///    \"AssetId\"(
///    \"value\":\"felt\"
///    )"
///    \"Timestamp\"(
///    \"seconds\":\"u64\"
///    )
/// );
const WITHDRAW_ARGS_TYPE_HASH: HashType =
    0xe448e0bfe1cbb05949be6a78782513a905154f70479e57a9a6a674445e84ed;

impl StructHashImpl of StructHash<WithdrawArgs> {
    fn hash_struct(self: @WithdrawArgs) -> HashType {
        let hash_state = PoseidonTrait::new();
        hash_state.update_with(WITHDRAW_ARGS_TYPE_HASH).update_with(*self).finalize()
    }
}
```

### TransferArgs

```rust
pub struct TransferArgs {
    pub recipient: PositionId,
    pub position_id: PositionId,
    pub collateral_id: AssetId,
    pub amount: u64,
    pub expiration: Timestamp,
    pub salt: felt252,
}


/// selector!(
///   "\"TransferArgs\"(
///    \"recipient\":\"PositionId\",
///    \"position_id\":\"PositionId\",
///    \"collateral_id\":\"AssetId\"
///    \"amount\":\"u64\"
///    \"expiration\":\"Timestamp\",
///    \"salt\":\"felt\"
///    )
///    \"PositionId\"(
///    \"value\":\"felt\"
///    )"
///    \"AssetId\"(
///    \"value\":\"felt\"
///    )"
///    \"Timestamp\"(
///    \"seconds\":\"u64\"
///    )
/// );
const TRANSFER_ARGS_TYPE_HASH: HashType =
    0x3fb5df0157f6dd203dfa79d636eb34324be3d0aae154623c6b904b2153a61f6;

impl StructHashImpl of StructHash<TransferArgs> {
    fn hash_struct(self: @TransferArgs) -> HashType {
        let hash_state = PoseidonTrait::new();
        hash_state.update_with(TRANSFER_ARGS_TYPE_HASH).update_with(*self).finalize()
    }
}
```

### SetPublicKeyArgs

```rust
pub struct SetPublicKeyArgs {
    pub position_id: PositionId,
    pub new_public_key: PublicKey,
    pub expiration: Timestamp,
}

/// selector!(
///   "\"SetPublicKeyArgs\"(
///    \"position_id\":\"PositionId\",
///    \"new_public_key\":\"felt\",
///    \"expiration\":\"Timestamp\"
///    )
///    \"PositionId\"(
///    \"value\":\"felt\"
///    )"
///    \"Timestamp\"(
///    \"seconds\":\"u64\"
///    )
/// );
const SET_PUBLIC_KEY_ARGS_HASH: HashType =
    0xb79fbe994c2722b9c9686014e7b05f49373b3d54baa20fb09d60bd8735301c;

impl StructHashImpl of StructHash<SetPublicKeyArgs> {
    fn hash_struct(self: @SetPublicKeyArgs) -> HashType {
        let hash_state = PoseidonTrait::new();
        hash_state.update_with(SET_PUBLIC_KEY_ARGS_HASH).update_with(*self).finalize()
    }
}
```

### SetOwnerAccountArgs

```rust
pub struct SetOwnerAccountArgs {
    pub position_id: PositionId,
    pub public_key: PublicKey,
    pub new_account_owner: ContractAddress,
    pub expiration: Timestamp,
}


/// selector!(
///   "\"SetOwnerAccountArgs\"(
///    \"position_id\":\"PositionId\",
///    \"public_key\":\"felt\",
///    \"new_account_owner\":\"ContractAddress\",
///    \"expiration\":\"Timestamp\"
///    )
///    \"PositionId\"(
///    \"value\":\"felt\"
///    )"
///    \"Timestamp\"(
///    \"seconds\":\"u64\"
///    )
/// );
const SET_POSITION_OWNER_ARGS_HASH: HashType =
    0x1015a2f2e38a330c931e7e8af30b630d21c0399752f94f9a2766534fe795c53;

impl StructHashImpl of StructHash<SetOwnerAccountArgs> {
    fn hash_struct(self: @SetOwnerAccountArgs) -> HashType {
        let hash_state = PoseidonTrait::new();
        hash_state.update_with(SET_POSITION_OWNER_ARGS_HASH).update_with(*self).finalize()
    }
}

```

### Order 

```rust
pub struct Order {
    pub position_id: PositionId,
    pub base_asset_id: AssetId,
    pub base_amount: i64,
    pub quote_asset_id: AssetId,
    pub quote_amount: i64,
    pub fee_asset_id: AssetId,
    pub fee_amount: u64,
    pub expiration: Timestamp,
    pub salt: felt252,
}


/// selector!(
///   "\"Order\"(
///    \"position_id\":\"PositionId\",
///    \"base_asset_id\":\"AssetId\",
///    \"base_amount\":\"i64\",
///    \"quote_asset_id\":\"AssetId\",
///    \"quote_amount\":\"i64\",
///    \"fee_asset_id\":\"AssetId\",
///    \"fee_amount\":\"u64\",
///    \"expiration\":\"Timestamp\",
///    \"salt\":\"felt\"
///    )
///    \"PositionId\"(
///    \"value\":\"felt\"
///    )"
///    \"AssetId\"(
///    \"value\":\"felt\"
///    )"
///    \"Timestamp\"(
///    \"seconds\":\"u64\"
///    )
/// );

const ORDER_TYPE_HASH: HashType = 0x26e3f2492aae9866d09bd1635084175acbb80a33730cd0f2314b21c7f9d47eb;

impl StructHashImpl of StructHash<Order> {
    fn hash_struct(self: @Order) -> HashType {
        let hash_state = PoseidonTrait::new();
        hash_state.update_with(ORDER_TYPE_HASH).update_with(*self).finalize()
    }
}

```

## Components 

### Assets

In charge of all assets-related.

```rust
#[starknet::interface]
pub trait IAssets<TContractState> {
    fn get_price_validation_interval(self: @TContractState) -> TimeDelta;
    fn get_funding_validation_interval(self: @TContractState) -> TimeDelta;
    fn get_max_funding_rate(self: @TContractState) -> u32;
}
```

```rust
#[storage]
Struct Storage {
    /// 32-bit fixed-point number with a 32-bit fractional part.
    max_funding_rate: u32,
    max_price_interval: TimeDelta,
    max_funding_interval: TimeDelta,
    // Updates each price validation.
    pub last_price_validation: Timestamp,
    // Updates every funding tick.
    pub last_funding_tick: Timestamp,
    pub collateral_config: Map<AssetId, Option<CollateralConfig>>,
    pub synthetic_config: Map<AssetId, Option<SyntheticConfig>>,
    pub collateral_timely_data_head: Option<AssetId>,
    pub collateral_timely_data: Map<AssetId, CollateralTimelyData>,
    pub num_of_active_synthetic_assets: usize,
    pub synthetic_timely_data_head: Option<AssetId>,
    pub synthetic_timely_data: Map<AssetId, SyntheticTimelyData>,
    pub risk_factor_tiers: Map<AssetId, Vec<FixedTwoDecimal>>,
    oracles: Map<AssetId, Map<PublicKey, felt252>>,
    max_oracle_price_validity: TimeDelta,
}
```

### Deposit 

General component for deposit, process, and cancellation.

```rust
#[starknet::interface]
pub trait IDeposit<TContractState> {
    fn deposit(
        ref self: TContractState,
        asset_id: felt252,
        quantized_amount: u128,
        beneficiary: u32,
        salt: felt252,
    );
    fn get_deposit_status(self: @TContractState, deposit_hash: HashType) -> DepositStatus;
    fn get_asset_data(self: @TContractState, asset_id: felt252) -> (ContractAddress, u64);
}

#[derive(Debug, Drop, PartialEq, Serde)]
pub(crate) enum DepositStatus {
    NON_EXIST,
    DONE,
    PENDING: Timestamp,
    CANCELED,
}
```

```rust
#[storage]
Struct Storage {
    pub registered_deposits: Map<HashType, DepositStatus>,
    pub pending_deposits: Map<felt252, u128>,
    pub asset_data: Map<felt252, (ContractAddress, u64)>,
    pub cancellation_time: TimeDelta,
}
```

### Nonce 

General component for deposit, process, and cancellation.

```rust
#[starknet::interface]
pub trait INonce<TContractState> {
    fn nonce(self: @TContractState) -> u64;
}
```

```rust
#[storage]
pub struct Storage {
    nonce: u64,
}
```

### Pausable

In charge of the pause mechanism of the contract.

```rust
#[starknet::interface]
pub trait IPausable<TState> {
    fn is_paused(self: @TState) -> bool;
    fn pause(ref self: TState);
    fn unpause(ref self: TState);
}

```

```rust
#[storage]
pub struct Storage {
    pub paused: bool,
}
```

### Replaceability

In charge of the upgrades of the contract

```rust
#[starknet::interface]
pub trait IReplaceable<TContractState> {
    fn get_upgrade_delay(self: @TContractState) -> u64;
    fn get_impl_activation_time(
        self: @TContractState, implementation_data: ImplementationData,
    ) -> u64;
    fn add_new_implementation(ref self: TContractState, implementation_data: ImplementationData);
    fn remove_implementation(ref self: TContractState, implementation_data: ImplementationData);
    fn replace_to(ref self: TContractState, implementation_data: ImplementationData);
}

```

```rust
#[storage]
struct Storage {
    // Delay in seconds before performing an upgrade.
    upgrade_delay: u64,
    // Timestamp by which implementation can be activated.
    impl_activation_time: Map<felt252, u64>,
    // Timestamp until which implementation can be activated.
    impl_expiration_time: Map<felt252, u64>,
    // Is the implementation finalized.
    finalized: bool,
}
```

### Requests

General component registeration of requests and validate. In charge of approving user requests for Transfer, Withdraw, and Set Public Key flows before the operator can execute them.

```rust
#[starknet::interface]
pub trait IRequestApprovals<TContractState> {
    /// Returns the status of a request.
    fn get_request_status(self: @TContractState, request_hash: HashType) -> RequestStatus;
}

#[derive(Debug, Drop, PartialEq, Serde)]
pub enum RequestStatus {
    NON_EXIST,
    DONE,
    PENDING,
}

```

```rust
#[storage]
pub struct Storage {
    pub approved_requests: Map<HashType, RequestStatus>,
}
```

### Roles

In charge of access control in the contract.

```rust
#[starknet::interface]
pub trait IRoles<TContractState> {
    fn is_app_governor(self: @TContractState, account: ContractAddress) -> bool;
    fn is_app_role_admin(self: @TContractState, account: ContractAddress) -> bool;
    fn is_governance_admin(self: @TContractState, account: ContractAddress) -> bool;
    fn is_operator(self: @TContractState, account: ContractAddress) -> bool;
    fn is_token_admin(self: @TContractState, account: ContractAddress) -> bool;
    fn is_upgrade_governor(self: @TContractState, account: ContractAddress) -> bool;
    fn is_security_admin(self: @TContractState, account: ContractAddress) -> bool;
    fn is_security_agent(self: @TContractState, account: ContractAddress) -> bool;
    fn register_app_governor(ref self: TContractState, account: ContractAddress);
    fn remove_app_governor(ref self: TContractState, account: ContractAddress);
    fn register_app_role_admin(ref self: TContractState, account: ContractAddress);
    fn remove_app_role_admin(ref self: TContractState, account: ContractAddress);
    fn register_governance_admin(ref self: TContractState, account: ContractAddress);
    fn remove_governance_admin(ref self: TContractState, account: ContractAddress);
    fn register_operator(ref self: TContractState, account: ContractAddress);
    fn remove_operator(ref self: TContractState, account: ContractAddress);
    fn register_token_admin(ref self: TContractState, account: ContractAddress);
    fn remove_token_admin(ref self: TContractState, account: ContractAddress);
    fn register_upgrade_governor(ref self: TContractState, account: ContractAddress);
    fn remove_upgrade_governor(ref self: TContractState, account: ContractAddress);
    fn renounce(ref self: TContractState, role: RoleId);
    fn register_security_admin(ref self: TContractState, account: ContractAddress);
    fn remove_security_admin(ref self: TContractState, account: ContractAddress);
    fn register_security_agent(ref self: TContractState, account: ContractAddress);
    fn remove_security_agent(ref self: TContractState, account: ContractAddress);
}

```

### Positions

In charge of all position-related.

```rust
#[starknet::interface]
pub trait IPositions<TContractState> {
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
}
```

```rust
#[storage]
pub struct Storage {
    pub positions: Map<PositionId, Position>,
}
```

## Storage

```rust
#[storage]
Struct Storage {
    // Order hash to fulfilled absolute base amount.
    fulfillment: Map<HashType, u64>,
    // --- Components ---
    #[substorage(v0)]
    accesscontrol: AccessControlComponent::Storage,
    #[substorage(v0)]
    nonce: NonceComponent::Storage,
    #[substorage(v0)]
    pausable: PausableComponent::Storage,
    #[substorage(v0)]
    pub replaceability: ReplaceabilityComponent::Storage,
    #[substorage(v0)]
    pub roles: RolesComponent::Storage,
    #[substorage(v0)]
    src5: SRC5Component::Storage,
    #[substorage(v0)]
    pub assets: AssetsComponent::Storage,
    #[substorage(v0)]
    pub deposits: Deposit::Storage,
    #[substorage(v0)]
    pub request_approvals: RequestApprovalsComponent::Storage,
    #[substorage(v0)]
    pub positions: Positions::Storage,
}
```

## Validations

### Pause

Checking that the contract is not paused. This is done using [SW pausable component](https://github.com/starkware-industries/starknet-apps/blob/dev/workspace/packages/contracts/src/components/pausable/pausable.cairo):

```rust
self.pausable.assert_not_paused()
```

### Position 

Checking that the position exists in the system.

### Operator Nonce

Checking that the caller of the function is the Operator. This is done using [SW roles component](https://github.com/starkware-industries/starknet-apps/blob/dev/workspace/packages/contracts/src/components/roles/roles.cairo):  
Check that the system nonce sent is the same as the contract nonce. This is done using Nonce component:

```rust
self.roles.only_operator()
// The operator_nonce is the parameters we got in the function call data
// nonces.use_checked_nonce also increments the nonce by 1
self.nonce.use_checked_nonce(nonce: operator_nonce)
```

### Signature

#### Caller validation

When a position has owner account the flows that require 2 phases (deposit, withdraw, transfer and change\_position\_public\_key) we validate that the caller of the request is the owner account.

#### Public key signature

This is done using the [OZ account/src/utils/signature.cairo](https://github.com/OpenZeppelin/cairo-contracts/blob/main/packages/account/src/utils/signature.cairo):

```
is_valid_stark_signature(msg_hash, public_key, signature)
```

### Expiration

Checking that the expiration timestamp of the transaction hasn’t expired:

```rust
expiration < get_block_timestamp()
```

### Requests 

Checking if there’s an approved request in the [requests component](#requests) ([deposit component](#deposit)) for the current (deposit) flow.

```rust
self.request_approvals.consume_approved_request(hash);
```

### Funding 

For each funding tick we update all the synthetic funding indexes and the storage timestamp of `last_funding_tick`. Each time we validate funding, we check that:

```rust
get_block_timestamp() - self.last_funding_tick.read() < self.funding_validation_interval.read()
```

### Price 

At the start of each flow, we check if `price_validation_interval` has passed since the `last price validation.` If that’s the case, we iterate through the active synthetic and collateral assets in the system and check if any asset has expired. Then, we update the `last_price_validation`.

```rust
if get_block_timestamp() - last_price_validation <  price_validation_interval:
    continue;
else:
For asset in <synthetic_timely_data/collateral_timely_data>:
    get_block_timestamp() - asset.last_price_update < price_validation_interval
    self.last_price_validation.write(get_block_timestamp())
```

### Amount 

Validate that the amount is positive/negative according to the flow.

### Asset 

Checking that the asset exists in the system and is not delisted. 

- Withdraw, Deposit asset\_ids must be collaterals  
- Trade, Liquidate \- quote, fee asset\_ids must be collaterals  
- Deleverage \- quote is active collateral. base must be synthetic, it can be deactivated.

### Fulfillment 

Check whether the transaction hasn’t already been completed by checking whether the fulfillment storage map value of the message hash is 0 or not entirely fulfilled.

### Fundamental 

Position after the change is [healthy](#healthy) or [is healthier](#is-healthier) after change.

## Errors 

- ONLY\_OPERATOR  
- INVALID\_NONCE  
- INVALID\_STARK\_SIGNATURE  
- ALREADY\_FULFILLED  
- WITHDRAW\_EXPIRED  
- INVALID\_OWNER\_SIGNATURE  
- ALREADY\_FULFILLED  
- NOT\_ENOUGH\_FUNDS  
- WITHDRAW\_NOT\_HEALTHY  
- INSUFFICENT\_FUNDS

## Events 

#### NewPosition

| Data | Type | Keyed |
| :---- | :---- | :---- |
| position\_id | [PositionId](#positionid) | yes |
| owner\_public\_key | felt252 | yes |
| owner\_account | ContractAddress | yes |

#### Deposit 

| Data | Type | Keyed |
| :---- | :---- | :---- |
| position\_id | u32 | yes |
| depositing\_address | ContractAddress | yes |
| easset\_id | felt252 | no |
| amount | u128 | no |
| deposit\_request\_hash | felt252 | yes |

#### DepositCanceled 

| Data | Type | Keyed |
| :---- | :---- | :---- |
| position\_id | u32 | yes |
| depositing\_address | ContractAddress | yes |
| asset\_id | felt252 | no |
| amount | u128 | no |
| deposit\_request\_hash | felt252 | yes |

#### DepositProcessed 

| Data | Type | Keyed |
| :---- | :---- | :---- |
| position\_id | u32 | yes |
| depositing\_address | ContractAddress | yes |
| asset\_id | felt252 | no |
| amount | u128 | no |
| deposit\_request\_hash | felt252 | yes |

#### WithdrawRequest 

| Data | Type | Keyed |
| :---- | :---- | :---- |
| position\_id | [PositionId](#positionid) | yes |
| recipient | ContractAddress | yes |
| collateral\_id | [AssetId](#assetid) | no |
| amount | u64 | no |
| expiration | [Timestamp](#timestamp) | no |
| withdraw\_request\_hash | felt252 | yes |

#### Withdraw 

| Data | Type | Keyed |
| :---- | :---- | :---- |
| position\_id | [PositionId](#positionid) | yes |
| recipient | ContractAddress | yes |
| collateral\_id | [AssetId](#assetid) | no |
| amount | u64 | no |
| expiration | [Timestamp](#timestamp) | no |
| withdraw\_request\_hash | felt252 | yes |

#### Trade 

| Data | Type | Keyed |
| :---- | :---- | :---- |
| order\_a\_position\_id | [PositionId](#positionid) | yes |
| order\_a\_base\_asset\_id | [AssetId](#assetid) | no |
| order\_a\_base\_amount | i64 | no |
| order\_a\_quote\_asset\_id | [AssetId](#AssetId) | no |
| order\_a\_quote\_amount | i64 | no |
| fee\_a | [AssetId](#AssetId) | no |
| order\_b\_position\_id | [PositionId](#positionid) | yes |
| order\_b\_base\_asset\_id | [AssetId](#AssetId) | no |
| order\_b\_base\_amount | i64 | no |
| order\_b\_quote\_asset\_id | [AssetId](#AssetId) | no |
| order\_b\_quote\_amount | i64 | no |
| fee\_b\_asset\_id | [AssetId](#AssetId) | no |
| fee\_b\_amount | u64 | no |
| actual\_amount\_base\_a | i64 | no |
| actual\_amount\_quote\_a | i64 | no |
| actual\_fee\_a | i64 | no |
| actual\_fee\_b | i64 | no |
| order\_a\_hash | felt252 | yes |
| order\_b\_hash | felt252 | yes |

#### Liquidate 

| Data | Type | Keyed |
| :---- | :---- | :---- |
| liquidated\_position\_id | [PositionId](#positionid) | yes |
| liquidator\_order\_position\_id | [PositionId](#positionid) | yes |
| liquidator\_order\_base | [AssetId](#AssetId) | no |
| liquidator\_order\_base\_amount | i64 | no |
| liquidator\_order\_quote | [AssetId](#AssetId) | no |
| liquidator\_order\_quote\_amount | i64 | no |
| liquidator\_order\_fee | [AssetId](#AssetId) | no |
| liquidator\_order\_fee\_amount | u64 | no |
| actual\_amount\_base\_liquidated | i64 | no |
| actual\_amount\_quote\_liquidated | i64 | no |
| actual\_liquidator\_fee | i64 | no |
| fee\_asset\_id | [AssetId](#AssetId) | no |
| fee\_amount | u64 | no |
| liquidator\_order\_hash | felt252 | yes |

#### Deleverage 

| Data | Type | Keyed |
| :---- | :---- | :---- |
| deleveraged\_position | [PositionId](#positionid) | yes |
| deleverager\_position | [PositionId](#positionid) | yes |
| deleveraged\_base\_asset\_id | [AssetId](#AssetId) | no |
| deleveraged\_base\_amount | i64 | no |
| deleveraged\_quote\_asset\_id | [AssetId](#AssetId) | no |
| deleveraged\_quote\_amount | i64 | no |

#### TransferRequest

| Data | Type | Keyed |
| :---- | :---- | :---- |
| position\_id | [PositionId](#positionid) | yes |
| recipient | [PositionId](#positionid) | yes |
| collateral\_id | [AssetId](#AssetId) | no |
| amount | u64 | no |
| expiration | [Timestamp](#timestamp) | no |
| transfer\_request\_hash | felt252 | yes |

#### Transfer 

| Data | Type | Keyed |
| :---- | :---- | :---- |
| position\_id | [PositionId](#positionid) | yes |
| recipient | [PositionId](#positionid) | yes |
| collateral\_id | [AssetId](#AssetId) | no |
| amount | u64 | no |
| expiration | [Timestamp](#timestamp) | no |
| transfer\_request\_hash | felt252 | yes |

#### SetOwnerAccount

| Data | Type | Keyed |
| :---- | :---- | :---- |
| position\_id | [PositionId](#positionid) | yes |
| public\_key | felt252 | yes |
| new\_account\_owner | ContractAddress | yes |
| expiration | [Timestamp](#timestamp) | no |

#### SetPublicKeyRequest 

| Data | Type | Keyed |
| :---- | :---- | :---- |
| position\_id | [PositionId](#positionid) | yes |
| new\_public\_key | felt252 | yes |
| expiration | [Timestamp](#timestamp) | no |
| set\_public\_key\_request\_hash | felt252 | yes |

#### SetPublicKey 

| Data | Type | Keyed |
| :---- | :---- | :---- |
| position\_id | [PositionId](#positionid) | yes |
| new\_public\_key | felt252 | yes |
| expiration | [Timestamp](#timestamp) | no |
| set\_public\_key\_request\_hash | felt252 | yes |

#### FundingTick

| Data | Type | Keyed |
| :---- | :---- | :---- |
| asset\_id | [AssetId](#assetid) | yes |
| funding\_index | [FundingIndex](#fundingindex) | no |

#### PriceTick 

| Data | Type | Keyed |
| :---- | :---- | :---- |
| asset\_id | [AssetId](#assetid) | yes |
| price | [Price](#price) | no |

#### AssetActivated 

| Data | Type | Keyed |
| :---- | :---- | :---- |
| asset\_id | [AssetId](#assetid) | yes |

#### AddSynthetic 

| Data | Type | Keyed |
| :---- | :---- | :---- |
| asset\_id | [AssetId](#assetid) | yes |
| risk\_factor\_tiers | Span\<u8\> | no |
| risk\_factor\_first\_tier\_boundary | u128 | no |
| risk\_factor\_tier\_size | u128 | no |
| resolution | u64 | no |
| quorum | u8 | no |

#### DeactivateSyntheticAsset 

| Data | Type | Keyed |
| :---- | :---- | :---- |
| asset\_id | [AssetId](#assetid) | yes |

#### UpdateOracleQuorum 

| Data | Type | Keyed |
| :---- | :---- | :---- |
| asset\_id | [AssetId](#AssetId) | yes |
| new\_quorum | u8 | no |
| old\_quorum | u8 | no |

#### RemoveOracle 

| Data | Type | Keyed |
| :---- | :---- | :---- |
| asset\_id | [AssetId](#AssetId) | yes |
| oracle\_public\_key | PublicKey | yes |

#### AddOracle 

| Data | Type | Keyed |
| :---- | :---- | :---- |
| asset\_id | [AssetId](#AssetId) | yes |
| oracle\_public\_key | PublicKey | yes |

#### RegisterCollateral 

| Data | Type | Keyed |
| :---- | :---- | :---- |
| asset\_id | [AssetId](#AssetId) | yes |
| token\_address | ContractAddress | yes |
| quantum | u64 | no |

#### 

## Constructor

#### Description 

It only runs once when deploying the contract and is used to initialize the state of the contract.

```rust
fn constructor(
	ref self: ContractState,
	governance_admin: ContractAddress,
	upgrade_delay: u64,
    max_price_interval: TimeDelta,
    max_funding_interval: TimeDelta,
    max_funding_rate: u32,
    max_oracle_price_validity: TimeDelta,
    cancellation_delay_time: TimeDelta,
    fee_position_owner_account: ContractAddress,
    fee_position_public_key: felt252,
    insurance_fund_owner_account: ContractAddress,
    insurance_fund_public_key: felt252,
)
```

#### Validations 

#### Logic 

1. Initialize roles with governance\_admin address.  
2. Update replaceability upgrade delay.  
3. Initialize assets: set max\_price\_interval, max\_funding\_interval, and max\_funding\_rate.  
4. Initialize deposits.  
5. Initialize positions: create fee and insurance fund positions.

## Public Functions

### New Position

#### Description

```rust
fn new_position(
	ref self: ContractState,
    operator_nonce: u64,
    position_id: PositionId,
    owner_public_key: felt252,
    owner_account: ContractAddress,
)
```

#### Access Control

Only the Operator can execute.

#### Hash

#### Validations 

1. [Pausable check](#pausable)
2. [Operator Nonce check](#operator-nonce)  
3. Check that the `position_id` doesn’t exist
4. Check that `owner_public_key` is not zero

#### Logic 

6. [Run open position validations](#validations-2)
7. `self.positions[positionId].owner_public_key = owner_public_key`  
8. `self.positions[positionId].owner_account = owner_account`

#### Errors

- POSITION\_ALREADY\_EXISTS  
- INVALID\_PUBLIC\_KEY

#### Emits

[NewPosition](#newposition)

### Deposit

#### Description

The user registers a deposit request using the [Deposit component](#deposit) \- this happens in the Deposit component.

```rust
fn deposit(
	ref self: ContractState,
    beneficiary: u32,
	asset_id: felt252,
    quantized_amount: u64,
    salt: felt252,
)
```

#### Access Control

Anyone can execute.

#### Hash

```rust
fn deposit_hash(
        ref self: ComponentState<TContractState>,
        signer: ContractAddress,
        asset_id: felt252,
        quantized_amount: u128,
        beneficiary: u32,
        salt: felt252,
) -> felt252 {
        PoseidonTrait::new()
        .update_with(value: get_caller_address())
        .update_with(value: asset_id)
        .update_with(value: quantized_amount)
        .update_with(value: beneficiary)
        .update_with(value: salt)
        .finalize()
}

```

#### Validations 

1. `quantized_amount>0`  
2. deposit\_hash not exists in registered\_deposits

#### Logic 

1. `self.registered_deposits.write(key: deposit_hash, value: DepositStatus::PENDING(Time::now()));`  
2. Add `quantized_amount` to pending deposits  
3. Transfer `quantized_amount*asset_id.quantum` from `get_caller_address()` to `get_contract_address()`

#### Errors

- INVALID\_NON\_POSITIVE\_AMOUNT  
- COLLATERAL\_NOT\_EXISTS

#### Emits

[deposit](#deposit-1)

### Process Deposit

#### Description

The user deposits collateral into the system.

```rust
fn process_deposit(
	ref self: ContractState,
    operator_nonce: u64,
    depositor: ContractAddress,
    position_id: PositionId,
    collateral_id: AssetId,
    amount: i64,
    salt: felt252,
)
```

#### Access Control

Only the Operator can execute.

#### Hash

```rust
fn deposit_hash(
        ref self: ComponentState<TContractState>,
        signer: ContractAddress,
        asset_id: felt252,
        quantized_amount: i64,
        beneficiary: u32,
        salt: felt252,
) -> felt252 {
        PoseidonTrait::new()
        .update_with(value: depositor)
        .update_with(value: asset_id)
        .update_with(value: quantized_amount)
        .update_with(value: beneficiary)
        .update_with(value: salt)
        .finalize()
}

```

#### Validations 

We assume that the position is always healthier for deposit

1. [Position check](#position)  
2. [Pausable check](#pausable)  
3. [Operator Nonce check](#operator-nonce)  
4. [Funding validation](#funding)  
5. [Price validation](#price)  
6. [Collateral amount is positive](#amount)  
7. [Collateral check](#asset)  
8. [Request approval check on deposit message](#requests)

#### Logic 

1. Run deposit validations
2. Add the amount to the collateral balance in the position.   
3. Mark deposit request as done   
4. Subtruct amount from pending deposits

#### Errors

- INVALID\_POSITION  
- PAUSED  
- ONLY\_OPERATOR  
- INVALID\_NONCE  
- FUNDING\_EXPIRED  
- SYNTHETIC\_EXPIRED\_PRICE  
- DEPOSIT\_EXPIRED  
- COLLATERAL\_NOT\_ACTIVE  
- DEPOSIT\_NOT\_REGISTERED  
- DEPOSIT\_ALREADY\_DONE

#### Emits

[deposit\_processed](#depositprocessed)

### Cancel Pending Deposit

#### Description

The user cancels a registered deposit request in the Deposit component.

```rust
fn cancel_pending_deposit(
	ref self: ContractState,
    beneficiary: u32,
	asset_id: felt252,
    quantized_amount: u128,
    salt: felt252,
)
```

#### Access Control

Anyone can execute. 

#### Hash

```rust
fn deposit_hash(
        ref self: ComponentState<TContractState>,
        signer: ContractAddress,
        beneficiary: u32,
        asset_id: felt252,
        quantized_amount: u128,

        salt: felt252,
) -> felt252 {
        PoseidonTrait::new()
        .update_with(value: get_caller_address())
        .update_with(value: beneficiary)
        .update_with(value: asset_id)
        .update_with(value: quantized_amount)

        .update_with(value: salt)
        .finalize()
}

```

#### Validations 

1. deposit\_hash is in `DepositStatus::PENDING` in registered\_deposits  
2. `self.approved_deposits[deposit_msg_hash].time + cancellation_time < Time::now()`

#### Logic 

1. Run validations  
2. `self.registered_deposits.write(key: deposit_hash, value: DepositStatus::CANCELED;`  
3. remove `quantized_amount` from pending deposits  
4. Transfer `asset_id` ERC-20 `amount * asset_id.quantum` to `get_caller_address()` 

#### Errors

#### Emits

[deposit\_canceled](#depositcanceled)

### Withdraw Request

#### Description

The user registers a withdraw request by registering a fact.

```rust
fn withdraw_request(
    ref self: ContractState,
    signature: Signature,
    operator_nonce: u64,
    // WithdrawArgs
    recipient: ContractAddress,
    position_id: PositionId,
    collateral_id: AssetId,
    amount: u64,
    expiration: Timestamp,
    salt: felt252,
)
```

#### Access Control

Anyone can execute.

#### Hash

[get\_message\_hash](#get-message-hash) on [WithdrawArgs](#withdrawargs) with position `public_key`.

#### Validations 

1. [signature validation](#signature)  
2. Request is new

#### Logic 

1. [Run validation](#validations-6)  
2. Register a request to the requests component

#### Errors

- INVALID\_POSITION  
- CALLER\_IS\_NOT\_OWNER\_ACCOUNT  
- INVALID\_STARK\_KEY\_SIGNATURE  
- APPROVAL\_ALREADY\_REGISTERED

#### Emits

[withdraw\_request](#withdrawrequest)

### Withdraw

#### Description

The user withdraws collateral amount from the position to the recipient.

```rust
fn withdraw(
    ref self: ContractState,
    operator_nonce: u64,
    // WithdrawArgs
    recipient: ContractAddress,
    position_id: PositionId,
    collateral_id: AssetId,
    amount: u64,
    expiration: Timestamp,
    salt: felt252,
)
```

#### Access Control

Only the Operator can execute.

#### Hash

[get\_message\_hash](#get-message-hash) on [WithdrawArgs](#withdrawargs) with position `public_key`.

#### Validations 

1. [Pausable check](#pausable)  
2. [Operator Nonce check](#operator-nonce)  
3. [Funding validation](#funding)  
4. [Price validation](#price)  
5. [Collateral amount is positive](#amount)  
6. [Expiration validation](#expiration)  
7. [Collateral check](#asset)  
8. [Request approval check on withdraw message](#requests-1)  
9. `collateral.asset_id.balance_of(perps contract) - collateral.amount * collateral.asset_id.quantum >= pending_deposits[collateral.asset_id] * collateral.asset_id.quantum`

This means that the withdraw is not taking money from the `pending_deposits`

#### Logic 

1. Run [withdraw validations](#validations-7)  
3. Remove the amount from the position collateral.  
4. `ERC20::transfer(recipient, amount * collateral.asset_id.quantum)`  
5. Mark withdraw request done in the requests component  
6. [Fundamental validation](#fundamental)

#### Errors

- PAUSED  
- ONLY\_OPERATOR  
- INVALID\_NONCE  
- FUNDING\_EXPIRED  
- SYNTHETIC\_EXPIRED\_PRICE  
- INVALID\_NON\_POSITIVE\_AMOUNT  
- WITHDRAW\_EXPIRED  
- COLLATERAL\_NOT\_ACTIVE  
- INVALID\_POSITION  
- APPROVAL\_NOT\_REGISTERED  
- ALREADY\_DONE  
- POSITION\_UNHEALTHY  
- APPLY\_DIFF\_MISMATCH  
- ASSET\_NOT\_EXISTS  
- APPROVAL\_NOT\_REGISTERED

#### Emits

[withdraw](#withdraw)

### Transfer Request

#### Description

```rust
fn transfer_request(
    ref self: ContractState,
    signature: Signature,
    // TransferArgs
    recipient: PositionId,
    position_id: PositionId,
    collateral_id: AssetId,
    amount: u64,
    expiration: Timestamp,
    salt: felt252,
)
```

#### Access Control

Anyone can execute.

#### Hash

[get\_message\_hash](#get-message-hash) on [TransferArgs](#transferargs) with position `public_key`.

#### Validations 

1. [signature validation](#signature)  
2. Request is new

#### Logic 

1. [Run validation](#validations-10)  
2. Register a request to transfer using the requests component

#### Emits

[TransferRequest](#transferrequest)

#### Errors

- INVALID\_POSITION  
- CALLER\_IS\_NOT\_OWNER\_ACCOUNT  
- INVALID\_STARK\_KEY\_SIGNATURE  
- APPROVAL\_ALREADY\_REGISTERED

### 

### Transfer

#### Description

```rust
fn transfer(
    ref self: ContractState,
    operator_nonce: u64,
    // TransferArgs
    recipient: PositionId,
    position_id: PositionId,
    collateral_id: AssetId,
    amount: u64,
    expiration: Timestamp,
    salt: felt252,
)
```

#### Access Control

Only the Operator can execute.

#### Hash

[get\_message\_hash](#get-message-hash) on [TransferArgs](#transferargs) with position `public_key`.

#### Validations 

1. [Pausable check](#pausable)  
2. [Operator Nonce check](#operator-nonce)  
3. [Funding validation](#funding)  
4. [Price validation](#price)  
5. [Position check](#position) for `transfer_args.position_id`  and `transfer_args.recipient`   
6. [Collateral amount is positive](#amount)  
7. [Expiration validation](#expiration)  
8. [Collateral check](#asset)  
9. [Request approval check on transfer message](#requests-1)

#### Logi

1. Run transfer validations
2. `positions[position_a].collateral_asset[collateral.asset_id] -= amount`  
3. `positions[position_b].collateral_asset[collateral.asset_id] += amount`  
4. [Fundamental validation](#fundamental) for `position_a` in transfer.

#### Emits 

[Transfer](#transfer)

#### Errors

- ONLY\_OPERATOR  
- INVALID\_NONCE  
- FUNDING\_EXPIRED  
- SYNTHETIC\_EXPIRED\_PRICE  
- INVALID\_POSITION  
- COLLATERAL\_NOT\_EXISTS  
- COLLATERAL\_NOT\_ACTIVE  
- INVALID\_TRANSFER\_AMOUNT  
- AMOUNT\_TOO\_LARGE  
- TRANSFER\_EXPIRED  
- APPROVAL\_NOT\_REGISTERED

### Trade

#### Description

A trade between 2 positions in the system.

```rust
fn trade(
	ref self: ContractState,
	operator_nonce: u64,
	signature_a: Signature,
	signature_b: Signature,
	order_a: Order,
	order_b: Order,
	actual_amount_base_a: i64,
	actual_amount_quote_a: i64,
	actual_fee_a: i64,
	actual_fee_b: i64,
)
```

#### Access Control

Only the Operator can execute.

#### Hash

[get\_message\_hash](#get-message-hash) on [Order](#order) with position `public_key`.

#### Validations 

1. [Pausable check](#pausable)  
2. [Operator Nonce check](#operator-nonce)  
3. [Funding validation](#funding)  
4. [Price validation](#price)  
5. [public key signature](#public-key-signature) on each `Order`  
6. [All fee amounts are positive (actuals and order)](#amounts)  
7. [Expiration validation](#expiration)  
8. [Assets check](#asset)  
9. `order_a.quote.amount` and `order_a.base.amount` have opposite signs and are non-zero.  
10. `order_b.quote.amount` and `order_b.base.amount` have opposite signs and are non-zero.  
11. `quote.asset_id` of both orders are the same (`order_a.quote.asset_id` \= `order_b.quote.asset_id`) registered and active collateral.  
12. `order_x`.`base.asset_id` of both orders are the same (`order_a`.`base.asset_id` \= `order_b.base.asset_id`) registered and active collateral/synthetic.  
13. `order_a.quote.amount` and `order_b.quote.amount` have opposite sign  
14. `actual_amount_base_a and actual_amount_quote_a are non-zero.`  
15. `order_a.base.amount` and `actual_amount_base_a` have the same sign.  
16. `order_a.quote.amount` and `actual_amount_quote` have the same sign.  
17. `|fulfillment[order_a_hash]|+|actual_amount_base_a|≤|order_a.base.amount|`  
18. `|fulfillment[order_b_hash]|+|actual_amount_base_a|≤|order_b.base.amount|`  
19. `actual_fee_a / |actual_amount_quote_a| ≤ order_a.fee.amount / |order_a.quote.amount|`  
20. `actual_fee_b / |actual_amount_quote_a| ≤ order_b.fee.amount / |order_b.quote.amount|`  
21. `order_a.base.amount/|order_a.quote.amount|≤actual_amount_base_a/|actual_amount_quote_a|`  
22. `order_b.base.amount/|order_b.quote.amount|≤-actual_amount_base_a/|actual_amount_quote_a|`

#### Logic

1. Run validations  
2. Subtract the fees from each position collateral.  
3. Add the fees to the fee\_position.  
4. If `order_X.base_type.asset_id` is synthetic:  
   1. Add the `actual_amount_base_a` to the `order_a` position synthetic.  
   2. Subtract the `actual_amount_base_a` from the `order_b` position synthetic.  
5. Else:  
   1. Add the `actual_amount_base_a` to the `order_a` position collateral.  
   2. Subtract the `actual_amount_base_a` from the `order_b` position collateral.  
6. Add the `actual_amount_quote_a` to the `order_a` position collateral.  
7. Subtract the `actual_amount_quote_a` from the `order_b` position collateral.  
8. [Fundamental validation](#fundamental) for both positions in trade.  
9. `fulfillment[order_a_hash]+=actual_amount_base_a`  
10. `fulfillment[order_b_hash]-=actual_amount_base_a`

#### Emits

[Trade](#trade)

#### Errors

- PAUSED  
- ONLY\_OPERATOR  
- INVALID\_NONCE  
- FUNDING\_EXPIRED  
- SYNTHETIC\_EXPIRED\_PRICE  
- ORDER\_EXPIRED  
- INVALID\_POSITION  
- INVALID\_STARK\_KEY\_SIGNATURE  
- INVALID\_NEGATIVE\_FEE  
- INVALID\_ZERO\_AMOUNT  
- COLLATERAL\_NOT\_ACTIVE  
- BASE\_ASSET\_NOT\_ACTIVE  
- INVALID\_TRADE\_WRONG\_AMOUNT\_SIGN  
- INVALID\_TRADE\_ACTUAL\_BASE\_SIGN  
- INVALID\_TRADE\_ACTUAL\_QUOTE\_SIGN  
- TRADE\_ILLEGAL\_BASE\_TO\_QUOTE\_RATIO  
- TRADE\_ILLEGAL\_FEE\_TO\_QUOTE\_RATIO  
- DIFFERENT\_QUOTE\_ASSET\_IDS  
- DIFFERENT\_BASE\_ASSET\_IDS  
- INVALID\_TRADE\_QUOTE\_AMOUNT\_SIGN  
- ASSET\_NOT\_EXISTS

### Liquidate

#### Description

When a user position [is liquidatable](#liquidatable), the system can match the liquidated position with a signed order without a signature of the liquidated position to make it [healthier](#is-healthier).

```rust
fn liquidate(
	ref self: ContractState,
	operator_nonce: u64,
    liquidator_signature: Signature,
	liquidated_position_id: PositionId,
	liquidator_order: Order,
	actual_amount_base_liquidated: i64,
	actual_amount_quote_liquidated: i64,
	actual_liquidator_fee: i64,
	fee_asset_id: AssetId,
	fee_amount: u64
)
```

#### Access Control

Only the Operator can execute.

#### Hash

[get\_message\_hash](#get-message-hash) on [Order](#order) with position `public_key`.

#### Validations 

1. [Pausable check](#pausable)  
2. [Operator Nonce check](#operator-nonce)  
3. [All fees amounts are non negative (actuals and order)](#amounts)  
4. [Expiration validation](#expiration)  
5. [Assets check](#asset)  
6. [Funding validation](#funding)  
7. [Price validation](#price)  
8. [public key signature](#public-key-signature) on `liquidator_order`  
9. `liquidator_order.quote_type.asset_id` is registered and active collateral  
10. `liquidator_order.base.asset_id` is registered and active synthetic or collateral.  
11. `liquidated_position_id.is_liquidatable()==true`  
12. `liquidator_order.quote.amount` and `liquidator_order.base.amount` have opposite signs.  
13. `liquidator_order.base.amount` and `actual_amount_base_liquidated` have opposite signs.  
14. `liquidator_order.quote.amount` and `actual_amount_quote_liquidated` have opposite signs.  
15. `|fulfillment[liquidator_order_hash]|+|actual_amount_base_liquidated|≤|liquidator_order.base.amount|`  
16. `actual_liquidator_fee / |actual_amount_quote_liquidated| ≤ liquidator_order.fee.amount / |liquidator_order.quote.amount|`  
17. `actual_amount_base_liquidated / |actual_amount_quote_liquidated| ≤ - liquidator_order.base.amount / |liquidator_order.quote.amount|`

#### Logic

1. Run validations
2. If `liquidator_order.base.asset_id` is synthetic:  
   1. `positions[liquidated_position_id].syntethic_assets[liquidated_position.base.asset_id] += actual_amount_base_liquidated`  
   2. `positions[liquidator_order.position_id].syntethic_assets[liquidator_position.base.asset_id] -= actual_amount_base_liquidated`  
3. Else:  
   1. `positions[liquidated_position].collateral_assets[liquidated_position.base.asset_id] += actual_amount_base_liquidated`  
   2. `positions[liquidator_order.position_id].collateral_assets[liquidator_position.base.asset_id] -= actual_amount_base_liquidated`  
4. `positions[liquidated_position].collateral_assets[liquidator_order.quote.asset_id] += actual_amount_quote_liquidated`  
5. `positions[liquidator_order.position_id].collateral_assets[liquidator_order.quote.asset_id] -= actual_amount_quote_liquidated`  
6. `positions[liquidator_order.position_id].collateral_assets[liquidator_order.fee.asset_id] -= liquidator_fee`  
7. `positions[fee_position].collateral_assets[liquidator_position.fee.asset_id] += liquidator_fee`  
8. `positions[liquidated_position].collateral_assets[insurance_fund_fee.asset_id] -= insurance_fund_fee_amount`  
9. `positions[insurance_fund].collateral_assets[insurance_fund_fee.asset_id] += insurance_fund_fee_amount`  
10. `fulfillment[liquidator_order_hash] -= actual_amount_base_liquidated`  
11. [Fundamental validation](#fundamental) for both positions.

#### Emits

[Liquidate](#liquidate)

#### Errors

- PAUSED  
- ONLY\_OPERATOR  
- INVALID\_NONCE  
- FUNDING\_EXPIRED  
- SYNTHETIC\_EXPIRED\_PRICE  
- ORDER\_EXPIRED  
- INVALID\_POSITION  
- INVALID\_STARK\_KEY\_SIGNATURE  
- INVALID\_NEGATIVE\_FEE  
- INVALID\_ZERO\_AMOUNT  
- COLLATERAL\_NOT\_ACTIVE  
- BASE\_ASSET\_NOT\_ACTIVE  
- INVALID\_TRADE\_WRONG\_AMOUNT\_SIGN  
- INVALID\_TRADE\_ACTUAL\_BASE\_SIGN  
- INVALID\_TRADE\_ACTUAL\_QUOTE\_SIGN  
- TRADE\_ILLEGAL\_BASE\_TO\_QUOTE\_RATIO  
- TRADE\_ILLEGAL\_FEE\_TO\_QUOTE\_RATIO  
- DIFFERENT\_QUOTE\_ASSET\_IDS  
- DIFFERENT\_BASE\_ASSET\_IDS  
- INVALID\_TRADE\_QUOTE\_AMOUNT\_SIGN  
- ASSET\_NOT\_EXISTS

### Deleverage

#### Description

When a user position [is deleveragable](#deleveragable), the system can match the deleveraged position with deleverger position, both without position’s signature, to make it [healthier](#is-healthier).

```rust
fn deleverage(
	ref self: ContractState,
    operator_nonce: u64,
    deleveraged_position: PositionId,
    deleverager_position: PositionId,
    deleveraged_base_asset_id: AssetId,
    deleveraged_base_amount: i64,
    deleveraged_quote_asset_id: AssetId,
    deleveraged_quote_amount: i64,

)
```

#### Access Control

Only the Operator can execute.

#### Validations 

1. [Pausable check](#pausable)  
2. [Operator Nonce check](#operator-nonce)  
3. [Assets check](#asset)   
4. [Funding validation](#funding)  
5. [Price validation](#price)  
6. deleveraged\_base.asset\_id must be a registered synthetic and can be either active or inactive.
7. deleveraged\_quote.asset\_id must be a registered collateral.
8. If base\_asset\_id is active:
   1. deleveraged\_position.is\_deleveragable() \== true
9. base\_deleveraged.amount and quote\_deleveraged.amount have opposite signs.
10. `deleveraged_position.balance decreases in magnitude after the change: |base_deleveraged.amount| must not exceed |deleveraged_position.balance|, and` both should `have the same sign.`   
11. `deleverager_position.balance decreases in magnitude after the change: |base_deleveraged.amount| must not exceed |deleverager_position.balance|, and both should have opposite sign.`

#### Logic

1. [Run Validations](#validations-12).  
2. `positions[position_delevereged].syntethic_assets[base_delevereged.asset_id] += base_delevereged.amount`  
3. `positions[position_deleverager].syntethic_assets[base_delevereged.asset_id] -= base_delevereged.amount`  
4. `positions[position_delevereged].collateral_assets[quote_delevereged.asset_id] += quote_delevereged.amount`  
5. `positions[position_deleverager].collateral_assets[quote_delevereged.asset_id] -= quote_delevereged.amount`  
6. [Fundamental validation](#fundamental) for both positions.

#### Emits

#### Errors

### 

### Set Owner Account

#### Description

Updates the account owner only for a no-owner position.

```rust
fn set_owner_account(
    ref self: ContractState,
    operator_nonce: u64,
    signature: Signature,
    // SetOwnerAccountArgs
    position_id: PositionId,
    public_key: felt252,
    new_account_owner: ContractAddress,
    expiration: Timestamp,
)
```

#### Access Control

Only the Operator can execute.

#### Hash

[get\_message\_hash](#get-message-hash) on [SetOwnerAccountArgs](#setowneraccountargs) with position `public_key`.

#### Validations 

1. [Pausable check](#pausable)  
2. [Operator Nonce check](#operator-nonce)  
3. [Expiration validation](#expiration)  
4. [Position check](#position-1)  
5. Self.positions\[position\_id\].owner \== NO\_OWNER  
6. [public key signature](#public-key-signature)

#### Logic

1. Run [validations](#validations-13)  
2. Self.positions\[position\_id\].owner \= owner

#### Errors

- ONLY\_OPERATOR  
- INVALID\_NONCE  
- INVALID\_POSITION  
- OWNER\_ALREADY\_EXISTS  
- INVALID\_STARK\_SIGNATURE

#### Emits

[SetPositionOwner](#setowneraccount)

### Set Public Key Request

#### Description

The user registers an update position public key request by registering a fact.

```rust
fn set_public_key_request(
    ref self: ContractState,
    // SetPublicKeyArgs
    position_id: PositionId,
    new_public_key: felt252,
    expiration: Timestamp,
)
```

#### Access Control

Anyone can execute.

#### Hash

[get\_message\_hash](#get-message-hash) on [SetPublicKeyArgs](#setpublickeyargs) with `new_public_key`.

#### Validations 

1. [signature validation](#signature)  
2. self.positions\[`update_position_public_key_message.position_id`\].owner \!= NO\_OWNER  
3. Request is new

#### Logic

1. Run validation
2. Register a request to set public key using the requests component

#### Errors

- INVALID\_POSITION  
- CALLER\_IS\_NOT\_OWNER\_ACCOUNT  
- INVALID\_STARK\_KEY\_SIGNATURE  
- APPROVAL\_ALREADY\_REGISTERED

#### Emits

[SetPublicKeyRequest](#setpublickeyrequest)

### Set Public Key

#### Description

Update the public key of a position.

```rust
fn set_public_key(
    ref self: ContractState,
    operator_nonce: u64,
    // SetPublicKeyArgs
    position_id: PositionId,
    new_public_key: felt252,
    expiration: Timestamp,
)
```

#### Access Control

Only the Operator can execute.

#### Hash

[get\_message\_hash](#get-message-hash) on [SetPublicKeyArgs](#setpublickeyargs) with `new_public_key`.

#### Validations 

1. [Pausable check](#pausable)  
2. [Operator Nonce check](#operator-nonce)  
3. [Expiration validation](#expiration)  
4. self.positions\[`update_position_public_key_message.position_id`\].owner \!= NO\_OWNER  
5. [Request approval check on set public key message](#requests-1)

#### Logic

1. Run [validations](#validations-15)  
2. `self.positions[position_id].public_key.write(new_public_key)`  
3. Mark request as done  
   

#### Errors

- PAUSED  
- INVALID\_NONCE  
- ONLY\_OPERATOR  
- SET\_PUBLIC\_KEY\_EXPIRED  
- INVALID\_POSITION  
- NO\_OWNER\_ACCOUNT  
- APPROVAL\_NOT\_REGISTERED

#### Emits

[SetPublicKey](#setpublickey)

### Funding Tick

#### Description

Updates the funding index of every active, and non-pending, asset in the system.

```rust
fn funding_tick(
    ref self: ContractState,
    operator_nonce: u64,
    funding_ticks: Span<FundingTick>,
)
```

Funding is calculated on the go and applied during any flow that requires checking the collateral balance. This calculation is done without updating the storage. When updating a position's synthetic assets, the following steps are taken:

1. Update the collateral balance based on the funding amount:

   change=global\_funding\_index-cached\_funding\_indexbalance232

Add `change` to the collateral balance (notice that `change` can be positive or negative)

2. Update the cached\_funding\_index of the synthetic asset  
3. Update the synthetic balance.

#### Access Control

Only the Operator can execute.

#### Validations 

1. [Pausable check](#pausable)  
2. [Operator Nonce check](#operator-nonce)

#### Logic

1. Run Validations
2. Validate that we get funding tick for all active synthetic assets in the system  
3. Initialize prev\_asset\_id to 0 (prev\_asset\_id is required for the ascending order check)  
4. Iterate over the funding ticks:  
   1. Verify that the assets are sorted in ascending order \- no duplicates.  
   2. **max\_funding\_rate validation**:  
      For **one** time unit, the following should be held: prev \- newprice%permitted   
      In practice, we would check:  
      prev\_idx-new\_idxmax\_funding\_rateblock\_timestamp-prev\_funding\_timeasset\_price  
   3. Update asset funding index if asset is active else panic.  
   4. prev\_asset\_id \= curr\_tick.asset\_id  
5. Update global last\_funding\_tick timestamp in storage

pseudo-code:

```
synthetic_timely_data.len() == funding_ticks.len()
prev_asset_id = 0
for tick in ticks:
	tick.asset_id > prev_asset_id // Strictly increasing.
	max_funding_rate validation // see above
if self.synthetic_configs[tick.asset_id].status.read() == AssetStatus::ACTIVATED:
self.synthetic_timely_data[tick.asset_id].funding_index.write(tick.funding_index)
else:
	//also not all active assets got funding tick 
	panic()
	prev_asset_id = tick.asset_id
self.last_funding_tick.write(get_block_timestamp())
```

#### Errors

- PAUSED  
- INVALID\_NONCE  
- INVALID\_FUNDING\_TICK\_LEN  
- INVALID\_FUNDING\_TICK  
- SYNTHETIC\_NOT\_ACTIVE

#### Emits

For each element in `funding_ticks`: [FundingTick](#fundingtick-1)

### 

### Add Oracle To Asset

#### Description

```rust
fn add_oracle_to_asset(
    ref ContractState,
    asset_id: AssetId,
    oracle_public_key: PublicKey
    oracle_name: felt252,
    asset_name: felt252,
)
```

#### Access Control

Only APP\_GOVERNOR can execute.

#### Validations 

1. `self.roles.only_app_governor()`  
2. `oracle_public_key` does not exist in the Oracles map  
3. `asset_name` is 128 bits  
4. `oracle_name` is 40 bits

#### Logic

1. Run validations  
2. `shifted_asset_name = TWO_POW_40 * asset_name`  
3. `self.assets.oracles.write(asset_id,(oracle_public_key, shifted_asset_name + oracle_name))`

#### Emits

[AddOracle](#addoracle)

#### Errors

### Remove Oracle

#### Description

```rust
fn remove_oracle_from_asset(
    ref ContractState,
    asset_id: AssetId,
    oracle_public_key: PublicKey
)
```

#### Access Control

Only APP\_GOVERNOR can execute.

#### Validations 

1. `self.roles.only_app_governor()`  
2. `oracle_public_key` exist in the Oracles map

#### Logic 

1. Run validations  
2. `self.assets.oracles.write(asset_id,(oracle_public_key, Zero::zero())`

#### Emits

[RemoveOracle](#removeoracle)

#### Errors

### Update Synthetic Quorum

#### Description

```rust
fn update_synthetic_quorum(
    self: ContractState,
    synthetic_id: AssetId,
    quorum: u8
)
```

#### Access Control

Only APP\_GOVERNOR can execute.

#### Validations 

1. `self.roles.only_app_governor()`  
2. Check that quorum is non zero  
3. [Asset](#asset) check \- `synthetic_id` exists and active  
4. Should we add a check the the quorum is ≤ the numbers of oracles for the asset

#### Logic 

1. Run validations  
2. `self.assets.synthetic_configs[synthetic_id].quorum = quorum`

#### Emits

[UpdateOracleQuorum](#updateoraclequorum)

#### Errors

### Price Tick

#### Description

Price tick for an asset to update its’ price.  
**price\_tick span must be sorted according to the signers public keys**

```rust
fn price_tick(
    ref self: ContractState,
    operator_nonce: u64,
    asset_id: AssetId,
    price: u128
    price_ticks: Span<PriceTick>
)
```

#### Access Control

Only the Operator can execute.

#### Validations

1. [Pausable check](#pausable)  
2. [Operator Nonce check](#operator-nonce)  
3. Timestamps are at most `max_oracle_price_validity`  
4. `price_ticks length >= synthetic_config[asset_id].quorum`  
5. Prices array is sorted according o the signers public key  
6. `Validate that the median_price accepted is actually the median price (odd: the middle; even: between middles)`  
7. Calculated `median_price`256

#### Logic 

1. For each `price_tick` in `price_ticks`:  
   1. Validate stark signature on:  
      `pedersen(`  
      `oracles[price_ticks[i].signer_public_key],`  
      `0...0(100 bits) || price_ticks[i].price(120 bits) || price_ticks[i].timestamp (32 bits)`  
      `)`  
2.   
3. `median_price =` price\*228asset\_id.resolution\_factor\*1012  
4. `Self.synthetic_timely_data[asset_id].price = media_price`

   Explanation: Oracles sign prices in the same format as StarkEx \- they sign proces of major unit with 18 decimals precision. So to ge the asset price of 1 Starknet unit of synthetic asset:

   SN\_asset\_price=oracle\_asset\_price\* 228resolution\_factor\*1012

   228: price has 28bit precision

   1012: converting 18 decimals to 6 USDC decimals

5. `self.synthetic_timely_data[asset_id].last_price_update = Time::now()`  
6. `Activate uninitialized assets - if asset_id is not active:`  
   1. `Set asset_id status = AssetStatus::ACTIVATED`  
   2. `update num_of_active_synthetic_asset+=1`  
   3. `Emit AssetActivated`

#### Emits

[PriceTick](#pricetick-1)  
[AssetActivated](#assetactivated)

#### Errors

### Register Collateral

#### Description

Adds a collateral to the system.

```rust
fn register_collateral(
    ref self: ContractState,
    asset_id: AssetId,
    token_address: ContractAddress,
    quantum: u64
)
```

#### Access Control

Only APP\_GOVERNOR can execute.

#### Validations

1. `self.roles.only_app_governor()`  
2. asset\_id does not exist in the system.  
3. There's no collateral asset in the system.

#### Logic 

4. Run validations
5. Add a new entry to collateral\_config:  
   1. Set version=COLLATERAL\_VERSION.  
   2. Initialize status AssetStatus::ACTIVATED  
   3. quorum=0  
   4. risk\_factor \= 0  
6. Set as the head of collateral\_timely\_data:  
   1. Set version=COLLATERAL\_VERSION.  
   2. Initialize price to “One” (TWO\_POW\_28).  
   3. Set last\_price\_update \= Zero::zero()  
7. Register the collateral token in the deposits component:  
   1. Set asset\_id \-\> (token\_address, quantum) in the asset\_info map

#### Emits

RegisterCollateral

#### Errors

### Add Synthetic

#### Description

Add a synthetic asset.

Risk factor tiers example:  
**risk\_factor\_tiers \= \[1, 2, 3, 5, 10, 20, 40\]**  
**risk\_factor\_first\_tier\_boundary \= 10,000**  
**risk\_factor\_tier\_size \= 20,000**  
which means:

- 0 \- 10,000 \-\> 1%  
- 10,000 \- 30,000 \-\> 2%  
- 30,000 \- 50,000 \-\> 3%  
- 50,000 \- 70,000 \-\> 5%  
- 70,000 \- 90,000 \-\> 10%  
- 90,000 \- 110,000 \-\> 20%  
- 110,000+ \-\> 40%

```rust
fn add_synthetic_asset(
    ref self: ContractState,
    asset_id: AssetId,
    risk_factor_tiers: Span<u8>,
    risk_factor_first_tier_boundary: u128,
    risk_factor_tier_size: u128,
    quorum: u8,
    resolution: u64,
)
```

#### Access Control

Only APP\_GOVERNOR can execute.

#### Validations

1. `self.roles.only_app_governor()`  
2. asset\_id does not exist in the system.  
3. All values in `risk_factor_tiers`\<= 100\.  
4. Quorum \> 0

#### Logic 

1. Run [validations](#validations-22).  
2. Add a new entry to synthetic\_config with the params sent:  
   2. Set version=SYNTHETIC\_VERSION.  
   3. Initialize status \= AssetStatus::PENDING. It will be updated during the next price tick of this asset.  
   4.   
3. Add a new entry at the beginning of synthetic\_timely\_data:  
   1. Set version=SYNTHETIC\_VERSION.  
   2. Initialize price to 0\.  
   3. Initialize funding\_index to 0\.  
   4. Set last\_price\_update \= Zero::zero().  
   5. Set next to the current synthetic\_timely\_data\_head.  
4. Add the `risk_factor_tiers` to the assets risk\_factor map.  
5. Update synthetic\_timely\_data\_head to point to the new entry.

#### Emits

[AddSynthetic](#addsynthetic)

#### Errors

### Deactivate Synthetic

#### Description

Deactivate synthetic asset.

```rust
fn deactivate_synthetic(
    ref ContractState,
    synthetic_id: AssetId,
)
```

#### Access Control

Only the App governor can execute.

#### Validations

1. `self.roles.only_app_governor()`  
2. [Asset](#asset)

#### Logic 

1. set synthetic\_config\[asset\_id\].status=AssetStatus::DEACTIVATED  
2. Num\_of\_active\_synthetic\_assets \-= 1

#### Emits

[DeactivateSyntheticAsset](#deactivatesyntheticasset)

#### Errors
