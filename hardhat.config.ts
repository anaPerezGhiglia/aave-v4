import { configVariable, defineConfig } from "hardhat/config";
import hardhatVerify from "@nomicfoundation/hardhat-verify";

export default defineConfig({
  plugins: [hardhatVerify],

  paths: {
    // Forge default: src — Hardhat default: ./contracts
    sources: "./src",
    // Forge default: tests — Hardhat default: ./test
    tests: "./tests",
  },

  solidity: {
    // Using profiles because [profile.coverage] has different compiler settings
    // (it resets compilation_restrictions, meaning Hub.sol and SpokeInstance.sol
    //  are compiled without viaIR under the coverage profile).
    profiles: {
      default: {
        compilers: [
          {
            version: "0.8.28",
            settings: {
              optimizer: {
                // Forge default: enabled=true, runs=200
                // Hardhat default: disabled — must set explicitly
                enabled: true,
                runs: 444444444444,
              },
              evmVersion: "cancun",
              viaIR: false,
              metadata: {
                // Foundry: bytecode_hash = "none"
                bytecodeHash: "none",
              },
            },
          },
        ],
        overrides: {
          // Foundry: additional_compiler_profiles hub + compilation_restrictions
          "src/hub/Hub.sol": {
            version: "0.8.28",
            settings: {
              optimizer: { enabled: true, runs: 22300 },
              evmVersion: "cancun",
              viaIR: true,
              metadata: { bytecodeHash: "none" },
            },
          },
          // Foundry: additional_compiler_profiles spoke + compilation_restrictions
          "src/spoke/instances/SpokeInstance.sol": {
            version: "0.8.28",
            settings: {
              optimizer: { enabled: true, runs: 750 },
              evmVersion: "cancun",
              viaIR: true,
              metadata: { bytecodeHash: "none" },
            },
          },
          // TODO: Foundry compilation_restrictions has { paths = "tests/**", optimizer = true, via_ir = false, optimizer_runs = 444444444444 }
          // Hardhat does not support glob patterns in overrides — each file would need to be listed individually.
          // See: https://github.com/NomicFoundation/hardhat/issues/4686
          // The default compiler settings already match (optimizer=true, viaIR=false, runs=444444444444),
          // so this restriction is effectively a no-op for default compilation and is safe to omit.
        },
      },

      // Foundry: [profile.coverage] — resets additional_compiler_profiles and compilation_restrictions,
      // meaning Hub.sol and SpokeInstance.sol are compiled with the default settings (no viaIR).
      // Also: fuzz.runs = 50 (test setting — no Hardhat build profile equivalent; set via CLI or env).
      coverage: {
        compilers: [
          {
            version: "0.8.28",
            settings: {
              optimizer: { enabled: true, runs: 444444444444 },
              evmVersion: "cancun",
              viaIR: false,
              metadata: { bytecodeHash: "none" },
            },
          },
        ],
        // No overrides — matches Foundry's coverage profile which resets compilation_restrictions = []
      },
    },
  },

  test: {
    solidity: {
      // Foundry: fuzz.runs = 1000 (default profile), fuzz.seed = "0x640"
      // Note: [profile.pr.fuzz] runs=5000, [profile.ci.fuzz] runs=10000 — use env vars or CLI args for those
      fuzz: {
        runs: 1000,
        seed: "0x640",
      },

      // Foundry: gas_limit = 1099511627776 (2^40)
      gasLimit: 1099511627776n,

      // Foundry: fs_permissions = [{ access = "read", path = "tests/mocks/JsonBindings.sol" }]
      fsPermissions: {
        readFile: ["tests/mocks/JsonBindings.sol"],
      },

      // Foundry: allow_internal_expect_revert = true (set via forge-config inline comments in 3 files)
      // Hardhat ignores forge-config inline comments (https://github.com/NomicFoundation/hardhat/issues/7355)
      // Setting globally to preserve behavior for AaveOracle.t.sol, KeyValueList.t.sol, MathUtils.t.sol
      allowInternalExpectRevert: true,

      // TODO: Foundry [profile.gas] uses isolate = true for gas tests under tests/gas/.
      // Hardhat supports isolate globally but not per-test-file or per-profile.
      // Gas tests are gated behind [profile.gas] in Forge — they are included in the default test run here.
      // isolate: false  (Hardhat default — leaving unset)

      // TODO: tests/unit/Hub/Hub.Rounding.t.sol uses forge-config: default.disable_block_gas_limit = true
      // No known equivalent in Hardhat 3 (blockGasLimit can be set to a number or false — check if false disables it)
      // blockGasLimit: false  — UNTESTED, left as TODO
    },
  },

  networks: {
    // Foundry: [rpc_endpoints]
    // Note: Hardhat 3 uses Etherscan API v2 with a single API key for all chains.
    // Foundry uses per-chain keys (ETHERSCAN_API_KEY_MAINNET, etc.) — see verify section below.
    mainnet: {
      type: "http",
      chainId: 1,
      url: configVariable("RPC_MAINNET"),
    },
    optimism: {
      type: "http",
      chainId: 10,
      url: configVariable("RPC_OPTIMISM"),
    },
    avalanche: {
      type: "http",
      chainId: 43114,
      url: configVariable("RPC_AVALANCHE"),
    },
    polygon: {
      type: "http",
      chainId: 137,
      url: configVariable("RPC_POLYGON"),
    },
    arbitrum: {
      type: "http",
      chainId: 42161,
      url: configVariable("RPC_ARBITRUM"),
    },
    fantom: {
      type: "http",
      chainId: 250,
      url: configVariable("RPC_FANTOM"),
    },
    harmony: {
      type: "http",
      // chainId not listed in [etherscan] section of foundry.toml — omitted
      url: configVariable("RPC_HARMONY"),
    },
    metis: {
      type: "http",
      chainId: 1088,
      url: configVariable("RPC_METIS"),
    },
    base: {
      type: "http",
      chainId: 8453,
      url: configVariable("RPC_BASE"),
    },
    zkevm: {
      type: "http",
      chainId: 1101,
      url: configVariable("RPC_ZKEVM"),
    },
    gnosis: {
      type: "http",
      chainId: 100,
      url: configVariable("RPC_GNOSIS"),
    },
    bnb: {
      type: "http",
      chainId: 56,
      url: configVariable("RPC_BNB"),
    },
    celo: {
      type: "http",
      chainId: 42220,
      url: configVariable("RPC_CELO"),
    },
  },

  verify: {
    // Foundry [etherscan]: per-chain API keys (ETHERSCAN_API_KEY_MAINNET, ETHERSCAN_API_KEY_OPTIMISM, etc.)
    // Hardhat 3 uses Etherscan API v2 which accepts a single key for all supported chains.
    // Using ETHERSCAN_API_KEY as the unified key — set this to any of the chain-specific keys
    // (they are usually interchangeable for Etherscan v2).
    // TODO: metis uses a custom explorer URL (https://andromeda-explorer.metis.io/) — configure separately if needed.
    etherscan: {
      apiKey: configVariable("ETHERSCAN_API_KEY"),
    },
  },

  // TODO: dynamic_test_linking = true — Foundry-only feature, no Hardhat equivalent
  // TODO: [bind_json] — Foundry-only feature (generates tests/mocks/JsonBindings.sol), no Hardhat equivalent
  // TODO: [lint] — Foundry-only linting; use prettier/solhint instead
  // TODO: gas_snapshot_check = false / [profile.gas] — no Hardhat equivalent
  //   See: https://github.com/NomicFoundation/hardhat/issues/7769
  // TODO: out = "out" — Hardhat uses artifacts/ + cache/ instead
  // TODO: libs = ["lib"] — Hardhat resolves via remappings.txt automatically
});
