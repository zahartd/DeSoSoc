// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {ICreditScoreSBT} from "../interfaces/ICreditScoreSBT.sol";
import {IBlackBadgeSBT} from "../interfaces/IBlackBadgeSBT.sol";
import {IRiskEngine} from "../interfaces/IRiskEngine.sol";

/// @title RiskEngine
/// @notice v0 risk engine: score-based collateral ratio + defaulter badge gate.
contract RiskEngine is IRiskEngine {
    uint16 internal constant SCORE_FREE = 800; // score >= this => 0% collateral tier
    uint16 internal constant MAX_RATIO_BPS = 15_000; // 150%

    ICreditScoreSBT public immutable scoreSbt;
    IBlackBadgeSBT public immutable badgeSbt;

    /// @notice Max borrow allowed when collateral ratio is 0% (no-collateral tier).
    uint256 public immutable maxBorrowNoCollateral;

    constructor(address scoreSbt_, address badgeSbt_, uint256 maxBorrowNoCollateral_) {
        scoreSbt = ICreditScoreSBT(scoreSbt_);
        badgeSbt = IBlackBadgeSBT(badgeSbt_);
        maxBorrowNoCollateral = maxBorrowNoCollateral_;
    }

    function isDefaulter(address borrower) public view returns (bool) {
        return address(badgeSbt) != address(0) && badgeSbt.hasBadge(borrower);
    }

    function collateralRatioBps(address borrower) public view returns (uint16) {
        uint16 score = address(scoreSbt) == address(0) ? 0 : scoreSbt.scoreOf(borrower);
        return _ratioFromScore(score);
    }

    function maxBorrow(address borrower) external view returns (uint256) {
        if (isDefaulter(borrower)) return 0;
        if (collateralRatioBps(borrower) == 0) return maxBorrowNoCollateral;
        return type(uint256).max;
    }

    function _ratioFromScore(uint16 score) internal pure returns (uint16) {
        if (score >= SCORE_FREE) return 0;

        uint256 remaining = uint256(SCORE_FREE - score);
        uint256 numerator = uint256(MAX_RATIO_BPS) * remaining;
        uint256 ratio = (numerator + SCORE_FREE - 1) / SCORE_FREE; // ceil
        return uint16(ratio);
    }
}
