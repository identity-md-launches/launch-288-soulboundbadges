// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {LaunchToken} from "../src/LaunchToken.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

contract LaunchTokenTest is Test {
    LaunchToken private token;
    address private constant USER = address(0xBEEF);
    address private constant SPENDER = address(0xCAFE);
    uint256 private constant SUPPLY = 1_000_000_000 ether;

    function setUp() public {
        token = new LaunchToken();
    }

    function test_fixedSupplyAndMetadata() public view {
        assertEq(token.name(), "Badges");
        assertEq(token.symbol(), "BDGE");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function testFuzz_transferConservesSupply(uint256 value) public {
        uint256 amount = bound(value, 0, SUPPLY);
        assertTrue(token.transfer(USER, amount));
        assertEq(token.balanceOf(USER), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_approvalSpendsExactAllowance() public {
        token.approve(SPENDER, 100 ether);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), USER, 100 ether));
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(USER), 100 ether);
        vm.prank(SPENDER);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        token.transferFrom(address(this), USER, 1);
    }

    function test_rejectsInsufficientBalanceAndZeroRecipient() public {
        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, USER, 0, 1));
        token.transfer(SPENDER, 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
    }

    function test_noAdminOrMintSelectorsForDeployerOrStranger() public {
        string[12] memory signatures = [
            "mint(address,uint256)",
            "mint(uint256)",
            "mint()",
            "issue(uint256)",
            "setOwner(address)",
            "transferOwnership(address)",
            "upgradeTo(address)",
            "initialize(address)",
            "unpause()",
            "setMinter(address)",
            "pause()",
            "burn(uint256)"
        ];
        for (uint256 actor; actor < 2; ++actor) {
            for (uint256 i; i < signatures.length; ++i) {
                vm.prank(actor == 0 ? address(this) : USER);
                (bool ok,) = address(token).call(abi.encodeWithSignature(signatures[i], USER, uint256(1 ether)));
                assertFalse(ok, signatures[i]);
            }
        }
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(USER), 0);
    }
}
