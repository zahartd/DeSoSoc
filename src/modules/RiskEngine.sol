// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {ICreditScoreSBT} from "../interfaces/ICreditScoreSBT.sol";
import {IBlackBadgeSBT} from "../interfaces/IBlackBadgeSBT.sol";
import {IRiskEngine} from "../interfaces/IRiskEngine.sol";

/// @title RiskEngine
/// @notice v0 risk engine: score-based collateral ratio + defaulter badge gate.
contract RiskEngine is IRiskEngine {
    uint16 internal constant SCORE_FREE = 800;
    uint16 internal constant MAX_RATIO_BPS = 15_000;

    ICreditScoreSBT public immutable SCORE_SBT;
    IBlackBadgeSBT public immutable BADGE_SBT;

    /// @notice Max borrow allowed when collateral ratio is 0% (no-collateral tier).
    uint256 public immutable MAX_BORROW_NO_COLLATERAL;

    constructor(address scoreSbt_, address badgeSbt_, uint256 maxBorrowNoCollateral_) {
        SCORE_SBT = ICreditScoreSBT(scoreSbt_);
        BADGE_SBT = IBlackBadgeSBT(badgeSbt_);
        MAX_BORROW_NO_COLLATERAL = maxBorrowNoCollateral_;
    }

    function isDefaulter(address borrower) public view returns (bool) {
        return address(BADGE_SBT) != address(0) && BADGE_SBT.hasBadge(borrower);
    }

    function collateralRatioBps(address borrower) public view returns (uint16) {
        uint16 score = address(SCORE_SBT) == address(0) ? 0 : SCORE_SBT.scoreOf(borrower);
        return _ratioFromScore(score);
    }

    function maxBorrow(address borrower) external view returns (uint256) {
        if (isDefaulter(borrower)) return 0;
        if (collateralRatioBps(borrower) == 0) return MAX_BORROW_NO_COLLATERAL;
        return type(uint256).max;
    }

    function _ratioFromScore(uint16 score) internal pure returns (uint16) {
        if (score >= SCORE_FREE) return 0;

        uint256 remaining = uint256(SCORE_FREE - score);
        uint256 numerator = uint256(MAX_RATIO_BPS) * remaining;
        uint256 ratio = (numerator + SCORE_FREE - 1) / SCORE_FREE;
        return SafeCast.toUint16(ratio);
    }
}
