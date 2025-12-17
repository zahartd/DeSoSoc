// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

/// @title IRiskEngine
/// @notice Policy interface for borrow eligibility and limits.
interface IRiskEngine {
    /// @notice Returns required collateral ratio (in bps) for `borrower`.
    function collateralRatioBps(address borrower) external view returns (uint16);

    /// @notice Returns maximum borrow amount for `borrower` (0 means borrowing is disabled).
    function maxBorrow(address borrower) external view returns (uint256);

    /// @notice Returns true if `borrower` is considered a defaulter.
    function isDefaulter(address borrower) external view returns (bool);
}
