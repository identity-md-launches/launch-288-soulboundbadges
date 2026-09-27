// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {LaunchToken} from "../src/LaunchToken.sol";
import {SoulboundBadges} from "../src/SoulboundBadges.sol";

contract BadgeHandler is Test {
    LaunchToken public immutable token;
    SoulboundBadges public immutable badges;
    uint256 public created;
    uint256 public minted;
    uint256 public burned;
    mapping(address => uint256) public feesPaid;
    mapping(uint256 => address) public issuerModel;

    constructor(LaunchToken token_, SoulboundBadges badges_) {
        token = token_;
        badges = badges_;
        for (uint256 i; i < 4; ++i) {
            vm.prank(actor(i));
            token.approve(address(badges), type(uint256).max);
        }
    }

    function actor(uint256 index) public pure returns (address) {
        return address(uint160(0x1000 + index % 4));
    }

    function createType(uint256 seed) external {
        if (created >= 12) return;
        address issuer = actor(seed);
        vm.prank(issuer);
        uint256 typeId = badges.createBadgeType("Community");
        ++created;
        assertEq(typeId, created);
        issuerModel[typeId] = issuer;
        feesPaid[issuer] += 100 ether;
    }

    function award(uint256 typeSeed, uint256 holderSeed) external {
        if (created == 0) return;
        uint256 typeId = 1 + typeSeed % created;
        address holder = actor(holderSeed);
        if (badges.badgeOf(typeId, holder) != 0) return;
        vm.prank(issuerModel[typeId]);
        uint256 id = badges.award(typeId, holder);
        ++minted;
        assertEq(id, minted, "IDs must never be reused");
    }

    function burn(uint256 typeSeed, uint256 holderSeed) external {
        if (created == 0) return;
        uint256 typeId = 1 + typeSeed % created;
        address holder = actor(holderSeed);
        uint256 id = badges.badgeOf(typeId, holder);
        if (id == 0) return;
        vm.prank(holder);
        badges.burn(id);
        ++burned;
    }

    function handover(uint256 typeSeed, uint256 issuerSeed) external {
        if (created == 0) return;
        uint256 typeId = 1 + typeSeed % created;
        address newIssuer = actor(issuerSeed);
        vm.prank(issuerModel[typeId]);
        badges.setIssuer(typeId, newIssuer);
        issuerModel[typeId] = newIssuer;
    }

    function tryMove(uint256 typeSeed, uint256 holderSeed) external {
        if (created == 0) return;
        address holder = actor(holderSeed);
        uint256 id = badges.badgeOf(1 + typeSeed % created, holder);
        if (id == 0) return;
        vm.prank(holder);
        vm.expectRevert(SoulboundBadges.Soulbound.selector);
        badges.transferFrom(holder, address(0xDEAD), id);
    }
}

contract BadgesInvariantTest is StdInvariant, Test {
    LaunchToken private token;
    SoulboundBadges private badges;
    BadgeHandler private handler;
    uint256 private constant FUNDING = 10_000 ether;

    function setUp() public {
        token = new LaunchToken();
        badges = new SoulboundBadges(address(token));
        handler = new BadgeHandler(token, badges);
        for (uint256 i; i < 4; ++i) {
            token.transfer(handler.actor(i), FUNDING);
        }
        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = handler.createType.selector;
        selectors[1] = handler.award.selector;
        selectors[2] = handler.burn.selector;
        selectors[3] = handler.handover.selector;
        selectors[4] = handler.tryMove.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_eachCreatedTypePaidExactlyOnceWithoutCustody() public view {
        assertEq(badges.typeCount(), handler.created());
        uint256 deadBalance = token.balanceOf(badges.BURN_ADDRESS());
        assertEq(deadBalance, handler.created() * 100 ether);
        assertEq(token.balanceOf(address(badges)), 0);
        assertEq(token.totalSupply(), 1_000_000_000 ether);
        uint256 accounted = deadBalance + token.balanceOf(address(this));
        for (uint256 i; i < 4; ++i) {
            address actor_ = handler.actor(i);
            uint256 balance = token.balanceOf(actor_);
            assertEq(balance + handler.feesPaid(actor_), FUNDING);
            accounted += balance;
        }
        assertEq(accounted, token.totalSupply());
    }

    function invariant_badgeLookupOwnershipEnumerationAndIssuersAgree() public view {
        uint256 live;
        for (uint256 a; a < 4; ++a) {
            address holder = handler.actor(a);
            uint256 held;
            for (uint256 typeId = 1; typeId <= handler.created(); ++typeId) {
                (, address issuer) = badges.badgeType(typeId);
                assertEq(issuer, handler.issuerModel(typeId));
                uint256 id = badges.badgeOf(typeId, holder);
                if (id != 0) {
                    ++held;
                    assertEq(badges.ownerOf(id), holder);
                    assertEq(badges.typeOf(id), typeId);
                    assertTrue(badges.locked(id));
                    assertEq(badges.getApproved(id), address(0));
                }
            }
            assertEq(badges.balanceOf(holder), held);
            for (uint256 index; index < held; ++index) {
                uint256 id = badges.tokenOfOwnerByIndex(holder, index);
                assertEq(badges.ownerOf(id), holder);
                assertEq(badges.badgeOf(badges.typeOf(id), holder), id);
                for (uint256 earlier; earlier < index; ++earlier) {
                    assertNotEq(badges.tokenOfOwnerByIndex(holder, earlier), id);
                }
            }
            live += held;
        }
        assertEq(badges.totalSupply(), live);
        assertEq(live, handler.minted() - handler.burned());
        for (uint256 index; index < live; ++index) {
            uint256 id = badges.tokenByIndex(index);
            assertEq(badges.badgeOf(badges.typeOf(id), badges.ownerOf(id)), id);
            for (uint256 earlier; earlier < index; ++earlier) {
                assertNotEq(badges.tokenByIndex(earlier), id);
            }
        }
    }
}
