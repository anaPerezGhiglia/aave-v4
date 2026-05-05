---
name: vm.snapshotGasLastCall name validation diverges from Foundry
description: EDR rejects gas snapshot names that Foundry accepts (colons, parentheses), breaking valid test code
type: bug
---

# `vm.snapshotGasLastCall` rejects names containing colons / parentheses; diverges from Foundry

## Summary

Hardhat 3 (via EDR) enforces a strict character allowlist on gas snapshot names passed to `vm.snapshotGasLastCall(string, string)`, `vm.startSnapshotGas(string, string)`, and related cheatcodes. **Foundry does not enforce any name validation** in the equivalent cheatcode (see [`crates/cheatcodes/src/evm.rs::inner_last_gas_snapshot`](https://github.com/foundry-rs/foundry/blob/master/crates/cheatcodes/src/evm.rs)). This makes EDR strictly more restrictive than Foundry and causes valid Foundry-idiomatic test code to fail under Hardhat.

The Aave V4 project's gas test suite uses descriptive snapshot names containing colons and parentheses (e.g. `'liquidationCall (reportDeficit): full'`, `'getUserAccountData: supplies: 0, borrows: 0'`), which Foundry accepts and which trip EDR's validator. Under Hardhat 3.4.4 (EDR `next.31`), **38 gas tests fail** with the validation error.

## Affected layer

EDR (`@nomicfoundation/edr`). Per the EDR changelog, the validator was introduced in **[`0.12.0-next.29`](https://github.com/NomicFoundation/edr/releases) (Mar 24)** — *"Added validation checks for names provided in gas snapshot cheatcodes"*. Releases before `next.29` had no validation (Foundry-equivalent behaviour). The allowlist was later relaxed in `next.31` (Apr 20) to permit commas and non-consecutive dots, but `:`, `(`, `)`, and `/` are still rejected. No Hardhat-side change is involved — every Hardhat 3 release that pins EDR ≥ `next.29` (which is every release since at least Hardhat 3.3.0) inherits this behaviour.

## Steps to reproduce

1. Install any Hardhat 3 release that pins EDR ≥ `0.12.0-next.29` (verified on Hardhat 3.3.0 / EDR `next.29` and Hardhat 3.4.4 / EDR `next.31`).
2. Add a Solidity test that calls `vm.snapshotGasLastCall(string,string)` with a name containing `:`:

   ```solidity
   // SPDX-License-Identifier: UNLICENSED
   pragma solidity 0.8.28;

   import { Test } from "forge-std/Test.sol";

   contract Repro is Test {
     function test_snapshotName() public {
       address(this).call("");
       vm.snapshotGasLastCall("Group", "name: with colon");
     }
   }
   ```

3. Minimal `hardhat.config.ts`:

   ```ts
   import { defineConfig } from "hardhat/config";
   export default defineConfig({
     solidity: { compilers: [{ version: "0.8.28" }] },
   });
   ```

4. Run `npx hardhat test solidity`.

## Expected vs actual

|             | Foundry (`forge test`)           | Hardhat 3 / EDR ≥ `next.29`                                                                                                                                                                   |
| ----------- | -------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Test result | **passes** — name accepted as-is | **fails** with `vm.snapshotGasLastCall: invalid snapshot name: "name: with colon". Only alphanumeric characters, hyphens, underscores, spaces, commas, and non-consecutive dots are allowed.` |

## Observed error

```
Error: vm.snapshotGasLastCall: invalid snapshot name: "liquidationCall (reportDeficit): full". Only alphanumeric characters, hyphens, underscores, spaces, commas, and non-consecutive dots are allowed.
```

## Foundry reference implementation

`inner_last_gas_snapshot` in [`crates/cheatcodes/src/evm.rs`](https://github.com/foundry-rs/foundry/blob/master/crates/cheatcodes/src/evm.rs):

```rust
fn inner_last_gas_snapshot<FEN: FoundryEvmNetwork>(
    ccx: &mut CheatsCtxt<'_, '_, FEN>,
    group: Option<String>,
    name: Option<String>,
    value: u64,
) -> Result {
    let (group, name) = derive_snapshot_name(ccx, group, name);
    ccx.state.gas_snapshots.entry(group).or_default().insert(name, value.to_string());
    Ok(value.abi_encode())
}
```

No validation is applied — the name is stored verbatim. Likewise for `inner_value_snapshot`, `inner_start_gas_snapshot`, and `inner_stop_gas_snapshot`.

## Suggested fix direction

Either remove the name validation from EDR entirely (matching Foundry behavior), or relax it to permit common ASCII separators (`:`, `(`, `)`, `/`) which are commonly used in descriptive snapshot names. The character set the EDR team likely cares about is "anything that doesn't break the snapshot file format" — Foundry stores the name as a plain JSON map key, which permits any string.

If filename-safe names are the concern (snapshot file paths derived from names), the validation should apply only when serialising to disk during `--snapshot` runs, not when the cheatcode is invoked during a regular test run.

## Failing tests

All 38 failures are in the `tests/gas/` directory and share the same root cause:

- `tests/gas/Spoke.Operations.gas.t.sol` — `SpokeOperations_Gas_Tests` (10 tests) and `SpokeOperations_ZeroRiskPremium_Gas_Tests` (10 tests, inherited)
- `tests/gas/Spoke.Getters.gas.t.sol` — `SpokeGetters_Gas_Tests` (5 tests)
- `tests/gas/Hub.Operations.gas.t.sol` — `HubOperations_Gas_Tests` (5 tests, includes `test_add`, `test_deficit`, `test_remove`, `test_restore`, `test_restore_with_transfer`)
- `tests/gas/Gateways.Operations.gas.t.sol` — `NativeTokenGateway_Gas_Tests::test_withdrawNative` (1 test)
- `tests/gas/PositionManagers.Operations.gas.t.sol` — `TakerPositionManager_Gas_Tests::test_withdrawOnBehalfOf` (1 test)
- `tests/gas/TokenizationSpoke.Operations.gas.t.sol` — `TokenizationSpokeOperations_Gas_Tests` (2 tests: `test_withdraw`, `test_redeem`)

Example offending names from the project: `'getUserAccountData: supplies: 0, borrows: 0'`, `'liquidationCall (reportDeficit): full'`, `'updateUserRiskPremium: 1 borrow'`, `'withdraw: 0 borrows, partial'`.

## Workaround

A workaround **exists** but is **not applied** in this dry run: rename every snapshot label to use only the EDR-allowed character set (e.g. swap `:` for `-` and drop parentheses). This would touch ~50 call sites across `tests/gas/*.t.sol`.

The workaround is **not applied** because:

1. The test code is correct, Foundry-idiomatic Solidity that runs unchanged under `forge test`. Mass-renaming labels would be churn driven by an EDR-specific limitation, not a logic problem.
2. Snapshot labels are externally meaningful — they appear in gas snapshot files consumed by downstream tooling and CI dashboards. Mechanically rewriting them would break diffs and existing baselines.
3. The fix belongs in EDR (relax validation to match Foundry).
