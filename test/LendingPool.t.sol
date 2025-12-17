// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

import {LendingPool} from "../src/core/LendingPool.sol";
import {RiskEngine} from "../src/modules/RiskEngine.sol";
import {CreditScoreSBT} from "../src/tokens/CreditScoreSBT.sol";
import {BlackBadgeSBT} from "../src/tokens/BlackBadgeSBT.sol";

contract LendingPoolTest is Test {
    address internal admin = address(this);
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);

    ERC20Mock internal token;
    CreditScoreSBT internal scoreSbt;
    BlackBadgeSBT internal badgeSbt;
    RiskEngine internal riskEngine;
    LendingPool internal pool;

    function setUp() public {
        token = new ERC20Mock();

        scoreSbt = new CreditScoreSBT(admin);
        badgeSbt = new BlackBadgeSBT(admin);
        riskEngine = new RiskEngine(address(scoreSbt), address(badgeSbt), 1_000 ether);

        LendingPool impl = new LendingPool();
        bytes memory initData = abi.encodeCall(
            LendingPool.initialize, (admin, address(token), address(riskEngine), address(scoreSbt), address(badgeSbt))
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        pool = LendingPool(address(proxy));

        scoreSbt.transferOwnership(address(pool));
        badgeSbt.transferOwnership(address(pool));

        token.mint(admin, 1_000 ether);
        token.approve(address(pool), type(uint256).max);
        pool.depositLiquidity(1_000 ether);

        token.mint(alice, 1_000 ether);
        vm.prank(alice);
        token.approve(address(pool), type(uint256).max);

        token.mint(bob, 1_000 ether);
        vm.prank(bob);
        token.approve(address(pool), type(uint256).max);
    }

    function test_initialize_setsModules_andOwner() public view {
        assertEq(pool.owner(), admin);
        assertEq(address(pool.token()), address(token));
        assertEq(address(pool.riskEngine()), address(riskEngine));
        assertEq(address(pool.scoreSbt()), address(scoreSbt));
        assertEq(address(pool.badgeSbt()), address(badgeSbt));
    }

    function test_borrow_repay_increasesScore_and_relaxesCollateral() public {
        vm.warp(1_000);

        vm.prank(alice);
        pool.borrow(100 ether, 150 ether, 7 days);

        assertEq(pool.lockedCollateral(), 150 ether);

        vm.prank(alice);
        pool.repay();

        assertEq(scoreSbt.scoreOf(alice), 250);
        assertEq(riskEngine.collateralRatioBps(alice), 10_313);

        vm.prank(alice);
        vm.expectRevert(bytes("LOW_COLLATERAL"));
        pool.borrow(100 ether, 103 ether, 7 days);

        vm.prank(alice);
        pool.borrow(100 ether, 104 ether, 7 days);
    }

    function test_default_marksDefaulter_and_blocksBorrow() public {
        vm.warp(1_000);

        vm.prank(bob);
        pool.borrow(100 ether, 150 ether, 1 days);

        vm.warp(1_000 + 1 days + 1);
        pool.markDefault(bob);

        assertTrue(badgeSbt.hasBadge(bob));
        assertTrue(riskEngine.isDefaulter(bob));

        vm.prank(bob);
        vm.expectRevert(bytes("NOT_ALLOWED"));
        pool.borrow(1 ether, 0, 7 days);
    }

    function test_withdraw_respectsLockedCollateral() public {
        vm.warp(1_000);

        vm.prank(alice);
        pool.borrow(100 ether, 150 ether, 7 days);

        vm.expectRevert(bytes("NO_LIQUIDITY"));
        pool.withdrawLiquidity(901 ether, admin);

        pool.withdrawLiquidity(900 ether, admin);
    }

    function test_zeroCollateralTier_enforcesMaxBorrow() public {
        vm.warp(1_000);

        for (uint256 i = 0; i < 4; i++) {
            vm.prank(alice);
            pool.borrow(10 ether, 15 ether, 7 days);

            vm.prank(alice);
            pool.repay();
        }

        assertEq(scoreSbt.scoreOf(alice), 800);
        assertEq(riskEngine.collateralRatioBps(alice), 0);

        uint256 limit = riskEngine.maxBorrowNoCollateral();

        vm.prank(alice);
        vm.expectRevert(bytes("NOT_ALLOWED"));
        pool.borrow(limit + 1, 0, 7 days);

        vm.prank(alice);
        pool.borrow(limit, 0, 7 days);
    }
}
