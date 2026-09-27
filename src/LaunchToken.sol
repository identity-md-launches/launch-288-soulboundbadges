// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Fixed-supply Badges token for the Sepolia project launch.
contract LaunchToken is ERC20 {
    constructor() ERC20("Badges", "BDGE") {
        _mint(msg.sender, 1_000_000_000 * 10 ** 18);
    }
}
