// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

/// @title Types
/// @notice Shared data types used across DeSoSoc v0 contracts.
library Types {
    /// @notice Loan lifecycle status.
    enum LoanStatus {
        None,
        Active,
        Repaid,
        Defaulted,
        Liquidated
    }

    /// @notice Loan state stored by the core contract.
    struct Loan {
        address borrower;
        address asset;
        address collateralAsset;
        uint256 principal;
        uint256 principalRepaid;
        uint256 collateralAmount;
        uint64 startTs;
        uint64 dueTs;
        LoanStatus status;
    }

    /// @notice Borrow request parameters provided by a borrower.
    struct BorrowRequest {
        address asset;
        uint256 amount;
        address collateralAsset;
        uint256 collateralAmount;
        uint64 duration;
        bytes proof;
    }

    /// @notice Result of risk assessment for a borrow request.
    struct RiskResult {
        bool allowed;
        uint16 collateralRatioBps;
        uint256 maxBorrow;
        string reason;
    }
}
