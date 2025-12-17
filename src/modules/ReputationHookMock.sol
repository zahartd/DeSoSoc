// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IReputationHook} from "../interfaces/IReputationHook.sol";

/// @title ReputationHookMock
/// @notice Minimal hook implementation for tests and v0 scaffolding.
contract ReputationHookMock is IReputationHook, Ownable {
    /// @notice Emitted when the hook is called on borrow.
    event HookLoanOpened(uint256 indexed loanId, address indexed borrower);

    /// @notice Emitted when the hook is called on repay.
    event HookLoanRepaid(
        uint256 indexed loanId,
        address indexed borrower,
        uint256 paidAmount,
        uint256 totalRepaid,
        uint256 totalDebt,
        bool fullyRepaid
    );

    /// @notice Emitted when the hook is called on default.
    event HookLoanDefaulted(uint256 indexed loanId, address indexed borrower);

    constructor(address initialOwner) Ownable(initialOwner) {}

    /// @inheritdoc IReputationHook
    function onLoanOpened(uint256 loanId, address borrower) external {
        emit HookLoanOpened(loanId, borrower);
    }

    /// @inheritdoc IReputationHook
    function onLoanRepaid(
        uint256 loanId,
        address borrower,
        uint256 paidAmount,
        uint256 totalRepaid,
        uint256 totalDebt,
        bool fullyRepaid
    ) external {
        emit HookLoanRepaid(loanId, borrower, paidAmount, totalRepaid, totalDebt, fullyRepaid);
    }

    /// @inheritdoc IReputationHook
    function onLoanDefaulted(uint256 loanId, address borrower) external {
        emit HookLoanDefaulted(loanId, borrower);
    }
}
