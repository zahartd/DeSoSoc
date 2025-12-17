// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

/// @title Errors
/// @notice Custom errors shared across DeSoSoc v0 contracts.
library Errors {
    /// @notice Caller is not authorized to perform this action.
    error Unauthorized();

    /// @notice Address parameter is invalid (e.g. zero address).
    error InvalidAddress();

    /// @notice Amount parameter is invalid (e.g. zero).
    error InvalidAmount();

    /// @notice Duration parameter is invalid (e.g. zero).
    error InvalidDuration();

    /// @notice Basis points value is invalid (e.g. > 10_000).
    error InvalidBps();

    /// @notice Protocol has insufficient free liquidity for the operation.
    error InsufficientLiquidity();

    /// @notice Collateral provided is below the required threshold.
    error LowCollateral();

    /// @notice Reentrancy detected.
    error Reentrancy();

    /// @notice Borrower already has an active loan.
    error LoanAlreadyActive();

    /// @notice Loan is expected to be active, but it is not.
    error LoanNotActive();

    /// @notice Loan does not exist.
    error LoanNotFound();

    /// @notice Action cannot be performed because loan is past due.
    error PastDue();

    /// @notice Action requires the loan to be past due, but it is not.
    error NotPastDue();

    /// @notice Borrow action is not allowed by policy.
    error BorrowNotAllowed();

    /// @notice Repay action is not allowed.
    error RepayNotAllowed();

    /// @notice Required module is not set.
    error ModuleNotSet();

    /// @notice Provided identity proof is invalid.
    error BadProof();

    /// @notice A critical invariant has been violated.
    error InvariantViolation();
}
