// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BadgeTestBase} from "./helpers/BadgeTestBase.sol";
import {SoulboundBadges} from "../src/SoulboundBadges.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract HostileReceiver is IERC721Receiver {
    SoulboundBadges public immutable badges;
    uint256 public attempts;
    bool public sawConsistentState;

    constructor(SoulboundBadges badges_) {
        badges = badges_;
    }

    function onERC721Received(address, address, uint256 id, bytes calldata) external returns (bytes4) {
        require(msg.sender == address(badges), "unexpected NFT");
        uint256 typeId = badges.typeOf(id);
        sawConsistentState = badges.ownerOf(id) == address(this) && badges.badgeOf(typeId, address(this)) == id
            && badges.locked(id) && badges.tokenOfOwnerByIndex(address(this), 0) == id;
        _reject(
            abi.encodeCall(badges.award, (typeId, address(this))), ReentrancyGuard.ReentrancyGuardReentrantCall.selector
        );
        _reject(abi.encodeCall(badges.burn, (id)), ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        _reject(
            abi.encodeCall(badges.createBadgeType, (bytes32("Recursive"))),
            ReentrancyGuard.ReentrancyGuardReentrantCall.selector
        );
        _reject(
            abi.encodeCall(badges.setIssuer, (typeId, address(0xCAFE))),
            ReentrancyGuard.ReentrancyGuardReentrantCall.selector
        );
        _reject(
            abi.encodeCall(badges.transferFrom, (address(this), address(0xCAFE), id)),
            SoulboundBadges.Soulbound.selector
        );
        _reject(
            abi.encodeWithSignature("safeTransferFrom(address,address,uint256)", address(this), address(0xCAFE), id),
            SoulboundBadges.Soulbound.selector
        );
        _reject(
            abi.encodeWithSignature(
                "safeTransferFrom(address,address,uint256,bytes)", address(this), address(0xCAFE), id, bytes("callback")
            ),
            SoulboundBadges.Soulbound.selector
        );
        _reject(abi.encodeCall(badges.approve, (address(0xCAFE), id)), SoulboundBadges.Soulbound.selector);
        _reject(abi.encodeCall(badges.setApprovalForAll, (address(0xCAFE), true)), SoulboundBadges.Soulbound.selector);
        return IERC721Receiver.onERC721Received.selector;
    }

    function burnAfterCallback(uint256 id) external {
        badges.burn(id);
    }

    function _reject(bytes memory data, bytes4 expectedError) private {
        (bool ok, bytes memory result) = address(badges).call(data);
        require(!ok && bytes4(result) == expectedError, "callback bypass");
        ++attempts;
    }
}

contract RejectingReceiver is IERC721Receiver {
    bool public accepts;

    function setAccepts(bool value) external {
        accepts = value;
    }

    function onERC721Received(address, address, uint256, bytes calldata) external view returns (bytes4) {
        return accepts ? IERC721Receiver.onERC721Received.selector : bytes4(0);
    }
}

contract FalseFeeToken {
    function transferFrom(address, address, uint256) external pure returns (bool) {
        return false;
    }
}

contract ReenteringFeeToken {
    SoulboundBadges public badges;
    bool public blocked;

    function setBadges(SoulboundBadges badges_) external {
        badges = badges_;
    }

    function transferFrom(address, address, uint256) external returns (bool) {
        (bool ok, bytes memory reason) =
            address(badges).call(abi.encodeCall(badges.createBadgeType, (bytes32("Reentered"))));
        blocked = !ok && bytes4(reason) == ReentrancyGuard.ReentrancyGuardReentrantCall.selector;
        require(blocked, "fee reentrancy was not blocked");
        return false;
    }
}

contract SoulboundBadgesSecurityTest is BadgeTestBase {
    function test_allTransferAndApprovalRoutesRevertForHolderIssuerAndStranger() public {
        _create(ALICE, "Builder");
        _award(ALICE, 1, BOB);
        address[3] memory actors = [BOB, ALICE, CAROL];
        for (uint256 a; a < actors.length; ++a) {
            for (uint256 self; self < 2; ++self) {
                address recipient = self == 0 ? CAROL : BOB;
                _blocked(actors[a], abi.encodeCall(badges.transferFrom, (BOB, recipient, 1)));
                _blocked(
                    actors[a], abi.encodeWithSignature("safeTransferFrom(address,address,uint256)", BOB, recipient, 1)
                );
                _blocked(
                    actors[a],
                    abi.encodeWithSignature(
                        "safeTransferFrom(address,address,uint256,bytes)", BOB, recipient, 1, bytes("payload")
                    )
                );
            }
            _blocked(actors[a], abi.encodeCall(badges.approve, (CAROL, 1)));
            _blocked(actors[a], abi.encodeCall(badges.approve, (address(0), 1)));
            _blocked(actors[a], abi.encodeCall(badges.setApprovalForAll, (CAROL, true)));
            _blocked(actors[a], abi.encodeCall(badges.setApprovalForAll, (CAROL, false)));
        }
        assertEq(badges.ownerOf(1), BOB);
        assertEq(badges.badgeOf(1, BOB), 1);
        assertEq(badges.badgeOf(1, CAROL), 0);
        assertEq(badges.getApproved(1), address(0));
        assertFalse(badges.isApprovedForAll(BOB, CAROL));
        assertEq(badges.totalSupply(), 1);
    }

    function test_transferToZeroCannotSubstituteForHolderBurn() public {
        _create(ALICE, "Builder");
        _award(ALICE, 1, BOB);
        bytes memory reason = abi.encodeWithSelector(IERC721Errors.ERC721InvalidReceiver.selector, address(0));
        vm.startPrank(BOB);
        vm.expectRevert(reason);
        badges.transferFrom(BOB, address(0), 1);
        vm.expectRevert(reason);
        badges.safeTransferFrom(BOB, address(0), 1);
        vm.expectRevert(reason);
        badges.safeTransferFrom(BOB, address(0), 1, "");
        vm.stopPrank();
        assertEq(badges.ownerOf(1), BOB);
    }

    function test_receiverReentrancyCannotMoveOrRewriteBadgeState() public {
        _create(ALICE, "Builder");
        HostileReceiver receiver = new HostileReceiver(badges);
        vm.prank(ALICE);
        badges.setIssuer(1, address(receiver));
        token.transfer(address(receiver), FEE);
        vm.prank(address(receiver));
        token.approve(address(badges), FEE);
        uint256 id = _award(address(receiver), 1, address(receiver));
        assertTrue(receiver.sawConsistentState());
        assertEq(receiver.attempts(), 9);
        assertEq(badges.ownerOf(id), address(receiver));
        assertEq(badges.typeCount(), 1);
        assertEq(badges.totalSupply(), 1);
        assertEq(token.balanceOf(address(receiver)), FEE);
        assertEq(token.balanceOf(DEAD), FEE);
        (, address issuer) = badges.badgeType(1);
        assertEq(issuer, address(receiver));
        receiver.burnAfterCallback(id);
        assertEq(badges.totalSupply(), 0);
        assertEq(badges.badgeOf(1, address(receiver)), 0);
    }

    function test_rejectingReceiverRollsBackMintAndDoesNotConsumeId() public {
        _create(ALICE, "Builder");
        RejectingReceiver receiver = new RejectingReceiver();
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InvalidReceiver.selector, address(receiver)));
        badges.award(1, address(receiver));
        assertEq(badges.badgeOf(1, address(receiver)), 0);
        assertEq(badges.balanceOf(address(receiver)), 0);
        assertEq(badges.totalSupply(), 0);
        // Another holder's award still succeeds after a failed safe mint.
        assertEq(_award(ALICE, 1, BOB), 1);
        receiver.setAccepts(true);
        assertEq(_award(ALICE, 1, address(receiver)), 2);
    }

    function test_contractWithoutReceiverCannotBeAwarded() public {
        _create(ALICE, "Builder");
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InvalidReceiver.selector, address(token)));
        badges.award(1, address(token));
        assertEq(badges.totalSupply(), 0);
        assertEq(badges.badgeOf(1, address(token)), 0);
    }

    function test_safeERC20FalseReturnCannotCreateType() public {
        FalseFeeToken fake = new FalseFeeToken();
        SoulboundBadges instance = new SoulboundBadges(address(fake));
        vm.expectRevert(abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, address(fake)));
        instance.createBadgeType("Unpaid");
        assertEq(instance.typeCount(), 0);
    }

    function test_feeCallbackCannotReenterAndFailedTransferRollsBackEverything() public {
        ReenteringFeeToken fake = new ReenteringFeeToken();
        SoulboundBadges instance = new SoulboundBadges(address(fake));
        fake.setBadges(instance);
        vm.expectCall(address(instance), abi.encodeCall(instance.createBadgeType, (bytes32("Reentered"))));
        vm.expectRevert(abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, address(fake)));
        instance.createBadgeType("Outer");
        assertEq(instance.typeCount(), 0);
        assertFalse(fake.blocked(), "even mock state rolls back");
    }

    function test_ethAndUnknownSelectorsAreRejected() public {
        vm.deal(ALICE, 1 ether);
        vm.startPrank(ALICE);
        (bool receiveOk,) = address(badges).call{value: 1}("");
        (bool payableOk,) = address(badges).call{value: 1}(abi.encodeCall(badges.createBadgeType, (bytes32("PaidETH"))));
        (bool unknownOk,) = address(badges).call(hex"deadbeef");
        vm.stopPrank();
        assertFalse(receiveOk);
        assertFalse(payableOk);
        assertFalse(unknownOk);
        assertEq(address(badges).balance, 0);
        assertEq(badges.typeCount(), 0);
        assertEq(token.balanceOf(DEAD), 0);
    }

    function test_unsolicitedTokenTransferDocumentsCustodyLimit() public {
        // Standard ERC-20 transfers do not consult the receiving contract.
        vm.prank(ALICE);
        assertTrue(token.transfer(address(badges), 1));
        assertEq(token.balanceOf(address(badges)), 1);
        _create(ALICE, "Builder");
        assertEq(token.balanceOf(DEAD), FEE);
        assertEq(token.balanceOf(address(badges)), 1, "fees still go directly to the dead address");
    }

    function _blocked(address actor, bytes memory data) private {
        vm.prank(actor);
        (bool ok, bytes memory reason) = address(badges).call(data);
        assertFalse(ok);
        assertEq(bytes4(reason), SoulboundBadges.Soulbound.selector);
    }
}
