// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

/// @title IReputationHook
/// @notice Hook called by the core protocol on lifecycle events to update reputation state.
interface IReputationHook {
    /// @notice Called when a new loan is opened.
    /// @dev Implementations may revert to block opening the loan (strict mode).
    /// @param loanId Loan identifier in the LendingPool.
    /// @param borrower Borrower address.
    function onLoanOpened(uint256 loanId, address borrower) external;

    /// @notice Called on each repay attempt (partial or full).
    /// @dev Implementations may revert to block the repay (strict mode).
    /// @param loanId Loan identifier in the LendingPool.
    /// @param borrower Borrower address.
    /// @param paidAmount Amount paid in this call.
    /// @param totalRepaid Total repaid after this call.
    /// @param totalDebt Current total debt at the time of repayment (interest model output).
    /// @param fullyRepaid True if `totalRepaid >= totalDebt`.
    function onLoanRepaid(
        uint256 loanId,
        address borrower,
        uint256 paidAmount,
        uint256 totalRepaid,
        uint256 totalDebt,
        bool fullyRepaid
    ) external;

    /// @notice Called when a loan is marked as defaulted.
    /// @dev Implementations may revert to block the default transition (strict mode).
    /// @param loanId Loan identifier in the LendingPool.
    /// @param borrower Borrower address.
    function onLoanDefaulted(uint256 loanId, address borrower) external;
}
