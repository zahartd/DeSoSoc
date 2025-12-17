// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {Errors} from "../utils/Errors.sol";
import {ICreditScoreSBT} from "../interfaces/ICreditScoreSBT.sol";

/// @title CreditScoreSBT
/// @notice Non-transferable ERC-721 token representing a user's credit score.
/// @dev Only the owner can mint tokens and update scores. Transfers are disabled (soulbound).
contract CreditScoreSBT is ICreditScoreSBT, ERC721, Ownable {
    /// @notice Next token ID to be minted.
    uint256 public nextTokenId;

    /// @notice Mapping from user address to their token ID (0 = no token).
    mapping(address user => uint256 tokenId) internal _tokenIdOf;

    /// @notice Mapping from token ID to score.
    mapping(uint256 tokenId => uint16 score) internal _scoreOf;

    /// @notice Emitted when a score token is minted.
    event ScoreMinted(address indexed user, uint256 indexed tokenId, uint16 initialScore);

    /// @notice Emitted when a user's score is updated.
    event ScoreUpdated(address indexed user, uint16 oldScore, uint16 newScore);

    /// @notice Initializes the contract with the owner address.
    /// @param initialOwner Address authorized to mint tokens and update scores.
    constructor(address initialOwner) ERC721("CreditScore", "CSCORE") Ownable(initialOwner) {
        nextTokenId = 1;
    }

    /// @inheritdoc ICreditScoreSBT
    function hasToken(address user) external view returns (bool) {
        return _tokenIdOf[user] != 0;
    }

    /// @inheritdoc ICreditScoreSBT
    function tokenOf(address user) external view returns (uint256) {
        return _tokenIdOf[user];
    }

    /// @inheritdoc ICreditScoreSBT
    function scoreOf(address user) external view returns (uint16) {
        uint256 tokenId = _tokenIdOf[user];
        if (tokenId == 0) return 0;
        return _scoreOf[tokenId];
    }

    /// @inheritdoc ICreditScoreSBT
    function mintIfNeeded(address user, uint16 initialScore) external onlyOwner returns (uint256 tokenId) {
        if (user == address(0)) revert Errors.InvalidAddress();

        // If user already has a token, return existing token ID
        tokenId = _tokenIdOf[user];
        if (tokenId != 0) return tokenId;

        // Mint new token
        tokenId = nextTokenId;
        nextTokenId = tokenId + 1;

        _tokenIdOf[user] = tokenId;
        _scoreOf[tokenId] = initialScore;
        _safeMint(user, tokenId);

        emit ScoreMinted(user, tokenId, initialScore);
    }

    /// @inheritdoc ICreditScoreSBT
    function setScore(address user, uint16 newScore) external onlyOwner {
        if (user == address(0)) revert Errors.InvalidAddress();

        uint256 tokenId = _tokenIdOf[user];

        // Auto-mint if user doesn't have a token
        if (tokenId == 0) {
            tokenId = nextTokenId;
            nextTokenId = tokenId + 1;

            _tokenIdOf[user] = tokenId;
            _safeMint(user, tokenId);

            emit ScoreMinted(user, tokenId, newScore);
        }

        uint16 oldScore = _scoreOf[tokenId];
        _scoreOf[tokenId] = newScore;

        emit ScoreUpdated(user, oldScore, newScore);
    }

    // =========================================================================
    // Soulbound: disable all transfers
    // =========================================================================

    /// @dev Override to prevent transfers. Soulbound tokens cannot be transferred.
    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        address from = _ownerOf(tokenId);

        // Allow minting (from == address(0)), block all other transfers
        if (from != address(0)) {
            revert Errors.Unauthorized();
        }

        return super._update(to, tokenId, auth);
    }

    /// @dev Override approve to disable approvals (not needed for soulbound).
    function approve(address, uint256) public pure override {
        revert Errors.Unauthorized();
    }

    /// @dev Override setApprovalForAll to disable approvals (not needed for soulbound).
    function setApprovalForAll(address, bool) public pure override {
        revert Errors.Unauthorized();
    }
}

