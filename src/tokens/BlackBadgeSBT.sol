// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {Errors} from "../utils/Errors.sol";
import {IBlackBadgeSBT} from "../interfaces/IBlackBadgeSBT.sol";
import {IERC5192} from "../interfaces/IERC5192.sol";

/// @title BlackBadgeSBT
/// @notice Non-transferable ERC-721 token representing a "black badge" (default/blacklist mark).
/// @dev Only the owner can mint badges. Transfers are disabled (soulbound).
contract BlackBadgeSBT is IBlackBadgeSBT, IERC5192, ERC721, Ownable {
    /// @notice Next token ID to be minted.
    uint256 public nextTokenId;

    /// @notice Mapping from user address to their badge token ID (0 = no badge).
    mapping(address user => uint256 tokenId) internal _tokenIdOf;

    /// @notice Emitted when a badge is minted.
    event BadgeMinted(address indexed user, uint256 indexed tokenId);

    /// @notice Initializes the contract with the owner (minter) address.
    /// @param initialOwner Address authorized to mint badges.
    constructor(address initialOwner) ERC721("BlackBadge", "BBADGE") Ownable(initialOwner) {
        nextTokenId = 1;
    }

    /// @inheritdoc IERC5192
    function locked(uint256 tokenId) external view returns (bool) {
        if (_ownerOf(tokenId) == address(0)) revert ERC721NonexistentToken(tokenId);
        return true;
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, IERC165) returns (bool) {
        return interfaceId == type(IERC5192).interfaceId || super.supportsInterface(interfaceId);
    }

    function hasBadge(address user) external view returns (bool) {
        return _tokenIdOf[user] != 0;
    }

    function mintBadge(address user) external onlyOwner returns (uint256 tokenId) {
        if (user == address(0)) revert Errors.InvalidAddress(user);

        tokenId = _tokenIdOf[user];
        if (tokenId != 0) return tokenId;

        tokenId = nextTokenId;
        nextTokenId = tokenId + 1;

        _tokenIdOf[user] = tokenId;
        _safeMint(user, tokenId);

        emit BadgeMinted(user, tokenId);
        emit Locked(tokenId);
    }

    /// @notice Returns the token ID owned by a user (0 if none).
    /// @param user Address to query.
    /// @return Token ID or 0.
    function tokenIdOf(address user) external view returns (uint256) {
        return _tokenIdOf[user];
    }

    /// @dev Override to prevent transfers. Soulbound tokens cannot be transferred.
    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        address from = _ownerOf(tokenId);

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
