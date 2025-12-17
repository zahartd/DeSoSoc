// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Types} from "../utils/Types.sol";

/// @title IRiskEngine
/// @notice Policy interface for borrow eligibility and limits.
interface IRiskEngine {
    /// @notice Assesses a borrow request and returns decision and parameters.
    function assessBorrow(address borrower, Types.BorrowRequest calldata req)
        external
        view
        returns (Types.RiskResult memory);

    /// @notice Returns required collateral ratio (in bps) for `borrower`.
    function collateralRatioBps(address borrower) external view returns (uint16);

    /// @notice Returns maximum borrow amount for `borrower` and `asset`.
    function maxBorrow(address borrower, address asset) external view returns (uint256);

    /// @notice Returns true if `borrower` is considered a defaulter.
    function isDefaulter(address borrower) external view returns (bool);
}
