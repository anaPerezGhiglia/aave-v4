# Foundry Migration Analysis: aave-v4

Generated during dry-run migration to Hardhat 3.

## Package Manager

**Selected: `npm`**

Reason: `package-lock.json` (2382 lines) is significantly larger/more recent than `yarn.lock` (279 lines), indicating npm is the active package manager. All install commands will use `npm`.

---

## `foundry.toml` Settings

### `[profile.default]`

| Setting | Value | Notes |
|---|---|---|
| `src` | `'src'` | Source directory |
| `test` | `'tests'` | Test directory (non-standard — Hardhat default is `./test`) |
| `out` | `'out'` | Build output dir — Foundry-only, Hardhat uses `artifacts/` |
| `libs` | `['lib']` | Dependency resolution via lib/ — Hardhat uses remappings |
| `fs_permissions` | `[{ access = "read", path = "tests/mocks/JsonBindings.sol" }]` | File-read permission for a specific file |
| `solc_version` | `"0.8.28"` | Solidity compiler version |
| `evm_version` | `"cancun"` | EVM version |
| `optimizer` | `true` | Optimizer enabled |
| `optimizer_runs` | `444444444444` | Optimizer runs (very high — prioritizes runtime gas) |
| `bytecode_hash` | `"none"` | Disable IPFS metadata hash |
| `gas_snapshot_check` | `false` | Gas snapshot CI check off — Foundry-only |
| `gas_limit` | `1099511627776` | = 2^40 |
| `dynamic_test_linking` | `true` | Foundry-only feature |

### `additional_compiler_profiles`

| Profile | via_ir | optimizer_runs | optimizer |
|---|---|---|---|
| `hub` | `true` | `22_300` | `true` |
| `spoke` | `true` | `750` | `true` |
| `tests` | `false` | `444444444444` | `true` |

### `compilation_restrictions`

| Path | via_ir | optimizer_runs |
|---|---|---|
| `src/hub/Hub.sol` | `true` | `22_300` |
| `src/spoke/instances/SpokeInstance.sol` | `true` | `750` |
| `tests/**` | `false` | `444444444444` |

Note: `tests/**` uses a glob pattern — Hardhat doesn't support glob overrides yet.
See: https://github.com/NomicFoundation/hardhat/issues/4686

### `[bind_json]`

```toml
out = "tests/mocks/JsonBindings.sol"
include = ["tests/mocks/EIP712Types.sol"]
```

Foundry-only feature — no Hardhat equivalent.

### `[lint]`

```toml
ignore = ["src/dependencies/**/*", "tests/**/*"]
lint_on_build = false
```

Foundry-only — projects typically use prettier/solhint.

### `[profile.default.fuzz]`

| Setting | Value |
|---|---|
| `runs` | `1000` |
| `seed` | `"0x640"` |

### `[profile.pr.fuzz]`

| Setting | Value |
|---|---|
| `runs` | `5000` |

Only changes fuzz runs — no Hardhat build profile equivalent.

### `[profile.ci.fuzz]`

| Setting | Value |
|---|---|
| `runs` | `10000` |

Only changes fuzz runs — no Hardhat build profile equivalent.

### `[profile.gas]`

| Setting | Value | Notes |
|---|---|---|
| `gas_snapshot_check` | `true` | Foundry-only |
| `test` | `'tests/gas'` | Gas test subdirectory |
| `isolate` | `true` | Foundry-only, no Hardhat equivalent |

### `[profile.coverage]`

| Setting | Value |
|---|---|
| `optimizer` | `true` |
| `optimizer_runs` | `444444444444` |
| `via_ir` | `false` |
| `fuzz.runs` | `50` |
| `additional_compiler_profiles` | `[]` (resets to empty) |
| `compilation_restrictions` | `[]` (resets to empty) |

### `[rpc_endpoints]`

13 networks: mainnet, optimism, avalanche, polygon, arbitrum, fantom, harmony, metis, base, zkevm, gnosis, bnb, celo

### `[etherscan]`

12 chains with per-chain API keys. Notable: metis uses a hardcoded key `"any"` with a custom URL.

---

## Remappings (`remappings.txt`)

```
erc4626-tests/=lib/erc4626-tests/
forge-std/=lib/forge-std/src/
```

---

## Git Submodules (`lib/`)

| Name | URL |
|---|---|
| `lib/forge-std` | https://github.com/foundry-rs/forge-std |
| `lib/erc4626-tests` | https://github.com/a16z/erc4626-tests |

Both submodules are initialized (directories have content).

---

## Source/Test/Script Directories

| Directory | Purpose |
|---|---|
| `src/` | Contract sources |
| `tests/` | Tests (non-standard name vs Hardhat default `test/`) |
| `tests/gas/` | Gas snapshot tests (profile-gated) |
| `tests/unit/` | Unit tests |
| `tests/misc/` | Misc tests |
| `tests/mocks/` | Mock contracts |
| No `script/` directory | No Forge deployment scripts |

---

## Inline Test Config (`forge-config:` comments)

Affected files (all use `/// forge-config:` single-line comments):

| File | Config |
|---|---|
| `tests/gas/Spoke.Operations.gas.t.sol` | `default.isolate = true` (x2) |
| `tests/gas/TokenizationSpoke.Operations.gas.t.sol` | `default.isolate = true` |
| `tests/gas/PositionManagers.Operations.gas.t.sol` | `default.isolate = true` (x4) |
| `tests/gas/Hub.Operations.gas.t.sol` | `default.isolate = true` |
| `tests/gas/Spoke.Getters.gas.t.sol` | `default.isolate = true` |
| `tests/gas/Gateways.Operations.gas.t.sol` | `default.isolate = true` (x2) |
| `tests/unit/Hub/Hub.Rounding.t.sol` | `default.disable_block_gas_limit = true` |
| `tests/unit/AaveOracle.t.sol` | `default.allow_internal_expect_revert = true` |
| `tests/unit/libraries/KeyValueList.t.sol` | `default.allow_internal_expect_revert = true` |
| `tests/unit/MathUtils.t.sol` | `default.allow_internal_expect_revert = true` |

All inline test config is silently ignored by Hardhat 3.
See: https://github.com/NomicFoundation/hardhat/issues/7355

The `allow_internal_expect_revert = true` configs need to be set globally in `hardhat.config.ts` as `test.solidity.allowInternalExpectRevert: true`.

The gas tests (`tests/gas/`) use `isolate = true` which has no Hardhat equivalent.

---

## Absolute Imports

The project uses **absolute imports** extensively with single-quoted paths:
- **55 files** in `src/` import from `'src/...'`
- **34 files** in `tests/` import from `'src/...'`
- **136 files** in `tests/` import from `'tests/...'`

Total: ~225+ files — far exceeds the 10-file threshold. **Solution: add remappings** to `remappings.txt`:
- `src/=./src/`
- `tests/=./tests/`

---

## Notable Patterns

1. **Very high optimizer runs** (444444444444) — unusual, optimizes for runtime gas at the cost of deploy gas
2. **Two contracts use viaIR** (`Hub.sol` and `SpokeInstance.sol`) via `compilation_restrictions`
3. **`tests/**` glob in `compilation_restrictions`** — cannot be expressed in Hardhat's `overrides` (glob not supported)
4. **`dynamic_test_linking`** — Foundry-only, no Hardhat equivalent
5. **`[bind_json]`** — Foundry-only, generates Solidity JSON bindings
6. **`allow_internal_expect_revert`** — Used in 3 test files via inline config — needs to be set globally in Hardhat
7. **`disable_block_gas_limit`** — Used in 1 test file (Hub.Rounding.t.sol) — no known Hardhat equivalent
8. **Gas tests** use `isolate = true` — gas tests under `tests/gas/` run under `[profile.gas]` in Forge; no equivalent in Hardhat
9. **137 total `.t.sol` files**, ~1379 test functions (excluding gas tests)

---

## Summary of Hardhat-Incompatible Features

| Feature | Used? |
|---|---|
| `dynamic_test_linking` | Yes |
| `gas_snapshot_check` / `[profile.gas]` | Yes |
| `isolate` | Yes (gas tests + inline config) |
| `[bind_json]` | Yes |
| `[lint]` | Yes |
| `/// forge-config:` inline test config | Yes (10 files) |
| Glob patterns in `compilation_restrictions` | Yes (`tests/**`) |
| Per-profile fuzz runs (pr, ci, coverage) | Yes |
| `disable_block_gas_limit` inline | Yes (Hub.Rounding.t.sol) |
