# Aave V4 — Hardhat 3 Migration Report

**Hardhat version installed:** `^3.1.12`
**Migration date:** 2026-03-16
**Foundry analysis:** [Foundry analysis](aave-v4-foundry-migration-analysis.md)

---

**Verdict:** 🟡 **Partial**

### Blockers

- 🚩 `vm.eip712HashStruct(string,bytes)` unsupported — 131 test instances commented out (across 22 files)
- 🚩 `vm.eip712HashType(string)` unsupported — 18 test instances commented out (across 9 files)

### Notable gaps (non-blocking, medium+ impact)

- 🚩 No equivalent for `forge snapshot` / gas snapshot checks — gas snapshot workflow unavailable
- 🟡 Inline `forge-config:` per-test overrides silently ignored — 10 test files affected (isolate, allow_internal_expect_revert, disable_block_gas_limit)
- 🟡 Glob patterns in compilation overrides not supported — `tests/**` restriction cannot be expressed

---

## 1. Test Count Comparison

| Metric | Count |
|---|---|
| Total `function test*` declarations in `.t.sol` files | 1451 |
| Commented out (HARDHAT-SKIP) function definitions | 140 |
| Active test function definitions | 1311 |
| Hardhat tests run | 1422 (passing) + 1 (skipped) |

**Note:** The difference between 1311 active definitions and 1422 running tests is expected — some test contracts inherit test functions from base contracts, so a single function definition runs multiple times across different contract contexts.

The 140 commented-out definitions account for 149 test instances (some functions are defined in base contracts inherited by multiple test contracts).

## 2. Feature Parity

### Gaps, bugs & partial support

| Feature | Parity | Impact | Workaround / Notes |
|---|---|---|---|
| `vm.eip712HashStruct(string,bytes)` | 🚩 **Gap** | **High** — 131 test instances disabled; EIP-712 signature testing untested | No tracking issue found — consider filing one; workaround: implement equivalent EIP-712 hashing in a Solidity helper |
| `vm.eip712HashType(string)` | 🚩 **Gap** | **High** — 18 test instances disabled; EIP-712 type hash testing untested | No tracking issue found — consider filing one; workaround: hardcode expected type hashes or compute in Solidity |
| Gas snapshots (`forge snapshot`, `gas_snapshot_check`) | 🚩 **Gap** | **Medium** — `[profile.gas]` workflow unavailable; tests still run but snapshots can't be generated | [#7769](https://github.com/NomicFoundation/hardhat/issues/7769) — no workaround currently |
| `dynamic_test_linking` | 🚩 **Gap** | **Low** — Foundry-only optimization; tests still work without it | No tracking issue found |
| `[bind_json]` config | 🚩 **Gap** | **Low** — Foundry-only JSON type binding generation for Solidity | No tracking issue found |
| `forge bind --alloy` (`rs:bind` script) | 🚩 **Gap** | **Low** — Rust/Alloy binding generation is Foundry-specific; no Hardhat equivalent | No tracking issue found |
| Inline test config (`forge-config:`) | 🟡 **Partial** | **Medium** — 10 files use per-test `isolate`, `allow_internal_expect_revert`, `disable_block_gas_limit`; silently ignored in Hardhat 3. Global `allowInternalExpectRevert: true` set as workaround; `isolate` and `disable_block_gas_limit` can only be set globally | [#7355](https://github.com/NomicFoundation/hardhat/issues/7355) — set affected settings globally in config as fallback |
| Glob patterns in `overrides` | 🟡 **Partial** | **Medium** — `tests/**` compilation restriction cannot be expressed; each file would need individual listing | [#4686](https://github.com/NomicFoundation/hardhat/issues/4686) — omitted since default compiler settings match the tests restriction |
| ABI extraction (`rs:abis` script) | 🟡 **Partial** | **Low** — `forge build --extra-output-files abi` extracts ABIs to flat dir; Hardhat produces ABIs in `artifacts/<Contract>.sol/<Contract>.json` but with a different structure | Workaround: extract ABIs from Hardhat artifacts with a shell script |
| Etherscan verification (per-chain keys) | 🟡 **Partial** | **Low** — Hardhat 3 uses Etherscan API v2 with a single key; Foundry has per-chain keys | Consolidate to a single `ETHERSCAN_API_KEY` — Etherscan API v2 accepts one key across all supported chains |
| PR/CI fuzz run profiles (`[profile.pr.fuzz]`, `[profile.ci.fuzz]`) | 🟡 **Partial** | **Low** — test-only profile settings; can use env vars or CLI args instead | Hardhat build profiles only cover compiler settings, not test settings |

### Full parity

These features work equivalently in Hardhat 3:

- Solidity compilation (`forge build` → `npx hardhat compile`)
- Solidity compiler settings (optimizer, optimizer_runs, evmVersion, bytecodeHash)
- Build profiles with per-file overrides (`additional_compiler_profiles` + `compilation_restrictions` → `solidity.profiles.default.overrides`)
- Coverage build profile (`[profile.coverage]` → `solidity.profiles.coverage`)
- forge-std cheatcodes (`vm.*`) — general (excluding `eip712HashStruct`, `eip712HashType`)
- Fuzz testing (`fuzz.runs`, `fuzz.seed`)
- `fs_permissions` → `fsPermissions`
- `gas_limit` → `gasLimit`
- `allow_internal_expect_revert` → `allowInternalExpectRevert` (global)
- Network RPC endpoints (`[rpc_endpoints]` → `networks`)
- Remappings (`remappings.txt` — natively supported)
- Git submodule dependencies (`lib/forge-std`, `lib/erc4626-tests` — resolved via remappings)

**Features not used by this project:**
- Deployment scripts (`forge script` / `.s.sol`) — project has a `script/` directory but no deploy scripts in `package.json`
- Invariant testing — no invariant tests found
- FFI — not enabled

**Foundry-only features with existing alternatives:**
- `[lint]` — Forge's built-in linter is configured in `foundry.toml` but the project uses `prettier` + `prettier-plugin-solidity` for linting (`lint`/`lint:fix` scripts); no Hardhat equivalent needed

## 3. Workarounds Applied

### Remappings for absolute imports

**What:** Added `src/=./src/`, `tests/=./tests/`, and `lib/=./lib/` to `remappings.txt`.

**Why:** The project uses 220+ absolute imports with `src/` and `tests/` prefixes (e.g., `import 'src/dependencies/openzeppelin/SafeERC20.sol'`). Hardhat 3 does not support absolute imports — all local imports must be relative or go through remappings. One file also imports `lib/erc4626-tests/ERC4626.test.sol` directly (bypassing the existing `erc4626-tests/` remapping). In Forge, `src = "src"` in `foundry.toml` implicitly makes `src/` a valid import prefix. Hardhat requires explicit remappings for this behavior.

### Global `allowInternalExpectRevert: true`

**What:** Set `test.solidity.allowInternalExpectRevert: true` globally in `hardhat.config.ts`.

**Why:** 3 test files use `/// forge-config: default.allow_internal_expect_revert = true` inline. Hardhat 3 silently ignores inline `forge-config:` directives ([#7355](https://github.com/NomicFoundation/hardhat/issues/7355)). Setting it globally ensures these tests pass. This is safe — the setting only affects `vm.expectRevert` behavior on internal/library calls.

### ESM module type

**What:** Added `"type": "module"` to `package.json`.

**Why:** Required by Hardhat 3. The project had no existing `.js` files with `require()`, so no breakage.

## 3b. UnsupportedCheatcode errors

149 test instances (140 function definitions) were commented out due to two unsupported cheatcodes. Each function has a `// HARDHAT-SKIP` header preserving the original code.

### `vm.eip712HashStruct(string,bytes)` — 131 test instances

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

### `vm.eip712HashType(string)` — 18 test instances

| File | Functions |
|---|---|
| `tests/unit/Spoke/Spoke.SetUserPositionManagerWithSig.t.sol` | 2 functions |
| `tests/unit/libraries/SpokeEIP712Hash.t.sol` | 1 function |
| `tests/unit/TokenizationSpoke/TokenizationSpoke.Constants.t.sol` | 5 functions |
| `tests/unit/position-manager/libraries/PositionManagerEIP712Hash.t.sol` | 1 function |
| `tests/unit/position-manager/SignatureGateway/SignatureGateway.Constants.t.sol` | 7 functions |
| `tests/unit/position-manager/PositionManagerBase.t.sol` | (included above) |

## 4. Next Steps

1. **File upstream issue for `vm.eip712HashStruct` and `vm.eip712HashType` support** — this blocks 149 tests (10.3% of total) covering all EIP-712 signature flows; filing on [NomicFoundation/edr](https://github.com/NomicFoundation/edr/issues) would unblock them once implemented
2. **Explore Solidity helper workaround for EIP-712 hashing** — implement `keccak256(abi.encode(typeHash, ...))` directly in test helpers to replace `vm.eip712HashStruct()` calls; this would restore test coverage without waiting for upstream support
3. **Enumerate test files for glob override** — list individual test files in `solidity.profiles.default.overrides` to replace `tests/**` restriction, or wait for [#4686](https://github.com/NomicFoundation/hardhat/issues/4686) to add glob support
