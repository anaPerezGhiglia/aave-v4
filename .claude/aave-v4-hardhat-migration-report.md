# Aave V4 — Hardhat 3 Migration Report

**Hardhat version installed:** `^3.6.0` (EDR `0.12.0-next.33`)
**Migration date:** 2026-05-26 (re-run against the just-released `3.6.0`; previous runs at `3.5.0` and `3.5.1`)
**Foundry analysis:** [Foundry analysis](aave-v4-foundry-migration-analysis.md)

---

**Verdict:** ❌ **Failed**

`npx hardhat test solidity` aborts before any test runs, blocked by two upstream Hardhat bugs filed during this session. Compilation itself succeeds.

- [NomicFoundation/hardhat#8341](https://github.com/NomicFoundation/hardhat/issues/8341) — `ERR_STRING_TOO_LONG` reading the build-info output. Fires because the project's default-profile build-info output is ~698 MiB (731,669,005 bytes), above Node's ~512 MiB string-length cap. Both `collectRawOverrides` and `collectEip712CanonicalTypes` call `JSON.parse(bytesToUtf8String(...))` on the full buffer.
- [NomicFoundation/hardhat#8344](https://github.com/NomicFoundation/hardhat/issues/8344) — `HHE818` thrown for an included struct because a same-named struct in an unrelated, non-included file ends up in the EIP-712 collector's registry. Latent under stock Hardhat (#8341 masks it); confirmed against a locally-patched build.

The `3.6.0` release (published 2026-05-26, one day after `3.5.1`) does not address either bug — confirmed against the changelog and reproduced byte-identically against `3.5.1` and `3.6.0`. EDR remains pinned at `0.12.0-next.33`. `3.6.0` adds hooks, deprecations, positional-args support, and a `hardhat flatten` cyclic-dependency fix; none of those touch the solidity-test runner's build-info read path.

### Blockers

- ❌ [#8341](https://github.com/NomicFoundation/hardhat/issues/8341) — 100% of Solidity tests are blocked; `--snapshot` and `--snapshot-check` are blocked by the same code path. Reproduces identically on `3.5.1` and `3.6.0`.
- ❌ [#8344](https://github.com/NomicFoundation/hardhat/issues/8344) — would block the project even after #8341 is fixed; latent only because #8341 fires first. Concrete trigger here: `src/config-engine/IAaveV4ConfigEngine.PositionManagerUpdate` (a structurally distinct struct in an unincluded, unimported file) collides by name with the included `tests/helpers/mocks/EIP712Types.sol::PositionManagerUpdate`. Forge `bind-json` does not see the collision because its include scope is `include` + Solidity-import closure.

### Notable gaps (non-blocking, medium+ impact)

- 🟡 Inline `forge-config:` per-test overrides — function-level support landed in Hardhat 3.3.0; inline `isolate` / `evm_version` landed in 3.5.0 (edr#1349 closed). 9 of 10 directives in this project are still at **contract level**, which is silently ignored. One function-level directive (`PostDeploymentVerificationTest.t.sol`) was added in the upstream merge.
- 🟡 Glob patterns in compilation overrides not supported (#4686 still open) — `tests/**` restriction cannot be expressed.

---

## 1. Test Count Comparison

| Metric                                                | Count                                                  |
| ----------------------------------------------------- | ------------------------------------------------------ |
| Total `function test*` declarations in `.t.sol` files | 1939                                                   |
| Commented out (HARDHAT-SKIP) function definitions     | 0                                                      |
| Active test function definitions                      | 1939                                                   |
| Hardhat tests run (stock `3.6.0`)                     | **0** — blocked at collection by [#8341](https://github.com/NomicFoundation/hardhat/issues/8341) |
| Hardhat tests run (with #8341 bypassed locally)       | **0** — blocked at collection by [#8344](https://github.com/NomicFoundation/hardhat/issues/8344), confirming the second bug is independently reachable |

**Note:** The previous report (against commit `f729aef`, before the upstream merge) recorded 1559 passing tests. The merge added ~488 new test definitions and grew the default-profile build-info output past Node's 512 MiB string-length cap, which is what now trips #8341.

## 2. Feature Parity

### Gaps, bugs & partial support

| Feature                                | Parity         | Impact                                                                                                                                                                                                                                                                                          | Workaround / Notes                                                                                                                                                                                                                                                                            |
| -------------------------------------- | -------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Inline test config / EIP-712 cheatcodes (build-info read) | ❌ **Bug**     | **High** — 0 of 1939 tests can run; `--snapshot` and `--snapshot-check` blocked by the same code path. Separately, 9 contract-level `forge-config:` directives in this project would be silently ignored even once the crash is fixed (Hardhat only honors function-level inline config). | Filed upstream as [NomicFoundation/hardhat#8341](https://github.com/NomicFoundation/hardhat/issues/8341) with a suggested byte-level JSON slicer fix. Test code not modified; fix required in Hardhat. Contract-level inline-config scope is a separate (pre-existing) limitation — global `allowInternalExpectRevert: true` is the workaround; `isolate` cannot be enabled globally without massive perf hit; no upstream tracking issue for contract-level support found. |
| EIP-712 cheatcodes (include-scope walk)                   | ❌ **Bug**     | **High** — 0 of 1939 tests run once #8341 is bypassed. Forge `bind-json` does not trigger this — its `include` scope is the file plus its Solidity-import closure. | Filed upstream as [NomicFoundation/hardhat#8344](https://github.com/NomicFoundation/hardhat/issues/8344) with two suggested fix shapes. Project-side workaround would be renaming `IAaveV4ConfigEngine.PositionManagerUpdate` (structurally distinct from the spoke/test copies; renaming has no semantic-equivalence risk). Not applied — workaround would mask the upstream divergence. |
| Gas snapshot values                    | 🟡 **Partial** | **Medium** — both `--snapshot` and `--snapshot-check` cannot run at all in this session due to the inline-config crash above. Previous run (at `f729aef`, before the merge) showed non-uniform value divergence vs the committed Forge baseline (≈ −29% to −86% per entry, larger for cheatcode-heavy ops). | Direction (Hardhat lower) is *observed*, not a quality claim — different conventions, not "better/worse". A baseline tracking one tool's numbers can't be reused under the other: regenerate `snapshots/*.json` under Hardhat or keep snapshot generation on Forge. Re-verify once the bug above is fixed. |
| Glob overrides                         | 🟡 **Partial** | **Medium** — `tests/**` compilation restriction cannot be expressed; each file would need individual listing                                                                                                                                                                                  | [#4686](https://github.com/NomicFoundation/hardhat/issues/4686) — omitted since default compiler settings match the tests restriction                                                                                                                                                          |
| ABI binding generation                 | 🚩 **Gap**     | **Low** — `forge bind --alloy` (used by `rs:bind` script) has no Hardhat equivalent                                                                                                                                                                                                            | No tracking issue found — consider filing one                                                                                                                                                                                                                                                |
| `forge build --extra-output-files abi` | 🟡 **Partial** | **Low** — `rs:abis` script extracts ABIs to a flat dir; Hardhat produces ABIs in `artifacts/<Contract>.sol/<Contract>.json` with a different structure                                                                                                                                         | Workaround: extract ABIs from Hardhat artifacts with a shell script                                                                                                                                                                                                                          |
| Dynamic test linking                   | 🚩 **Gap**     | **Low** — Foundry-only optimization; tests still work without it                                                                                                                                                                                                                              | No tracking issue found                                                                                                                                                                                                                                                                      |
| Fuzz/invariant profile overrides       | 🟡 **Partial** | **Low** — `[profile.pr.fuzz]` / `[profile.ci.fuzz]` test-only profile settings; can use env vars or CLI args instead                                                                                                                                                                          | Hardhat build profiles only cover compiler settings, not test settings                                                                                                                                                                                                                       |
| Etherscan verification                 | 🟡 **Partial** | **Low** — Hardhat 3 uses Etherscan API v2 with a single key; Foundry has per-chain keys                                                                                                                                                                                                       | Consolidate to a single `ETHERSCAN_API_KEY` — Etherscan API v2 accepts one key across all supported chains                                                                                                                                                                                   |

### Full parity

These features work equivalently in Hardhat 3 (verified up to and including compilation; test-runtime verification blocked by the bug above):

- Solidity compilation (`forge build` → `npx hardhat compile`) — succeeds, produces 455 compiled `.sol` files
- Solidity compiler settings (optimizer, optimizer_runs, evmVersion, bytecodeHash)
- Build profiles with per-file overrides (`additional_compiler_profiles` + `compilation_restrictions` → `solidity.profiles.default.overrides`)
- Coverage build profile (`[profile.coverage]` → `solidity.profiles.coverage`)
- forge-std cheatcodes (`vm.*`) — general (last verified at `f729aef`)
- `vm.eip712HashStruct` / `vm.eip712HashType` — supported via `test.solidity.eip712Types.include` (added in Hardhat 3.5.0); the project uses these via `tests/helpers/mocks/EIP712Types.sol`. Last verified at `f729aef`.
- `vm.snapshotGasLastCall` name validation — fixed in EDR `0.12.0-next.33`
- Fuzz testing (`fuzz.runs`, `fuzz.seed`)
- `fs_permissions` → `fsPermissions` (multi-entry support including directory-prefix variants)
- `gas_limit` → `gasLimit`
- `allow_internal_expect_revert` → `allowInternalExpectRevert` (global)
- Network RPC endpoints (`[rpc_endpoints]` → `networks`)
- Remappings (`remappings.txt` — natively supported)
- Git submodule dependencies (`lib/forge-std`, `lib/erc4626-tests` — resolved via remappings)

**Features not used by this project:**

- Deployment scripting (`forge script` / `.s.sol`) — project has `script/` and `scripts/` directories but no `forge script` invocations in `package.json`
- Invariant testing — no invariant tests found
- FFI — not enabled

**Foundry-only features with existing alternatives:**

- Built-in formatter / `[lint]` — project uses `prettier` + `prettier-plugin-solidity` (`lint`/`lint:fix` scripts); no Hardhat equivalent needed

## 3. Workarounds Applied

### Remappings for absolute imports (updated)

**What:** `src/=./src/`, `tests/=./tests/`, `lib/=./lib/`, **`scripts/=./scripts/`** (newly added 2026-05-26) in `remappings.txt`.

**Why:** The project uses 220+ absolute imports across `src/`, `tests/`, and the upstream merge added a `scripts/` deployment engine plus tests that import from it (e.g., `import 'scripts/deploy/AaveV4DeployBatchBase.s.sol'`). Hardhat 3 does not support absolute imports — they must be relative or resolved via remappings. In Forge, `src = "src"` plus `libs = ["lib"]` makes these prefixes implicit; Hardhat requires explicit declarations.

### Global `allowInternalExpectRevert: true`

**What:** Set `test.solidity.allowInternalExpectRevert: true` globally in `hardhat.config.ts`.

**Why:** 3 test files use `/// forge-config: default.allow_internal_expect_revert = true` at the **contract level**. Hardhat 3.3.0+ supports inline `forge-config:` at the function level (#7355 closed); 3.5.0 / EDR `next.33` added function-level `isolate` and `evm_version` (edr#1349 closed). Contract-level directives are still silently ignored. Setting it globally is the only available workaround. Safe — only affects `vm.expectRevert` behavior on internal/library calls.

### Config updates triggered by the upstream merge

**What:** Updated `hardhat.config.ts` to match the new `foundry.toml` after the `e141a05` merge:

- `optimizer_runs`: `444_444_444_444` → `44_444_444` (upstream `dd26d09`)
- Hub override path: `src/hub/Hub.sol` → `src/hub/instances/HubInstance.sol`
- `fs_permissions`: added `readDirectory: ['./config', './out']` and `dangerouslyReadWriteDirectory: ['./output']` to mirror the new entries; updated `readFile` path for `JsonBindings.sol`
- `eip712Types.include`: updated path to `tests/helpers/mocks/EIP712Types.sol`
- Added `anvil` network entry

**Why:** The upstream merge restructured the test directory and reduced optimizer runs. The `hardhat.config.ts` from the previous migration was silently using stale paths (the `src/hub/Hub.sol` override was effectively a no-op since the file no longer exists). These are not workarounds for Hardhat limitations — they are config-drift corrections.

### ESM module type

**What:** `"type": "module"` in `package.json`.

**Why:** Required by Hardhat 3. The project had no existing `.js` files with `require()`, so no breakage.

## 4. Next Steps

1. **Track [#8341](https://github.com/NomicFoundation/hardhat/issues/8341)** — single highest-impact item; blocks every test from running. The issue body includes a suggested byte-level JSON slicer fix that the upstream team could adopt directly. Both call sites (`collectRawOverrides`, `collectEip712CanonicalTypes`) need the same treatment.
2. **Track [#8344](https://github.com/NomicFoundation/hardhat/issues/8344)** — second blocker, latent until #8341 is fixed but real on its own. The issue includes a self-contained minimal repro and two suggested fix shapes.
3. **Re-run the migration after both bugs are fixed** — every other gap (gas-value divergence, contract-level inline config, ABI/binding scripts) is a "test-runner-works-but" gap; none can be re-verified until the runner starts. The previous report at `f729aef` (1559 passing tests under `3.5.0`) is the most recent green baseline; expect a similar pass-count after the upstream patches land.
4. **Track contract-level inline `forge-config:` support** — Hardhat 3.5.x closed function-level support, but contract-level remains unimplemented. 9 files in this project rely on contract-level directives. Until upstream support lands, the global `allowInternalExpectRevert: true` workaround remains; `isolate` cannot be promoted to global without a major performance regression.
5. **Replace `rs:bind` / `rs:abis` scripts (Low impact)** — `forge bind --alloy` and `forge build --extra-output-files abi` have no direct Hardhat equivalent. Either keep them on Forge (both toolchains can coexist) or write a custom script that extracts ABIs from Hardhat's `artifacts/<Contract>.sol/<Contract>.json` output.
