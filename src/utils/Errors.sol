// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

/// @title Errors
/// @notice Custom errors shared across DeSoSoc v0 contracts.
library Errors {
    /// @notice Caller is not authorized to perform this action.
    error Unauthorized();

    /// @notice Address parameter is invalid (e.g. zero address).
    error InvalidAddress(address addr);

    /// @notice Amount parameter is invalid (e.g. zero).
    error InvalidAmount(uint256 amount);

    /// @notice Duration parameter is invalid (e.g. out of bounds).
    error InvalidDuration(uint64 duration, uint64 min, uint64 max);

    /// @notice Duration bounds are invalid (e.g. min > max or outside configured limits).
    error InvalidDurationBounds(uint64 min, uint64 max);

    /// @notice Score cap configuration is invalid.
    error InvalidScoreFree(uint16 scoreFree);

    /// @notice Basis points value is invalid (e.g. > 10_000).
    error InvalidBps(uint16 bps, uint16 maxBps);

    /// @notice Protocol has insufficient free liquidity for the operation.
    error InsufficientLiquidity(uint256 available, uint256 required);

    /// @notice Collateral provided is below the required threshold.
    error LowCollateral(uint256 provided, uint256 required);

    /// @notice Reentrancy detected.
    error Reentrancy();

    /// @notice Borrower already has an active loan.
    error LoanAlreadyActive(address borrower);

    /// @notice Loan is expected to be active, but it is not.
    error LoanNotActive(address borrower);

    /// @notice Action requires the loan to be past due, but it is not.
    error NotPastDue(uint64 dueTs, uint32 gracePeriod, uint64 nowTs);

    /// @notice Borrow action is not allowed by policy.
    error BorrowNotAllowed(address borrower, uint256 amount, uint256 maxBorrow);
}
