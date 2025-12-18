// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import {LendingPool} from "../src/core/LendingPool.sol";
import {RiskEngine} from "../src/modules/RiskEngine.sol";
import {InterestModelLinear} from "../src/modules/InterestModelLinear.sol";
import {CreditScoreSBT} from "../src/tokens/CreditScoreSBT.sol";
import {BlackBadgeSBT} from "../src/tokens/BlackBadgeSBT.sol";
import {Errors} from "../src/utils/Errors.sol";

contract LendingPoolV2 is LendingPool {
    function version() external pure returns (uint256) {
        return 2;
    }
}

contract LendingPoolTest is Test {
    address internal admin = address(this);
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);
    address internal treasury = address(0xBEEF);
    address internal keeper = address(0xC0FFEE);

    ERC20Mock internal token;
    CreditScoreSBT internal scoreSbt;
    BlackBadgeSBT internal badgeSbt;
    RiskEngine internal riskEngine;
    InterestModelLinear internal interestModel;
    LendingPool internal pool;

    function setUp() public {
        token = new ERC20Mock();

        scoreSbt = new CreditScoreSBT(admin);
        badgeSbt = new BlackBadgeSBT(admin);
        riskEngine = new RiskEngine(address(scoreSbt), address(badgeSbt), 1_000 ether);
        interestModel = new InterestModelLinear(1000, 2000); // 10% APR, 20% penalty APR

        LendingPool impl = new LendingPool();
        bytes memory initData = abi.encodeCall(
            LendingPool.initialize,
            (
                admin,
                address(token),
                address(riskEngine),
                address(scoreSbt),
                address(badgeSbt),
                address(interestModel),
                treasury
            )
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        pool = LendingPool(address(proxy));

        scoreSbt.transferOwnership(address(pool));
        badgeSbt.transferOwnership(address(pool));

        pool.setFees(1000, 100, treasury); // 10% of interest, 1% origination

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
        assertEq(address(pool.interestModel()), address(interestModel));
        assertEq(pool.treasury(), treasury);
    }

    function test_borrow_repay_increasesScore_and_relaxesCollateral() public {
        vm.warp(1_000);

        uint256 aliceBalBefore = token.balanceOf(alice);

        vm.prank(alice);
        pool.borrow(100 ether, 150 ether, 48 hours);

        assertEq(pool.lockedCollateral(), 150 ether);
        assertEq(token.balanceOf(treasury), 1 ether);
        assertEq(token.balanceOf(alice), aliceBalBefore - 150 ether + 99 ether);

        vm.warp(1_000 + 10 days);
        uint256 debt = pool.getDebt(alice);
        uint256 interestAccrued = debt - 100 ether;
        uint256 expectedProtocolFee = (interestAccrued * pool.protocolFeeBps()) / 10_000;

        vm.prank(alice);
        pool.repay(debt);

        assertEq(token.balanceOf(treasury), 1 ether + expectedProtocolFee);
        assertEq(scoreSbt.scoreOf(alice), 250);
        assertEq(riskEngine.collateralRatioBps(alice), 10_313);

        vm.prank(alice);
        vm.expectPartialRevert(Errors.LowCollateral.selector);
        pool.borrow(100 ether, 103 ether, 48 hours);

        vm.prank(alice);
        pool.borrow(100 ether, 104 ether, 48 hours);
    }

    function test_default_marksDefaulter_and_blocksBorrow() public {
        vm.warp(1_000);

        uint256 collateralAmount = 150 ether;

        vm.prank(bob);
        pool.borrow(100 ether, collateralAmount, 24 hours);

        vm.warp(1_000 + 24 hours + 1);
        vm.prank(keeper);
        vm.expectPartialRevert(Errors.NotPastDue.selector);
        pool.markDefault(bob);

        vm.warp(1_000 + 24 hours + 24 hours + 1);
        uint256 expectedBounty = (collateralAmount * pool.defaultBountyBps()) / 10_000;
        uint256 keeperBalBefore = token.balanceOf(keeper);

        vm.prank(keeper);
        pool.markDefault(bob);

        assertEq(token.balanceOf(keeper), keeperBalBefore + expectedBounty);

        assertTrue(badgeSbt.hasBadge(bob));
        assertTrue(riskEngine.isDefaulter(bob));

        vm.prank(bob);
        vm.expectPartialRevert(Errors.BorrowNotAllowed.selector);
        pool.borrow(1 ether, 0, 48 hours);
    }

    function test_proxyUpgrade_preservesState_and_exposesNewLogic() public {
        vm.expectRevert();
        LendingPoolV2(address(pool)).version();

        vm.warp(1_000);
        vm.prank(alice);
        pool.borrow(100 ether, 150 ether, 48 hours);

        LendingPool.Loan memory loanBefore = pool.getLoan(alice);
        uint256 lockedBefore = pool.lockedCollateral();

        LendingPoolV2 newImpl = new LendingPoolV2();

        vm.prank(alice);
        vm.expectRevert();
        pool.upgradeToAndCall(address(newImpl), "");

        pool.upgradeToAndCall(address(newImpl), "");

        assertEq(LendingPoolV2(address(pool)).version(), 2);
        assertEq(pool.owner(), admin);
        assertEq(pool.lockedCollateral(), lockedBefore);

        LendingPool.Loan memory loanAfter = pool.getLoan(alice);
        assertEq(loanAfter.principal, loanBefore.principal);
        assertEq(loanAfter.collateral, loanBefore.collateral);
        assertEq(loanAfter.repaid, loanBefore.repaid);
        assertEq(loanAfter.start, loanBefore.start);
        assertEq(loanAfter.due, loanBefore.due);
        assertEq(loanAfter.active, loanBefore.active);
    }

    function test_withdraw_respectsLockedCollateral() public {
        vm.warp(1_000);

        vm.prank(alice);
        pool.borrow(100 ether, 150 ether, 48 hours);

        vm.expectPartialRevert(Errors.InsufficientLiquidity.selector);
        pool.withdrawLiquidity(901 ether, admin);

        pool.withdrawLiquidity(900 ether, admin);
    }

    function test_zeroCollateralTier_enforcesMaxBorrow() public {
        vm.warp(1_000);

        for (uint256 i = 0; i < 4; i++) {
            vm.prank(alice);
            pool.borrow(10 ether, 15 ether, 48 hours);

            uint256 debt = pool.getDebt(alice);
            vm.prank(alice);
            pool.repay(debt);
        }

        assertEq(scoreSbt.scoreOf(alice), 800);
        assertEq(riskEngine.collateralRatioBps(alice), 0);

        uint256 limit = riskEngine.MAX_BORROW_NO_COLLATERAL();

        vm.prank(alice);
        vm.expectPartialRevert(Errors.BorrowNotAllowed.selector);
        pool.borrow(limit + 1, 0, 48 hours);

        vm.prank(alice);
        pool.borrow(limit, 0, 48 hours);
    }

    function test_pause_blocksBorrow_and_repay() public {
        vm.warp(1_000);

        pool.pause();

        vm.prank(alice);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        pool.borrow(1 ether, 2 ether, 48 hours);

        pool.unpause();

        vm.prank(alice);
        pool.borrow(10 ether, 15 ether, 48 hours);

        pool.pause();

        uint256 debt = pool.getDebt(alice);
        vm.prank(alice);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        pool.repay(debt);
    }

    function test_borrow_revertsOnInvalidDuration() public {
        vm.warp(1_000);

        vm.prank(alice);
        vm.expectPartialRevert(Errors.InvalidDuration.selector);
        pool.borrow(100 ether, 150 ether, 1 hours);

        vm.prank(alice);
        vm.expectPartialRevert(Errors.InvalidDuration.selector);
        pool.borrow(100 ether, 150 ether, 73 hours);
    }

    function test_ownerCanUpdateConfigInBatch() public {
        vm.warp(1_000);

        vm.prank(alice);
        vm.expectRevert();
        pool.setConfig(
            1000, // scoreIncrement
            1000,
            100,
            treasury,
            50,
            uint32(24 hours),
            300, // scoreFree
            6 hours,
            48 hours
        );

        pool.setConfig(
            1000, // scoreIncrement
            1000,
            100,
            treasury,
            50,
            uint32(24 hours),
            300, // scoreFree
            6 hours,
            48 hours
        );
        assertEq(pool.minDuration(), 6 hours);
        assertEq(pool.maxDuration(), 48 hours);

        vm.prank(alice);
        vm.expectPartialRevert(Errors.InvalidDuration.selector);
        pool.borrow(1 ether, 2 ether, 5 hours);

        assertEq(pool.scoreFree(), 300);

        vm.prank(alice);
        pool.borrow(10 ether, 15 ether, 6 hours);

        uint256 debt = pool.getDebt(alice);
        vm.prank(alice);
        pool.repay(debt);

        assertEq(scoreSbt.scoreOf(alice), 300);
    }
}
