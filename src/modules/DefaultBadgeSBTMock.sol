// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {Errors} from "../utils/Errors.sol";
import {IDefaultBadgeSBT} from "../interfaces/IDefaultBadgeSBT.sol";

/// @title DefaultBadgeSBTMock
/// @notice Minimal mock for default/blacklist badge storage (owner-controlled).
contract DefaultBadgeSBTMock is IDefaultBadgeSBT, Ownable {
    uint256 public nextTokenId;

    mapping(address user => uint256 tokenId) internal tokenIdOf;

    constructor(address initialOwner) Ownable(initialOwner) {
        nextTokenId = 1;
    }

    function hasBadge(address user) external view returns (bool) {
        return tokenIdOf[user] != 0;
    }

    function mintBadge(address user) external onlyOwner returns (uint256 tokenId) {
        if (user == address(0)) revert Errors.InvalidAddress();

        tokenId = tokenIdOf[user];
        if (tokenId != 0) return tokenId;

        tokenId = nextTokenId;
        nextTokenId = tokenId + 1;
        tokenIdOf[user] = tokenId;
    }
}

