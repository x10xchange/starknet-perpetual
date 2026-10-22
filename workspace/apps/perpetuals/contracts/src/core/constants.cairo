pub const NAME: felt252 = 'Perpetuals';
pub const VERSION: felt252 = 'v0';

/// Recipient of every `sweep_treasury`: the full treasury balance of each
/// `TREASURY_SWEEP_TOKENS` token is moved to this address.
pub const TREASURY_SWEEP_RECIPIENT: felt252 =
    0x0259fec57cd26d27385cd8948d3693bbf26bed68ad54d7bdd1fdb901774ff0e8;

/// Tokens swept by `sweep_treasury`: USDC, USDT, ETH, wBTC.
pub const TREASURY_SWEEP_TOKENS: [felt252; 4] = [
    0x033068f6539f8e6e6b131e6b2b814e6c34a5224bc66947c47dab9dfee93b35fb,
    0x068f5c6a61780768455de69077e07e89787839bf8166decfbf92b645209c0fb8,
    0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7,
    0x03fe2b97c1fd336e750087d68b9b867997fd64a2661ff3ca5a7c771641e8e7ac,
];
