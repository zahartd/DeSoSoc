// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {StorageSlot} from "@openzeppelin/contracts/utils/StorageSlot.sol";

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/// @title ReentrancyGuardUpgradeable
/// @notice Upgradeable variant of OpenZeppelin's {ReentrancyGuard} using ERC-7201 namespaced storage.
/// @dev OZ v5.x removed {ReentrancyGuardUpgradeable}; this local shim keeps upgradeable hygiene and ensures the
/// guard is initialized for proxy deployments.
abstract contract ReentrancyGuardUpgradeable is Initializable {
    using StorageSlot for bytes32;

    // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.ReentrancyGuard")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant REENTRANCY_GUARD_STORAGE =
        0x9b779b17422d0df92223018b32b4d1fa46e071723d6817e2486d003becc55f00;

    uint256 private constant NOT_ENTERED = 1;
    uint256 private constant ENTERED = 2;

    /// @notice Unauthorized reentrant call.
    error ReentrancyGuardReentrantCall();

    /// @dev Initializes the reentrancy guard state for proxy deployments.
    function __ReentrancyGuard_init() internal onlyInitializing {
        __ReentrancyGuard_init_unchained();
    }

    function __ReentrancyGuard_init_unchained() internal onlyInitializing {
        _reentrancyGuardStorageSlot().getUint256Slot().value = NOT_ENTERED;
    }

    /// @notice Prevents a contract from calling itself, directly or indirectly.
    modifier nonReentrant() {
        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    /// @notice View-only variant of {nonReentrant}.
    modifier nonReentrantView() {
        _nonReentrantBeforeView();
        _;
    }

    function _nonReentrantBeforeView() private view {
        if (_reentrancyGuardEntered()) {
            revert ReentrancyGuardReentrantCall();
        }
    }

    function _nonReentrantBefore() private {
        _nonReentrantBeforeView();
        _reentrancyGuardStorageSlot().getUint256Slot().value = ENTERED;
    }

    function _nonReentrantAfter() private {
        _reentrancyGuardStorageSlot().getUint256Slot().value = NOT_ENTERED;
    }

    /// @notice Returns true if the reentrancy guard is currently set to "entered".
    function _reentrancyGuardEntered() internal view returns (bool) {
        return _reentrancyGuardStorageSlot().getUint256Slot().value == ENTERED;
    }

    function _reentrancyGuardStorageSlot() internal pure virtual returns (bytes32) {
        return REENTRANCY_GUARD_STORAGE;
    }
}

