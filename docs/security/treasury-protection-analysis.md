# Security Analysis — Treasury ↔ Perpetuals Loss Limiting

**Scope:** Interaction between `ProtocolTreasury` (`workspace/treasury`) and the
perpetuals `Core` contract (`workspace/apps/perpetuals/contracts`), with focus on
the stated requirement:

> The treasury contract must limit losses to the maximum limit set by the
> protocol governance.

**Branch analyzed:** `next_version`
**Date:** 2026-06-09

---

## 1. How the mechanism works today

All collateral now lives in `ProtocolTreasury`. The perps `Core` contract holds no
token balances; it pulls funds from the treasury on every outflow.

### Outflow paths (treasury → perps → user)

Every token that leaves the treasury goes through exactly one function:

```
ProtocolTreasury::withdraw_from(collateral_address, amount)
  - assert caller == perps_contract            // only perps may pull funds
  - update_withdrawn_and_verify(...)           // enforces the protection limit
  - ERC20.transfer(perps_contract, amount)
```

It is reached from two places in `Core`:

1. **User withdrawals** — `withdrawal_manager.cairo::_withdraw` →
   `treasury.withdraw_from(token, amount)` then forwards the tokens to the user.
2. **Vault redemptions** — `vaults_contract.cairo` pulls the vault-share tokens
   out of the treasury so they can be burned.

Deposits flow the other way through `deposit_into`, which only ever *increases*
the treasury balance and is not rate-limited by the protection logic.

### The protection limit (`protocol_treasury.cairo`, `types.cairo`)

State is tracked **per collateral token**:

```cairo
struct ProtectionState {
    time_of_last_reset: Timestamp,
    amount_withdrawn_since_reset: u128,
    balance_at_last_reset: u128,
    max_allowed_withdrawal: u128,   // = balance_at_last_reset * percent / 100
}
```

- `max_allowed_withdrawal = compute_max_withdrawal(balance, percent)`
  `= balance * (percent * 10) / 1000`, i.e. `percent` percent of the snapshot
  balance. Default `percent` is **5%**.
- On each `withdraw_from`, `update_and_get_protection_limit` checks whether more
  than `CHECK_FREQUENCY` (**1 day**) has elapsed since `time_of_last_reset`. If so,
  it **re-snapshots the live balance**, recomputes `max_allowed_withdrawal`, and
  **resets `amount_withdrawn_since_reset` to 0**.
- `update_withdrawn_and_verify` accumulates `amount_withdrawn_since_reset` and
  panics with `"Treasury Protection Limit Exceeded"` if the running total would
  exceed `max_allowed_withdrawal`.

Governance (the `app_governor` role) can:
- `change_protection_limit_percent(token, percent)` — set the per-token percent.
- `reset_protection_limit(token)` — re-snapshot balance and zero the counter now.

### What is implemented correctly (positives)

- **Checks-effects-interactions ordering.** State (`amount_withdrawn_since_reset`)
  is written *before* the ERC20 transfer, so a reentrant/malicious token cannot
  loop `withdraw_from` to bypass the cap.
- **Access control.** Only `perps_contract` can withdraw; only `app_governor` can
  change/reset the limit. Tests cover perps, governance-admin and arbitrary
  callers being rejected.
- **Default-on protection.** An uninitialized token has `time_of_last_reset = 0`,
  so the first withdrawal auto-initializes the limit at the default 5% — the
  treasury is never unprotected just because governance forgot to configure it.
- **Per-token isolation.** Each collateral has independent accounting; draining
  one token's budget does not affect another. Vault-share round-trips no longer
  double-count against the USDC budget (regression test present).

---

## 2. Findings

### F-1 (High / Design) — It is a loss *rate* limiter, not a loss *cap*

The window **fully resets every day**: after `CHECK_FREQUENCY`, the next
withdrawal starts a brand-new window with a fresh 100% allowance computed from the
current balance. There is **no absolute or aggregate ceiling** on cumulative
losses.

Consequence: a malicious/compromised operator (or a logic bug that drives losses)
can extract `percent`% of the balance **every day, indefinitely**. At the default
5%/day a treasury can be drained to ~half its value in ~14 days and to ~5% of its
value in ~58 days, with no governance action able to retroactively claw the funds
back.

If governance's intent behind "the maximum limit" is an **absolute** maximum loss
(e.g. "this treasury may never pay out more than X without an explicit unlock"),
**that property does not hold today.** The contract only bounds the *rate* of loss
per 24h, not the total. This is the single most important gap relative to the
stated requirement and should be confirmed against the product intent.

*Recommendation:* If an absolute cap is desired, add an aggregate
`total_withdrawn` (or a long-horizon budget) that does not auto-reset and can only
be raised by an explicit governance action. Keep the daily limiter as a secondary
control.

### F-2 (High) — Fixed-window (non-sliding) allows a ~2× burst at the boundary

The window is a fixed window keyed to `time_of_last_reset`, not a sliding window.
An actor can withdraw the full allowance at the very end of one window and the
full allowance again immediately after the reset:

1. At `T` (≈1 day into the current window) withdraw the max `percent`% — counter is
   now at the cap.
2. At `T + ε`, because `now - time_of_last_reset > 1 day`, the next withdrawal
   triggers a reset and grants a fresh `percent`% allowance — withdraw it.

The two withdrawals can be seconds apart, so the **effective short-term drain is
up to 2× the nominal per-window limit** (~10% at the default 5%). Standard
fixed-window rate-limiter weakness.

*Recommendation:* Use a sliding/rolling window, or carry a fraction of the unused
budget rather than hard-resetting, or align resets so back-to-back maxima are not
possible.

### F-3 (Medium-High) — `percent = 0` is overloaded and cannot durably freeze withdrawals

`get_protection_percent` treats an override of `0` as **"no override, fall back to
the default 5%"**:

```cairo
let override_percent = self.protection_percent_override.read(collateral_address);
if override_percent != 0 { override_percent } else { DEFAULT_PROTECTION_PERCENT }
```

So if `app_governor` calls `change_protection_limit_percent(token, 0)` intending to
**freeze** all withdrawals of a token (the natural reading of "max limit = 0"):

- It works *immediately* (the function writes `max_allowed_withdrawal = 0`), but
- on the **next daily auto-reset** `update_and_get_protection_limit` recomputes the
  limit with `get_protection_percent`, which returns **5%**, silently re-opening
  withdrawals.

The project's own test `test_treasury_withdrawal_exceeding_limit_fails` documents
this by deliberately *not* calling reset, and `test_change_protection_limit_to_zero`
only checks the same-window behavior. Governance cannot durably express a 0% limit
through the percent path; they must use `pause()` instead, which is non-obvious and
easy to get wrong. This directly undermines "limit losses to the maximum (possibly
zero) set by governance."

*Recommendation:* Distinguish "unset" from "0" — e.g. store the override in an
`Option<u64>` or add a separate `is_set` flag — so an explicit 0% survives the
auto-reset.

### F-4 (Medium) — No upper bound on `percent`; single role, unbounded power

`change_protection_limit_percent` accepts any `u64`:

- `percent > 100` makes `max_allowed_withdrawal > balance`, effectively
  **disabling the protection** (the whole treasury becomes withdrawable in one
  window).
- A very large `percent` makes `compute_max_withdrawal` overflow `u128` and panic
  with `MUL_DIV_OVERFLOW`, **bricking all withdrawals** of that token until the
  value is changed again (DoS).

The safety limit is fully controlled by a single `app_governor` role with no cap,
no timelock, and no two-step confirmation. A compromised or careless governor can
neutralize the protection in one transaction.

*Recommendation:* Bound `percent` (e.g. `assert(percent <= 100)`), and consider
gating limit *increases* behind the replaceability/upgrade timelock or a
second role.

### F-5 (Medium) — `reset_protection_limit` lets governance bypass the per-window cap on demand

`reset_protection_limit` zeroes `amount_withdrawn_since_reset` immediately. A
governor who can also drive perps withdrawals can therefore loop
`reset → withdraw max → reset → withdraw max …` and extract far more than the daily
limit in a single block. The protection meaningfully constrains only the
**operator**, not the **app_governor**. This is a deliberate trust assumption, but
it should be documented and ideally hardened (timelock on reset, or rate-limit the
resets themselves).

### F-6 (Low / Informational) — Limit basis includes user deposits and is live-read

`max_allowed_withdrawal` is `percent`% of the **total ERC20 balance**, which
includes user collateral. So:

- The absolute daily drain ceiling **grows with TVL** — the more users deposit, the
  larger the absolute amount an attacker can pull per day.
- The snapshot is a **live `balance_of`** read at reset time. A large transient
  deposit immediately before a reset (or before a manual `reset_protection_limit`)
  inflates `balance_at_last_reset` and hence the allowance for that window.

Neither lets an actor net-extract more than they contributed, but both widen the
window available to the rate-limited drain in F-1/F-2.

### F-7 (Low) — Floor rounding blocks dust balances

`compute_max_withdrawal` floor-divides, so for very small balances
(`balance * percent * 10 < 1000`) the max is `0` and all withdrawals of that token
revert. Minor, affects only dust-sized treasuries.

### F-8 (Informational) — Upgradeable treasury is a trust root

`ProtocolTreasury` embeds `ReplaceabilityComponent`. Governance can replace the
implementation (subject to `upgrade_delay`) with one that ignores the protection
limit. The limit therefore protects against operator-level compromise within a
fixed implementation, not against governance-level compromise. Worth stating
explicitly in the threat model.

---

## 3. Verdict on the stated requirement

> "The treasury contract must limit losses to the maximum limit set by the protocol
> governance."

- **Within a single 24h window, per token: YES.** Outflows are correctly gated to
  `percent`% of the snapshot balance, accounting is reentrancy-safe, and protection
  is on by default. This part is solid and well-tested.
- **As an absolute / durable maximum: NO.** The daily fixed-window reset (F-1),
  the ~2× boundary burst (F-2), the inability to durably set 0% (F-3), the
  uncapped governor-set percent (F-4), and on-demand `reset_protection_limit`
  (F-5) mean the design enforces a **loss rate**, not a **loss ceiling**, and the
  ceiling it does enforce can be widened or neutralized by a single governance
  role.

If the product intent is a rate limiter, F-3 and F-4 are still real correctness
bugs that should be fixed before release. If the intent is a hard maximum loss,
F-1 is a fundamental gap and the design needs an aggregate, non-resetting budget.

## 4. Suggested priorities before release

1. Decide rate-limit vs. absolute-cap semantics (F-1). If absolute, add a
   non-resetting aggregate budget.
2. Fix the `percent = 0` overload so a 0% freeze survives auto-reset (F-3).
3. Bound `percent <= 100` to prevent accidental/ malicious disabling and the
   overflow DoS (F-4).
4. Document and consider hardening the `app_governor` trust assumptions around
   `reset_protection_limit` (F-5).
5. Consider a sliding window to remove the boundary burst (F-2).
