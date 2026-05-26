# `vm.eip712HashStruct` registry rejects a selected struct when an **unrelated, non-included** source defines a same-named struct with a different shape

## Summary

When `test.solidity.eip712Types.include` lists a Solidity file as the source of EIP-712 type definitions, users reasonably expect that to bound the cheatcode registry — only structs in that file (and its Solidity-import closure) should populate `eipCanonicalTypes`, and only conflicts between those structs should matter.

Hardhat does **not** scope the AST walk that way. `collectEip712CanonicalTypes` (`solidity-test/eip712/index.ts:57`) iterates every source of every build info and `collected.push(...structs)` unconditionally. `include`/`exclude` only filters which struct **names** are added to `selectedNames` for emit-time selection. As a result, `canonicalize.ts:indexByName` sees every project struct, and a selected struct's name colliding with a same-named struct in an unrelated, non-included file throws `HHE818` — even though the user has explicitly told Hardhat not to consider that other file.

This is a **structural divergence from Forge `bind-json`**, which walks `include` plus the Solidity-import closure of `include`'d files. A struct in `src/x/Y.sol` that is neither in `include` nor imported (transitively) by any `include`'d file is simply invisible to Forge — and to the tests that compile against the Forge-generated `JsonBindings.sol`.

Distinct from [`inline-config-build-info-string-too-long.md`](./inline-config-build-info-string-too-long.md): different code path (`collectEip712CanonicalTypes` vs `collectRawOverrides`), different failure mode (deliberate HHE818 throw vs ERR_STRING_TOO_LONG crash), different project-side workaround (rename one of the structs vs. split build infos).

## Where

- File: `packages/hardhat/src/internal/builtin-plugins/solidity-test/eip712/index.ts`
- Lines 91–116 (after our streaming-slice rewrite, but the underlying semantics existed pre-rewrite):

  ```ts
  for (const [inputSourceName, source] of sources) {
    let userSourceName = inputToUserSource.get(inputSourceName);
    // … recover userSourceName …

    // Collect every source so non-selected files can serve as dep targets;
    // selection is enforced at emit time via `selectedNames`.
    const structs = extractStructsFromAst(
      source.ast,
      userSourceName,
      userDefinedValueTypeI,
    );
    collected.push(...structs);

    if (isPathSelected(userSourceName, include, exclude)) {
      for (const s of structs) {
        selectedNames.add(s.name);
      }
    }
  }
  ```

  The `collected.push(...structs)` happens for every source. Only `selectedNames.add(...)` is gated by `isPathSelected`.

- Conflict detection: `packages/hardhat/src/internal/builtin-plugins/solidity-test/eip712/canonicalize.ts:216-249`

  ```ts
  for (const struct of ordered) {
    const fingerprint = fingerprintStruct(struct);
    const existingFingerprint = fingerprintByName.get(struct.name);

    if (existingFingerprint === undefined) {
      byName.set(struct.name, struct);
      fingerprintByName.set(struct.name, fingerprint);
      // …
      continue;
    }

    if (existingFingerprint === fingerprint) {
      continue;
    }

    if (!selectedNames.has(struct.name)) {
      // … deferred …
      continue;
    }

    throw new HardhatError(
      HardhatError.ERRORS.CORE.SOLIDITY_TESTS.EIP712_DUPLICATE_STRUCT_NAME,
      { name: struct.name, … },
    );
  }
  ```

  The immediate throw fires whenever a struct's name **is** in `selectedNames` and a previously-seen definition (which may live in an unselected file) had a different fingerprint. The "different fingerprint" check is name-keyed and source-blind.

## Observed error (on aave-v4 `hh3-migration-v2`)

```
Error HHE818: Two different EIP-712 struct definitions named "PositionManagerUpdate" were found:
- src/config-engine/interfaces/IAaveV4ConfigEngine.sol
- src/spoke/interfaces/ISpoke.sol

EIP-712 cheatcodes resolve types by name, so each struct name must have a single canonical definition. Rename one of the structs, or scope your `test.solidity.eip712Types.include` / `exclude` globs in `hardhat.config.ts` to only one of them.
```

The user's `hardhat.config.ts` has:

```ts
test: {
  solidity: {
    eip712Types: { include: ["tests/helpers/mocks/EIP712Types.sol"] },
  },
},
```

Neither `src/config-engine/interfaces/IAaveV4ConfigEngine.sol` nor `src/spoke/interfaces/ISpoke.sol` is in `include`, nor is either imported by `tests/helpers/mocks/EIP712Types.sol` (the file is a self-contained struct re-declaration mock — zero imports).

## How Forge handles the same situation

`foundry.toml`:

```toml
[bind_json]
out = "tests/helpers/mocks/JsonBindings.sol"
include = ["tests/helpers/mocks/EIP712Types.sol"]
```

`forge bind-json` produces `tests/helpers/mocks/JsonBindings.sol` containing exactly one definition for the conflicting name:

```solidity
string constant schema_PositionManagerUpdate = "PositionManagerUpdate(address positionManager,bool approve)";
```

No `_0` / `_1` suffix, no other definition included. The fingerprint matches the test-mock copy (and, coincidentally, the `ISpoke.sol` copy). The `IAaveV4ConfigEngine.sol` copy (with a structurally different `{ ISpokeConfigurator, address, address, bool }` shape) is simply not in scope because the included file imports nothing from `src/`.

Tests using `vm.eip712HashStruct('PositionManagerUpdate', …)` therefore work under Forge — there is no ambiguity from Forge's perspective.

## Environment

| | |
|---|---|
| Hardhat | `3.5.1` and **`3.6.0`** (just released; reproduces byte-identically once the streaming-string bug is bypassed) |
| EDR | `@nomicfoundation/edr@0.12.0-next.33` (unchanged between `3.5.1` and `3.6.0`) |
| Node.js | `v22.x` |
| OS | Linux 6.10 (devcontainer) |
| Project | `aave/aave-v4`, branch `hh3-migration-v2` @ `e141a05` |
| Forge | as of the checked-in `tests/helpers/mocks/JsonBindings.sol` (regenerated by the project's `forge bind-json` flow) |

## Steps to reproduce (real project)

```bash
git clone https://github.com/aave/aave-v4.git
cd aave-v4
git checkout hh3-migration-v2  # at commit e141a05
yarn install --ignore-scripts
# `hardhat.config.ts` already sets eip712Types.include = ["tests/helpers/mocks/EIP712Types.sol"]
npx hardhat compile
npx hardhat test solidity
# → Error HHE818: Two different EIP-712 struct definitions named "PositionManagerUpdate"
```

Note: requires also having the unrelated `ERR_STRING_TOO_LONG` bug fixed (e.g., via the `findJsonObjectEntries` slicer), otherwise the run aborts earlier from the other bug.

## Minimal reproduction

```
project/
  hardhat.config.ts
  contracts/
    A.sol           ← included
    B.sol           ← NOT included, NOT imported by A.sol
  tests/
    Foo.t.sol       ← uses vm.eip712HashStruct('Order', ...)
```

`contracts/A.sol` (the only file in `eip712Types.include`):

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

library A {
    struct Order { address user; uint256 amount; }
}
```

`contracts/B.sol` (deliberately unrelated — nothing imports it from A.sol or Foo.t.sol; lives in a completely different feature area):

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

contract B {
    struct Order { bytes32 id; bool active; }
}
```

`tests/Foo.t.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";

contract FooTest is Test {
    function test_orderHash() external view {
        A.Order memory o = A.Order({ user: address(this), amount: 1 });
        bytes32 h = vm.eip712HashStruct("Order", abi.encode(o));
        assertEq(h.length, 32);
    }
}
```

`hardhat.config.ts`:

```ts
import { defineConfig } from "hardhat/config";

export default defineConfig({
  paths: { sources: "./contracts", tests: "./tests" },
  solidity: {
    compilers: [
      { version: "0.8.28", settings: { evmVersion: "cancun" } },
    ],
  },
  test: {
    solidity: {
      eip712Types: { include: ["contracts/A.sol"] },
    },
  },
});
```

Both `A.sol` and `B.sol` end up in the same build info (default compiler settings). `npx hardhat test solidity` fails with `HHE818: Two different EIP-712 struct definitions named "Order"`. Removing `B.sol` makes the test pass. Adding `B.sol` back under a *different* compiler profile (separate build info) still fails — the collector walks all build infos.

The same test under Forge with `[bind_json] include = ["contracts/A.sol"]` succeeds: `bind-json` only walks `A.sol`'s import closure, so `B.sol::Order` is never seen.

## Expected vs actual

| | Expected (Forge-equivalent) | Actual |
|---|---|---|
| Scope of AST walk for EIP-712 type collection | `include`'d files + their Solidity-import closure | every compiled source in every build info |
| Conflict detection scope | among structs reachable from `include` | among all collected structs, name-keyed |
| `Order` defined in unincluded, unimported `B.sol` | invisible to the EIP-712 registry; no error | counted in `byName`; triggers `HHE818` when its fingerprint differs from `A.Order` |
| Project-side fix | scope `include` correctly (already done) | also have to ensure no struct *anywhere in the codebase* shares a name with a selected struct (or rename) |

## Which test(s) fail (in aave-v4)

All Solidity tests — the throw happens during `collectEip712CanonicalTypes`, before any test runs.

Concrete tests that *would* have used the registered `PositionManagerUpdate` type if the run had proceeded:

- `tests/contracts/spoke/libraries/EIP712Hash.t.sol:28` — `vm.eip712HashType('PositionManagerUpdate')`
- `tests/contracts/spoke/libraries/EIP712Hash.t.sol:93` — `vm.eip712HashStruct('PositionManagerUpdate', abi.encode(params))`
- `tests/contracts/spoke/position-manager/Spoke.SetUserPositionManagerWithSig.t.sol:93` — `vm.eip712HashType('PositionManagerUpdate')`

These tests pass under Forge.

## Suggested fix direction

Two viable shapes, in increasing order of behavioral change:

1. **Scope the conflict-detection set to `include`'d files (smallest behavior change).** Leave the AST walk untouched (it still feeds the `byName` index for cross-file user-defined value type resolution, per the existing `eip712/index.ts:102-115` comment), but change `canonicalize.ts:indexByName` so that the first-wins definition is always a definition from a *selected* file. Concretely, do the two-pass walk that's already there (`ordered = [...selected, ...unselected]`), then **drop** unselected definitions that conflict with a previously-seen selected one rather than throwing. Throw only if two **selected** definitions conflict, or if an unselected definition is `reachable` (per the existing `reachableFromSelected` machinery) from a selected one.

   Effect: `A.Order` would be the canonical `Order`; `B.Order` would be silently ignored because it's not in `include` and nothing in `include` depends on it.

2. **Match Forge's import-closure scoping (closer behavioral match to `bind-json`).** Compute the import closure of `include` (via the project's `remappings.txt` + Solidity import resolution), then only feed *that* set of sources into `extractStructsFromAst`. Files outside the closure don't get walked at all. Cheaper at parse time on large projects and exactly mirrors what `bind-json` does.

   Caveat: this changes the user-defined value type index too. If a selected struct's member references a UDVT defined in an unselected, unimported file, that reference becomes unresolved. In practice this is the same constraint Solidity itself imposes (the import has to exist for the type to be in scope), so it shouldn't bite real code — but it's a stricter invariant than option 1.

   Existing comment in `eip712/index.ts:108-115` is specifically about the UDVT case ("a struct member's `referencedDeclaration` can point at a user-defined value type defined in any source within the same compilation"). That comment defends walking the whole build info. Option 2 narrows it to the include closure within the build info, which still covers any case where the type is *actually reachable* from a selected struct.

Either fix preserves the existing protection against same-named structs colliding **within** the user's selected set — which is the legitimate ambiguity worth catching.

## Workaround (project-side)

Rename `PositionManagerUpdate` in `src/config-engine/interfaces/IAaveV4ConfigEngine.sol`. It is structurally distinct from the spoke / test-mock copy (different field set, different purpose: configuration update vs. spoke-level position-manager assignment), so renaming it has no semantic-equivalence risk. Forge runs would be unaffected because Forge never looks at that file in the first place.

The workaround is **not applied** in this dry-run — leaving the failure visible so the upstream bug remains diagnosable.

## Layer

Pure Hardhat (test-runner plugin), not EDR. The throw originates in `solidity-test/eip712/canonicalize.ts` before EDR is invoked.
