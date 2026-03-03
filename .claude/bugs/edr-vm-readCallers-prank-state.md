# Bug: `vm.readCallers()` does not return active prank state in Hardhat 3 EDR

**Component:** Hardhat 3 EDR / forge-std cheatcode compatibility
**Severity:** Medium — breaks standard Foundry test patterns that rely on `pausePrank`-style modifiers
**Affects:** Any test that calls `vm.readCallers()` while a `vm.startPrank()` is active

---

## Summary

When `vm.startPrank(sender)` is active, a call to `vm.readCallers()` should return `(CallerMode.RecurrentPrank, sender, txOrigin)`. In Hardhat 3 EDR it returns `(CallerMode.None, address(0), address(0))`, making the prank invisible to any code that inspects caller mode.

This breaks the standard Foundry `pausePrank` modifier pattern, which uses `vm.readCallers()` to detect an active recurrent prank, stop it, run a block that needs a different `vm.prank()`, then restore the original prank. Because EDR reports no active prank, the stop never happens and the inner `vm.prank()` throws.

---

## Reproduction

### Minimal test

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

contract ReadCallersTest is Test {
    address alice = makeAddr("alice");
    address bob   = makeAddr("bob");

    modifier pausePrank() {
        (VmSafe.CallerMode mode, address sender, address origin) = vm.readCallers();
        if (mode == VmSafe.CallerMode.RecurrentPrank) vm.stopPrank();
        _;
        if (mode == VmSafe.CallerMode.RecurrentPrank) vm.startPrank(sender, origin);
    }

    function test_readCallers_insideStartPrank() public {
        vm.startPrank(alice);

        (VmSafe.CallerMode mode, address sender,) = vm.readCallers();

        // Should pass in Foundry, fails in Hardhat 3 EDR:
        assertEq(uint(mode), uint(VmSafe.CallerMode.RecurrentPrank));
        assertEq(sender, alice);

        vm.stopPrank();
    }

    function test_pausePrank_modifier() public pausePrank {
        vm.startPrank(alice);
        _helperThatNeedsDifferentSender();
        vm.stopPrank();
    }

    function _helperThatNeedsDifferentSender() internal pausePrank {
        // pausePrank should have stopped alice's prank here.
        // In Hardhat 3 EDR it does NOT → the vm.prank below throws:
        // "vm.prank: cannot override an ongoing prank with a single vm.prank"
        vm.prank(bob);
        // ... do something as bob
    }
}
```

### Minimal `hardhat.config.ts`

```ts
import { HardhatUserConfig } from "hardhat/config";

const config: HardhatUserConfig = {
  solidity: "0.8.26",
};

export default config;
```

### Steps to reproduce

```bash
npx hardhat test solidity
```

---

## Expected vs actual behaviour

| Scenario | Expected (`CallerMode`, `msgSender`, `txOrigin`) | Actual in EDR |
|---|---|---|
| Inside `vm.startPrank(alice)` | `(RecurrentPrank, alice, tx.origin)` | `(None, address(0), address(0))` |
| Inside `vm.startPrank(alice, origin)` | `(RecurrentPrank, alice, origin)` | `(None, address(0), address(0))` |
| Inside `vm.prank(alice)` | `(Prank, alice, tx.origin)` | _(not confirmed, likely same issue)_ |
| No active prank | `(None, msg.sender, tx.origin)` | `(None, msg.sender, tx.origin)` ✓ |

---

## Observed error

When the `pausePrank` modifier is used (a standard Foundry pattern), the missing prank detection causes the following runtime error:

```
Error: vm.prank: cannot override an ongoing prank with a single vm.prank;
       use vm.startPrank to override the current prank
```

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

**Call chain that fails:**

```
SpokeOperations_Gas_Tests::test_updateUserDynamicConfig()   [Spoke.Operations.gas.t.sol:209]
  vm.startPrank(alice)
  _updateLiquidationFee(spoke, reserveId.usdx, 10_00)       [Base.t.sol:1198, modifier: pausePrank]
    vm.readCallers() → (CallerMode.None, 0x0, 0x0)           ← BUG: should be RecurrentPrank
    condition false → vm.stopPrank() NOT called
    vm.prank(SPOKE_ADMIN)                                    [Base.t.sol:1206]  ← THROWS
```

**Failing tests (Hardhat 3 only):**

| Test | File |
|---|---|
| `SpokeOperations_Gas_Tests::test_updateUserDynamicConfig` | `tests/gas/Spoke.Operations.gas.t.sol:209` |
| `SpokeOperations_ZeroRiskPremium_Gas_Tests::test_updateUserDynamicConfig` (inherited) | same file |

Both tests pass on Foundry (`forge test`) with identical source code.

---

## Suggested fix

In the EDR cheatcode implementation for `readCallers`, query the current prank state from the EVM environment and populate the return values accordingly:

- When `vm.startPrank(sender)` is active → return `(CallerMode.RecurrentPrank, sender, currentTxOrigin)`
- When `vm.startPrank(sender, origin)` is active → return `(CallerMode.RecurrentPrank, sender, origin)`
- When `vm.prank(sender)` is active (single-call prank) → return `(CallerMode.Prank, sender, currentTxOrigin)`
- When no prank is active → return `(CallerMode.None, msg.sender, tx.origin)` _(already correct)_

The Foundry reference implementation is in
[`crates/cheatcodes/src/evm/prank.rs`](https://github.com/foundry-rs/foundry/blob/master/crates/cheatcodes/src/evm/prank.rs)
(`read_callers` function).

---

## Workaround (not applied)

The `_updateLiquidationFee` helper (and any other helper decorated with `pausePrank`) could be rewritten to manually stop and restart the prank instead of using the modifier:

```solidity
// caller saves / restores prank manually — avoids vm.readCallers()
vm.stopPrank();
_updateLiquidationFee(spoke, reserveId.usdx, 10_00);
vm.startPrank(alice);
```

This workaround is **not applied** — the test code is correct Foundry-idiomatic code and should work once EDR is fixed. Applying the workaround would mask the EDR bug and add unnecessary boilerplate to every test that calls `pausePrank`-decorated helpers.

---

## References

- Foundry `readCallers` spec: <https://book.getfoundry.sh/cheatcodes/read-callers>
- Hardhat cheatcode tracking: <https://github.com/NomicFoundation/hardhat/issues>
- aave-v4 migration report: [`aave-v4-hardhat-migration-report.md`](../aave-v4-hardhat-migration-report.md)
