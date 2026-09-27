// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.26;

/// @notice Minimal soulbound interface (ERC-5192).
interface IERC5192 {
    event Locked(uint256 tokenId);
    event Unlocked(uint256 tokenId);

    /// @notice Returns true for a live, permanently locked badge; reverts for a nonexistent badge.
    function locked(uint256 tokenId) external view returns (bool);
}
