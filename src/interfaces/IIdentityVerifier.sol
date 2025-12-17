// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

/// @title IIdentityVerifier
/// @notice Optional verifier for KYC/ZK/anti-sybil proofs.
interface IIdentityVerifier {
    /// @notice Verifies `proof` for `user`.
    function verify(address user, bytes calldata proof) external view returns (bool);
}

