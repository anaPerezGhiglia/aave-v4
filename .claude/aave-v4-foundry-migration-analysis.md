# Aave V4 — Foundry Migration Analysis

> Re-verified 2026-05-26 against the just-released Hardhat `3.6.0`. Project structure unchanged since the upstream-merge update earlier on the same day. Notable upstream-merge changes (still current): optimizer runs reduced (`44_444_444`), test directory restructured (`tests/contracts/...`, `tests/helpers/mocks/...`, `tests/deployments/...`), new `scripts/` directory with deployment engine, additional `fs_permissions` entries. Migration outcome under `3.6.0` is unchanged vs `3.5.1` — see [migration report](aave-v4-hardhat-migration-report.md) for details.

## Project Structure

- **Source directory:** `src/` (subdirs: access, dependencies, hub, interfaces, libraries, misc, position-manager, spoke, utils)
- **Test directory:** `tests/` (subdirs: contracts, deployments, gas, helpers, integrations, misc, setup, utils, scripts)
- **Scripts directory:** `scripts/` (new, post-merge) — deployment engine plus `utils/`
- **Total .sol files (src + tests + scripts):** ~290+ (455 compiled, including dependencies)
- **Submodules (`lib/`):**
  - `forge-std` → https://github.com/foundry-rs/forge-std
  - `erc4626-tests` → https://github.com/a16z/erc4626-tests
- **Remappings (`remappings.txt`):**
  - `erc4626-tests/=lib/erc4626-tests/`
  - `forge-std/=lib/forge-std/src/`
  - `lib/=./lib/`
  - `scripts/=./scripts/` (added 2026-05-26)
  - `src/=./src/`
  - `tests/=./tests/`

## Package Manager

**Selected:** `yarn` (classic v1.22.22)
**Reason:** `yarn.lock` is the active lockfile; `package-lock.json` is older. Will not introduce a second lockfile.

## foundry.toml — All Sections and Settings

### `[profile.default]`

| Setting                | Value                                                                                                                                                                                                |
| ---------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `src`                  | `src`                                                                                                                                                                                                |
| `test`                 | `tests`                                                                                                                                                                                              |
| `out`                  | `out`                                                                                                                                                                                                |
| `libs`                 | `["lib"]`                                                                                                                                                                                            |
| `fs_permissions`       | `[{read tests/helpers/mocks/JsonBindings.sol}, {read ./config}, {read ./out}, {read-write ./output}]`                                                                                                |
| `skip`                 | `["tests/helpers/mocks/JsonBindings.sol"]`                                                                                                                                                           |
| `solc_version`         | `0.8.28`                                                                                                                                                                                             |
| `evm_version`          | `cancun`                                                                                                                                                                                             |
| `optimizer`            | `true`                                                                                                                                                                                               |
| `optimizer_runs`       | `44444444` (reduced from `444_444_444_444` in upstream commit `dd26d09`)                                                                                                                             |
| `bytecode_hash`        | `none`                                                                                                                                                                                               |
| `gas_snapshot_check`   | `false`                                                                                                                                                                                              |
| `gas_limit`            | `1099511627776`                                                                                                                                                                                      |
| `dynamic_test_linking` | `true`                                                                                                                                                                                               |

### `additional_compiler_profiles`

| Profile | optimizer | via_ir | optimizer_runs |
| ------- | --------- | ------ | -------------- |
| `hub`   | true      | true   | 22,300         |
| `spoke` | true      | true   | 750            |
| `tests` | true      | false  | 44,444,444     |

### `compilation_restrictions`

| Path pattern                            | optimizer | via_ir | optimizer_runs |
| --------------------------------------- | --------- | ------ | -------------- |
| `src/hub/instances/HubInstance.sol`     | true      | true   | 22,300         |
| `src/spoke/instances/SpokeInstance.sol` | true      | true   | 750            |
| `tests/**`                              | true      | false  | 44,444,444     |

### `[bind_json]`

- `out = "tests/helpers/mocks/JsonBindings.sol"`
- `include = ["tests/helpers/mocks/EIP712Types.sol"]`

### `[lint]`

- `ignore = ["src/dependencies/**/*", "tests/**/*"]`
- `lint_on_build = false`

### `[profile.default.fuzz]`

- `runs = 1000`
- `seed = "0x640"`

### `[profile.pr.fuzz]`

- `runs = 5000`

### `[profile.ci.fuzz]`

- `runs = 10000`

### `[profile.gas]`

- `gas_snapshot_check = true`
- `test = "tests/gas"`
- `isolate = true`

### `[profile.coverage]`

- `optimizer = true`
- `optimizer_runs = 44444444`
- `via_ir = false`
- `fuzz.runs = 50`
- `additional_compiler_profiles = []`
- `compilation_restrictions = []`

### `[rpc_endpoints]`

mainnet, optimism, avalanche, polygon, arbitrum, fantom, harmony, metis, base, zkevm, gnosis, bnb, celo — all using `${RPC_*}` env vars. Plus `anvil = "http://127.0.0.1:8545"` (added in merge).

### `[etherscan]`

Per-chain API keys for: mainnet (1), optimism (10), avalanche (43114), polygon (137), arbitrum (42161), fantom (250), metis (1088, custom URL), base (8453), zkevm (1101), gnosis (100), bnb (56), celo (42220).

## Inline Test Config (`forge-config:` comments)

Found in 10 files (one more than the previous analysis: `Hub.Rounding.t.sol` was removed; `PostDeploymentVerificationTest.t.sol` was added with a function-level directive):

**Contract-level directives (9 files — silently ignored by Hardhat):**

- `tests/gas/Gateways.Operations.gas.t.sol` — `default.isolate = true`
- `tests/gas/Hub.Operations.gas.t.sol` — `default.isolate = true`
- `tests/gas/PositionManagers.Operations.gas.t.sol` — `default.isolate = true`
- `tests/gas/Spoke.Getters.gas.t.sol` — `default.isolate = true`
- `tests/gas/Spoke.Operations.gas.t.sol` — `default.isolate = true`
- `tests/gas/TokenizationSpoke.Operations.gas.t.sol` — `default.isolate = true`
- `tests/contracts/spoke/AaveOracle.t.sol` — `default.allow_internal_expect_revert = true`
- `tests/contracts/libraries/math/MathUtils.t.sol` — `default.allow_internal_expect_revert = true`
- `tests/contracts/spoke/libraries/KeyValueList.t.sol` — `default.allow_internal_expect_revert = true`

**Function-level directives (1 file — supported by Hardhat 3.3.0+ in principle):**

- `tests/deployments/fork/PostDeploymentVerificationTest.t.sol` — `default.fuzz.runs = 1000` on `testFuzz_postDeploymentCheck`

**Note:** Hardhat 3.3.0+ supports inline `forge-config:` at the **function level** ([#7355](https://github.com/NomicFoundation/hardhat/issues/7355) closed); Hardhat 3.5.0 / EDR `0.12.0-next.33` added function-level support for `isolate` and `evm_version` ([edr#1349](https://github.com/NomicFoundation/edr/issues/1349) closed). **Contract-level** directives remain silently ignored — Hardhat only honors function-level inline config. No tracking issue for contract-level support found.

## Forge-Dependent `package.json` Scripts

| Script        | Command                                          | Forge feature                  |
| ------------- | ------------------------------------------------ | ------------------------------ |
| `rs:bind`     | `forge bind --bindings-path ...`                 | Rust/Alloy bindings generation |
| `rs:abis`     | `forge build --out ... --extra-output-files abi` | ABI extraction                 |
| `rs:generate` | `npm run rs:bind && npm run rs:abis`             | Combined binding + ABI         |

**No `test`, `build`, `coverage`, or `snapshot` scripts** — only `lint`, `lint:fix`, `rs:*`, and `prepare`.

## Absolute Imports

**220+ files** use absolute imports with single-quoted prefixes:

- `src/...` (in 55+ src files)
- `tests/...` (in 165+ test files)
- `scripts/...` (5 files in the new deployment engine — `tests/scripts/AaveV4DeployBatchBaseScript.t.sol`, `tests/deployments/fork/PostDeploymentVerificationTest.t.sol`, and 3 files in `scripts/`)
- `lib/erc4626-tests/...` (1 file)

Remappings required: `src/=./src/`, `tests/=./tests/`, `lib/=./lib/`, `scripts/=./scripts/`.

## zkSync

**None.** No zkSync profiles or contracts found.
