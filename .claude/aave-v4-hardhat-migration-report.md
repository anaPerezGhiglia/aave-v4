# Aave V4 — Hardhat 3 Migration Report

**Hardhat version installed:** `^3.4.4`
**Migration date:** 2026-05-04
**Foundry analysis:** [Foundry analysis](aave-v4-foundry-migration-analysis.md)

---

**Verdict:** ❌ **Failed**

### Blockers

- ❌ `vm.snapshotGasLastCall` strict name validation — 38 gas tests failing ([local bug report](bugs/vm-snapshotGasLastCall-name-validation.md), not yet filed upstream). EDR rejects snapshot names containing colons / parentheses; Foundry imposes no such restriction. Regression vs Hardhat 3.1.12 where these tests passed.
- 🚩 `vm.eip712HashStruct(string,bytes)` unsupported — 131 test instances commented out (across 22 files)
- 🚩 `vm.eip712HashType(string)` unsupported — 18 test instances commented out (across 9 files)

### Notable gaps (non-blocking, medium+ impact)

- 🟡 Inline `forge-config:` per-test overrides — function-level support landed in Hardhat 3.3.0 (#7355 closed), but every directive in this project is at **contract level**, which is still silently ignored. `isolate` / `evm_version` are not yet supported inline even at function level.
- 🟡 Glob patterns in compilation overrides not supported (#4686 still open) — `tests/**` restriction cannot be expressed.

---

## 1. Test Count Comparison

| Metric | Count |
|---|---|
| Total `function test*` declarations in `.t.sol` files | 1451 |
| Commented out (HARDHAT-SKIP) function definitions | 140 |
| Active test function definitions | 1311 |
| Hardhat tests run | 1384 passing + 38 failing + 1 skipped = 1423 |

**Note:** The difference between 1311 active definitions and 1423 running tests is expected — some test contracts inherit test functions from base contracts, so a single function definition runs multiple times across different contract contexts.

The 140 commented-out definitions account for 149 test instances. The 38 newly-failing tests are all in `tests/gas/*.t.sol` and share a single root cause (see Section 3).

## 2. Feature Parity

### Gaps, bugs & partial support

| Feature | Parity | Impact | Workaround / Notes |
|---|---|---|---|
| `vm.snapshotGasLastCall` name validation | ❌ **Bug** | **High** — 38 gas tests failing; full gas-test suite blocked | [Local bug report](bugs/vm-snapshotGasLastCall-name-validation.md) (not yet filed upstream) — EDR `0.12.0-next.31` enforces a strict character allowlist that Foundry does not. Tests are not modified — fix needed in EDR. |
| `vm.eip712HashStruct(string,bytes)` | 🚩 **Gap** | **High** — 131 test instances disabled; EIP-712 signature testing untested | Implemented in EDR `0.12.0-next.32` but Hardhat 3.4.4 still pins EDR `next.31`. Will be picked up automatically once Hardhat bumps EDR. |
| `vm.eip712HashType(string)` | 🚩 **Gap** | **High** — 18 test instances disabled; EIP-712 type hash testing untested | Same as above — implemented in EDR `next.32`, awaiting a Hardhat release that bumps EDR. |
| Inline test config | 🟡 **Partial** | **Medium** — 10 files use contract-level `forge-config:` (`isolate`, `allow_internal_expect_revert`, `disable_block_gas_limit`); silently ignored. Global `allowInternalExpectRevert: true` set as workaround; `isolate` cannot be enabled globally without massive perf hit | [#7355](https://github.com/NomicFoundation/hardhat/issues/7355) closed (function-level only); contract-level scope and `isolate`/`evm_version` inline tracked at [edr#1349](https://github.com/NomicFoundation/edr/issues/1349) |
| Glob overrides | 🟡 **Partial** | **Medium** — `tests/**` compilation restriction cannot be expressed; each file would need individual listing | [#4686](https://github.com/NomicFoundation/hardhat/issues/4686) — omitted since default compiler settings match the tests restriction |
| ABI binding generation | 🚩 **Gap** | **Low** — `forge bind --alloy` (used by `rs:bind` script) has no Hardhat equivalent | No tracking issue found — consider filing one |
| `forge build --extra-output-files abi` | 🟡 **Partial** | **Low** — `rs:abis` script extracts ABIs to a flat dir; Hardhat produces ABIs in `artifacts/<Contract>.sol/<Contract>.json` with a different structure | Workaround: extract ABIs from Hardhat artifacts with a shell script |
| Dynamic test linking | 🚩 **Gap** | **Low** — Foundry-only optimization; tests still work without it | No tracking issue found |
| `[bind_json]` config | 🚩 **Gap** | **Low** — Foundry-only JSON type binding generation for Solidity | No tracking issue found |
| Fuzz/invariant profile overrides | 🟡 **Partial** | **Low** — `[profile.pr.fuzz]` / `[profile.ci.fuzz]` test-only profile settings; can use env vars or CLI args instead | Hardhat build profiles only cover compiler settings, not test settings |
| Etherscan verification | 🟡 **Partial** | **Low** — Hardhat 3 uses Etherscan API v2 with a single key; Foundry has per-chain keys | Consolidate to a single `ETHERSCAN_API_KEY` — Etherscan API v2 accepts one key across all supported chains |

### Full parity

These features work equivalently in Hardhat 3:

- Solidity compilation (`forge build` → `npx hardhat compile`)
- Solidity compiler settings (optimizer, optimizer_runs, evmVersion, bytecodeHash)
- Build profiles with per-file overrides (`additional_compiler_profiles` + `compilation_restrictions` → `solidity.profiles.default.overrides`)
- Coverage build profile (`[profile.coverage]` → `solidity.profiles.coverage`)
- forge-std cheatcodes (`vm.*`) — general (excluding `eip712HashStruct`, `eip712HashType`, and the snapshot-name bug)
- Fuzz testing (`fuzz.runs`, `fuzz.seed`)
- `fs_permissions` → `fsPermissions`
- `gas_limit` → `gasLimit`
- `allow_internal_expect_revert` → `allowInternalExpectRevert` (global)
- Gas snapshots (`forge snapshot` → `npx hardhat test solidity --snapshot` / `--snapshot-check`) — the CLI flags work; this project's gas-test names trigger an unrelated EDR validation bug (see ❌ row above)
- Network RPC endpoints (`[rpc_endpoints]` → `networks`)
- Remappings (`remappings.txt` — natively supported)
- Git submodule dependencies (`lib/forge-std`, `lib/erc4626-tests` — resolved via remappings)

**Features not used by this project:**

- Deployment scripting (`forge script` / `.s.sol`) — project has a `script/` directory but no deploy scripts in `package.json`
- Invariant testing — no invariant tests found
- FFI — not enabled

**Foundry-only features with existing alternatives:**

- Built-in formatter / `[lint]` — Forge's built-in linter is configured in `foundry.toml` but the project uses `prettier` + `prettier-plugin-solidity` for linting (`lint`/`lint:fix` scripts); no Hardhat equivalent needed

## 3. Hardhat / EDR Bug Reports

### `vm.snapshotGasLastCall` name validation diverges from Foundry

**Root cause (one sentence):** EDR `0.12.0-next.31` enforces a strict character allowlist on gas snapshot names (`[a-zA-Z0-9_\- ,]` plus non-consecutive dots) that Foundry does not, causing valid Foundry-idiomatic test code containing colons or parentheses in snapshot names to fail.

**Local bug report:** [bugs/vm-snapshotGasLastCall-name-validation.md](bugs/vm-snapshotGasLastCall-name-validation.md) — **not yet filed upstream**.

**Failing tests (38 total, all in `tests/gas/`):**

| File | Contract(s) | Failing functions |
|---|---|---|
| `tests/gas/Spoke.Operations.gas.t.sol` | `SpokeOperations_Gas_Tests`, `SpokeOperations_ZeroRiskPremium_Gas_Tests` | `test_borrow`, `test_liquidation_full`, `test_liquidation_partial`, `test_liquidation_receiveShares_full`, `test_liquidation_receiveShares_partial`, `test_liquidation_reportDeficit_full`, `test_repay`, `test_supply`, `test_updateRiskPremium`, `test_updateUserDynamicConfig`, `test_usingAsCollateral`, `test_withdraw` (×2 contracts via inheritance, 20 instances) |
| `tests/gas/Spoke.Getters.gas.t.sol` | `SpokeGetters_Gas_Tests` | `test_getUserAccountData`, `test_getUserAccountData_oneSupplies`, `test_getUserAccountData_twoSupplies`, `test_getUserAccountData_twoSupplies_oneBorrows`, `test_getUserAccountData_twoSupplies_twoBorrows` |
| `tests/gas/Hub.Operations.gas.t.sol` | `HubOperations_Gas_Tests` | `test_add`, `test_deficit`, `test_remove`, `test_restore`, `test_restore_with_transfer` |
| `tests/gas/Gateways.Operations.gas.t.sol` | `NativeTokenGateway_Gas_Tests` | `test_withdrawNative` |
| `tests/gas/PositionManagers.Operations.gas.t.sol` | `TakerPositionManager_Gas_Tests` | `test_withdrawOnBehalfOf` |
| `tests/gas/TokenizationSpoke.Operations.gas.t.sol` | `TokenizationSpokeOperations_Gas_Tests` | `test_redeem`, `test_withdraw` |

**These tests are not commented out** — they are active blockers. The test code is correct Foundry-idiomatic Solidity (Foundry imposes no validation on snapshot names — see [`inner_last_gas_snapshot`](https://github.com/foundry-rs/foundry/blob/master/crates/cheatcodes/src/evm.rs)), and the fix belongs in EDR.

## 4. Workarounds Applied

### Remappings for absolute imports

**What:** `src/=./src/`, `tests/=./tests/`, `lib/=./lib/` added to `remappings.txt`.

**Why:** The project uses 220+ absolute imports with `src/` and `tests/` prefixes (e.g., `import 'src/dependencies/openzeppelin/SafeERC20.sol'`). Hardhat 3 does not support absolute imports — all local imports must be relative or go through remappings. One file also imports `lib/erc4626-tests/ERC4626.test.sol` directly. In Forge, `src = "src"` in `foundry.toml` implicitly makes `src/` a valid import prefix; Hardhat requires explicit remappings.

### Global `allowInternalExpectRevert: true`

**What:** Set `test.solidity.allowInternalExpectRevert: true` globally in `hardhat.config.ts`.

**Why:** 3 test files use `/// forge-config: default.allow_internal_expect_revert = true` at the **contract level** (placed on the contract definition, not on individual test functions). Hardhat 3.3.0+ supports inline `forge-config:` at the function level only — contract-level directives are silently ignored ([#7355](https://github.com/NomicFoundation/hardhat/issues/7355) closed for function-level scope; contract-level scope is unresolved). Setting it globally is the only available workaround. Safe — only affects `vm.expectRevert` behavior on internal/library calls.

### ESM module type

**What:** `"type": "module"` in `package.json`.

**Why:** Required by Hardhat 3. The project had no existing `.js` files with `require()`, so no breakage.

### 4b. UnsupportedCheatcode errors

149 test instances (140 function definitions) are commented out due to two unsupported cheatcodes. Each function has a `// HARDHAT-SKIP` header preserving the original code. **Both cheatcodes were implemented in EDR `0.12.0-next.32` (released April 24)** but Hardhat 3.4.4 still pins EDR `0.12.0-next.31` — the next Hardhat release that bumps EDR will unblock them.

#### `vm.eip712HashStruct(string,bytes)` — 131 test instances

| File | Functions |
|---|---|
| `tests/gas/Gateways.Operations.gas.t.sol` | 8 functions |
| `tests/gas/PositionManagers.Operations.gas.t.sol` | 3 functions |
| `tests/gas/Spoke.Operations.gas.t.sol` | 2 functions (4 instances via inheritance) |
| `tests/gas/TokenizationSpoke.Operations.gas.t.sol` | 5 functions |
| `tests/unit/Spoke/Spoke.PermitReserve.t.sol` | 1 function |
| `tests/unit/Spoke/Spoke.SetUserPositionManagerWithSig.t.sol` | 10 functions |
| `tests/unit/libraries/SpokeEIP712Hash.t.sol` | 6 functions |
| `tests/unit/TokenizationSpoke/TokenizationSpoke.DepositWithPermit.t.sol` | 1 function |
| `tests/unit/TokenizationSpoke/TokenizationSpoke.Permit.t.sol` | 6 functions |
| `tests/unit/TokenizationSpoke/TokenizationSpoke.Reverts.InsufficientAllowance.t.sol` | 2 functions |
| `tests/unit/TokenizationSpoke/TokenizationSpoke.WithSig.Reverts.InvalidSignature.t.sol` | 12 functions |
| `tests/unit/TokenizationSpoke/TokenizationSpoke.WithSig.t.sol` | 4 functions |
| `tests/unit/position-manager/PositionManagerBase.t.sol` | 2 functions |
| `tests/unit/position-manager/libraries/PositionManagerEIP712Hash.t.sol` | 7 functions |
| `tests/unit/position-manager/SignatureGateway/SignatureGateway.PermitReserve.t.sol` | 1 function |
| `tests/unit/position-manager/SignatureGateway/SignatureGateway.Reverts.InsufficientAllowance.t.sol` | 2 functions |
| `tests/unit/position-manager/SignatureGateway/SignatureGateway.Reverts.InvalidSignature.t.sol` | 21 functions |
| `tests/unit/position-manager/SignatureGateway/SignatureGateway.Reverts.Unauthorized.t.sol` | 7 functions (14 instances via inheritance) |
| `tests/unit/position-manager/SignatureGateway/SignatureGateway.SetSelfAsUserPositionManagerWithSig.t.sol` | 1 function |
| `tests/unit/position-manager/SignatureGateway/SignatureGateway.t.sol` | 11 functions |
| `tests/unit/position-manager/TakerPositionManager/TakerPositionManager.Permit.t.sol` | 12 functions |

#### `vm.eip712HashType(string)` — 18 test instances

| File | Functions |
|---|---|
| `tests/unit/Spoke/Spoke.SetUserPositionManagerWithSig.t.sol` | 2 functions |
| `tests/unit/libraries/SpokeEIP712Hash.t.sol` | 1 function |
| `tests/unit/TokenizationSpoke/TokenizationSpoke.Constants.t.sol` | 5 functions |
| `tests/unit/position-manager/libraries/PositionManagerEIP712Hash.t.sol` | 1 function |
| `tests/unit/position-manager/SignatureGateway/SignatureGateway.Constants.t.sol` | 7 functions |
| `tests/unit/position-manager/PositionManagerBase.t.sol` | (included above) |

## 5. Next Steps

1. **File the EDR bug report upstream** — open an issue at [NomicFoundation/edr](https://github.com/NomicFoundation/edr/issues) referencing [`bugs/vm-snapshotGasLastCall-name-validation.md`](bugs/vm-snapshotGasLastCall-name-validation.md). This blocks 38 gas tests (the entire gas-test suite) and is a regression versus Hardhat 3.1.12. Highest priority — without a fix, gas snapshot generation cannot be exercised against the project as written.
2. **Wait for the next Hardhat release that bumps EDR to `0.12.0-next.32`** (or open the bump request) — that release will pick up `vm.eip712HashStruct` and `vm.eip712HashType`, unblocking 149 test instances (10.3% of the suite) covering EIP-712 signature flows. After bumping, uncomment the `// HARDHAT-SKIP` blocks and re-run the migration update.
3. **Track [edr#1349](https://github.com/NomicFoundation/edr/issues/1349)** for inline `isolate` / `evm_version` support and contract-level `forge-config:` parity. Until then, the global `allowInternalExpectRevert` workaround is the right call; do not promote `isolate` to global (it would impose a major performance penalty on the entire suite).
4. **Enumerate test files for glob override** — list individual test files in `solidity.profiles.default.overrides` to replace `tests/**`, or wait for [#4686](https://github.com/NomicFoundation/hardhat/issues/4686) to add glob support. Low priority: the default compiler settings already match the `tests/**` restriction in this project.
