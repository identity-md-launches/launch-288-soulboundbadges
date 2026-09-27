// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC5192} from "./interfaces/IERC5192.sol";

/// @notice Sepolia test toy. Badges are not credentials.
/// @dev Fully configured at construction; no owner, upgrade path, or custody of creation fees.
contract SoulboundBadges is ERC721Enumerable, IERC5192, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Strings for uint256;

    uint256 public constant CREATION_FEE = 100 * 10 ** 18;
    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;
    IERC20 public immutable token;
    uint256 public typeCount;

    struct BadgeType {
        bytes32 name;
        address issuer;
    }

    mapping(uint256 typeId => BadgeType) private _types;
    mapping(uint256 typeId => mapping(address holder => uint256 tokenId)) private _badges;
    mapping(uint256 tokenId => uint256 typeId) private _tokenTypes;
    uint256 private _nextTokenId = 1;

    error InvalidToken();
    error InvalidName();
    error UnknownType(uint256 typeId);
    error NotIssuer(uint256 typeId, address caller);
    error ZeroAddress();
    error AlreadyAwarded(uint256 typeId, address holder);
    error NotHolder(uint256 tokenId, address caller);
    error Soulbound();

    event TypeCreated(uint256 indexed typeId, bytes32 name, address indexed issuer);
    event IssuerChanged(uint256 indexed typeId, address indexed previousIssuer, address indexed newIssuer);

    /// @param token_ The launch's BDGE address, supplied as $token by the project factory.
    constructor(address token_) ERC721("Soulbound Badges", "SBADGE") {
        if (token_.code.length == 0) revert InvalidToken();
        token = IERC20(token_);
    }

    /// @notice Creates a type after sending 100 BDGE directly from the caller to the dead address.
    /// @dev Names are nonempty, right-zero-padded ASCII [A-Za-z0-9 _-]. Duplicate names are allowed.
    function createBadgeType(bytes32 name_) external nonReentrant returns (uint256 typeId) {
        _validateName(name_);
        token.safeTransferFrom(msg.sender, BURN_ADDRESS, CREATION_FEE);
        typeId = ++typeCount;
        _types[typeId] = BadgeType(name_, msg.sender);
        emit TypeCreated(typeId, name_, msg.sender);
    }

    /// @notice Immediately hands a type to a nonzero new issuer; existing badges remain live.
    function setIssuer(uint256 typeId, address newIssuer) external nonReentrant {
        BadgeType storage badge = _requireIssuer(typeId);
        if (newIssuer == address(0)) revert ZeroAddress();
        address previousIssuer = badge.issuer;
        badge.issuer = newIssuer;
        emit IssuerChanged(typeId, previousIssuer, newIssuer);
    }

    /// @notice Awards one live badge of this type to a holder. Contracts must accept ERC-721 safe minting.
    function award(uint256 typeId, address to) external nonReentrant returns (uint256 tokenId) {
        _requireIssuer(typeId);
        if (to == address(0)) revert ZeroAddress();
        if (_badges[typeId][to] != 0) revert AlreadyAwarded(typeId, to);
        tokenId = _nextTokenId++;
        _badges[typeId][to] = tokenId;
        _tokenTypes[tokenId] = typeId;
        // All lookup and enumerable state is installed before the receiver callback.
        _safeMint(to, tokenId);
    }

    /// @notice Only the holder may burn. The issuer can then re-award with a fresh token id.
    function burn(uint256 tokenId) external nonReentrant {
        address holder = _requireOwned(tokenId);
        if (msg.sender != holder) revert NotHolder(tokenId, msg.sender);
        delete _badges[_tokenTypes[tokenId]][holder];
        delete _tokenTypes[tokenId];
        _burn(tokenId);
    }

    function badgeType(uint256 typeId) external view returns (bytes32 name_, address issuer) {
        BadgeType storage badge = _requireType(typeId);
        return (badge.name, badge.issuer);
    }

    /// @notice Returns the live badge id, or zero (including for an unknown type or zero holder).
    function badgeOf(uint256 typeId, address holder) external view returns (uint256) {
        return _badges[typeId][holder];
    }

    function typeOf(uint256 tokenId) external view returns (uint256) {
        _requireOwned(tokenId);
        return _tokenTypes[tokenId];
    }

    function locked(uint256 tokenId) external view override returns (bool) {
        _requireOwned(tokenId);
        return true;
    }

    function approve(address, uint256) public pure override(ERC721, IERC721) {
        revert Soulbound();
    }

    function setApprovalForAll(address, bool) public pure override(ERC721, IERC721) {
        revert Soulbound();
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IERC5192).interfaceId || super.supportsInterface(interfaceId);
    }

    /// @notice On-chain JSON and SVG. The issuer field reflects the type's current issuer.
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        uint256 typeId = _tokenTypes[tokenId];
        BadgeType storage badge = _types[typeId];
        string memory badgeName = _nameString(badge.name);
        string memory svg = string.concat(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 640 360">',
            '<rect width="640" height="360" rx="24" fill="hsl(',
            (uint256(keccak256(abi.encode(typeId))) % 360).toString(),
            ',60%,32%)"/>',
            '<text x="320" y="160" text-anchor="middle" font-family="monospace" font-size="24" fill="white">',
            badgeName,
            '</text><text x="320" y="220" text-anchor="middle" font-family="monospace" font-size="18" fill="white">Type #',
            typeId.toString(),
            '</text><text x="320" y="290" text-anchor="middle" font-family="monospace" font-size="14" fill="white">',
            "Sepolia test toy - not a credential</text></svg>"
        );
        string memory json = string.concat(
            '{"name":"',
            badgeName,
            '","typeId":',
            typeId.toString(),
            ',"issuer":"',
            Strings.toHexString(badge.issuer),
            '","description":"Sepolia test toy. Badges are not credentials.","image":"data:image/svg+xml;base64,',
            Base64.encode(bytes(svg)),
            '"}'
        );
        return string.concat("data:application/json;base64,", Base64.encode(bytes(json)));
    }

    /// @dev Central restriction covers transferFrom, both safeTransferFrom overloads, and self-transfers.
    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        if (to != address(0) && _ownerOf(tokenId) != address(0)) revert Soulbound();
        address from = super._update(to, tokenId, auth);
        if (from == address(0) && to != address(0)) emit Locked(tokenId);
        return from;
    }

    function _requireType(uint256 typeId) private view returns (BadgeType storage badge) {
        badge = _types[typeId];
        if (badge.issuer == address(0)) revert UnknownType(typeId);
    }

    function _requireIssuer(uint256 typeId) private view returns (BadgeType storage badge) {
        badge = _requireType(typeId);
        if (badge.issuer != msg.sender) revert NotIssuer(typeId, msg.sender);
    }

    function _validateName(bytes32 name_) private pure {
        if (name_ == bytes32(0)) revert InvalidName();
        bool padding = false;
        for (uint256 i; i < 32; ++i) {
            uint8 char = uint8(name_[i]);
            if (char == 0) {
                padding = true;
            } else if (
                padding
                    || !((char >= 65 && char <= 90)
                        || (char >= 97 && char <= 122)
                        || (char >= 48 && char <= 57)
                        || char == 32
                        || char == 95
                        || char == 45)
            ) {
                // Each malformed byte must reject the complete name, before payment.
                // forge-lint: disable-next-line(require-revert-in-loop)
                revert InvalidName();
            }
        }
    }

    function _nameString(bytes32 name_) private pure returns (string memory) {
        uint256 length = 0;
        while (length < 32 && name_[length] != 0) ++length;
        bytes memory result = new bytes(length);
        for (uint256 i; i < length; ++i) {
            result[i] = name_[i];
        }
        return string(result);
    }
}
