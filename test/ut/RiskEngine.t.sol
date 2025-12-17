// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

import {Types} from "../../src/utils/Types.sol";

import {IdentityVerifierMock} from "../../src/modules/IdentityVerifierMock.sol";
import {CreditScoreSBTMock} from "../../src/modules/CreditScoreSBTMock.sol";
import {DefaultBadgeSBTMock} from "../../src/modules/DefaultBadgeSBTMock.sol";
import {PriceOracleMock} from "../../src/modules/PriceOracleMock.sol";
import {RiskEngine} from "../../src/modules/RiskEngine.sol";

contract RiskEngineTest is Test {
    uint256 internal constant BPS = 10_000;

    ERC20Mock internal asset;
    ERC20Mock internal collateral;

    CreditScoreSBTMock internal scoreSbt;
    DefaultBadgeSBTMock internal badgeSbt;
    IdentityVerifierMock internal verifier;
    PriceOracleMock internal oracle;

    RiskEngine internal engine;

    address internal borrower = address(0xB0B0);

    function setUp() public {
        asset = new ERC20Mock();
        collateral = new ERC20Mock();

        scoreSbt = new CreditScoreSBTMock(address(this));
        badgeSbt = new DefaultBadgeSBTMock(address(this));
        verifier = new IdentityVerifierMock(address(this));
        oracle = new PriceOracleMock(address(this));

        oracle.setPrice(address(collateral), address(asset), 1e18, 18);

        engine = new RiskEngine(address(this), address(scoreSbt), address(badgeSbt), address(verifier), address(oracle));
        engine.setConfig(false, 1_000 ether);
    }

    function test_collateralRatioBps_fromScoreLinear() public {
        assertEq(engine.collateralRatioBps(borrower), 15_000);

        scoreSbt.setScore(borrower, 100);
        assertEq(engine.collateralRatioBps(borrower), 13_125);

        scoreSbt.setScore(borrower, 300);
        assertEq(engine.collateralRatioBps(borrower), 9_375);

        scoreSbt.setScore(borrower, 600);
        assertEq(engine.collateralRatioBps(borrower), 3_750);

        scoreSbt.setScore(borrower, 800);
        assertEq(engine.collateralRatioBps(borrower), 0);
    }

    function test_assessBorrow_requiresProof_whenConfigured() public {
        engine.setConfig(true, 1_000 ether);

        Types.BorrowRequest memory req = Types.BorrowRequest({
            asset: address(asset),
            amount: 100 ether,
            collateralAsset: address(collateral),
            collateralAmount: 150 ether,
            duration: 7 days,
            proof: hex""
        });

        Types.RiskResult memory res = engine.assessBorrow(borrower, req);
        assertFalse(res.allowed);
        assertEq(res.collateralRatioBps, 15_000);
        assertEq(res.reason, "MISSING_PROOF");

        req.proof = hex"1234";
        res = engine.assessBorrow(borrower, req);
        assertTrue(res.allowed);
        assertEq(res.maxBorrow, 100 ether);
    }

    function test_assessBorrow_enforcesCollateralUsingOracle() public view {
        Types.BorrowRequest memory req = Types.BorrowRequest({
            asset: address(asset),
            amount: 100 ether,
            collateralAsset: address(collateral),
            collateralAmount: 149 ether,
            duration: 7 days,
            proof: hex""
        });

        Types.RiskResult memory res = engine.assessBorrow(borrower, req);
        assertFalse(res.allowed);
        assertEq(res.reason, "LIMIT");
        assertEq(res.collateralRatioBps, 15_000);

        uint256 expectedMax = (149 ether * BPS) / 15_000;
        assertEq(res.maxBorrow, expectedMax);

        req.collateralAmount = 150 ether;
        res = engine.assessBorrow(borrower, req);
        assertTrue(res.allowed);
        assertEq(res.maxBorrow, 100 ether);
    }

    function test_assessBorrow_noOracleDisallowed() public {
        engine.setDependencies(address(scoreSbt), address(badgeSbt), address(verifier), address(0));

        Types.BorrowRequest memory req = Types.BorrowRequest({
            asset: address(asset),
            amount: 1 ether,
            collateralAsset: address(collateral),
            collateralAmount: 2 ether,
            duration: 7 days,
            proof: hex""
        });

        Types.RiskResult memory res = engine.assessBorrow(borrower, req);
        assertFalse(res.allowed);
        assertEq(res.reason, "NO_ORACLE");
    }

    function test_zeroCollateralTier_usesMaxBorrowNoCollateral() public {
        scoreSbt.setScore(borrower, 900);
        engine.setConfig(false, 500 ether);

        Types.BorrowRequest memory req = Types.BorrowRequest({
            asset: address(asset),
            amount: 500 ether,
            collateralAsset: address(0),
            collateralAmount: 0,
            duration: 7 days,
            proof: hex""
        });

        Types.RiskResult memory res = engine.assessBorrow(borrower, req);
        assertTrue(res.allowed);
        assertEq(res.collateralRatioBps, 0);
        assertEq(res.maxBorrow, 500 ether);

        req.amount = 501 ether;
        res = engine.assessBorrow(borrower, req);
        assertFalse(res.allowed);
        assertEq(res.reason, "LIMIT");
        assertEq(res.maxBorrow, 500 ether);
    }

    function test_defaulterDenied() public {
        badgeSbt.mintBadge(borrower);

        Types.BorrowRequest memory req = Types.BorrowRequest({
            asset: address(asset),
            amount: 1 ether,
            collateralAsset: address(collateral),
            collateralAmount: 2 ether,
            duration: 7 days,
            proof: hex""
        });

        Types.RiskResult memory res = engine.assessBorrow(borrower, req);
        assertFalse(res.allowed);
        assertEq(res.reason, "DEFAULTER");
        assertEq(res.maxBorrow, 0);
    }
}
