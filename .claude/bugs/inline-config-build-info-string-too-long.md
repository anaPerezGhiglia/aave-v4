# `npx hardhat test solidity` crashes with `ERR_STRING_TOO_LONG` when a build-info output exceeds Node.js's max string length

## Summary

Hardhat 3's solidity-test runner reads each build-info `*.output.json` file into a Node.js string via `bytesToUtf8String(...)` and then `JSON.parse(...)` in **two independent places**:

1. The **inline-config collector** (`collectRawOverrides`) does this for every build info whose bytes contain a `forge-config:` or `hardhat-config:` marker.
2. The **EIP-712 type collector** (`collectEip712CanonicalTypes`) does this for every build info whose bytes contain the substring `struct ` — i.e. effectively every build info in any non-trivial project — whenever `test.solidity.eip712Types.include` is set.

When the build-info output is larger than V8's `String::kMaxLength` (≈ 512 MiB, `0x1fffffe8` UTF-16 code units), `TextDecoder.decode()` throws `RangeError: Cannot create a string longer than 0x1fffffe8 characters` and the whole test run aborts before a single test runs.

The triggers are fast byte scans, so any project with at least one inline `forge-config:` directive OR `eip712Types.include` set AND a build-info output > 512 MiB hits this. Once a project's compilation set is large enough — many test contracts, via_ir, or both — the build-info output reaches that size organically. In our case, the default-profile output is **732 MB** (`732_142_209` bytes) after a recent merge that added ~25k lines of test code.

The two call sites must be fixed together. Patching only the inline-config one leaves the EIP-712 collector as a second crash site — confirmed empirically: a fix to only `inline-config/index.ts` still aborts the runner with the same `ERR_STRING_TOO_LONG`, now thrown from `collectEip712CanonicalTypes`.

## Where

### Call site 1 — inline-config collector

- File: `packages/hardhat/src/internal/builtin-plugins/solidity-test/inline-config/index.ts`
- Lines 152–158 (in `collectRawOverrides`):

  ```ts
  if (!buildInfoContainsInlineConfig(buildInfoAndOutput.buildInfo)) {
    continue;
  }

  const buildInfoOutput: SolidityBuildInfoOutput = JSON.parse(
    bytesToUtf8String(buildInfoAndOutput.output),
  );
  ```

- Pre-check helper: `inline-config/helpers.ts:19` (`buildInfoContainsInlineConfig` — byte scan for `forge-config:` / `hardhat-config:` anywhere in the file). Cheap, no allocation.
- Used downstream for: `output.sources[*].ast` (to walk NatSpec) and `output.contracts[*][*].evm.methodIdentifiers` (to resolve function selectors).

### Call site 2 — EIP-712 type collector

- File: `packages/hardhat/src/internal/builtin-plugins/solidity-test/eip712/index.ts`
- Lines 57–66 (in `collectEip712CanonicalTypes`):

  ```ts
  for (const { buildInfo, output } of buildInfosAndOutputs) {
    // Byte-level fast path: a build info whose source bytes don't contain
    // `struct ` can't define any EIP-712 type, so skip JSON-parsing its output.
    if (!bytesIncludesUtf8String(buildInfo, "struct ")) {
      continue;
    }

    const parsedOutput: SolidityBuildInfoOutput = JSON.parse(
      bytesToUtf8String(output),
    );
  ```

- The `struct ` byte scan is coarse — any Solidity file containing the word `struct` (extremely common) matches, so the fast path almost never skips a real-world build info.
- Used downstream for: `output.sources[*].ast` only (struct walking + user-defined value type indexing). The `output.contracts` half of the build info is never consulted, so >95% of the parsed JSON is discarded after extraction.

### Underlying primitive

- `node_modules/@nomicfoundation/hardhat-utils/src/bytes.ts:59` (`bytesToUtf8String` → `new TextDecoder().decode(bytes)`). One-shot decode, no streaming surface.

## Observed error

Both call sites produce the same `ERR_STRING_TOO_LONG`; only the stack frame above `bytesToUtf8String` differs.

### Call site 1 — inline-config collector

```
Running Solidity tests

An unexpected error occurred:

Error: Cannot create a string longer than 0x1fffffe8 characters
    at TextDecoder.decode (node:internal/encoding:447:16)
    at bytesToUtf8String (.../hardhat-utils/src/bytes.ts:59:28)
    at collectRawOverrides (.../solidity-test/inline-config/index.ts:157:7)
    at getTestFunctionOverrides (.../solidity-test/inline-config/index.ts:55:27)
    at runSolidityTests (.../solidity-test/task-action.ts:234:33)
    ...
  code: 'ERR_STRING_TOO_LONG'
```

### Call site 2 — EIP-712 collector (observed after patching call site 1)

```
Error: Cannot create a string longer than 0x1fffffe8 characters
    at TextDecoder.decode (node:internal/encoding:447:16)
    at bytesToUtf8String (.../hardhat-utils/src/bytes.ts:59:28)
    at collectEip712CanonicalTypes (.../solidity-test/eip712/index.ts:65:21)
    at runSolidityTests (.../solidity-test/task-action.ts:...)
    ...
  code: 'ERR_STRING_TOO_LONG'
```

## Environment

| | |
|---|---|
| Hardhat | `3.5.1` and **`3.6.0`** (just released; reproduces byte-identically — confirmed against published npm) |
| EDR | `@nomicfoundation/edr@0.12.0-next.33` (unchanged between `3.5.1` and `3.6.0`) |
| Node.js | `v22.x` (default in repo devcontainer) |
| OS | Linux 6.10 (devcontainer) |
| Project | `aave/aave-v4`, branch `hh3-migration-v2` @ `e141a05` |
| solc | `0.8.28`, `evm_version = cancun`, `optimizer_runs = 44_444_444`, `viaIR = false` for default profile |
| Build-info output size | `731_669_005` bytes (~698 MiB) for the default profile |

## Steps to reproduce (real project)

```bash
git clone https://github.com/aave/aave-v4.git
cd aave-v4
git checkout hh3-migration-v2  # at commit e141a05
yarn install --ignore-scripts
npx hardhat compile             # succeeds, produces a 698 MiB build-info output
npx hardhat test solidity       # crashes with ERR_STRING_TOO_LONG
```

## Minimal reproduction

A self-contained repro: any project where the resulting build-info output JSON is larger than ~512 MiB AND **either** (a) at least one Solidity source contains a `/// forge-config:` directive (triggers call site 1), **or** (b) `test.solidity.eip712Types.include` is non-empty (triggers call site 2 — and almost any Solidity source containing the word `struct` will pass the byte fast-path). The fastest synthetic way to grow the output past the cap is to compile a large number of contracts with `viaIR: false` and a very high `optimizer.runs`, so the embedded source/bytecode/methodIdentifiers blow up the output JSON.

Minimal `hardhat.config.ts`:

```ts
import { defineConfig } from "hardhat/config";

export default defineConfig({
  paths: { sources: "./src", tests: "./tests" },
  solidity: {
    compilers: [
      {
        version: "0.8.28",
        settings: {
          optimizer: { enabled: true, runs: 444_444_444_444 },
          evmVersion: "cancun",
          metadata: { bytecodeHash: "none" },
        },
      },
    ],
  },
  test: {
    solidity: { allowInternalExpectRevert: true },
  },
});
```

Minimal `tests/Trigger.t.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";

/// forge-config: default.allow_internal_expect_revert = true
contract TriggerTest is Test {
    function test_dummy() external pure { assert(true); }
}
```

…plus enough other test/source files in the same compilation set to push the resulting `artifacts/build-info/solc-*.output.json` past ~512 MiB. (In `aave-v4` this happens naturally with ~290 `.sol` files.)

## Expected vs actual

| | Expected | Actual |
|---|---|---|
| `npx hardhat test solidity` | Inline `forge-config:` directives are extracted and EIP-712 structs are indexed; tests run | `RangeError: ERR_STRING_TOO_LONG` thrown from `collectRawOverrides` or `collectEip712CanonicalTypes`; the test runner aborts before any test runs |
| Build-info AST traversal on >512 MiB output | Either streams/chunks the read, or skips with a warning | Crashes the entire test command |

## Which test(s) fail

All of them — `runSolidityTests` never starts. The crash is at the inline-config collection stage (when `forge-config:` is present) or the EIP-712 collection stage (when `eip712Types.include` is set), depending on which one runs first against the oversized build info.

## Suggested fix direction

The fix must be applied to **both** call sites. The two consumers only ever read a narrow slice of the build-info output:

- `collectRawOverrides` needs `output.sources[*].ast` and `output.contracts[*][*].evm.methodIdentifiers`.
- `collectEip712CanonicalTypes` needs `output.sources[*].ast` only.

Everything else in the output (bytecode, deployedBytecode, gasEstimates, irOptimized, storageLayout, etc.) is discarded immediately after parsing. So whichever fix is chosen, the goal is to extract just those slices without ever materializing the whole output as a single Node string.

Options, in increasing order of effort:

1. **Best-effort fallback (quick unblock — already prototyped).** Wrap each `JSON.parse(bytesToUtf8String(...))` in try/catch. On `ERR_STRING_TOO_LONG`, log a yellow warning and `continue` past that build info. The byte-level pre-checks (`buildInfoContainsInlineConfig`, `bytesIncludesUtf8String("struct ")`) are already no-allocation, so this is a surgical addition. Confirmed working against this project — see "Workaround prototype" below. Drawback: any inline-config directives or EIP-712 struct definitions in the skipped build info are silently lost, and a 181-test failure cluster ensued in this project for that reason.

2. **Hand-rolled targeted slicer.** Write a small Uint8Array-aware JSON scanner that, given a JSON path like `output.sources` or `output.contracts.*.*.evm.methodIdentifiers`, returns the byte ranges of each matching child value. Then `JSON.parse` only those slices (each is well under the 512 MiB cap — a single source's AST is typically 1–50 MiB, methodIdentifiers per contract is < 1 MiB). No new dependency required. The slicer can live in `hardhat-utils` and replace both call sites. ~200–300 lines of tokenizer code plus tests.

3. **Streaming JSON parser via a new dependency.** Replace the read with `fs.createReadStream(buildInfoOutputPath)` piped through `stream-json` (or `@streamparser/json`). The bytes are already on disk; nothing forces them to pass through a single Node string in the first place. Cleanest at the consumer side, but Hardhat currently has **no streaming-JSON dependency** in its tree (confirmed against `pnpm-lock.yaml` on `main`), so this means a new dep — something the contribution guide suggests checking against `hardhat-utils` first.

4. **Don't materialize all output bytes in memory at all.** The current `BuildInfoAndOutput.output: Uint8Array` field is what forces both call sites to operate on the full buffer. Switching to `BuildInfoAndOutput.outputPath: string` (with on-demand streaming reads) sidesteps the 512 MiB ceiling and also reduces peak memory for large projects. Larger refactor, but addresses the root issue.

For reference, Foundry doesn't hit this because it parses inline `forge-config:` directives directly from each source file's tokens during the test pipeline, not from a single aggregated build-info artifact. The Hardhat 3 approach is structurally sounder (the AST is authoritative), but needs to scale to multi-hundred-MB outputs.

## Workaround prototype

A best-effort fallback (option 1 above) has been applied to a local checkout of `hardhat@3.6.0` against this project — diff against `packages/hardhat/src/internal/builtin-plugins/solidity-test/`:

- `inline-config/index.ts`: try/catch around `JSON.parse(bytesToUtf8String(...))`; on `ERR_STRING_TOO_LONG`, emit `Warning: build info X is too large to scan for inline test config (...)` and `continue`.
- `eip712/index.ts`: same shape — `Warning: build info X is too large to scan for EIP-712 struct definitions (...)` and `continue`.

Both warnings include the build-info ID, the exact byte size, and a remediation hint pointing users at `solidity.profiles.<name>.overrides` to split compilation groups.

Test result against this project after the workaround: **1866 passing, 181 failing, 1 skipped** out of 1939 test definitions. All 181 failures are `vm.eip712HashStruct: '<TypeName>' not defined in eip712CanonicalTypes` (Permit, Borrow, Repay, SetUsingAsCollateral, SetUserPositionManagers, etc.) — the direct consequence of skipping EIP-712 indexing for the only build info that contains the project's `tests/helpers/mocks/EIP712Types.sol`. The warning explicitly predicts this failure mode; the project-side fix is to put `EIP712Types.sol` and its struct dependencies under a smaller override.

## Project-side workaround

Aside from patching Hardhat itself, the only project-side options are:

- The `forge-config:` directives in this project are all **contract-level** (e.g. `/// forge-config: default.allow_internal_expect_revert = true` on the contract definition). Hardhat already silently ignores contract-level inline config, so the scan can never extract anything useful from these files — yet it still triggers the read. Removing them would break Forge runs (this is a dual-toolchain dry-run; both must keep working).
- There is no `solidity-test` config flag to disable inline-config scanning or EIP-712 collection.
- Splitting the compilation into smaller build-info groups via `solidity.profiles.default.overrides` does mitigate the issue: if the file containing `forge-config:` directives or EIP-712 structs ends up in a sub-512-MiB build info, that build info parses fine. But it requires per-file overrides with subtly different settings, and it still leaves the bug unfixed for any project whose largest single profile exceeds 512 MiB on its own.

## Layer

Pure Hardhat (test-runner plugin), not EDR. The failure occurs entirely inside the `solidity-test` task-action before any cheatcode / EDR call.
