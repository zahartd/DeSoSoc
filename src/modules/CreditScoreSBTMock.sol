// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {Errors} from "../utils/Errors.sol";
import {ICreditScoreSBT} from "../interfaces/ICreditScoreSBT.sol";

/// @title CreditScoreSBTMock
/// @notice Minimal mock for credit score storage (owner-controlled).
contract CreditScoreSBTMock is ICreditScoreSBT, Ownable {
    uint256 public nextTokenId;

    mapping(address user => uint256 tokenId) internal tokenIdOf;
    mapping(uint256 tokenId => uint16 score) internal scoreOfToken;

    constructor(address initialOwner) Ownable(initialOwner) {
        nextTokenId = 1;
    }

    function hasToken(address user) external view returns (bool) {
        return tokenIdOf[user] != 0;
    }

    function tokenOf(address user) external view returns (uint256) {
        return tokenIdOf[user];
    }

    function scoreOf(address user) external view returns (uint16) {
        uint256 tokenId = tokenIdOf[user];
        if (tokenId == 0) return 0;
        return scoreOfToken[tokenId];
    }

    function mintIfNeeded(address user, uint16 initialScore) external onlyOwner returns (uint256 tokenId) {
        if (user == address(0)) revert Errors.InvalidAddress();

        tokenId = tokenIdOf[user];
        if (tokenId != 0) return tokenId;

        tokenId = nextTokenId;
        nextTokenId = tokenId + 1;

        tokenIdOf[user] = tokenId;
        scoreOfToken[tokenId] = initialScore;
    }

    function setScore(address user, uint16 newScore) external onlyOwner {
        if (user == address(0)) revert Errors.InvalidAddress();

        uint256 tokenId = tokenIdOf[user];
        if (tokenId == 0) {
            tokenId = nextTokenId;
            nextTokenId = tokenId + 1;
            tokenIdOf[user] = tokenId;
        }

        scoreOfToken[tokenId] = newScore;
    }
}

