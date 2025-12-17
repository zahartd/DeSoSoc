// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Types} from "../utils/Types.sol";
import {IInterestModel} from "../interfaces/IInterestModel.sol";
import {IRiskEngine} from "../interfaces/IRiskEngine.sol";

/// @title LendingPoolStorage
/// @notice Storage layout for {LendingPool}.
abstract contract LendingPoolStorage {
    /// @notice Active risk engine module.
    IRiskEngine public riskEngine;

    /// @notice Active interest model module.
    IInterestModel public interestModel;

    /// @notice Treasury address (liquidity source placeholder for v0).
    address public treasury;

    /// @notice Next loan id to be assigned (starts from 1).
    uint256 public nextLoanId;

    /// @notice Loan storage by id.
    mapping(uint256 loanId => Types.Loan loan) internal loans;

    /// @notice Active loan id for a borrower (0 if none).
    mapping(address borrower => uint256 loanId) public activeLoanIdOf;

    uint256[50] private __gap;
}
