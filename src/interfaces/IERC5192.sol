// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @title IERC5192
/// @notice Minimal Soulbound NFTs (EIP-5192).
/// @dev See https://eips.ethereum.org/EIPS/eip-5192
interface IERC5192 is IERC165 {
    /// @notice Emitted when a token is locked (becomes non-transferable).
    event Locked(uint256 tokenId);

    /// @notice Emitted when a token is unlocked (becomes transferable).
    event Unlocked(uint256 tokenId);

    /// @notice Returns true if `tokenId` is locked (non-transferable).
    function locked(uint256 tokenId) external view returns (bool);
}

