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

    /// @inheritdoc ICreditScoreSBT
    function hasToken(address user) external view override returns (bool) {
        return _tokenIdOf[user] != 0;
    }

    /// @inheritdoc ICreditScoreSBT
    function tokenOf(address user) public view override returns (uint256) {
        return _tokenIdOf[user];
    }

    /// @notice Returns tokenId owned by `user` (alias for {tokenOf}).
    function tokenIdOf(address user) external view override returns (uint256) {
        return tokenOf(user);
    }

    /// @inheritdoc ICreditScoreSBT
    function scoreOf(address user) public view override returns (uint16) {
        uint256 tokenId = _tokenIdOf[user];
        if (tokenId == 0) return 0;
        return _scoreOf[tokenId];
    }

    /// @inheritdoc ICreditScoreSBT
    function mintIfNeeded(address user) public override onlyOwner returns (uint256 tokenId) {
        if (user == address(0)) revert Errors.InvalidAddress(user);

        tokenId = _tokenIdOf[user];
        if (tokenId != 0) return tokenId;

        tokenId = nextTokenId;
        nextTokenId = tokenId + 1;

        _tokenIdOf[user] = tokenId;
        _safeMint(user, tokenId);

        emit ScoreMinted(user, tokenId);
    }

    /// @inheritdoc ICreditScoreSBT
    function setScore(address user, uint16 newScore) external override onlyOwner {
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
