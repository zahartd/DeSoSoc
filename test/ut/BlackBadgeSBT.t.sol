// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {BlackBadgeSBT} from "../../src/tokens/BlackBadgeSBT.sol";
import {Errors} from "../../src/utils/Errors.sol";

contract BlackBadgeSBTTest is Test {
    BlackBadgeSBT internal sbt;

    address internal owner = address(this);
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);

    event BadgeMinted(address indexed user, uint256 indexed tokenId);

    function setUp() public {
        sbt = new BlackBadgeSBT(owner);
    }

    // =========================================================================
    // Constructor
    // =========================================================================

    function test_constructor_setsOwner() public view {
        assertEq(sbt.owner(), owner);
    }

    function test_constructor_setsTokenMetadata() public view {
        assertEq(sbt.name(), "BlackBadge");
        assertEq(sbt.symbol(), "BBADGE");
    }

    function test_constructor_initializesNextTokenId() public view {
        assertEq(sbt.nextTokenId(), 1);
    }

    // =========================================================================
    // hasBadge
    // =========================================================================

    function test_hasBadge_returnsFalse_whenNoBadge() public view {
        assertFalse(sbt.hasBadge(alice));
        assertFalse(sbt.hasBadge(bob));
    }

    function test_hasBadge_returnsTrue_afterMint() public {
        sbt.mintBadge(alice);
        assertTrue(sbt.hasBadge(alice));
    }

    function test_hasBadge_canBeCalledByAnyone() public {
        sbt.mintBadge(alice);

        vm.prank(bob);
        assertTrue(sbt.hasBadge(alice));

        vm.prank(alice);
        assertTrue(sbt.hasBadge(alice));
    }

    // =========================================================================
    // mintBadge
    // =========================================================================

    function test_mintBadge_onlyOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        sbt.mintBadge(bob);
    }

    function test_mintBadge_revertsOnZeroAddress() public {
        vm.expectPartialRevert(Errors.InvalidAddress.selector);
        sbt.mintBadge(address(0));
    }

    function test_mintBadge_mintsNewToken() public {
        vm.expectEmit(true, true, false, false);
        emit BadgeMinted(alice, 1);

        uint256 tokenId = sbt.mintBadge(alice);

        assertEq(tokenId, 1);
        assertEq(sbt.tokenIdOf(alice), 1);
        assertEq(sbt.ownerOf(1), alice);
        assertEq(sbt.balanceOf(alice), 1);
        assertEq(sbt.nextTokenId(), 2);
    }

    function test_mintBadge_incrementsTokenId() public {
        uint256 tokenId1 = sbt.mintBadge(alice);
        uint256 tokenId2 = sbt.mintBadge(bob);

        assertEq(tokenId1, 1);
        assertEq(tokenId2, 2);
        assertEq(sbt.nextTokenId(), 3);
    }

    function test_mintBadge_returnsExistingTokenId_ifAlreadyMinted() public {
        uint256 tokenId1 = sbt.mintBadge(alice);
        uint256 tokenId2 = sbt.mintBadge(alice);

        assertEq(tokenId1, tokenId2);
        assertEq(sbt.balanceOf(alice), 1);
        assertEq(sbt.nextTokenId(), 2);
    }

    // =========================================================================
    // tokenIdOf
    // =========================================================================

    function test_tokenIdOf_returnsZero_whenNoBadge() public view {
        assertEq(sbt.tokenIdOf(alice), 0);
    }

    function test_tokenIdOf_returnsTokenId_afterMint() public {
        sbt.mintBadge(alice);
        assertEq(sbt.tokenIdOf(alice), 1);
    }

    // =========================================================================
    // Soulbound: transfers disabled
    // =========================================================================

    function test_transfer_reverts() public {
        sbt.mintBadge(alice);

        vm.prank(alice);
        vm.expectRevert(Errors.Unauthorized.selector);
        sbt.transferFrom(alice, bob, 1);
    }

    function test_safeTransfer_reverts() public {
        sbt.mintBadge(alice);

        vm.prank(alice);
        vm.expectRevert(Errors.Unauthorized.selector);
        sbt.safeTransferFrom(alice, bob, 1);
    }

    function test_safeTransferWithData_reverts() public {
        sbt.mintBadge(alice);

        vm.prank(alice);
        vm.expectRevert(Errors.Unauthorized.selector);
        sbt.safeTransferFrom(alice, bob, 1, "");
    }

    // =========================================================================
    // Soulbound: approvals disabled
    // =========================================================================

    function test_approve_reverts() public {
        sbt.mintBadge(alice);

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
