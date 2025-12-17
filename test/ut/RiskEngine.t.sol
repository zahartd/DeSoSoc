// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {RiskEngine} from "../../src/modules/RiskEngine.sol";
import {CreditScoreSBT} from "../../src/tokens/CreditScoreSBT.sol";
import {BlackBadgeSBT} from "../../src/tokens/BlackBadgeSBT.sol";

contract RiskEngineTest is Test {
    CreditScoreSBT internal scoreSbt;
    BlackBadgeSBT internal badgeSbt;
    RiskEngine internal engine;

    address internal borrower = address(0xB0B0);

    function setUp() public {
        scoreSbt = new CreditScoreSBT(address(this));
        badgeSbt = new BlackBadgeSBT(address(this));
        engine = new RiskEngine(address(scoreSbt), address(badgeSbt), 1_000 ether);
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

    function test_zeroCollateralTier_usesMaxBorrowNoCollateral() public {
        scoreSbt.setScore(borrower, 900);
        assertEq(engine.collateralRatioBps(borrower), 0);
        assertEq(engine.maxBorrow(borrower), 1_000 ether);
    }

    function test_defaulterDenied() public {
        badgeSbt.mintBadge(borrower);
        assertTrue(engine.isDefaulter(borrower));
        assertEq(engine.maxBorrow(borrower), 0);
    }
}
