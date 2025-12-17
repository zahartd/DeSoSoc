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

    function setUp() public {
        sbt = new CreditScoreSBT(owner);
    }

    function test_mintIfNeeded_mintsOnce() public {
        uint256 tokenId1 = sbt.mintIfNeeded(alice);
        uint256 tokenId2 = sbt.mintIfNeeded(alice);

        assertEq(tokenId1, 1);
        assertEq(tokenId2, 1);
        assertEq(sbt.tokenIdOf(alice), 1);
        assertEq(sbt.ownerOf(1), alice);
        assertEq(sbt.nextTokenId(), 2);
    }

    function test_setScore_mintsAndUpdates() public {
        sbt.setScore(alice, 123);
        assertEq(sbt.scoreOf(alice), 123);
        assertEq(sbt.tokenIdOf(alice), 1);

        sbt.setScore(alice, 456);
        assertEq(sbt.scoreOf(alice), 456);
        assertEq(sbt.tokenIdOf(alice), 1);
    }

    function test_onlyOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        sbt.mintIfNeeded(bob);

        vm.prank(alice);
        vm.expectRevert();
        sbt.setScore(bob, 1);
    }

    function test_soulbound_transfers_and_approvalsRevert() public {
        sbt.mintIfNeeded(alice);

        vm.prank(alice);
        vm.expectRevert(Errors.Unauthorized.selector);
        sbt.transferFrom(alice, bob, 1);

        vm.prank(alice);
        vm.expectRevert(Errors.Unauthorized.selector);
        sbt.approve(bob, 1);
    }
}
