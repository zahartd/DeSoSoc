// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

/// @title IBlackBadgeSBT
/// @notice Interface for the soulbound default/blacklist badge.
interface IBlackBadgeSBT {
    /// @notice Returns true if `user` has a badge.
    function hasBadge(address user) external view returns (bool);

    /// @notice Mints a badge for `user`.
    /// @return tokenId Minted token id.
    function mintBadge(address user) external returns (uint256 tokenId);

    /// @notice Returns the token ID owned by a user (0 if none).
    function tokenIdOf(address user) external view returns (uint256);
}
