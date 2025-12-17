// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {ICreditScoreSBT} from "../interfaces/ICreditScoreSBT.sol";
import {Errors} from "../utils/Errors.sol";

/// @title CreditScoreSBT
/// @notice Non-transferable ERC-721 token storing a per-address credit score (uint16).
/// @dev Only the owner can mint/update scores. Transfers and approvals are disabled (soulbound).
contract CreditScoreSBT is ICreditScoreSBT, ERC721, Ownable {
    uint256 public nextTokenId;

    mapping(address user => uint256 tokenId) internal _tokenIdOf;
    mapping(uint256 tokenId => uint16 score) internal _scoreOf;

    event ScoreMinted(address indexed user, uint256 indexed tokenId);
    event ScoreUpdated(address indexed user, uint16 score);

    constructor(address initialOwner) ERC721("CreditScore", "CSCORE") Ownable(initialOwner) {
        nextTokenId = 1;
    }

    function tokenIdOf(address user) external view returns (uint256) {
        return _tokenIdOf[user];
    }

    function scoreOf(address user) public view returns (uint16) {
        uint256 tokenId = _tokenIdOf[user];
        if (tokenId == 0) return 0;
        return _scoreOf[tokenId];
    }

    function mintIfNeeded(address user) public onlyOwner returns (uint256 tokenId) {
        if (user == address(0)) revert Errors.InvalidAddress();

        tokenId = _tokenIdOf[user];
        if (tokenId != 0) return tokenId;

        tokenId = nextTokenId;
        nextTokenId = tokenId + 1;

        _tokenIdOf[user] = tokenId;
        _safeMint(user, tokenId);

        emit ScoreMinted(user, tokenId);
    }

    function setScore(address user, uint16 newScore) external onlyOwner {
        uint256 tokenId = mintIfNeeded(user);
        _scoreOf[tokenId] = newScore;
        emit ScoreUpdated(user, newScore);
    }

    // =========================================================================
    // Soulbound: disable all transfers + approvals
    // =========================================================================

    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        address from = _ownerOf(tokenId);
        if (from != address(0)) revert Errors.Unauthorized();
        return super._update(to, tokenId, auth);
    }

    function approve(address, uint256) public pure override {
        revert Errors.Unauthorized();
    }

    function setApprovalForAll(address, bool) public pure override {
        revert Errors.Unauthorized();
    }
}
