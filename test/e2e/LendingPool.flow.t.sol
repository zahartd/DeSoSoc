// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

import {LendingPool} from "../../src/core/LendingPool.sol";
import {Types} from "../../src/utils/Types.sol";
import {InterestModelLinear} from "../../src/modules/InterestModelLinear.sol";
import {ReputationHookMock} from "../../src/modules/ReputationHookMock.sol";
import {RiskEngineSimple} from "../../src/modules/RiskEngineSimple.sol";

contract LendingPoolFlowTest is Test {
    uint256 internal constant BPS = 10_000;

    LendingPool internal pool;
    ERC20Mock internal asset;
    ERC20Mock internal collateral;

    RiskEngineSimple internal riskEngine;
    InterestModelLinear internal interestModel;
    ReputationHookMock internal hook;

    address internal admin = address(this);
    address internal treasury = address(0xBEEF);

    address internal alice = address(0xA11CE);

    function setUp() public {
        asset = new ERC20Mock();
        collateral = new ERC20Mock();

        riskEngine = new RiskEngineSimple(address(this), address(0), address(0), address(0), address(0));
        interestModel = new InterestModelLinear(1000, 2000); // 10% APR, 20% penalty APR (v0 example)
        hook = new ReputationHookMock(address(this));

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
    }

    function test_liquidity_adminDepositWithdraw() public {
        uint256 poolBalBefore = asset.balanceOf(address(pool));
        pool.withdrawLiquidity(address(asset), 10 ether, admin);
        assertEq(asset.balanceOf(address(pool)), poolBalBefore - 10 ether);
        assertEq(asset.balanceOf(admin), 10 ether);
    }

    function test_flow_borrow_repay_splitsInterestAndReturnsCollateral() public {
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

        Types.Loan memory loanAfter = pool.getLoan(loanId);
        assertEq(uint8(loanAfter.status), uint8(Types.LoanStatus.Repaid));
        assertEq(pool.activeLoanIdOf(alice), 0);

        uint256 interestAccrued = debt - principal;
        uint256 protocolFee = (interestAccrued * pool.protocolFeeBps()) / BPS;
        assertEq(asset.balanceOf(treasury), originationFee + protocolFee);

        // Collateral returned.
        assertEq(collateral.balanceOf(address(pool)), 0);
        assertEq(collateral.balanceOf(alice), aliceCollateralBefore);
    }

    function test_flow_default_keepsCollateralEscrowed() public {
        vm.warp(1_000);

        Types.BorrowRequest memory req = Types.BorrowRequest({
            asset: address(asset),
            amount: 100 ether,
            collateralAsset: address(collateral),
            collateralAmount: 150 ether,
            duration: 1 days,
            proof: hex""
        });

        uint256 aliceCollateralBefore = collateral.balanceOf(alice);

        vm.prank(alice);
        uint256 loanId = pool.borrow(req);

        Types.Loan memory loanBefore = pool.getLoan(loanId);
        vm.warp(uint256(loanBefore.dueTs) + 1);

        pool.markDefault(loanId);

        Types.Loan memory loanAfter = pool.getLoan(loanId);
        assertEq(uint8(loanAfter.status), uint8(Types.LoanStatus.Defaulted));
        assertEq(pool.activeLoanIdOf(alice), 0);

        // Collateral remains in escrow.
        assertEq(collateral.balanceOf(address(pool)), req.collateralAmount);
        assertEq(collateral.balanceOf(alice), aliceCollateralBefore - req.collateralAmount);
    }
}

