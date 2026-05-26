# Aave V4 — Hardhat 3 Migration Report

**Hardhat version installed:** `^3.6.0` (EDR `0.12.0-next.33`)
**Migration date:** 2026-05-26 (re-run against the just-released `3.6.0`; previous runs at `3.5.0` and `3.5.1`)
**Foundry analysis:** [Foundry analysis](aave-v4-foundry-migration-analysis.md)

---

**Verdict:** ❌ **Failed**

`npx hardhat test solidity` crashes with `RangeError: Cannot create a string longer than 0x1fffffe8 characters` before any test runs. The cause is a Hardhat bug in the inline-config collector: when any source file contains a `forge-config:` or `hardhat-config:` directive, the test runner reads the entire build-info `*.output.json` for that compilation set into a single Node.js string via `bytesToUtf8String + JSON.parse`. After an upstream merge brought the project's default-profile build-info output to ~698 MiB (731,669,005 bytes), this exceeds V8's `String::kMaxLength` (~512 MiB) and the call aborts. The EIP-712 type collector (`collectEip712CanonicalTypes`) hits the same crash via the same primitive. Compilation itself succeeds.

The `3.6.0` release (published 2026-05-26, one day after `3.5.1`) **does not address either bug** — confirmed against the changelog and reproduced byte-identically here. EDR remains pinned at `0.12.0-next.33`. The `3.6.0` notes are limited to new hooks (`cleanupArtifacts`, `getCompilationJobErrors`, `processArtifactsAfterSuccessfulBuild`), several deprecations, positional-args support, and a `hardhat flatten` cyclic-dependency fix — none of which touch the solidity-test runner's build-info read path.

A separate latent bug was identified after locally patching the streaming-string crash: the EIP-712 collector walks every compiled source's AST regardless of `eip712Types.include`, so a same-named struct in an *unincluded, unimported* file (e.g. `src/config-engine/IAaveV4ConfigEngine.PositionManagerUpdate` vs the project's intentionally-scoped `tests/helpers/mocks/EIP712Types.sol`) triggers `HHE818`. Forge's `bind-json` does not see this collision because its include scope is `include` + Solidity-import closure, not "every source in the build info". This second bug is only reachable once the first is bypassed, but it would block the project even if the runner started.

### Blockers

- ❌ Build-info inline-config scan crashes on >512 MiB output → [local bug report](bugs/inline-config-build-info-string-too-long.md) (not yet filed upstream). 100% of Solidity tests are blocked; `--snapshot` and `--snapshot-check` are blocked by the same code path. Same crash signature on `3.5.1` and `3.6.0`.
- ❌ EIP-712 collector throws `HHE818` against an `include`'d struct because of a same-named struct in an unrelated, *non-included* source → [local bug report](bugs/eip712-name-collision-from-non-included-sources.md) (not yet filed upstream). Latent under the current published Hardhat (masked by the first bug); confirmed against a locally-patched build. Forge `bind-json` does not have this divergence — its include scope is import-closure-based, so out-of-scope files are never opened.

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
| Hardhat tests run (against published `3.6.0`)         | **0 — test runner crashes during inline-config collection (ERR_STRING_TOO_LONG)** |
| Hardhat tests run (against locally-patched `3.6.0` with the streaming slicer applied) | **0 of 1939 — runner aborts during EIP-712 collection with `HHE818`** (proves second bug is reachable, not the first one being miscategorized) |

**Note:** The test runner never starts under published Hardhat. The crash happens at `getTestFunctionOverrides → collectRawOverrides → bytesToUtf8String` while loading the build-info output. With the streaming-slicer fix applied locally, the same crash also surfaces from `collectEip712CanonicalTypes` (same primitive, second consumer) — both are fixed by the slicer. After both are bypassed, the EIP-712 `HHE818` collision throw fires next. The previous report (against commit `f729aef`, before the upstream merge) recorded 1559 passing tests; the merge added ~488 new test definitions and grew the default-profile build-info output past the 512 MiB string-length cap.

## 2. Feature Parity

### Gaps, bugs & partial support

| Feature                                | Parity         | Impact                                                                                                                                                                                                                                                                                          | Workaround / Notes                                                                                                                                                                                                                                                                            |
| -------------------------------------- | -------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Inline test config / EIP-712 cheatcodes (build-info read) | ❌ **Bug**     | **High** — `npx hardhat test solidity` crashes with `ERR_STRING_TOO_LONG` during inline-config collection; 0 of 1939 tests can run. Same crash blocks `--snapshot` and `--snapshot-check`. The EIP-712 collector hits the same crash via the same primitive (`bytesToUtf8String`). Separately, 9 contract-level directives in the project would be silently ignored even once the crash is fixed (Hardhat only honors function-level). | [Local bug report](bugs/inline-config-build-info-string-too-long.md) (not yet filed upstream) — `collectRawOverrides` and `collectEip712CanonicalTypes` both call `JSON.parse(bytesToUtf8String(output))` on the full build-info output. Hand-rolled byte-level JSON slicer (`findJsonObjectEntries` in `hardhat-utils/bytes.ts`) prototyped locally and verified — see report's Workaround prototype. Test code not modified; fix required in Hardhat. Contract-level scope is a separate (pre-existing) limitation — global `allowInternalExpectRevert: true` is the workaround; `isolate` cannot be enabled globally without massive perf hit; no tracking issue for contract-level support found. |
| EIP-712 cheatcodes (include-scope walk)                   | ❌ **Bug**     | **High** — under a locally-patched Hardhat that bypasses the `ERR_STRING_TOO_LONG` crash, the EIP-712 collector throws `HHE818` because `src/config-engine/IAaveV4ConfigEngine.PositionManagerUpdate` (a structurally distinct struct in an *unincluded, unimported* file) collides by name with the project's selected `tests/helpers/mocks/EIP712Types.sol::PositionManagerUpdate`. 0 of 1939 tests run. Forge `bind-json` doesn't trigger this — its `include` scope is the file plus its Solidity-import closure, so `src/config-engine` is invisible. | [Local bug report](bugs/eip712-name-collision-from-non-included-sources.md) (not yet filed upstream) — `collectEip712CanonicalTypes` walks every source's AST and `collected.push(...structs)` unconditionally; `include` only filters the *emit set* (`selectedNames`), not the *walk set*. Two fix shapes proposed: (a) drop unselected definitions when they conflict with a selected name in `canonicalize.ts:indexByName`; (b) restrict the AST walk to `include`'s Solidity-import closure (Forge-equivalent). Project-side workaround would be renaming `IAaveV4ConfigEngine.PositionManagerUpdate` (structurally distinct from the spoke/test copies; renaming has no semantic-equivalence risk). Not applied — workaround would mask the upstream divergence. |
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

## 3. Hardhat / EDR Bug Reports

Two high-severity bugs were identified, both blocking the entire test runner. Tests are **not** commented out — they are active blockers.

### 3a. `npx hardhat test solidity` crashes with `ERR_STRING_TOO_LONG` reading build-info output (two call sites)

- Root cause: `collectRawOverrides` (`solidity-test/inline-config/index.ts:157`) and `collectEip712CanonicalTypes` (`solidity-test/eip712/index.ts:65`) both call `JSON.parse(bytesToUtf8String(buildInfoAndOutput.output))`. When the build-info output JSON exceeds Node.js's `String::kMaxLength` (~512 MiB), `TextDecoder.decode()` throws. The triggers are `buildInfoContainsInlineConfig` (returns true on any `forge-config:` / `hardhat-config:` byte sequence) and `bytesIncludesUtf8String(buildInfo, "struct ")` (matches almost any real Solidity build info when `eip712Types.include` is non-empty).
- Failing tests: **all 1939** test function definitions; the runner aborts before any test runs.
- Local report: [`bugs/inline-config-build-info-string-too-long.md`](bugs/inline-config-build-info-string-too-long.md) — includes a minimal-repro recipe, both crash sites with stack traces, four suggested fix directions (best-effort fallback / hand-rolled slicer / streaming JSON parser / on-disk reads), and a verified workaround prototype: the `findJsonObjectEntries` byte-level JSON slicer added to `hardhat-utils/bytes.ts`. Layer: Hardhat (not EDR).
- Status: not yet filed upstream. Tests left as-is; no workaround applied to the published Hardhat install (the directives in this project are contract-level and Hardhat ignores them anyway, but their bytes still trigger the build-info read).

### 3b. EIP-712 collector throws `HHE818` against an unrelated, non-included source

- Root cause: `collectEip712CanonicalTypes` (`solidity-test/eip712/index.ts:91-116`) iterates every source's AST and unconditionally `collected.push(...structs)`; `include`/`exclude` only filters which struct names enter `selectedNames` for emit-time. `canonicalize.ts:indexByName` then detects a fingerprint conflict between a *selected* struct and an *unselected* struct anywhere in the build and throws.
- Concretely: `tests/helpers/mocks/EIP712Types.sol::PositionManagerUpdate { address, bool }` is selected; `src/config-engine/IAaveV4ConfigEngine.sol::PositionManagerUpdate { ISpokeConfigurator, address, address, bool }` is not in `include` and is not imported by the selected file, but is collected by the AST walk anyway and triggers `HHE818`.
- Forge `bind-json` does not have this divergence — its include scope is `include` + Solidity-import closure, so `src/config-engine` is invisible.
- Failing tests: latent under published Hardhat (masked by 3a); under the locally-patched build with 3a bypassed, all 1939 tests are blocked at the EIP-712 collection stage. The concrete tests that depend on the registered `PositionManagerUpdate` type — `tests/contracts/spoke/libraries/EIP712Hash.t.sol:28,93` and `tests/contracts/spoke/position-manager/Spoke.SetUserPositionManagerWithSig.t.sol:93` — pass under Forge today.
- Local report: [`bugs/eip712-name-collision-from-non-included-sources.md`](bugs/eip712-name-collision-from-non-included-sources.md) — includes a self-contained minimal repro (three files + minimal `hardhat.config.ts`) and two fix shapes ((1) drop unselected conflicts in `canonicalize.ts:indexByName`; (2) narrow the AST walk to `include`'s import closure, Forge-equivalent). Layer: Hardhat (not EDR).
- Status: not yet filed upstream. Project-side workaround would be renaming `IAaveV4ConfigEngine.PositionManagerUpdate` (structurally distinct from the spoke/test copies; renaming has no semantic-equivalence risk). Not applied — would mask the upstream divergence.

## 4. Workarounds Applied

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

## 5. Next Steps

1. **File the build-info `ERR_STRING_TOO_LONG` bug upstream** ([local report](bugs/inline-config-build-info-string-too-long.md)) — single highest-impact item; blocks every test from running. The local report includes a verified prototype fix (`findJsonObjectEntries` slicer in `hardhat-utils/bytes.ts`, ~330 LOC + 14 unit tests) that the upstream team could adopt directly. Two call sites (`collectRawOverrides`, `collectEip712CanonicalTypes`) need the same treatment.
2. **File the EIP-712 include-scope bug upstream** ([local report](bugs/eip712-name-collision-from-non-included-sources.md)) — second blocker, latent until item 1 is fixed but it's a real one. The report includes a minimal three-file repro and two fix shapes (`canonicalize.ts` drop-unselected, or import-closure-scoped walk). Filing alongside item 1 keeps both bugs visible to the same maintainers.
3. **Re-run the migration after both bugs are fixed** — every other gap (gas-value divergence, contract-level inline config, ABI/binding scripts) is a "test-runner-works-but" gap; none can be re-verified until the runner starts. The previous report at `f729aef` (1559 passing tests under `3.5.0`) is the most recent green baseline; expect a similar pass-count after the upstream patches land.
4. **Track contract-level inline `forge-config:` support** — Hardhat 3.5.x closed function-level support, but contract-level remains unimplemented. 9 files in this project rely on contract-level directives. Until upstream support lands, the global `allowInternalExpectRevert: true` workaround remains; `isolate` cannot be promoted to global without a major performance regression.
5. **Replace `rs:bind` / `rs:abis` scripts (Low impact)** — `forge bind --alloy` and `forge build --extra-output-files abi` have no direct Hardhat equivalent. Either keep them on Forge (both toolchains can coexist) or write a custom script that extracts ABIs from Hardhat's `artifacts/<Contract>.sol/<Contract>.json` output.
