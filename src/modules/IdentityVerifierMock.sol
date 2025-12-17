// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IIdentityVerifier} from "../interfaces/IIdentityVerifier.sol";

/// @title IdentityVerifierMock
/// @notice Simple mock verifier (allow-all by default).
contract IdentityVerifierMock is IIdentityVerifier, Ownable {
    /// @notice If true, all users are considered verified.
    bool public allowAll;

    /// @notice Optional allowlist for strict mode.
    mapping(address => bool) public allowed;

    /// @notice Emitted when allow-all mode is changed.
    event AllowAllSet(bool allowAll);

    /// @notice Emitted when a user allowlist flag is changed.
    event AllowedSet(address indexed user, bool allowed);

    constructor(address initialOwner) Ownable(initialOwner) {
        allowAll = true;
    }

    /// @notice Enables/disables allow-all mode.
    function setAllowAll(bool newAllowAll) external onlyOwner {
        allowAll = newAllowAll;
        emit AllowAllSet(newAllowAll);
    }

    /// @notice Updates allowlist for a `user` (used when `allowAll == false`).
    function setAllowed(address user, bool isAllowed) external onlyOwner {
        allowed[user] = isAllowed;
        emit AllowedSet(user, isAllowed);
    }

    /// @inheritdoc IIdentityVerifier
    function verify(address user, bytes calldata) external view returns (bool) {
        return allowAll || allowed[user];
    }
}

