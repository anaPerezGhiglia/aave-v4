# Hardhat 3 Migration Report: aave-v4

**Hardhat version installed:** `^3.1.10`
**Migration date:** 2026-03-03

---

**Verdict:** ❌ **Failed**

### Blockers
- ❌ `vm.readCallers()` returns wrong `CallerMode` inside `vm.startPrank()` — 2 tests actively failing ([local bug report](bugs/vm-readCallers-prank-state.md), not yet filed upstream)
- 🚩 `vm.eip712HashStruct()` / `vm.eip712HashType()` unsupported — 149 test instances (139 functions) commented out; entire EIP-712 signature layer is untested

### Notable gaps (non-blocking, medium+ impact)
- 🚩 No equivalent for `forge bind --alloy` (Rust bindings) or `forge build --extra-output-files abi` (ABI export) — `rs:bind`, `rs:abis`, `rs:generate` scripts have no Hardhat counterpart
- 🚩 Gas snapshot tests (`forge snapshot`) not supported

---

## 1. Test Count Comparison

| Metric | Count |
|---|---|
| Total `function test*` declarations in `.t.sol` files (excl. commented-out) | 1336 |
| Hardhat tests executed (includes inherited tests counted per contract) | 1447 |
| Tests passing | 1445 |
| Tests failing | 2 |
| Tests skipped (pending) | 1 |
| Functions fully commented out (`HARDHAT-SKIP`, signature + body) | 139 definitions → 149 instances (10 from inheritance) |

**Note:** The 1336 vs 1447 discrepancy is expected — Hardhat counts test functions per concrete contract, including inherited ones. When a base contract's test is inherited by multiple derived contracts, Hardhat counts each. The 139 commented-out functions (149 instances) are absent from both the declaration count and the Hardhat run — they do not appear in either total.

---

## 2. Feature Parity

### Gaps, bugs & partial support

| Feature | Parity | Impact | Workaround / Notes |
|---|---|---|---|
| `vm.readCallers()` + `pausePrank` modifier | ❌ **Bug** | **High** — 2 tests actively failing; genuine blocker | [Local bug report](bugs/vm-readCallers-prank-state.md) (not yet filed upstream) — fix needed in EDR; test code not modified |
| `vm.eip712HashStruct(string,bytes)` | 🚩 **Gap** | **High** — 131 test instances disabled; entire EIP-712 signature layer (SignatureGateway, TakerPositionManager, TokenizationSpoke WithSig) is untested | No tracking issue found — consider filing one; workaround: implement EIP-712 hashing in a Solidity helper |
| `vm.eip712HashType(string)` | 🚩 **Gap** | **High** — 18 test instances disabled (covered by same helpers as above) | No tracking issue found — consider filing one |
| Rust bindings (`forge bind --alloy`) | 🚩 **Gap** | **Medium** — `rs:bind` / `rs:generate` scripts broken; Rust integration workflow unavailable | Run the `alloy` CLI separately against ABI files extracted from Hardhat artifacts |
| Rust ABI export (`forge build --extra-output-files abi`) | 🚩 **Gap** | **Medium** — `rs:abis` script broken; ABI extraction pipeline unavailable | ABIs are in `artifacts/**/*.json`; write a custom extraction script |
| Gas snapshot tests | 🚩 **Gap** | **Medium** — `tests/gas/` tests run but snapshots can't be generated or checked against baselines | [#7769](https://github.com/NomicFoundation/hardhat/issues/7769) — no workaround currently |
| Inline test config (`/// forge-config:`) | 🚩 **Gap** | **Low** — `allow_internal_expect_revert` set globally as workaround; `isolate` and `disable_block_gas_limit` have no per-file/per-profile equivalent | [#7355](https://github.com/NomicFoundation/hardhat/issues/7355) |
| `isolate` per-profile / per-file | 🚩 **Gap** | **Low** — tests still run; global `test.solidity.isolate` works but can't be scoped | [#7355](https://github.com/NomicFoundation/hardhat/issues/7355) — global setting is a partial workaround |
| Fuzz profiles (`[profile.pr.fuzz]`, `[profile.ci.fuzz]`) | 🚩 **Gap** | **Low** — default 1000 runs still used; higher-run CI profiles not replicable | Pass `--fuzz-runs N` on the CLI or use an env var per CI job |
| Glob overrides (`tests/**`) | 🚩 **Gap** | **Low** — no-op in practice; default compiler settings already match the restriction | [#4686](https://github.com/NomicFoundation/hardhat/issues/4686) — list files individually if needed |
| `dynamic_test_linking` | 🚩 **Gap** | **Low** — no observable impact in Hardhat test runs | Foundry-only |
| `[bind_json]` | 🚩 **Gap** | **Low** — `JsonBindings.sol` is pre-generated and committed; not regeneratable | Foundry-only |
| Formatter | 🚩 **Gap** | **Low** — no action needed; prettier already configured | Use prettier + prettier-plugin-solidity |
| Etherscan verification | 🟡 **Partial** | **Low** — key model differs; minor CI secret update needed | Etherscan API v2 accepts one key across all chains — consolidate to a single `ETHERSCAN_API_KEY` |

### Full parity

These features work equivalently in Hardhat 3:

- Solidity compilation (`forge build` → `npx hardhat compile`)
- Unit & integration tests (`forge test` → `npx hardhat test solidity`) — non-EIP-712-sig tests only
- Fuzz testing
- `remappings.txt` auto-loaded
- Absolute imports (`src/`, `tests/`, `lib/`) via remappings
- forge-std cheatcodes (`vm.*`) — general
- `allowInternalExpectRevert` (set globally)
- `fsPermissions`
- `gasLimit`
- Per-file compiler overrides
- Build profiles (`[profile.coverage]`)

**Features not used by this project:**
- Deployment scripts (`forge script` / `.s.sol`) — project has no `script/` directory

---

## 3. Hardhat / EDR Bug Reports

### `vm.readCallers()` — wrong `CallerMode` inside `vm.startPrank()`

The `pausePrank` modifier in `tests/Base.t.sol` calls `vm.readCallers()` and conditionally calls `vm.stopPrank()`. In Hardhat 3 EDR, `vm.readCallers()` does not reliably return `CallerMode.RecurrentPrank` during an active `vm.startPrank`, so `vm.stopPrank()` is never called, leaving the prank active when `vm.prank(SPOKE_ADMIN)` runs inside `_updateLiquidationFee`.

This is a confirmed bug — `vm.readCallers()` returns `(CallerMode.None, address(0), address(0))` inside an active `vm.startPrank()` instead of `(CallerMode.RecurrentPrank, sender, txOrigin)`. A structured bug report has been written for the Hardhat/NomicFoundation team: **[`.claude/bugs/vm-readCallers-prank-state.md`](bugs/vm-readCallers-prank-state.md)**.

These tests are **not** commented out — they are actively failing and represent a blocker.

| File | Function | Error |
|---|---|---|
| `tests/gas/Spoke.Operations.gas.t.sol` | `SpokeOperations_Gas_Tests::test_updateUserDynamicConfig` | `vm.prank: cannot override an ongoing prank` |
| `tests/gas/Spoke.Operations.gas.t.sol` | `SpokeOperations_ZeroRiskPremium_Gas_Tests::test_updateUserDynamicConfig` (inherited) | same |

---

## 4. Workarounds Applied

1. **`remappings.txt` additions** — Added three new remappings to handle absolute imports used throughout the project:
   ```
   lib/=./lib/
   src/=./src/
   tests/=./tests/
   ```
   225+ files in `src/` and `tests/` use single-quoted absolute imports (`'src/...'`, `'tests/...'`). Adding remappings was the correct approach (10+ file threshold by a large margin).

2. **`lib/=./lib/` remapping** — `TokenizationSpoke.ERC4626Compliance.t.sol` directly imports `lib/erc4626-tests/ERC4626.test.sol` without using the `erc4626-tests/` remapping. Added `lib/=./lib/` to resolve it.

3. **`allowInternalExpectRevert: true` set globally** — Three test files (`AaveOracle.t.sol`, `KeyValueList.t.sol`, `MathUtils.t.sol`) use `/// forge-config: default.allow_internal_expect_revert = true` inline (silently ignored by Hardhat). Set the option globally in `hardhat.config.ts` to preserve behavior.

4. **`"type": "module"` added to `package.json`** — Required for Hardhat 3 (ESM). No existing CommonJS files were present, so no compatibility issues.

5. **`compilation_restrictions` glob skipped** — `tests/**` glob in `compilation_restrictions` has no Hardhat equivalent. The default compiler settings already match the restriction (optimizer=true, viaIR=false, runs=444444444444), so omitting it is a no-op for the default build profile. A TODO comment is left in `hardhat.config.ts`.

---

## 4b. Functions Commented Out (UnsupportedCheatcode)

### `vm.eip712HashStruct(string,bytes)` — 131 test instances, ~127 functions fully commented out

All EIP-712 signature tests. The cheatcode is used in base helper functions (`signXxx()` helpers) that cascade into many test functions.

Files affected:

| File | Contract(s) | Functions disabled |
|---|---|---|
| `tests/unit/position-manager/SignatureGateway/SignatureGateway.Reverts.InsufficientAllowance.t.sol` | `SignatureGateway_InsufficientAllowance_Test` | 2 |
| `tests/unit/position-manager/SignatureGateway/SignatureGateway.Reverts.Unauthorized.t.sol` | `*PositionManagerActive_Test`, `*NotActive_Test` | 7 (×2 via inheritance) |
| `tests/unit/position-manager/PositionManagerBase.t.sol` | `PositionManagerBaseTest` | 2 |
| `tests/unit/position-manager/libraries/PositionManagerEIP712Hash.t.sol` | `PositionManagerEIP712HashTest` | 8 |
| `tests/unit/position-manager/SignatureGateway/SignatureGateway.Constants.t.sol` | `SignatureGatewayConstantsTest` | 7 |
| `tests/unit/position-manager/SignatureGateway/SignatureGateway.Reverts.InvalidSignature.t.sol` | `SignatureGatewayInvalidSignatureTest` | 21 |
| `tests/unit/position-manager/SignatureGateway/SignatureGateway.PermitReserve.t.sol` | `SignatureGatewayPermitReserveTest` | 1 |
| `tests/unit/position-manager/SignatureGateway/SignatureGateway.SetSelfAsUserPositionManagerWithSig.t.sol` | `SignatureGatewaySetSelfAsUserPositionManagerTest` | 1 |
| `tests/unit/position-manager/SignatureGateway/SignatureGateway.t.sol` | `SignatureGatewayTest` | 11 |
| `tests/unit/position-manager/TakerPositionManager/TakerPositionManager.Permit.t.sol` | `TakerPositionManagerPermitTest` | 12 |
| `tests/unit/TokenizationSpoke/TokenizationSpoke.Constants.t.sol` | `TokenizationSpokeConstantsTest` | 5 |
| `tests/unit/TokenizationSpoke/TokenizationSpoke.Permit.t.sol` | `TokenizationSpokePermitTest` | 6 |
| `tests/unit/TokenizationSpoke/TokenizationSpoke.WithSig.Reverts.InvalidSignature.t.sol` | `TokenizationSpokeWithSigInvalidSignatureTest` | 12 |
| `tests/unit/TokenizationSpoke/TokenizationSpoke.WithSig.t.sol` | `TokenizationSpokeWithSigTest` | 4 |
| `tests/unit/TokenizationSpoke/TokenizationSpoke.DepositWithPermit.t.sol` | `TokenizationSpokeDepositWithPermitTest` | 1 |
| `tests/unit/TokenizationSpoke/TokenizationSpoke.Reverts.InsufficientAllowance.t.sol` | `TokenizationSpokeInsufficientAllowanceTest` | 2 |
| `tests/unit/Spoke/Spoke.SetUserPositionManagerWithSig.t.sol` | `SpokeSetUserPositionManagersWithSigTest` | 12 |
| `tests/unit/Spoke/Spoke.PermitReserve.t.sol` | `SpokePermitReserveTest` | 1 |
| `tests/unit/libraries/SpokeEIP712Hash.t.sol` | `SpokeEIP712HashTest` | 7 |
| `tests/gas/PositionManagers.Operations.gas.t.sol` | `PositionManager_Gas_Tests`, `TakerPositionManager_Gas_Tests` | 3 |
| `tests/gas/TokenizationSpoke.Operations.gas.t.sol` | `TokenizationSpokeOperations_Gas_Tests` | 5 |
| `tests/gas/Gateways.Operations.gas.t.sol` | `SignatureGateway_Gas_Tests` | 8 |
| `tests/gas/Spoke.Operations.gas.t.sol` | `SpokeOperations_Gas_Tests` (also `ZeroRiskPremium`) | 2 (×2 via inheritance) |

### `vm.eip712HashType(string)` — 18 test instances

Covered by the same functions as above (the same helpers call both cheatcodes).

---

## 5. Next steps

1. **Implement EIP-712 hashing in a Solidity helper** — unblocks 149 test instances immediately without waiting on Hardhat; avoids the `vm.eip712HashStruct`/`vm.eip712HashType` cheatcode dependency entirely
2. **File the `vm.readCallers()` bug upstream** — 2 tests are actively failing; bug is documented in [`.claude/bugs/vm-readCallers-prank-state.md`](bugs/vm-readCallers-prank-state.md); file at [NomicFoundation/hardhat](https://github.com/NomicFoundation/hardhat/issues) or [NomicFoundation/edr](https://github.com/NomicFoundation/edr/issues) depending on where the root cause lies
3. **Track `vm.eip712HashStruct`/`vm.eip712HashType` upstream** — long-term resolution; no tracking issue exists yet, consider filing one
