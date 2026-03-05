// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from 'forge-std/Test.sol';
import {VmSafe} from 'forge-std/Vm.sol';

/// @notice Targeted tests to isolate prank-related cheatcode bugs in Hardhat 3 EDR.
///         Each test is designed to pass on Foundry and isolate one specific EDR behaviour.
///         Run with: npx hardhat test -vvv tests/unit/ReadCallersTest.t.sol
contract ReadCallersTest is Test {
  address alice = makeAddr('alice');
  address bob = makeAddr('bob');
  address carol = makeAddr('carol');

  // ───────────────────────────────────────────────────────────
  // Group 1: readCallers basic correctness
  //   Tests that readCallers returns the correct CallerMode enum
  //   values matching the forge-std 5-variant enum:
  //     None=0, Broadcast=1, RecurrentBroadcast=2, Prank=3, RecurrentPrank=4
  // ───────────────────────────────────────────────────────────

  /// @dev readCallers with no prank active should return CallerMode.None (0)
  function test_readCallers_noPrank() public {
    (VmSafe.CallerMode mode, address sender, address origin) = vm.readCallers();
    assertEq(uint(mode), uint(VmSafe.CallerMode.None), 'mode should be None');
    assertTrue(sender != address(0), 'sender should not be zero');
    assertTrue(origin != address(0), 'origin should not be zero');
  }

  /// @dev readCallers inside startPrank(sender) should return RecurrentPrank (4)
  ///      EDR BUG: returns 2 instead of 4 (uses 3-variant enum without Broadcast modes)
  function test_readCallers_startPrank_oneSender() public {
    vm.startPrank(alice);

    (VmSafe.CallerMode mode, address sender, ) = vm.readCallers();

    assertEq(uint(mode), uint(VmSafe.CallerMode.RecurrentPrank), 'mode should be RecurrentPrank (4)');
    assertEq(sender, alice, 'sender should be alice');

    vm.stopPrank();
  }

  /// @dev readCallers inside startPrank(sender, origin) should return both
  ///      EDR BUG: returns mode=2 instead of mode=4
  function test_readCallers_startPrank_senderAndOrigin() public {
    vm.startPrank(alice, bob);

    (VmSafe.CallerMode mode, address sender, address origin) = vm.readCallers();

    assertEq(uint(mode), uint(VmSafe.CallerMode.RecurrentPrank), 'mode should be RecurrentPrank (4)');
    assertEq(sender, alice, 'sender should be alice');
    assertEq(origin, bob, 'origin should be bob');

    vm.stopPrank();
  }

  /// @dev readCallers inside a single prank(sender) should return Prank (3)
  ///      EDR BUG: returns 1 instead of 3
  function test_readCallers_singlePrank() public {
    vm.prank(alice);

    (VmSafe.CallerMode mode, address sender, ) = vm.readCallers();

    assertEq(uint(mode), uint(VmSafe.CallerMode.Prank), 'mode should be Prank (3)');
    assertEq(sender, alice, 'sender should be alice');
  }

  /// @dev readCallers after stopPrank should return None (0)
  function test_readCallers_afterStopPrank() public {
    vm.startPrank(alice);
    vm.stopPrank();

    (VmSafe.CallerMode mode, , ) = vm.readCallers();

    assertEq(uint(mode), uint(VmSafe.CallerMode.None), 'mode should be None after stopPrank');
  }

  // ───────────────────────────────────────────────────────────
  // Group 2: Verify the exact raw enum values returned by EDR
  //   These tests document what EDR actually returns so the
  //   bug can be precisely characterized.
  // ───────────────────────────────────────────────────────────

  /// @dev Confirm the raw uint value for CallerMode during startPrank.
  ///      Foundry: 4 (RecurrentPrank). EDR: expected to return 2.
  function test_rawEnum_startPrank() public {
    vm.startPrank(alice);
    (VmSafe.CallerMode mode, , ) = vm.readCallers();

    // This documents the EDR bug — if EDR returns 2, this passes.
    // On Foundry this would fail because Foundry returns 4.
    // Flip the assertion to match your platform:
    uint raw = uint(mode);
    assertTrue(raw == 2 || raw == 4, 'raw should be 2 (EDR bug) or 4 (Foundry correct)');

    vm.stopPrank();
  }

  /// @dev Confirm the raw uint value for CallerMode during prank.
  ///      Foundry: 3 (Prank). EDR: expected to return 1.
  function test_rawEnum_prank() public {
    vm.prank(alice);
    (VmSafe.CallerMode mode, , ) = vm.readCallers();

    uint raw = uint(mode);
    assertTrue(raw == 1 || raw == 3, 'raw should be 1 (EDR bug) or 3 (Foundry correct)');
  }

  // ───────────────────────────────────────────────────────────
  // Group 3: readCallers stability across multiple calls
  // ───────────────────────────────────────────────────────────

  /// @dev readCallers should return the same values on repeated calls
  function test_readCallers_stableAcrossMultipleCalls() public {
    vm.startPrank(alice);

    for (uint i = 0; i < 5; i++) {
      (VmSafe.CallerMode mode, address sender, ) = vm.readCallers();
      assertEq(uint(mode), uint(VmSafe.CallerMode.RecurrentPrank), string.concat('mode iter ', vm.toString(i)));
      assertEq(sender, alice, string.concat('sender iter ', vm.toString(i)));
    }

    vm.stopPrank();
  }

  /// @dev readCallers should remain correct after external calls are made
  function test_readCallers_stableAcrossExternalCalls() public {
    vm.startPrank(alice);

    _doNothing();

    (VmSafe.CallerMode mode1, address sender1, ) = vm.readCallers();
    assertEq(uint(mode1), uint(VmSafe.CallerMode.RecurrentPrank), 'mode after 1st external call');
    assertEq(sender1, alice, 'sender after 1st external call');

    _doNothing();
    _doNothing();

    (VmSafe.CallerMode mode2, address sender2, ) = vm.readCallers();
    assertEq(uint(mode2), uint(VmSafe.CallerMode.RecurrentPrank), 'mode after more external calls');
    assertEq(sender2, alice, 'sender after more external calls');

    vm.stopPrank();
  }

  // ───────────────────────────────────────────────────────────
  // Group 4: stopPrank effectiveness
  // ───────────────────────────────────────────────────────────

  /// @dev After stopPrank, a single prank() should succeed
  function test_stopPrank_allowsSubsequentPrank() public {
    vm.startPrank(alice);
    vm.stopPrank();

    vm.prank(bob);
    _doNothing();
  }

  /// @dev After stopPrank, a new startPrank should succeed
  function test_stopPrank_allowsSubsequentStartPrank() public {
    vm.startPrank(alice);
    vm.stopPrank();

    vm.startPrank(bob);

    (VmSafe.CallerMode mode, address sender, ) = vm.readCallers();
    assertEq(uint(mode), uint(VmSafe.CallerMode.RecurrentPrank), 'mode should be RecurrentPrank');
    assertEq(sender, bob, 'sender should be bob');

    vm.stopPrank();
  }

  /// @dev The core pausePrank pattern: stop, prank as someone else, restore
  function test_stopPrank_thenPrank_corePattern() public {
    vm.startPrank(alice);

    (VmSafe.CallerMode mode, address sender, address origin) = vm.readCallers();
    assertEq(uint(mode), uint(VmSafe.CallerMode.RecurrentPrank), 'should detect prank');

    vm.stopPrank();

    (VmSafe.CallerMode modeAfter, , ) = vm.readCallers();
    assertEq(uint(modeAfter), uint(VmSafe.CallerMode.None), 'should be None after stop');

    vm.prank(bob);
    _doNothing();

    vm.startPrank(sender, origin);

    (VmSafe.CallerMode modeRestored, address senderRestored, ) = vm.readCallers();
    assertEq(uint(modeRestored), uint(VmSafe.CallerMode.RecurrentPrank), 'should be restored');
    assertEq(senderRestored, alice, 'should be alice again');

    vm.stopPrank();
  }

  // ───────────────────────────────────────────────────────────
  // Group 5: startPrank persistence across calls
  // ───────────────────────────────────────────────────────────

  /// @dev startPrank should persist across multiple external calls
  function test_startPrank_persistsAcrossCalls() public {
    vm.startPrank(alice);

    _doNothing();
    _doNothing();
    _doNothing();
    _doNothing();
    _doNothing();

    (VmSafe.CallerMode mode, address sender, ) = vm.readCallers();
    assertEq(uint(mode), uint(VmSafe.CallerMode.RecurrentPrank), 'prank should persist');
    assertEq(sender, alice, 'sender should still be alice');

    vm.stopPrank();
  }

  /// @dev startPrank should persist across staticcalls
  function test_startPrank_persistsAcrossStaticcalls() public {
    vm.startPrank(alice);

    _viewCall();

    (VmSafe.CallerMode mode, address sender, ) = vm.readCallers();
    assertEq(uint(mode), uint(VmSafe.CallerMode.RecurrentPrank), 'prank should persist after staticcall');
    assertEq(sender, alice);

    vm.stopPrank();
  }

  // ───────────────────────────────────────────────────────────
  // Group 6: prank() vs startPrank() interaction
  // ───────────────────────────────────────────────────────────

  /// @dev A single prank should be consumed after one call
  function test_singlePrank_consumedAfterOneCall() public {
    vm.prank(alice);
    _doNothing();

    (VmSafe.CallerMode mode, , ) = vm.readCallers();
    assertEq(uint(mode), uint(VmSafe.CallerMode.None), 'prank should be consumed');
  }

  /// @dev Switching pranks: stop one, start another, verify readCallers
  function test_switchPranks() public {
    vm.startPrank(alice);
    (VmSafe.CallerMode m1, address s1, ) = vm.readCallers();
    assertEq(uint(m1), uint(VmSafe.CallerMode.RecurrentPrank));
    assertEq(s1, alice);

    vm.stopPrank();
    vm.startPrank(bob);

    (VmSafe.CallerMode m2, address s2, ) = vm.readCallers();
    assertEq(uint(m2), uint(VmSafe.CallerMode.RecurrentPrank));
    assertEq(s2, bob);

    vm.stopPrank();
  }

  // ───────────────────────────────────────────────────────────
  // Group 7: The full pausePrank modifier pattern
  // ───────────────────────────────────────────────────────────

  modifier pausePrank() {
    (VmSafe.CallerMode mode, address sender, address origin) = vm.readCallers();
    if (mode == VmSafe.CallerMode.RecurrentPrank) vm.stopPrank();
    _;
    if (mode == VmSafe.CallerMode.RecurrentPrank) vm.startPrank(sender, origin);
  }

  /// @dev pausePrank with no active prank — should be a no-op
  function test_pausePrank_noPrankActive() public pausePrank {
    vm.prank(bob);
    _doNothing();
  }

  /// @dev pausePrank with active startPrank — the standard pattern
  function test_pausePrank_withActivePrank() public {
    vm.startPrank(alice);
    _helperNeedingDifferentSender();
    vm.stopPrank();
  }

  /// @dev Nested pausePrank — inner helper also uses the modifier
  function test_pausePrank_nested() public {
    vm.startPrank(alice);
    _outerHelper();
    vm.stopPrank();
  }

  /// @dev Multiple sequential pausePrank calls within a startPrank
  function test_pausePrank_repeatedCalls() public {
    vm.startPrank(alice);

    _helperNeedingDifferentSender();

    (VmSafe.CallerMode mode1, address sender1, ) = vm.readCallers();
    assertEq(uint(mode1), uint(VmSafe.CallerMode.RecurrentPrank), 'prank restored after 1st');
    assertEq(sender1, alice, 'alice after 1st');

    _helperNeedingDifferentSender();

    (VmSafe.CallerMode mode2, address sender2, ) = vm.readCallers();
    assertEq(uint(mode2), uint(VmSafe.CallerMode.RecurrentPrank), 'prank restored after 2nd');
    assertEq(sender2, alice, 'alice after 2nd');

    vm.stopPrank();
  }

  // ───────────────────────────────────────────────────────────
  // Group 8: Edge cases — call depth and timing
  // ───────────────────────────────────────────────────────────

  /// @dev readCallers immediately after startPrank, no intervening calls
  function test_readCallers_immediatelyAfterStartPrank() public {
    vm.startPrank(alice);
    (VmSafe.CallerMode mode, address sender, ) = vm.readCallers();
    assertEq(uint(mode), uint(VmSafe.CallerMode.RecurrentPrank));
    assertEq(sender, alice);
    vm.stopPrank();
  }

  /// @dev readCallers after startPrank with one intervening call
  function test_readCallers_afterOneCall() public {
    vm.startPrank(alice);
    _doNothing();
    (VmSafe.CallerMode mode, address sender, ) = vm.readCallers();
    assertEq(uint(mode), uint(VmSafe.CallerMode.RecurrentPrank));
    assertEq(sender, alice);
    vm.stopPrank();
  }

  /// @dev readCallers after startPrank with many intervening calls
  function test_readCallers_afterManyCalls() public {
    vm.startPrank(alice);
    for (uint i = 0; i < 10; i++) {
      _doNothing();
    }
    (VmSafe.CallerMode mode, address sender, ) = vm.readCallers();
    assertEq(uint(mode), uint(VmSafe.CallerMode.RecurrentPrank));
    assertEq(sender, alice);
    vm.stopPrank();
  }

  // ───────────────────────────────────────────────────────────
  // Group 9: Workaround validation — using raw enum comparison
  //   These tests use raw uint comparison to work around the
  //   enum mismatch and verify that the underlying prank
  //   mechanics (stop/start/switch) work correctly in EDR
  //   when the enum issue is bypassed.
  // ───────────────────────────────────────────────────────────

  /// @dev Same as test_stopPrank_thenPrank_corePattern but using raw uint
  ///      to bypass the enum mismatch. If this passes on EDR, the only
  ///      bug is the enum values — stopPrank/startPrank work fine.
  function test_workaround_corePattern_rawEnum() public {
    vm.startPrank(alice);

    (VmSafe.CallerMode mode, address sender, address origin) = vm.readCallers();
    // Accept either 2 (EDR) or 4 (Foundry) as "recurrent prank"
    uint raw = uint(mode);
    assertTrue(raw == 2 || raw == 4, 'should be recurrent prank (2 or 4)');
    assertEq(sender, alice);

    vm.stopPrank();

    (VmSafe.CallerMode modeAfter, , ) = vm.readCallers();
    assertEq(uint(modeAfter), 0, 'should be None after stop');

    vm.prank(bob);
    _doNothing();

    vm.startPrank(sender, origin);
    (VmSafe.CallerMode modeRestored, address senderRestored, ) = vm.readCallers();
    uint rawRestored = uint(modeRestored);
    assertTrue(rawRestored == 2 || rawRestored == 4, 'should be recurrent prank again');
    assertEq(senderRestored, alice);

    vm.stopPrank();
  }

  /// @dev pausePrank modifier using raw uint — bypasses enum mismatch
  modifier pausePrankRaw() {
    (VmSafe.CallerMode mode, address sender, address origin) = vm.readCallers();
    uint raw = uint(mode);
    // 2 = EDR's RecurrentPrank, 4 = Foundry's RecurrentPrank
    bool wasPranking = (raw == 2 || raw == 4);
    if (wasPranking) vm.stopPrank();
    _;
    if (wasPranking) vm.startPrank(sender, origin);
  }

  /// @dev Full pausePrank pattern using raw enum workaround
  function test_workaround_pausePrank_rawEnum() public {
    vm.startPrank(alice);
    _helperRaw();
    vm.stopPrank();
  }

  function _helperRaw() internal pausePrankRaw {
    vm.prank(bob);
    _doNothing();
  }

  /// @dev Nested pausePrank with raw enum workaround
  function test_workaround_pausePrank_nested_rawEnum() public {
    vm.startPrank(alice);
    _outerHelperRaw();
    vm.stopPrank();
  }

  function _outerHelperRaw() internal pausePrankRaw {
    vm.prank(bob);
    _doNothing();
    _innerHelperRaw();
  }

  function _innerHelperRaw() internal pausePrankRaw {
    vm.prank(carol);
    _doNothing();
  }

  // ───────────────────────────────────────────────────────────
  // Helpers
  // ───────────────────────────────────────────────────────────

  Dummy dummy = new Dummy();

  function _doNothing() internal {
    dummy.noop();
  }

  function _viewCall() internal view {
    dummy.viewNoop();
  }

  function _helperNeedingDifferentSender() internal pausePrank {
    vm.prank(bob);
    dummy.noop();
  }

  function _outerHelper() internal pausePrank {
    vm.prank(bob);
    dummy.noop();
    _innerHelper();
  }

  function _innerHelper() internal pausePrank {
    vm.prank(carol);
    dummy.noop();
  }
}

/// @dev Minimal contract to ensure external calls actually happen on-chain
contract Dummy {
  uint public x;

  function noop() external {
    x = x;
  }

  function viewNoop() external view returns (uint) {
    return x;
  }
}
