// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {Errors} from "../utils/Errors.sol";
import {IPriceOracle} from "../interfaces/IPriceOracle.sol";

/// @title PriceOracleMock
/// @notice Simple configurable oracle for tests and v0 scaffolding.
contract PriceOracleMock is IPriceOracle, Ownable {
    struct PriceData {
        uint256 price;
        uint8 decimals;
        bool isSet;
    }

    /// @notice Emitted when a price is updated.
    event PriceSet(address indexed base, address indexed quote, uint256 price, uint8 decimals);

    uint256 internal constant DEFAULT_PRICE = 1e18;
    uint8 internal constant DEFAULT_DECIMALS = 18;

    mapping(bytes32 => PriceData) internal prices;

    constructor(address initialOwner) Ownable(initialOwner) {}

    /// @notice Sets a price for `base/quote`.
    /// @dev Only the owner can update prices.
    function setPrice(address base, address quote, uint256 price, uint8 decimals) external onlyOwner {
        if (base == address(0) || quote == address(0)) revert Errors.InvalidAddress();
        if (price == 0) revert Errors.InvalidAmount();

        bytes32 key = _pairKey(base, quote);
        prices[key] = PriceData({price: price, decimals: decimals, isSet: true});

        emit PriceSet(base, quote, price, decimals);
    }

    /// @inheritdoc IPriceOracle
    function getPrice(address base, address quote) external view returns (uint256 price, uint8 decimals) {
        bytes32 key = _pairKey(base, quote);
        PriceData memory data = prices[key];

        if (!data.isSet) return (DEFAULT_PRICE, DEFAULT_DECIMALS);
        return (data.price, data.decimals);
    }

    function _pairKey(address base, address quote) internal pure returns (bytes32) {
        return keccak256(abi.encode(base, quote));
    }
}
