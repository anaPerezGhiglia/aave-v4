# Aave V4 — Foundry Migration Analysis

## Project Structure

- **Source directory:** `src/` (subdirs: access, dependencies, hub, interfaces, libraries, misc, position-manager, spoke, utils)
- **Test directory:** `tests/` (subdirs: gas, misc, mocks, unit; plus helper files Base.t.sol, Constants.sol, etc.)
- **Script directory:** `script/` (exists but not inspected in detail)
- **Total .sol files (src + tests):** 291
- **Submodules (`lib/`):**
  - `forge-std` → https://github.com/foundry-rs/forge-std
  - `erc4626-tests` → https://github.com/a16z/erc4626-tests
- **Remappings (`remappings.txt`):**
  - `erc4626-tests/=lib/erc4626-tests/`
  - `forge-std/=lib/forge-std/src/`

## Package Manager

**Selected:** `yarn` (classic v1.22.22)
**Reason:** `yarn.lock` is more recently modified (Mar 16) vs `package-lock.json` (Mar 9). Both exist; yarn.lock is the active lockfile. Will not introduce a second lockfile.

## foundry.toml — All Sections and Settings

### `[profile.default]`

| Setting | Value |
|---|---|
| `src` | `src` |
| `test` | `tests` |
| `out` | `out` |
| `libs` | `["lib"]` |
| `fs_permissions` | `[{ access = "read", path = "tests/mocks/JsonBindings.sol" }]` |
| `solc_version` | `0.8.28` |
| `evm_version` | `cancun` |
| `optimizer` | `true` |
| `optimizer_runs` | `444444444444` |
| `bytecode_hash` | `none` |
| `gas_snapshot_check` | `false` |
| `gas_limit` | `1099511627776` |
| `dynamic_test_linking` | `true` |

### `additional_compiler_profiles`

| Profile | optimizer | via_ir | optimizer_runs |
|---|---|---|---|
| `hub` | true | true | 22,300 |
| `spoke` | true | true | 750 |
| `tests` | true | false | 444,444,444,444 |

### `compilation_restrictions`

| Path pattern | optimizer | via_ir | optimizer_runs |
|---|---|---|---|
| `src/hub/Hub.sol` | true | true | 22,300 |
| `src/spoke/instances/SpokeInstance.sol` | true | true | 750 |
| `tests/**` | true | false | 444,444,444,444 |

### `[bind_json]`

- `out = "tests/mocks/JsonBindings.sol"`
- `include = ["tests/mocks/EIP712Types.sol"]`

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
- `optimizer_runs = 444444444444`
- `via_ir = false`
- `fuzz.runs = 50`
- `additional_compiler_profiles = []`
- `compilation_restrictions = []`

### `[rpc_endpoints]`

mainnet, optimism, avalanche, polygon, arbitrum, fantom, harmony, metis, base, zkevm, gnosis, bnb, celo — all using `${RPC_*}` env vars.

### `[etherscan]`

Per-chain API keys for: mainnet (1), optimism (10), avalanche (43114), polygon (137), arbitrum (42161), fantom (250), metis (1088, custom URL), base (8453), zkevm (1101), gnosis (100), bnb (56), celo (42220).

## Inline Test Config (`forge-config:` comments)

Found in 10 files:

- `tests/gas/*.t.sol` (6 files) — `forge-config: default.isolate = true`
- `tests/unit/MathUtils.t.sol` — `forge-config: default.allow_internal_expect_revert = true`
- `tests/unit/libraries/KeyValueList.t.sol` — `forge-config: default.allow_internal_expect_revert = true`
- `tests/unit/AaveOracle.t.sol` — `forge-config: default.allow_internal_expect_revert = true`
- `tests/unit/Hub/Hub.Rounding.t.sol` — `forge-config: default.disable_block_gas_limit = true`

**Note:** These per-test overrides are silently ignored by Hardhat 3 ([#7355](https://github.com/NomicFoundation/hardhat/issues/7355)).

## Forge-Dependent `package.json` Scripts

| Script | Command | Forge feature |
|---|---|---|
| `rs:bind` | `forge bind --bindings-path ...` | Rust/Alloy bindings generation |
| `rs:abis` | `forge build --out ... --extra-output-files abi` | ABI extraction |
| `rs:generate` | `npm run rs:bind && npm run rs:abis` | Combined binding + ABI |

**No `test`, `build`, `coverage`, or `snapshot` scripts** — only `lint`, `lint:fix`, `rs:*`, and `prepare`.

## Absolute Imports

**None found.** All imports use relative paths or package-style paths.

## zkSync

**None.** No zkSync profiles or contracts found.
