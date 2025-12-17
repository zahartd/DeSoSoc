// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

/// @title IDefaultBadgeSBT
/// @notice Interface for the soulbound default/blacklist badge.
interface IDefaultBadgeSBT {
    /// @notice Returns true if `user` has a default badge.
    function hasBadge(address user) external view returns (bool);

    /// @notice Mints a default badge for `user`.
    /// @return tokenId Minted token id.
    function mintBadge(address user) external returns (uint256 tokenId);
}

