// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {LaunchToken} from "../src/LaunchToken.sol";
import {SoulboundBadges} from "../src/SoulboundBadges.sol";

/// @dev Constructor-only factory model. No initialization calls or token funding of the application.
contract ConstructorFactory {
    function deploy() external returns (LaunchToken token, SoulboundBadges badges) {
        token = new LaunchToken{salt: bytes32(uint256(1))}();
        badges = new SoulboundBadges{salt: bytes32(uint256(2))}(address(token));
    }

    function tryPayableConstruction(bytes memory code) external returns (address deployed) {
        assembly ("memory-safe") {
            deployed := create(1, add(code, 32), mload(code))
        }
    }
}

contract DeploymentTest is Test {
    function test_factoryConstructionPreservesSupplyAndNeedsNoInitialization() public {
        ConstructorFactory factory = new ConstructorFactory();
        (LaunchToken token, SoulboundBadges badges) = factory.deploy();
        assertEq(token.totalSupply(), 1_000_000_000 ether);
        assertEq(token.balanceOf(address(factory)), token.totalSupply());
        assertEq(token.balanceOf(address(badges)), 0);
        assertEq(address(badges.token()), address(token));
        assertEq(badges.typeCount(), 0);
        _checkRuntime(address(token));
        _checkRuntime(address(badges));
        vm.prank(address(factory));
        token.transfer(address(this), 100 ether);
        token.approve(address(badges), 100 ether);
        assertEq(badges.createBadgeType("Ready"), 1);
        assertEq(badges.award(1, address(0xBEEF)), 1);
    }

    function test_bothConstructorsRejectETH() public {
        ConstructorFactory factory = new ConstructorFactory();
        vm.deal(address(factory), 2);
        assertEq(factory.tryPayableConstruction(type(LaunchToken).creationCode), address(0));
        LaunchToken token = new LaunchToken();
        bytes memory badgeCode = abi.encodePacked(type(SoulboundBadges).creationCode, abi.encode(address(token)));
        assertEq(factory.tryPayableConstruction(badgeCode), address(0));
    }

    function _checkRuntime(address deployed) private view {
        bytes memory code = deployed.code;
        assertGt(code.length, 0);
        assertLe(code.length, 24_576);
        for (uint256 i; i < code.length; ++i) {
            uint8 op = uint8(code[i]);
            if (op >= 0x60 && op <= 0x7f) {
                i += op - 0x5f;
                continue;
            }
            assertTrue(op != 0xf4 && op != 0xf2 && op != 0xff, "forbidden runtime opcode");
        }
    }
}
