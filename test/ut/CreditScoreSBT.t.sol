// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {CreditScoreSBT} from "../../src/tokens/CreditScoreSBT.sol";
import {Errors} from "../../src/utils/Errors.sol";

contract CreditScoreSBTTest is Test {
    CreditScoreSBT internal sbt;

    address internal owner = address(this);
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);

    event ScoreMinted(address indexed user, uint256 indexed tokenId, uint16 initialScore);
    event ScoreUpdated(address indexed user, uint16 oldScore, uint16 newScore);

    function setUp() public {
        sbt = new CreditScoreSBT(owner);
    }

    // =========================================================================
    // Constructor
    // =========================================================================

    function test_constructor_setsOwner() public view {
        assertEq(sbt.owner(), owner);
    }

    function test_constructor_setsTokenMetadata() public view {
        assertEq(sbt.name(), "CreditScore");
        assertEq(sbt.symbol(), "CSCORE");
    }

    function test_constructor_initializesNextTokenId() public view {
        assertEq(sbt.nextTokenId(), 1);
    }

    // =========================================================================
    // hasToken
    // =========================================================================

    function test_hasToken_returnsFalse_whenNoToken() public view {
        assertFalse(sbt.hasToken(alice));
        assertFalse(sbt.hasToken(bob));
    }

    function test_hasToken_returnsTrue_afterMint() public {
        sbt.mintIfNeeded(alice, 500);
        assertTrue(sbt.hasToken(alice));
    }

    function test_hasToken_canBeCalledByAnyone() public {
        sbt.mintIfNeeded(alice, 500);

        vm.prank(bob);
        assertTrue(sbt.hasToken(alice));
    }

    // =========================================================================
    // tokenOf
    // =========================================================================

    function test_tokenOf_returnsZero_whenNoToken() public view {
        assertEq(sbt.tokenOf(alice), 0);
    }

    function test_tokenOf_returnsTokenId_afterMint() public {
        sbt.mintIfNeeded(alice, 500);
        assertEq(sbt.tokenOf(alice), 1);
    }

    // =========================================================================
    // scoreOf
    // =========================================================================

    function test_scoreOf_returnsZero_whenNoToken() public view {
        assertEq(sbt.scoreOf(alice), 0);
    }

    function test_scoreOf_returnsScore_afterMint() public {
        sbt.mintIfNeeded(alice, 750);
        assertEq(sbt.scoreOf(alice), 750);
    }

    function test_scoreOf_canBeCalledByAnyone() public {
        sbt.mintIfNeeded(alice, 800);

        vm.prank(bob);
        assertEq(sbt.scoreOf(alice), 800);
    }

    // =========================================================================
    // mintIfNeeded
    // =========================================================================

    function test_mintIfNeeded_onlyOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        sbt.mintIfNeeded(bob, 500);
    }

    function test_mintIfNeeded_revertsOnZeroAddress() public {
        vm.expectRevert(Errors.InvalidAddress.selector);
        sbt.mintIfNeeded(address(0), 500);
    }

    function test_mintIfNeeded_mintsNewToken() public {
        vm.expectEmit(true, true, false, true);
        emit ScoreMinted(alice, 1, 600);

        uint256 tokenId = sbt.mintIfNeeded(alice, 600);

        assertEq(tokenId, 1);
        assertEq(sbt.tokenOf(alice), 1);
        assertEq(sbt.scoreOf(alice), 600);
        assertEq(sbt.ownerOf(1), alice);
        assertEq(sbt.balanceOf(alice), 1);
        assertEq(sbt.nextTokenId(), 2);
    }

    function test_mintIfNeeded_incrementsTokenId() public {
        uint256 tokenId1 = sbt.mintIfNeeded(alice, 500);
        uint256 tokenId2 = sbt.mintIfNeeded(bob, 600);

        assertEq(tokenId1, 1);
        assertEq(tokenId2, 2);
        assertEq(sbt.nextTokenId(), 3);
    }

    function test_mintIfNeeded_returnsExistingTokenId_ifAlreadyMinted() public {
        uint256 tokenId1 = sbt.mintIfNeeded(alice, 500);
        uint256 tokenId2 = sbt.mintIfNeeded(alice, 999);

        assertEq(tokenId1, tokenId2);
        assertEq(sbt.balanceOf(alice), 1);
        assertEq(sbt.scoreOf(alice), 500); // score unchanged
        assertEq(sbt.nextTokenId(), 2);
    }

    // =========================================================================
    // setScore
    // =========================================================================

    function test_setScore_onlyOwner() public {
        sbt.mintIfNeeded(alice, 500);

        vm.prank(bob);
        vm.expectRevert();
        sbt.setScore(alice, 600);
    }

    function test_setScore_revertsOnZeroAddress() public {
        vm.expectRevert(Errors.InvalidAddress.selector);
        sbt.setScore(address(0), 500);
    }

    function test_setScore_updatesScore() public {
        sbt.mintIfNeeded(alice, 500);

        vm.expectEmit(true, false, false, true);
        emit ScoreUpdated(alice, 500, 750);

        sbt.setScore(alice, 750);
        assertEq(sbt.scoreOf(alice), 750);
    }

    function test_setScore_autoMintsIfNoToken() public {
        vm.expectEmit(true, true, false, true);
        emit ScoreMinted(alice, 1, 800);

        vm.expectEmit(true, false, false, true);
        emit ScoreUpdated(alice, 0, 800);

        sbt.setScore(alice, 800);

        assertTrue(sbt.hasToken(alice));
        assertEq(sbt.tokenOf(alice), 1);
        assertEq(sbt.scoreOf(alice), 800);
        assertEq(sbt.ownerOf(1), alice);
    }

    function test_setScore_canSetToZero() public {
        sbt.mintIfNeeded(alice, 500);
        sbt.setScore(alice, 0);
        assertEq(sbt.scoreOf(alice), 0);
    }

    function test_setScore_canSetToMax() public {
        sbt.mintIfNeeded(alice, 500);
        sbt.setScore(alice, type(uint16).max);
        assertEq(sbt.scoreOf(alice), type(uint16).max);
    }

    // =========================================================================
    // Soulbound: transfers disabled
    // =========================================================================

    function test_transfer_reverts() public {
        sbt.mintIfNeeded(alice, 500);

        vm.prank(alice);
        vm.expectRevert(Errors.Unauthorized.selector);
        sbt.transferFrom(alice, bob, 1);
    }

    function test_safeTransfer_reverts() public {
        sbt.mintIfNeeded(alice, 500);

        vm.prank(alice);
        vm.expectRevert(Errors.Unauthorized.selector);
        sbt.safeTransferFrom(alice, bob, 1);
    }

    function test_safeTransferWithData_reverts() public {
        sbt.mintIfNeeded(alice, 500);

        vm.prank(alice);
        vm.expectRevert(Errors.Unauthorized.selector);
        sbt.safeTransferFrom(alice, bob, 1, "");
    }

    // =========================================================================
    // Soulbound: approvals disabled
    // =========================================================================

    function test_approve_reverts() public {
        sbt.mintIfNeeded(alice, 500);

        vm.prank(alice);
        vm.expectRevert(Errors.Unauthorized.selector);
        sbt.approve(bob, 1);
    }

    function test_setApprovalForAll_reverts() public {
        vm.prank(alice);
        vm.expectRevert(Errors.Unauthorized.selector);
        sbt.setApprovalForAll(bob, true);
    }
}

