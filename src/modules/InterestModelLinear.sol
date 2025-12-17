// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IInterestModel} from "../interfaces/IInterestModel.sol";

/// @title InterestModelLinear
/// @notice Linear APR + penalty APR interest model (v0 placeholder).
contract InterestModelLinear is IInterestModel {
    uint256 internal constant YEAR = 365 days;
    uint256 internal constant BPS = 10_000;

    /// @notice Base APR in basis points.
    uint16 public immutable aprBps;

    /// @notice Penalty APR in basis points (applies after due date).
    uint16 public immutable penaltyAprBps;

    constructor(uint16 aprBps_, uint16 penaltyAprBps_) {
        aprBps = aprBps_;
        penaltyAprBps = penaltyAprBps_;
    }

    function debt(uint256 principal, uint64 startTs, uint64 nowTs) external view returns (uint256) {
        return _debtAtRate(principal, startTs, nowTs, aprBps);
    }

    function debtWithPenalty(uint256 principal, uint64 startTs, uint64 dueTs, uint64 nowTs)
        external
        view
        returns (uint256)
    {
        if (principal == 0) return 0;
        if (nowTs <= startTs) return principal;

        if (nowTs <= dueTs) {
            return _debtAtRate(principal, startTs, nowTs, aprBps);
        }

        uint64 effectiveDue = dueTs > startTs ? dueTs : startTs;
        uint256 normalDt = uint256(effectiveDue - startTs);
        uint256 penaltyDt = uint256(nowTs - effectiveDue);

        uint256 normalInterest = _interest(principal, aprBps, normalDt);
        uint256 penaltyInterest = _interest(principal, penaltyAprBps, penaltyDt);

        return principal + normalInterest + penaltyInterest;
    }

    function _debtAtRate(uint256 principal, uint64 startTs, uint64 nowTs, uint16 rateBps)
        internal
        pure
        returns (uint256)
    {
        if (principal == 0) return 0;
        if (nowTs <= startTs) return principal;

        uint256 dt = uint256(nowTs - startTs);
        return principal + _interest(principal, rateBps, dt);
    }

    function _interest(uint256 principal, uint16 rateBps, uint256 dt) internal pure returns (uint256) {
        if (rateBps == 0 || dt == 0) return 0;
        return Math.mulDiv(principal, uint256(rateBps) * dt, YEAR * BPS);
    }
}

