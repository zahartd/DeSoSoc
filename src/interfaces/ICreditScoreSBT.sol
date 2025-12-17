// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

/// @title ICreditScoreSBT
/// @notice Interface for the soulbound credit score token.
interface ICreditScoreSBT {
    /// @notice Returns current score (0..10000 or arbitrary scale) for `user`.
    function scoreOf(address user) external view returns (uint16);

    /// @notice Mints a token for `user` if missing.
    /// @param user Target user.
    /// @return tokenId Minted (or existing) token id.
    function mintIfNeeded(address user) external returns (uint256 tokenId);

    /// @notice Updates score for `user`.
    function setScore(address user, uint16 newScore) external;

    /// @notice Returns the token ID owned by a user (0 if none).
    function tokenIdOf(address user) external view returns (uint256);
}
