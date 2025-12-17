// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {LendingPool} from "../src/core/LendingPool.sol";
import {Types} from "../src/utils/Types.sol";
import {InterestModelLinear} from "../src/modules/InterestModelLinear.sol";
import {ReputationHookMock} from "../src/modules/ReputationHookMock.sol";
import {RiskEngineSimple} from "../src/modules/RiskEngineSimple.sol";

contract LendingPoolSkeletonTest is Test {
    LendingPool internal pool;

    RiskEngineSimple internal riskEngine;
    InterestModelLinear internal interestModel;
    ReputationHookMock internal hook;

    address internal admin = address(this);
    address internal treasury = address(0xBEEF);

    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);

    function setUp() public {
        riskEngine = new RiskEngineSimple(address(this), address(0), address(0), address(0), address(0));
        interestModel = new InterestModelLinear(0, 0);
        hook = new ReputationHookMock(address(this));

        LendingPool impl = new LendingPool();
        bytes memory initData = abi.encodeCall(
            LendingPool.initialize, (admin, address(riskEngine), address(interestModel), address(hook), treasury)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        pool = LendingPool(address(proxy));
    }

    function test_initialize_setsConfig() public view {
        assertEq(address(pool.riskEngine()), address(riskEngine));
        assertEq(address(pool.interestModel()), address(interestModel));
        assertEq(address(pool.reputationHook()), address(hook));
        assertEq(pool.treasury(), treasury);
        assertEq(pool.nextLoanId(), 1);

        assertTrue(pool.hasRole(pool.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(pool.hasRole(pool.UPGRADER_ROLE(), admin));
        assertTrue(pool.hasRole(pool.RISK_ADMIN_ROLE(), admin));
        assertTrue(pool.hasRole(pool.PAUSER_ROLE(), admin));
    }

    function test_setModules_accessControl() public {
        RiskEngineSimple newRiskEngine =
            new RiskEngineSimple(address(this), address(0), address(0), address(0), address(0));
        InterestModelLinear newInterestModel = new InterestModelLinear(0, 0);
        ReputationHookMock newHook = new ReputationHookMock(address(this));

        vm.startPrank(bob);
        vm.expectRevert();
        pool.setRiskEngine(address(newRiskEngine));
        vm.expectRevert();
        pool.setInterestModel(address(newInterestModel));
        vm.expectRevert();
        pool.setReputationHook(address(newHook));
        vm.stopPrank();

        pool.setRiskEngine(address(newRiskEngine));
        pool.setInterestModel(address(newInterestModel));
        pool.setReputationHook(address(newHook));
    }

    function test_borrow_opensLoan_and_setsActiveLoanId() public {
        vm.warp(1_000);

        Types.BorrowRequest memory req = Types.BorrowRequest({
            asset: address(0xCAFE),
            amount: 100,
            collateralAsset: address(0xBEEFCAFE),
            collateralAmount: 150,
            duration: 7 days,
            proof: hex""
        });

        vm.prank(alice);
        uint256 loanId = pool.borrow(req);

        assertEq(loanId, 1);
        assertEq(pool.activeLoanIdOf(alice), loanId);

        Types.Loan memory loan = pool.getLoan(loanId);
        assertEq(loan.borrower, alice);
        assertEq(loan.asset, req.asset);
        assertEq(loan.principal, req.amount);
        assertEq(loan.startTs, uint64(1_000));
        assertEq(loan.dueTs, uint64(1_000 + req.duration));
        assertEq(uint8(loan.status), uint8(Types.LoanStatus.Active));
    }

    function test_markDefault_afterDueTs() public {
        vm.warp(1_000);

        Types.BorrowRequest memory req = Types.BorrowRequest({
            asset: address(0xCAFE),
            amount: 100,
            collateralAsset: address(0),
            collateralAmount: 0,
            duration: 3 days,
            proof: hex""
        });

        vm.prank(alice);
        uint256 loanId = pool.borrow(req);

        Types.Loan memory loanBefore = pool.getLoan(loanId);
        vm.warp(uint256(loanBefore.dueTs) + 1);

        pool.markDefault(loanId);

        Types.Loan memory loanAfter = pool.getLoan(loanId);
        assertEq(uint8(loanAfter.status), uint8(Types.LoanStatus.Defaulted));
        assertEq(pool.activeLoanIdOf(alice), 0);
    }

    function test_repay_updatesPrincipalRepaid_and_closesLoan() public {
        vm.warp(1_000);

        Types.BorrowRequest memory req = Types.BorrowRequest({
            asset: address(0xCAFE),
            amount: 100,
            collateralAsset: address(0),
            collateralAmount: 0,
            duration: 30 days,
            proof: hex""
        });

        vm.prank(alice);
        uint256 loanId = pool.borrow(req);

        vm.prank(alice);
        pool.repay(loanId, 100);

        Types.Loan memory loanAfter = pool.getLoan(loanId);
        assertEq(loanAfter.principalRepaid, 100);
        assertEq(uint8(loanAfter.status), uint8(Types.LoanStatus.Repaid));
        assertEq(pool.activeLoanIdOf(alice), 0);
    }
}
