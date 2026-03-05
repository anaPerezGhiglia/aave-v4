# Bug: `vm.readCallers()` returns wrong `CallerMode` enum values in Hardhat 3 EDR

**Component:** Hardhat 3 EDR / forge-std cheatcode compatibility
**Severity:** Medium — breaks standard Foundry test patterns that rely on `pausePrank`-style modifiers
**Affects:** Any test that calls `vm.readCallers()` and compares the `CallerMode` enum
**Root cause:** EDR uses a 3-variant `CallerMode` enum instead of the 5-variant enum defined in forge-std

---

## Summary

`vm.readCallers()` in EDR **does** correctly detect active pranks and returns the correct `msgSender` and `txOrigin`. However, it returns **wrong `CallerMode` enum values** because EDR defines `CallerMode` as a 3-variant enum (omitting the `Broadcast` modes), while forge-std defines it as a 5-variant enum:

| CallerMode | forge-std (Foundry) value | EDR actual value |
|---|---|---|
| `None` | 0 | 0 |
| `Broadcast` | 1 | _(not implemented)_ |
| `RecurrentBroadcast` | 2 | _(not implemented)_ |
| `Prank` | 3 | **1** |
| `RecurrentPrank` | 4 | **2** |

When Solidity code checks `mode == VmSafe.CallerMode.RecurrentPrank`, it compares against `4`. EDR returns `2`. The comparison is **always false**, making the active prank invisible to any enum-based branching.

This is a **single root cause** that breaks the standard Foundry `pausePrank` modifier pattern. The underlying `startPrank`, `stopPrank`, and `prank` cheatcodes all work correctly in EDR — the only issue is the enum mapping in `readCallers`.

---

## Reproduction

### Minimal test

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

contract ReadCallersEnumTest is Test {
    function test_readCallers_enumValue_prank() public {
        vm.prank(makeAddr("alice"));
        (VmSafe.CallerMode mode, , ) = vm.readCallers();
        // Foundry: mode = 3 (Prank). EDR: mode = 1.
        assertEq(uint(mode), uint(VmSafe.CallerMode.Prank), "should be Prank (3)");
    }

    function test_readCallers_enumValue_startPrank() public {
        vm.startPrank(makeAddr("alice"));
        (VmSafe.CallerMode mode, , ) = vm.readCallers();
        // Foundry: mode = 4 (RecurrentPrank). EDR: mode = 2.
        assertEq(uint(mode), uint(VmSafe.CallerMode.RecurrentPrank), "should be RecurrentPrank (4)");
        vm.stopPrank();
    }
}
```

### Steps to reproduce

```bash
npx hardhat test -vvv tests/unit/ReadCallersTest.t.sol
```

---

## Evidence from traces

### `readCallers` returns correct addresses but wrong enum

Output from `npx hardhat test -vvv` (run 2026-03-05):

```
├─ [0] VM::startPrank(alice: [0x328809Bc894f92807417D2dAD6b7C998c1aFdac6])
├─ [0] VM::readCallers()
│    └─ ← 2, alice: [0x328809Bc894f92807417D2dAD6b7C998c1aFdac6], DefaultSender: [0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38]
├─ [0] VM::assertEq(2, 4, "mode should be RecurrentPrank (4)") [staticcall]
│    └─ ← mode should be RecurrentPrank (4): 2 != 4
```

The sender (`alice`) and origin (`DefaultSender`) are **correct**. Only the mode enum value (`2` instead of `4`) is wrong.

### Single prank shows same pattern

```
├─ [0] VM::prank(alice: [0x328809Bc894f92807417D2dAD6b7C998c1aFdac6])
├─ [0] VM::readCallers()
│    └─ ← 1, alice: [0x328809Bc894f92807417D2dAD6b7C998c1aFdac6], DefaultSender: [0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38]
├─ [0] VM::assertEq(1, 3, "mode should be Prank (3)") [staticcall]
│    └─ ← mode should be Prank (3): 1 != 3
```

### Workaround tests confirm it's only the enum

Tests using raw `uint` comparison (`raw == 2 || raw == 4`) all pass, proving the underlying prank mechanics work correctly:

```
✔ test_workaround_corePattern_rawEnum()        — stop/prank/restore cycle works
✔ test_workaround_pausePrank_rawEnum()          — pausePrank modifier works
✔ test_workaround_pausePrank_nested_rawEnum()   — nested pausePrank works
```

---

## Test results summary

Full test suite: `tests/unit/ReadCallersTest.t.sol` — 26 tests, run against EDR.

| Group | Tests | Pass | Fail | Notes |
|---|---|---|---|---|
| 1. readCallers basic correctness | 5 | 2 | 3 | Fails: enum comparison for Prank and RecurrentPrank |
| 2. Raw enum value verification | 2 | 2 | 0 | Confirms EDR returns 1/2 instead of 3/4 |
| 3. readCallers stability | 2 | 0 | 2 | Fails: same enum issue, sender/origin are correct |
| 4. stopPrank effectiveness | 3 | 1 | 2 | `stopPrank_allowsSubsequentPrank` passes; others fail on enum |
| 5. startPrank persistence | 2 | 0 | 2 | Fails: enum issue; prank state actually persists fine |
| 6. prank vs startPrank interaction | 2 | 1 | 1 | `singlePrank_consumed` passes; `switchPranks` fails on enum |
| 7. pausePrank modifier (forge-std enum) | 4 | 1 | 3 | `noPrankActive` passes; all active-prank cases fail |
| 8. Edge cases (call depth/timing) | 3 | 0 | 3 | Fails: enum issue only |
| 9. **Workaround (raw enum)** | **3** | **3** | **0** | **All pass — proves prank mechanics are correct** |

**10 passing, 16 failing.** Every failure is caused by the enum mismatch. Every test that bypasses the enum comparison passes.

---

## Affected aave-v4 code

**Modifier definition:** [`tests/Base.t.sol:3073`](../../../tests/Base.t.sol#L3073)

```solidity
modifier pausePrank() {
  (VmSafe.CallerMode callerMode, address msgSender, address txOrigin) = vm.readCallers();
  if (callerMode == VmSafe.CallerMode.RecurrentPrank) vm.stopPrank();
  _;
  if (callerMode == VmSafe.CallerMode.RecurrentPrank) vm.startPrank(msgSender, txOrigin);
}
```

The condition `callerMode == VmSafe.CallerMode.RecurrentPrank` compares the returned value against `4`, but EDR returns `2`. The condition is always `false`, so `stopPrank()` is never called, and the inner `vm.prank()` throws:

```
Error: vm.prank: cannot override an ongoing prank with a single vm.prank;
       use vm.startPrank to override the current prank
```

**Failing tests (Hardhat 3 only):**

| Test | File |
|---|---|
| `SpokeOperations_Gas_Tests::test_updateUserDynamicConfig` | `tests/gas/Spoke.Operations.gas.t.sol:209` |
| `SpokeOperations_ZeroRiskPremium_Gas_Tests::test_updateUserDynamicConfig` (inherited) | same file |

Both tests pass on Foundry (`forge test`) with identical source code.

---

## Suggested fix

In the EDR `readCallers` cheatcode implementation, update the `CallerMode` enum to match the forge-std 5-variant definition:

```
enum CallerMode {
    None,               // 0
    Broadcast,          // 1
    RecurrentBroadcast, // 2
    Prank,              // 3
    RecurrentPrank      // 4
}
```

Currently EDR appears to use:
```
enum CallerMode {
    None,               // 0
    Prank,              // 1  ← should be 3
    RecurrentPrank      // 2  ← should be 4
}
```

The fix is to return `3` for single prank and `4` for recurrent prank, matching the forge-std `VmSafe.CallerMode` enum.

The Foundry reference implementation is in
[`crates/cheatcodes/src/evm/prank.rs`](https://github.com/foundry-rs/foundry/blob/master/crates/cheatcodes/src/evm/prank.rs)
(`read_callers` function).

---

## Workaround (not applied)

A raw `uint` comparison can be used to work around the enum mismatch:

```solidity
modifier pausePrank() {
  (VmSafe.CallerMode mode, address sender, address origin) = vm.readCallers();
  uint raw = uint(mode);
  // 2 = EDR's RecurrentPrank, 4 = Foundry's RecurrentPrank
  bool wasPranking = (raw == 2 || raw == 4);
  if (wasPranking) vm.stopPrank();
  _;
  if (wasPranking) vm.startPrank(sender, origin);
}
```

This workaround is **validated** by the test suite (Group 9 tests all pass). However, it is **not applied** to the aave-v4 codebase — the test code is correct Foundry-idiomatic code and should work once EDR is fixed.

---

## References

- Foundry `readCallers` spec: <https://book.getfoundry.sh/cheatcodes/read-callers>
- forge-std `CallerMode` enum: `VmSafe.sol` in forge-std
- Hardhat cheatcode tracking: <https://github.com/NomicFoundation/hardhat/issues>
- aave-v4 migration report: [`aave-v4-hardhat-migration-report.md`](../aave-v4-hardhat-migration-report.md)
- Diagnostic test suite: [`tests/unit/ReadCallersTest.t.sol`](../../../tests/unit/ReadCallersTest.t.sol)
