// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

/// @title IPriceOracle
/// @notice Generic price oracle interface.
interface IPriceOracle {
    /// @notice Returns price of `base` denominated in `quote`.
    /// @dev `price` uses `decimals` decimal places.
    function getPrice(address base, address quote) external view returns (uint256 price, uint8 decimals);
}
