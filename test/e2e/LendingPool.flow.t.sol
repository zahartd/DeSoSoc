// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

import {LendingPool} from "../../src/core/LendingPool.sol";
import {Types} from "../../src/utils/Types.sol";
import {Errors} from "../../src/utils/Errors.sol";
import {InterestModelLinear} from "../../src/modules/InterestModelLinear.sol";
import {PriceOracleMock} from "../../src/modules/PriceOracleMock.sol";
import {ReputationHookMock} from "../../src/modules/ReputationHookMock.sol";
import {RiskEngine} from "../../src/modules/RiskEngine.sol";
import {CreditScoreSBTMock} from "../../src/modules/CreditScoreSBTMock.sol";
import {DefaultBadgeSBTMock} from "../../src/modules/DefaultBadgeSBTMock.sol";

contract LendingPoolFlowTest is Test {
    uint256 internal constant BPS = 10_000;

    LendingPool internal pool;
    ERC20Mock internal asset;
    ERC20Mock internal collateral;

    PriceOracleMock internal oracle;
    RiskEngine internal riskEngine;
    InterestModelLinear internal interestModel;
    ReputationHookMock internal hook;

    CreditScoreSBTMock internal scoreSbt;
    DefaultBadgeSBTMock internal badgeSbt;

    address internal admin = address(this);
    address internal treasury = address(0xBEEF);

    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);

    function setUp() public {
        asset = new ERC20Mock();
        collateral = new ERC20Mock();

        oracle = new PriceOracleMock(address(this));
        oracle.setPrice(address(collateral), address(asset), 1e18, 18);

        scoreSbt = new CreditScoreSBTMock(address(this));
        badgeSbt = new DefaultBadgeSBTMock(address(this));
        hook = new ReputationHookMock(address(this));

        riskEngine = new RiskEngine(address(this), address(scoreSbt), address(badgeSbt), address(0), address(oracle));
        riskEngine.setConfig(false, 1_000 ether);
        interestModel = new InterestModelLinear(1000, 2000); // 10% APR, 20% penalty APR (v0 example)

        LendingPool impl = new LendingPool();
        bytes memory initData = abi.encodeCall(
            LendingPool.initialize, (admin, address(riskEngine), address(interestModel), address(hook), treasury)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        pool = LendingPool(address(proxy));

        // Configure fees: 10% of interest to treasury, 1% origination fee on borrow.
        pool.setFees(1000, 100);

        // Seed liquidity.
        asset.mint(admin, 1_000 ether);
        asset.approve(address(pool), type(uint256).max);
        pool.depositLiquidity(address(asset), 1_000 ether);

        // Seed borrower collateral + approvals.
        collateral.mint(alice, 1_000 ether);
        vm.prank(alice);
        collateral.approve(address(pool), type(uint256).max);
        vm.prank(alice);
        asset.approve(address(pool), type(uint256).max);

        collateral.mint(bob, 1_000 ether);
        vm.prank(bob);
        collateral.approve(address(pool), type(uint256).max);
        vm.prank(bob);
        asset.approve(address(pool), type(uint256).max);
    }

    function test_liquidity_adminDepositWithdraw() public {
        uint256 poolBalBefore = asset.balanceOf(address(pool));
        pool.withdrawLiquidity(address(asset), 10 ether, admin);
        assertEq(asset.balanceOf(address(pool)), poolBalBefore - 10 ether);
        assertEq(asset.balanceOf(admin), 10 ether);
    }

    function test_flow_borrow_repay_increasesScore_and_relaxesCollateralRatio() public {
        vm.warp(1_000);

        uint256 principal = 100 ether;
        uint256 collateralAmount = 150 ether;
        uint64 duration = 30 days;

        Types.BorrowRequest memory req = Types.BorrowRequest({
            asset: address(asset),
            amount: principal,
            collateralAsset: address(collateral),
            collateralAmount: collateralAmount,
            duration: duration,
            proof: hex""
        });

        uint256 poolAssetBeforeBorrow = asset.balanceOf(address(pool));
        uint256 aliceCollateralBefore = collateral.balanceOf(alice);

        vm.prank(alice);
        uint256 loanId = pool.borrow(req);

        uint256 originationFee = (principal * pool.originationFeeBps()) / BPS;
        assertEq(asset.balanceOf(treasury), originationFee);
        assertEq(asset.balanceOf(alice), principal - originationFee);
        assertEq(asset.balanceOf(address(pool)), poolAssetBeforeBorrow - principal);

        assertEq(collateral.balanceOf(address(pool)), collateralAmount);
        assertEq(collateral.balanceOf(alice), aliceCollateralBefore - collateralAmount);

        // Accrue some interest (no penalty).
        vm.warp(1_000 + 10 days);
        uint256 debt = pool.getDebt(loanId);

        // Ensure borrower can repay interest.
        uint256 aliceAssetBal = asset.balanceOf(alice);
        if (aliceAssetBal < debt) {
            asset.mint(alice, debt - aliceAssetBal);
        }

        vm.prank(alice);
        pool.repay(loanId, debt);

        // Out of scope: SBT / score update is mocked here.
        scoreSbt.setScore(alice, 250);
        assertEq(scoreSbt.scoreOf(alice), 250);
        assertEq(riskEngine.collateralRatioBps(alice), 10_313);

        Types.Loan memory loanAfter = pool.getLoan(loanId);
        assertEq(uint8(loanAfter.status), uint8(Types.LoanStatus.Repaid));
        assertEq(pool.activeLoanIdOf(alice), 0);

        uint256 interestAccrued = debt - principal;
        uint256 protocolFee = (interestAccrued * pool.protocolFeeBps()) / BPS;
        assertEq(asset.balanceOf(treasury), originationFee + protocolFee);

        // Collateral returned.
        assertEq(collateral.balanceOf(address(pool)), 0);
        assertEq(collateral.balanceOf(alice), aliceCollateralBefore);

        // Second loan with better terms: same collateral supports a larger borrow amount.
        Types.BorrowRequest memory req2 = Types.BorrowRequest({
            asset: address(asset),
            amount: 120 ether,
            collateralAsset: address(collateral),
            collateralAmount: collateralAmount,
            duration: duration,
            proof: hex""
        });

        vm.prank(alice);
        pool.borrow(req2);
    }

    function test_flow_default_mintsBadge_and_blocksBorrow() public {
        vm.warp(1_000);

        Types.BorrowRequest memory req = Types.BorrowRequest({
            asset: address(asset),
            amount: 100 ether,
            collateralAsset: address(collateral),
            collateralAmount: 150 ether,
            duration: 1 days,
            proof: hex""
        });

        vm.prank(bob);
        uint256 loanId = pool.borrow(req);

        Types.Loan memory loanBefore = pool.getLoan(loanId);
        vm.warp(uint256(loanBefore.dueTs) + 1);

        pool.markDefault(loanId);

        // Out of scope: SBT badge mint is mocked here.
        badgeSbt.mintBadge(bob);

        Types.Loan memory loanAfter = pool.getLoan(loanId);
        assertEq(uint8(loanAfter.status), uint8(Types.LoanStatus.Defaulted));
        assertEq(pool.activeLoanIdOf(bob), 0);
        assertTrue(badgeSbt.hasBadge(bob));
        assertTrue(riskEngine.isDefaulter(bob));

        vm.startPrank(bob);
        vm.expectRevert(Errors.BorrowNotAllowed.selector);
        pool.borrow(req);
        vm.stopPrank();
    }
}
