# Hardhat 3 Migration Report: aave-v4

**Hardhat version installed:** `^3.1.10`
**Migration date:** 2026-03-03

---

**Verdict:** ❌ **Failed**

### Blockers
- ❌ `vm.readCallers()` returns wrong `CallerMode` inside `vm.startPrank()` — 2 tests actively failing ([local bug report](bugs/edr-vm-readCallers-prank-state.md), not yet filed upstream)
- 🚩 `vm.eip712HashStruct()` / `vm.eip712HashType()` unsupported — 149 test instances (139 functions) commented out; entire EIP-712 signature layer is untested

### Notable gaps (non-blocking)
- 🚩 No equivalent for `forge bind --alloy` (Rust bindings) or `forge build --extra-output-files abi` (ABI export) — `rs:bind`, `rs:abis`, `rs:generate` scripts have no Hardhat counterpart
- 🚩 Gas snapshot tests (`forge snapshot`) not supported
- 🚩 Inline test config (`/// forge-config:`) silently ignored — `isolate` per-profile/per-file and `disable_block_gas_limit` have no equivalent
- 🟡 Etherscan verification: Hardhat uses a single API v2 key vs Foundry's per-chain keys

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

## 2. Feature Parity Table

| Feature | Forge | Hardhat 3 | Parity | Workaround / Notes |
|---|---|---|---|---|
| `vm.readCallers()` + `pausePrank` modifier | Native | Behavioral difference in EDR | ❌ **Bug** | [Local bug report](bugs/edr-vm-readCallers-prank-state.md) (not yet filed upstream) — fix needed in EDR; test code is correct and not modified |
| `vm.eip712HashStruct(string,bytes)` | Native | Unsupported | 🚩 **Gap** | No tracking issue found — consider filing one; workaround: implement EIP-712 hashing in a Solidity helper to remove the cheatcode dependency |
| `vm.eip712HashType(string)` | Native | Unsupported | 🚩 **Gap** | Same as above — no tracking issue found |
| Rust bindings (`forge bind --alloy`) | `rs:bind` script | No equivalent command | 🚩 **Gap** | Run the `alloy` CLI separately against ABI files extracted from Hardhat artifacts |
| Rust ABI export (`forge build --extra-output-files abi`) | `rs:abis` script | No `--extra-output-files` flag | 🚩 **Gap** | ABIs are in `artifacts/**/*.json`; write a custom extraction script to replicate the current `find … cp` pipeline |
| Glob overrides (`tests/**`) | `compilation_restrictions` glob | Not supported | 🚩 **Gap** | [#4686](https://github.com/NomicFoundation/hardhat/issues/4686) — list files individually; no-op here since default compiler settings already match the restriction |
| Fuzz profiles (`[profile.pr.fuzz]`, `[profile.ci.fuzz]`) | `[profile.pr.fuzz]`, `[profile.ci.fuzz]` | No test settings in build profiles | 🚩 **Gap** | Pass `--fuzz-runs N` on the CLI or use an env var per CI job |
| Gas snapshot tests | `forge snapshot` / `[profile.gas]` | Not supported | 🚩 **Gap** | [#7769](https://github.com/NomicFoundation/hardhat/issues/7769) — no workaround currently |
| `isolate` | `[profile.gas]` `isolate = true` / `/// forge-config:` per-test | No per-profile or per-file test settings; global `test.solidity.isolate` works | 🚩 **Gap** | [#7355](https://github.com/NomicFoundation/hardhat/issues/7355) — global setting is a partial workaround but cannot be scoped per profile or per file |
| Inline test config (`/// forge-config:`) | Native | Silently ignored | 🚩 **Gap** | [#7355](https://github.com/NomicFoundation/hardhat/issues/7355) — `allow_internal_expect_revert` set globally as workaround; `isolate` and `disable_block_gas_limit` have no equivalent |
| `dynamic_test_linking` | Native | No equivalent | 🚩 **Gap** | Foundry-only — no observable impact in Hardhat test runs |
| `[bind_json]` | Generates `JsonBindings.sol` | No equivalent | 🚩 **Gap** | Foundry-only — `JsonBindings.sol` is pre-generated and committed; not regeneratable from Hardhat |
| Formatter | `forge fmt` | Not available | 🚩 **Gap** | Already using prettier + prettier-plugin-solidity — no action needed |
| Etherscan verification | `forge verify-contract` (per-chain API keys) | `hardhat-verify` (single API v2 key) | 🟡 **Partial** | Etherscan API v2 accepts one key across all supported chains — consolidate CI secrets to a single `ETHERSCAN_API_KEY` |
| Solidity compilation | `forge build` | `npx hardhat compile` | ✅ **Full** | |
| Unit & integration tests | `forge test` | `npx hardhat test solidity` | ✅ **Full** | Non-EIP-712-sig tests only; sig tests commented out due to `vm.eip712HashStruct` gap |
| Fuzz testing | auto-detects `testFuzz_*` / `function test*` with params | Built-in | ✅ **Full** | |
| `remappings.txt` | Native | Auto-loaded | ✅ **Full** | |
| `src/` / `tests/` absolute imports | Via remappings | Added `src/=./src/` `tests/=./tests/` `lib/=./lib/` | ✅ **Full** | |
| forge-std cheatcodes (`vm.*`) — general | Native | Supported via EDR | ✅ **Full** | |
| `allowInternalExpectRevert` | Per-test via `forge-config:` | Set globally in `test.solidity` | ✅ **Full** | Set globally — affects all tests, no known downside for this project |
| `fsPermissions` | Array format | `fsPermissions` object format | ✅ **Full** | |
| `gasLimit` | `gas_limit = 1099511627776` | `gasLimit: 1099511627776n` | ✅ **Full** | |
| Per-file compiler overrides | `compilation_restrictions` (exact files) | `solidity.overrides` | ✅ **Full** | |
| Build profiles | `[profile.coverage]` | `solidity.profiles.coverage` | ✅ **Full** | |

**Features not used by this project** (no parity assessment needed):
- Deployment scripts (`forge script` / `.s.sol`) — project has no `script/` directory

---

## 3. Workarounds Applied

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

## 3b. Functions Commented Out (UnsupportedCheatcode / Behavioral Differences)

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

### `vm.prank` behavioral difference — 2 test instances failing (NOT commented out)

The `pausePrank` modifier in `tests/Base.t.sol` calls `vm.readCallers()` and conditionally calls `vm.stopPrank()`. In Hardhat 3 EDR, `vm.readCallers()` does not reliably return `CallerMode.RecurrentPrank` during an active `vm.startPrank`, so `vm.stopPrank()` is never called, leaving the prank active when `vm.prank(SPOKE_ADMIN)` runs inside `_updateLiquidationFee`.

This is a confirmed EDR bug — `vm.readCallers()` returns `(CallerMode.None, address(0), address(0))` inside an active `vm.startPrank()` instead of `(CallerMode.RecurrentPrank, sender, txOrigin)`. A structured bug report has been filed for the Hardhat/NomicFoundation team: **[`.claude/bugs/edr-vm-readCallers-prank-state.md`](bugs/edr-vm-readCallers-prank-state.md)**.

These tests are **not** commented out — they are actively failing and represent a blocker.

| File | Function | Error |
|---|---|---|
| `tests/gas/Spoke.Operations.gas.t.sol` | `SpokeOperations_Gas_Tests::test_updateUserDynamicConfig` | `vm.prank: cannot override an ongoing prank` |
| `tests/gas/Spoke.Operations.gas.t.sol` | `SpokeOperations_ZeroRiskPremium_Gas_Tests::test_updateUserDynamicConfig` (inherited) | same |

---

## 4. Missing Features / Gaps

Features the project **actually uses** that have no Hardhat 3 equivalent:

| Feature | Impact | Tracking |
|---|---|---|
| `vm.eip712HashStruct(string,bytes)` | **High** — 131 test instances disabled. All EIP-712 signature tests for SignatureGateway, TakerPositionManager, TokenizationSpoke WithSig flows are skipped. | [NomicFoundation/hardhat](https://github.com/NomicFoundation/hardhat/issues) |
| `vm.eip712HashType(string)` | **High** — 18 test instances disabled (type hash constant tests). | Same issue |
| `vm.readCallers()` — `pausePrank` modifier | **Medium** — affects tests that call config helpers inside `vm.startPrank` contexts. | **Bug** — [bug report filed](bugs/edr-vm-readCallers-prank-state.md) |
| Gas snapshot tests (`forge snapshot` / `[profile.gas]`) | **Medium** — `tests/gas/` tests run (no errors from this), but gas snapshots can't be generated or checked. | [#7769](https://github.com/NomicFoundation/hardhat/issues/7769) |
| `isolate` per-test-file | **Low** — gas tests have `/// forge-config: default.isolate = true` which is silently ignored. Tests still run. | [#7355](https://github.com/NomicFoundation/hardhat/issues/7355) |
| Inline `forge-config:` test settings | **Low** — 10 files use `/// forge-config:` (isolate, allow_internal_expect_revert, disable_block_gas_limit). The `allow_internal_expect_revert` was set globally as a workaround. `isolate` has no per-file equivalent. `disable_block_gas_limit` has no known equivalent. | [#7355](https://github.com/NomicFoundation/hardhat/issues/7355) |
| `compilation_restrictions` glob (`tests/**`) | **Low** — default compiler settings already match the restriction, so this is a no-op in practice. | [#4686](https://github.com/NomicFoundation/hardhat/issues/4686) |
| `dynamic_test_linking` | **Unknown** — Foundry-only. May affect test isolation in Forge; no observable impact in Hardhat. | Foundry-only |
| `[bind_json]` | **Low** — `tests/mocks/JsonBindings.sol` is pre-generated. Not regeneratable from Hardhat. | Foundry-only |
| Per-profile fuzz runs (`[profile.pr]`, `[profile.ci]`) | **Low** — `runs=1000` (default profile) is used. Higher run counts in pr/ci profiles require env var or CLI workarounds. | No equivalent |

---

## 5. Verdict

**Failed** — 2 tests actively fail due to a `vm.readCallers()` behavioral difference in Hardhat 3 EDR. Additionally, **149 test instances (139 unique functions, signature + body fully commented out)** were disabled due to unsupported cheatcodes. The commented-out tests cover all EIP-712 signature-related functionality (SignatureGateway, TakerPositionManager permits, TokenizationSpoke WithSig operations, Spoke EIP-712 hash verification). This represents a significant coverage gap for the EIP-712/signature subsystem.

**Hardhat version:** `^3.1.10`

### What works
- Full compilation (all 291 contracts + test files)
- All non-signature tests: Hub logic, Spoke operations, HubConfigurator, SpokeConfigurator, access control, oracle, math libraries, position managers (non-sig), tokenization spoke (non-sig), gas tests (excluding sig operations)
- Fuzz testing (1000 runs per fuzz function)
- Per-file compiler overrides (`Hub.sol` viaIR, `SpokeInstance.sol` viaIR)

### What doesn't work
- Any test using `vm.eip712HashStruct()` or `vm.eip712HashType()` — the entire EIP-712 signature testing layer is blocked by this single missing cheatcode pair
- `pausePrank` modifier in tests calling config helpers inside active pranks

### Recommended next steps
1. Track `vm.eip712HashStruct`/`vm.eip712HashType` support in Hardhat — this is the single most impactful blocker
2. Consider implementing EIP-712 hashing in a Solidity helper contract as a workaround (avoids the cheatcode dependency)
3. For `pausePrank` behavioral difference — EDR bug documented in [`.claude/bugs/edr-vm-readCallers-prank-state.md`](bugs/edr-vm-readCallers-prank-state.md); file upstream at <https://github.com/NomicFoundation/hardhat/issues>
