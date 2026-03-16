import { configVariable, defineConfig } from "hardhat/config";
import hardhatVerify from "@nomicfoundation/hardhat-verify";

// Shared base compiler settings (DRY across profiles)
const baseCompilerSettings = {
  optimizer: { enabled: true, runs: 444_444_444_444 },
  evmVersion: "cancun" as const,
  metadata: { bytecodeHash: "none" as const },
};

export default defineConfig({
  plugins: [hardhatVerify],

  paths: {
    sources: "./src",
    tests: "./tests",
  },

  solidity: {
    profiles: {
      default: {
        compilers: [
          {
            version: "0.8.28",
            settings: baseCompilerSettings,
          },
        ],
        overrides: {
          // Hub profile: via_ir = true, optimizer_runs = 22300
          "src/hub/Hub.sol": {
            version: "0.8.28",
            settings: {
              ...baseCompilerSettings,
              optimizer: { enabled: true, runs: 22_300 },
              viaIR: true,
            },
          },
          // Spoke profile: via_ir = true, optimizer_runs = 750
          "src/spoke/instances/SpokeInstance.sol": {
            version: "0.8.28",
            settings: {
              ...baseCompilerSettings,
              optimizer: { enabled: true, runs: 750 },
              viaIR: true,
            },
          },
          // Tests profile: via_ir = false, optimizer_runs = 444444444444
          // TODO: Foundry uses glob `tests/**` for compilation_restrictions.
          //       Hardhat does not support glob patterns in overrides.
          //       See: https://github.com/NomicFoundation/hardhat/issues/4686
          //       Individual test files would need to be listed here.
          //       Omitting since the default profile already uses these same settings (sans viaIR which defaults to false).
        },
      },

      // Coverage profile: same optimizer settings, via_ir = false, no additional_compiler_profiles
      coverage: {
        compilers: [
          {
            version: "0.8.28",
            settings: {
              ...baseCompilerSettings,
              // via_ir explicitly false for coverage (same as default)
            },
          },
        ],
        // No overrides — coverage profile clears additional_compiler_profiles and compilation_restrictions
      },
    },
  },

  test: {
    solidity: {
      // Fuzz settings from [profile.default.fuzz]
      fuzz: {
        runs: 1000,
        seed: "0x640",
      },
      // TODO: [profile.pr.fuzz] runs=5000 and [profile.ci.fuzz] runs=10000 have no Hardhat build profile
      // equivalent — Hardhat profiles only cover compiler settings, not test settings.
      // Use env vars or CLI args to override fuzz runs in CI.

      // fs_permissions: read access to tests/mocks/JsonBindings.sol
      fsPermissions: {
        readFile: ["./tests/mocks/JsonBindings.sol"],
      },

      // gas_limit = 1099511627776 (must be bigint)
      gasLimit: 1099511627776n,

      // allow_internal_expect_revert — needed for tests using forge-config inline override
      // (inline config is silently ignored by Hardhat: https://github.com/NomicFoundation/hardhat/issues/7355)
      // Setting globally since per-test overrides aren't supported
      allowInternalExpectRevert: true,
    },
  },

  networks: {
    mainnet: { type: "http", chainId: 1, url: configVariable("RPC_MAINNET") },
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
      url: configVariable("RPC_HARMONY"),
    },
    metis: { type: "http", chainId: 1088, url: configVariable("RPC_METIS") },
    base: { type: "http", chainId: 8453, url: configVariable("RPC_BASE") },
    zkevm: { type: "http", chainId: 1101, url: configVariable("RPC_ZKEVM") },
    gnosis: { type: "http", chainId: 100, url: configVariable("RPC_GNOSIS") },
    bnb: { type: "http", chainId: 56, url: configVariable("RPC_BNB") },
    celo: { type: "http", chainId: 42220, url: configVariable("RPC_CELO") },
  },

  // Etherscan verification — Hardhat 3 uses Etherscan API v2 which requires a single API key
  // for all supported chains. Foundry had per-chain keys (ETHERSCAN_API_KEY_MAINNET, etc.).
  // Consolidate to one key.
  verify: {
    etherscan: {
      apiKey: configVariable("ETHERSCAN_API_KEY"),
    },
  },

  // ============================================================================
  // Foundry-only settings (no Hardhat equivalent)
  // ============================================================================
  // - dynamic_test_linking = true → Foundry-only
  // - gas_snapshot_check = false → Not supported. See: https://github.com/NomicFoundation/hardhat/issues/7769
  // - [profile.gas] (isolate, gas_snapshot_check, test='tests/gas') → Not supported. See: https://github.com/NomicFoundation/hardhat/issues/7769
  // - [bind_json] → Foundry-only (forge bind)
  // - [lint] → Foundry-only (project uses prettier)
  // - out = "out" → Hardhat uses artifacts/ + cache/
  // - libs = ["lib"] → Hardhat resolves lib/ deps via remappings.txt
  // - forge-config: inline test config (isolate, allow_internal_expect_revert, disable_block_gas_limit)
  //   → Silently ignored. See: https://github.com/NomicFoundation/hardhat/issues/7355
  //   Note: disable_block_gas_limit maps to blockGasLimit: false in Hardhat, but only globally — not per-test.
});
