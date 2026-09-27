// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {LaunchToken} from "../../src/LaunchToken.sol";
import {SoulboundBadges} from "../../src/SoulboundBadges.sol";

abstract contract BadgeTestBase is Test {
    LaunchToken internal token;
    SoulboundBadges internal badges;
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant CAROL = address(0xCA401);
    address internal constant DEAD = 0x000000000000000000000000000000000000dEaD;
    uint256 internal constant FEE = 100 ether;

    function setUp() public virtual {
        token = new LaunchToken();
        badges = new SoulboundBadges(address(token));
        token.transfer(ALICE, 10_000 ether);
        token.transfer(BOB, 10_000 ether);
        vm.prank(ALICE);
        token.approve(address(badges), type(uint256).max);
        vm.prank(BOB);
        token.approve(address(badges), type(uint256).max);
    }

    function _create(address issuer, bytes32 name_) internal returns (uint256) {
        vm.prank(issuer);
        return badges.createBadgeType(name_);
    }

    function _award(address issuer, uint256 typeId, address holder) internal returns (uint256) {
        vm.prank(issuer);
        return badges.award(typeId, holder);
    }
}
