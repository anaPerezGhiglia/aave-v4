# Aave V4 — Hardhat 3 Migration Report

**Hardhat version installed:** `^3.5.0` (EDR `0.12.0-next.33`)
**Migration date:** 2026-05-21
**Foundry analysis:** [Foundry analysis](aave-v4-foundry-migration-analysis.md)

---

**Verdict:** 🟡 **Successful with gaps**

All 1559 tests pass. The previous blockers (`vm.snapshotGasLastCall` name validation bug, missing `vm.eip712HashStruct` / `vm.eip712HashType` cheatcodes) were resolved by upstream EDR releases. Gas snapshots (`--snapshot` / `--snapshot-check`) work end-to-end. The remaining gaps are non-blocking and limited to contract-level inline test config and a few Foundry-only utilities.

### Notable gaps (non-blocking, medium+ impact)

- 🟡 Inline `forge-config:` per-test overrides — function-level support landed in Hardhat 3.3.0; inline `isolate` / `evm_version` landed in 3.5.0 (edr#1349 closed). However, every directive in this project is at **contract level**, which is still silently ignored.
- 🟡 Gas values produced by EDR diverge non-uniformly from the committed Forge baseline (observed range across `snapshots/*.json`: roughly −29% to −86% per entry, with larger deltas concentrated on cheatcode-heavy operations and smaller deltas on plain state ops). The infrastructure works; the existing baselines can't be reused as-is, so adopting Hardhat for CI requires regenerating them under the new toolchain.
- 🟡 Glob patterns in compilation overrides not supported (#4686 still open) — `tests/**` restriction cannot be expressed.

---

## 1. Test Count Comparison

| Metric                                                | Count                                  |
| ----------------------------------------------------- | -------------------------------------- |
| Total `function test*` declarations in `.t.sol` files | 1451                                   |
| Commented out (HARDHAT-SKIP) function definitions     | 0                                      |
| Active test function definitions                      | 1451                                   |
| Hardhat tests run                                     | 1559 passing + 0 failing + 1 skipped = 1560 |

**Note:** The difference between 1451 definitions and 1559 running tests is expected — some test contracts inherit test functions from base contracts, so a single function definition runs multiple times across different contract contexts. The 140 previously commented-out functions (vm.eip712Hash* cheatcodes) have been fully restored.

## 2. Feature Parity

### Gaps, bugs & partial support

| Feature                                     | Parity         | Impact                                                                                                                                                                                                                                                                       | Workaround / Notes                                                                                                                                                                                                                                       |
| ------------------------------------------- | -------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Inline test config                          | 🟡 **Partial** | **Medium** — 10 files use contract-level `forge-config:` (`isolate`, `allow_internal_expect_revert`, `disable_block_gas_limit`); silently ignored. Global `allowInternalExpectRevert: true` set as workaround; `isolate` cannot be enabled globally without massive perf hit | Function-level inline config now supports `isolate` / `evm_version` ([edr#1349](https://github.com/NomicFoundation/edr/issues/1349) closed in 3.5.0), but contract-level scope is still unresolved. No tracking issue for contract-level support found — consider filing one. |
| Gas snapshot values                         | 🟡 **Partial** | **Medium** — both `--snapshot` and `--snapshot-check` run cleanly, but values diverge non-uniformly from the committed Forge baseline. Observed range: roughly −29% to −86% per entry, larger for cheatcode-heavy ops (e.g. `*WithSig` tests in the −70% to −85% band) and smaller for plain state operations. The non-uniform pattern suggests systematically different accounting conventions (candidates: pre- vs post-refund reporting, intrinsic / cold-access inclusion, cheatcode-call overhead — none verified against EDR source) rather than a fixed offset. | Direction (Hardhat lower) is *observed*, not a quality claim — different conventions, not "better/worse". A baseline tracking one tool's numbers can't be reused under the other: either regenerate `snapshots/*.json` under Hardhat (and migrate CI to the new baseline) or keep snapshot generation on Forge while running other tests under Hardhat. No tracking issue found — consider filing one if exact cross-toolchain parity is required. |
| Glob overrides                              | 🟡 **Partial** | **Medium** — `tests/**` compilation restriction cannot be expressed; each file would need individual listing                                                                                                                                                                | [#4686](https://github.com/NomicFoundation/hardhat/issues/4686) — omitted since default compiler settings match the tests restriction                                                                                                                    |
| ABI binding generation                      | 🚩 **Gap**     | **Low** — `forge bind --alloy` (used by `rs:bind` script) has no Hardhat equivalent                                                                                                                                                                                          | No tracking issue found — consider filing one                                                                                                                                                                                                            |
| `forge build --extra-output-files abi`      | 🟡 **Partial** | **Low** — `rs:abis` script extracts ABIs to a flat dir; Hardhat produces ABIs in `artifacts/<Contract>.sol/<Contract>.json` with a different structure                                                                                                                       | Workaround: extract ABIs from Hardhat artifacts with a shell script                                                                                                                                                                                      |
| Dynamic test linking                        | 🚩 **Gap**     | **Low** — Foundry-only optimization; tests still work without it                                                                                                                                                                                                            | No tracking issue found                                                                                                                                                                                                                                  |
| Fuzz/invariant profile overrides            | 🟡 **Partial** | **Low** — `[profile.pr.fuzz]` / `[profile.ci.fuzz]` test-only profile settings; can use env vars or CLI args instead                                                                                                                                                         | Hardhat build profiles only cover compiler settings, not test settings                                                                                                                                                                                   |
| Etherscan verification                      | 🟡 **Partial** | **Low** — Hardhat 3 uses Etherscan API v2 with a single key; Foundry has per-chain keys                                                                                                                                                                                     | Consolidate to a single `ETHERSCAN_API_KEY` — Etherscan API v2 accepts one key across all supported chains                                                                                                                                               |

### Full parity

These features work equivalently in Hardhat 3:

- Solidity compilation (`forge build` → `npx hardhat compile`)
- Solidity compiler settings (optimizer, optimizer_runs, evmVersion, bytecodeHash)
- Build profiles with per-file overrides (`additional_compiler_profiles` + `compilation_restrictions` → `solidity.profiles.default.overrides`)
- Coverage build profile (`[profile.coverage]` → `solidity.profiles.coverage`)
- forge-std cheatcodes (`vm.*`) — general
- `vm.eip712HashStruct` / `vm.eip712HashType` (added in EDR `0.12.0-next.32`, picked up in Hardhat 3.5.0) — Hardhat's `test.solidity.eip712Types.include` is the workflow-equivalent of Forge's `[bind_json].include`: both register the canonical EIP-712 types so the cheatcodes can resolve by name. The mechanism differs (Forge reads from the generated `JsonBindings.sol` via `bind_json_path`; Hardhat walks the AST of the included files at test-runner startup), but the user-facing role and configuration are equivalent. Hardhat does **not** emit a `JsonBindings.sol`-style helper file — this is a non-issue for this project since no test imports any symbol from it, but could matter for projects that consume the generated `schema_*` constants or `serialize`/`deserialize` helpers.
- `vm.snapshotGasLastCall` name validation — previously rejected names containing colons/parentheses (regression vs Hardhat 3.1.12); fixed in EDR `0.12.0-next.33` / Hardhat 3.5.0
- Fuzz testing (`fuzz.runs`, `fuzz.seed`)
- `fs_permissions` → `fsPermissions`
- `gas_limit` → `gasLimit`
- `allow_internal_expect_revert` → `allowInternalExpectRevert` (global)
- Gas snapshots (`forge snapshot` → `npx hardhat test solidity --snapshot` / `--snapshot-check`) — both commands succeed; see "Gas snapshot values" gap above for cross-toolchain value differences
- Network RPC endpoints (`[rpc_endpoints]` → `networks`)
- Remappings (`remappings.txt` — natively supported)
- Git submodule dependencies (`lib/forge-std`, `lib/erc4626-tests` — resolved via remappings)

**Features not used by this project:**

- Deployment scripting (`forge script` / `.s.sol`) — project has a `script/` directory but no deploy scripts in `package.json`
- Invariant testing — no invariant tests found
- FFI — not enabled

**Foundry-only features with existing alternatives:**

- Built-in formatter / `[lint]` — Forge's built-in linter is configured in `foundry.toml` but the project uses `prettier` + `prettier-plugin-solidity` for linting (`lint`/`lint:fix` scripts); no Hardhat equivalent needed

## 3. Workarounds Applied

### Remappings for absolute imports

**What:** `src/=./src/`, `tests/=./tests/`, `lib/=./lib/` added to `remappings.txt`.

**Why:** The project uses 220+ absolute imports with `src/` and `tests/` prefixes (e.g., `import 'src/dependencies/openzeppelin/SafeERC20.sol'`). Hardhat 3 does not support absolute imports — all local imports must be relative or go through remappings. One file also imports `lib/erc4626-tests/ERC4626.test.sol` directly. In Forge, `src = "src"` in `foundry.toml` implicitly makes `src/` a valid import prefix; Hardhat requires explicit remappings.

### Global `allowInternalExpectRevert: true`

**What:** Set `test.solidity.allowInternalExpectRevert: true` globally in `hardhat.config.ts`.

**Why:** 3 test files use `/// forge-config: default.allow_internal_expect_revert = true` at the **contract level** (placed on the contract definition, not on individual test functions). Hardhat 3.3.0+ supports inline `forge-config:` at the function level; Hardhat 3.5.0 / EDR `next.33` added function-level support for `isolate` and `evm_version` ([edr#1349](https://github.com/NomicFoundation/edr/issues/1349) closed). Contract-level directives, however, are still silently ignored. Setting it globally is the only available workaround. Safe — only affects `vm.expectRevert` behavior on internal/library calls.

### ESM module type

**What:** `"type": "module"` in `package.json`.

**Why:** Required by Hardhat 3. The project had no existing `.js` files with `require()`, so no breakage.

## 4. Next Steps

1. **Decide on adoption** — All blockers from the previous migration attempt are resolved. The remaining gaps are all 🟡 Partial, none block testing. Hardhat 3 is now a viable replacement for Forge on this project, modulo the snapshot-value and ABI-export workflow changes called out in the gap table.
2. **Regenerate gas snapshots under Hardhat before adoption** — values diverge non-uniformly from the committed Forge baseline (roughly −29% to −86% per entry, varying by test pattern). The two toolchains appear to use different accounting conventions, so the baseline can't be reused as-is. If CI tracks snapshots, replace `snapshots/*.json` with output from `npx hardhat test solidity --snapshot` and document the toolchain switch in PR history. Don't mix old (Forge) and new (Hardhat) entries in the same baseline file.
3. **Replace `rs:bind` / `rs:abis` scripts** — `forge bind --alloy` and `forge build --extra-output-files abi` have no direct Hardhat equivalent. Either keep them on Forge (both toolchains can coexist) or write a custom script that extracts ABIs from Hardhat's `artifacts/<Contract>.sol/<Contract>.json` output.
4. **Track contract-level inline `forge-config:` support** — Hardhat 3.5.0 closed function-level inline support but contract-level remains unimplemented. 10 files in this project rely on contract-level directives. Until upstream support lands, the global `allowInternalExpectRevert: true` workaround remains; `isolate` cannot be promoted to global without a major performance regression.
5. **File upstream issues for the documented gaps** — none of the open gaps (contract-level inline config, ABI binding parity, dynamic test linking, gas-value divergence) appear to have tracking issues. Filing them would put the project on the Hardhat team's radar for prioritization.
