// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

/// @title IInterestModel
/// @notice Debt growth model used by the core lending pool.
interface IInterestModel {
    /// @notice Computes debt for `principal` from `startTs` to `nowTs`.
    function debt(uint256 principal, uint64 startTs, uint64 nowTs) external view returns (uint256);

    /// @notice Computes debt with penalty APR after `dueTs`.
    function debtWithPenalty(uint256 principal, uint64 startTs, uint64 dueTs, uint64 nowTs)
        external
        view
        returns (uint256);
}

