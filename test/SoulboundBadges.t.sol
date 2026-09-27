// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BadgeTestBase} from "./helpers/BadgeTestBase.sol";
import {DataURI} from "./helpers/DataURI.sol";
import {SoulboundBadges} from "../src/SoulboundBadges.sol";
import {IERC20Errors, IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC5192} from "../src/interfaces/IERC5192.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract SoulboundBadgesTest is BadgeTestBase {
    event TypeCreated(uint256 indexed typeId, bytes32 name, address indexed issuer);
    event IssuerChanged(uint256 indexed typeId, address indexed previousIssuer, address indexed newIssuer);

    function test_initialConfigurationAndInterfaces() public view {
        assertEq(address(badges.token()), address(token));
        assertEq(badges.CREATION_FEE(), FEE);
        assertEq(badges.BURN_ADDRESS(), DEAD);
        assertEq(badges.name(), "Soulbound Badges");
        assertEq(badges.symbol(), "SBADGE");
        assertEq(badges.typeCount(), 0);
        assertEq(badges.totalSupply(), 0);
        assertEq(token.balanceOf(address(badges)), 0);
        assertTrue(badges.supportsInterface(0x01ffc9a7));
        assertTrue(badges.supportsInterface(0x80ac58cd));
        assertTrue(badges.supportsInterface(0x5b5e139f));
        assertTrue(badges.supportsInterface(0x780e9d63));
        assertTrue(badges.supportsInterface(0xb45a3c0e));
        assertFalse(badges.supportsInterface(0xffffffff));
    }

    function test_constructorRejectsZeroAndNonContract() public {
        vm.expectRevert(SoulboundBadges.InvalidToken.selector);
        new SoulboundBadges(address(0));
        vm.expectRevert(SoulboundBadges.InvalidToken.selector);
        new SoulboundBadges(ALICE);
    }

    function test_createChargesExactFeeDirectlyAndAllowsDuplicateNames() public {
        vm.prank(ALICE);
        token.approve(address(badges), 2 * FEE);
        vm.expectEmit(true, true, false, true, address(badges));
        emit TypeCreated(1, bytes32("Builder"), ALICE);
        assertEq(_create(ALICE, "Builder"), 1);
        assertEq(_create(ALICE, "Builder"), 2);
        assertEq(_create(BOB, "Builder"), 3);
        (bytes32 name_, address issuer) = badges.badgeType(1);
        assertEq(name_, bytes32("Builder"));
        assertEq(issuer, ALICE);
        (, issuer) = badges.badgeType(3);
        assertEq(issuer, BOB);
        assertEq(badges.typeCount(), 3);
        assertEq(token.balanceOf(ALICE), 10_000 ether - 2 * FEE);
        assertEq(token.balanceOf(BOB), 10_000 ether - FEE);
        assertEq(token.balanceOf(DEAD), 3 * FEE);
        assertEq(token.balanceOf(address(badges)), 0);
        assertEq(token.allowance(ALICE, address(badges)), 0);
        assertEq(token.totalSupply(), 1_000_000_000 ether);
    }

    function test_noAllowanceAndShortAllowanceCannotSkipFee() public {
        token.transfer(CAROL, FEE);
        vm.startPrank(CAROL);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(badges), 0, FEE)
        );
        badges.createBadgeType("Unpaid");
        token.approve(address(badges), FEE - 1);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(badges), FEE - 1, FEE)
        );
        badges.createBadgeType("Underpaid");
        vm.stopPrank();
        assertEq(badges.typeCount(), 0);
        assertEq(token.balanceOf(DEAD), 0);
        assertEq(token.balanceOf(CAROL), FEE);
        assertEq(token.balanceOf(address(badges)), 0);
    }

    function test_failedFeeRollsBackAllowanceAndTypeCounter() public {
        vm.startPrank(CAROL);
        token.approve(address(badges), FEE);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, CAROL, 0, FEE));
        badges.createBadgeType("Unfunded");
        vm.stopPrank();
        assertEq(token.allowance(CAROL, address(badges)), FEE);
        assertEq(token.balanceOf(DEAD), 0);
        assertEq(badges.typeCount(), 0);
        token.transfer(CAROL, FEE);
        assertEq(_create(CAROL, "Funded"), 1);
    }

    function test_nameBoundariesAndCharset() public {
        assertEq(_create(ALICE, "A"), 1);
        assertEq(_create(ALICE, "ABCDEFGHIJKLMNOPQRSTUVWXYZ012345"), 2);
        assertEq(_create(ALICE, "abcXYZ012 _-"), 3);
        assertEq(_create(ALICE, " "), 4);
        bytes32[10] memory invalid = [
            bytes32(0),
            bytes32("<script>"),
            bytes32('"name"'),
            bytes32("a&b"),
            bytes32("a'b"),
            bytes32("line\nfeed"),
            bytes32("tab\t"),
            bytes32("back\\slash"),
            bytes32(hex"410042"),
            bytes32(hex"c3a9")
        ];
        for (uint256 i; i < invalid.length; ++i) {
            vm.prank(ALICE);
            vm.expectRevert(SoulboundBadges.InvalidName.selector);
            badges.createBadgeType(invalid[i]);
        }
        assertEq(badges.typeCount(), 4);
        assertEq(token.balanceOf(DEAD), 4 * FEE);
    }

    function testFuzz_singleByteAlphabetIsExact(uint8 char) public {
        bytes32 candidate = bytes32(bytes1(char));
        bool allowed = DataURI.contains(
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 _-", string(abi.encodePacked(bytes1(char)))
        );
        if (!allowed) {
            vm.prank(ALICE);
            vm.expectRevert(SoulboundBadges.InvalidName.selector);
            badges.createBadgeType(candidate);
            assertEq(token.balanceOf(DEAD), 0);
        } else {
            assertEq(_create(ALICE, candidate), 1);
            (bytes32 actual,) = badges.badgeType(1);
            assertEq(actual, candidate);
            assertEq(token.balanceOf(DEAD), FEE);
        }
    }

    function testFuzz_anyNonzeroByteAfterPaddingIsRejected(uint8 value, uint8 offset) public {
        uint8 nonzero = uint8(bound(value, 1, 255));
        uint256 index = bound(offset, 2, 31);
        bytes memory candidate = new bytes(32);
        candidate[0] = "A";
        candidate[index] = bytes1(nonzero);
        vm.prank(ALICE);
        vm.expectRevert(SoulboundBadges.InvalidName.selector);
        badges.createBadgeType(bytes32(candidate));
        assertEq(badges.typeCount(), 0);
        assertEq(token.balanceOf(DEAD), 0);
    }

    function test_awardSequentialIdsEnumerateAndEmitLocked() public {
        _create(ALICE, "Builder");
        _create(BOB, "Helper");
        vm.expectEmit(true, true, true, true, address(badges));
        emit IERC721.Transfer(address(0), CAROL, 1);
        vm.expectEmit(false, false, false, true, address(badges));
        emit IERC5192.Locked(1);
        assertEq(_award(ALICE, 1, CAROL), 1);
        assertEq(_award(BOB, 2, CAROL), 2);
        assertEq(_award(ALICE, 1, BOB), 3);
        assertEq(badges.totalSupply(), 3);
        assertEq(badges.balanceOf(CAROL), 2);
        assertEq(badges.tokenOfOwnerByIndex(CAROL, 0), 1);
        assertEq(badges.tokenOfOwnerByIndex(CAROL, 1), 2);
        assertEq(badges.tokenByIndex(2), 3);
        assertEq(badges.ownerOf(1), CAROL);
        assertEq(badges.typeOf(2), 2);
        assertEq(badges.badgeOf(1, CAROL), 1);
        assertTrue(badges.locked(1));
        assertEq(badges.getApproved(1), address(0));
        assertFalse(badges.isApprovedForAll(CAROL, ALICE));
        assertEq(token.balanceOf(DEAD), 2 * FEE);
        assertEq(token.balanceOf(address(badges)), 0);
    }

    function test_awardAuthorizationZeroAndDuplicates() public {
        _create(ALICE, "Builder");
        vm.prank(BOB);
        vm.expectRevert(abi.encodeWithSelector(SoulboundBadges.NotIssuer.selector, 1, BOB));
        badges.award(1, BOB);
        vm.prank(ALICE);
        vm.expectRevert(SoulboundBadges.ZeroAddress.selector);
        badges.award(1, address(0));
        _award(ALICE, 1, BOB);
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(SoulboundBadges.AlreadyAwarded.selector, 1, BOB));
        badges.award(1, BOB);
        assertEq(badges.totalSupply(), 1);
        assertEq(_award(ALICE, 1, CAROL), 2);
    }

    function test_holderOnlyBurnAndReawardMaintainEnumeration() public {
        _create(ALICE, "Builder");
        _create(ALICE, "Helper");
        _award(ALICE, 1, BOB);
        _award(ALICE, 2, BOB);
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(SoulboundBadges.NotHolder.selector, 1, ALICE));
        badges.burn(1);
        vm.prank(CAROL);
        vm.expectRevert(abi.encodeWithSelector(SoulboundBadges.NotHolder.selector, 1, CAROL));
        badges.burn(1);
        vm.expectEmit(true, true, true, true, address(badges));
        emit IERC721.Transfer(BOB, address(0), 1);
        vm.prank(BOB);
        badges.burn(1);
        assertEq(badges.badgeOf(1, BOB), 0);
        assertEq(badges.totalSupply(), 1);
        assertEq(badges.balanceOf(BOB), 1);
        assertEq(badges.tokenOfOwnerByIndex(BOB, 0), 2);
        assertEq(badges.tokenByIndex(0), 2);
        _assertNonexistent(1);
        assertEq(_award(ALICE, 1, BOB), 3);
        assertEq(badges.badgeOf(1, BOB), 3);
        assertEq(badges.totalSupply(), 2);
        vm.expectRevert(abi.encodeWithSelector(ERC721Enumerable.ERC721OutOfBoundsIndex.selector, BOB, 2));
        badges.tokenOfOwnerByIndex(BOB, 2);
    }

    function test_issuerHandoverChangesAuthorizationAndMetadataOnly() public {
        _create(ALICE, "Builder");
        _award(ALICE, 1, CAROL);
        vm.prank(BOB);
        vm.expectRevert(abi.encodeWithSelector(SoulboundBadges.NotIssuer.selector, 1, BOB));
        badges.setIssuer(1, BOB);
        vm.prank(ALICE);
        vm.expectRevert(SoulboundBadges.ZeroAddress.selector);
        badges.setIssuer(1, address(0));
        vm.expectEmit(true, true, true, true, address(badges));
        emit IssuerChanged(1, ALICE, BOB);
        vm.prank(ALICE);
        badges.setIssuer(1, BOB);
        (, address issuer) = badges.badgeType(1);
        assertEq(issuer, BOB);
        assertEq(badges.ownerOf(1), CAROL);
        assertEq(badges.badgeOf(1, CAROL), 1);
        string memory json = string(DataURI.decode(badges.tokenURI(1), "data:application/json;base64,"));
        assertEq(vm.parseJsonString(json, ".issuer"), Strings.toHexString(BOB));
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(SoulboundBadges.NotIssuer.selector, 1, ALICE));
        badges.award(1, ALICE);
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(SoulboundBadges.NotIssuer.selector, 1, ALICE));
        badges.setIssuer(1, CAROL);
        _award(BOB, 1, ALICE);
        vm.prank(BOB);
        vm.expectRevert(abi.encodeWithSelector(SoulboundBadges.AlreadyAwarded.selector, 1, CAROL));
        badges.award(1, CAROL);
    }

    function test_unknownTypesAndTokenViewsRevert() public {
        for (uint256 id; id < 2; ++id) {
            vm.expectRevert(abi.encodeWithSelector(SoulboundBadges.UnknownType.selector, id));
            badges.badgeType(id);
            vm.expectRevert(abi.encodeWithSelector(SoulboundBadges.UnknownType.selector, id));
            badges.award(id, BOB);
            vm.expectRevert(abi.encodeWithSelector(SoulboundBadges.UnknownType.selector, id));
            badges.setIssuer(id, ALICE);
            assertEq(badges.badgeOf(id, BOB), 0);
            _assertNonexistent(id);
        }
    }

    function test_metadataDecodesToJSONAndSVGWithAllRequiredFields() public {
        _assertMetadata("Az09 _-", "Az09 _-");
        _assertMetadata("ABCDEFGHIJKLMNOPQRSTUVWXYZ012345", "ABCDEFGHIJKLMNOPQRSTUVWXYZ012345");
        _assertMetadata(" ", " ");
    }

    function testFuzz_validNamesAlwaysProduceParseableMetadata(bytes32 seed, uint8 size) public {
        bytes memory alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 _-";
        bytes memory name_ = new bytes(bound(size, 1, 32));
        for (uint256 i; i < name_.length; ++i) {
            name_[i] = alphabet[uint8(seed[i]) % alphabet.length];
        }
        _assertMetadata(bytes32(name_), string(name_));
    }

    function _assertMetadata(bytes32 name_, string memory expectedName) private {
        uint256 typeId = _create(ALICE, name_);
        uint256 id = _award(ALICE, typeId, BOB);
        string memory json = string(DataURI.decode(badges.tokenURI(id), "data:application/json;base64,"));
        assertEq(vm.parseJsonKeys(json, "$").length, 5);
        assertEq(vm.parseJsonString(json, ".name"), expectedName);
        assertEq(vm.parseJsonUint(json, ".typeId"), typeId);
        assertEq(vm.parseJsonString(json, ".issuer"), Strings.toHexString(ALICE));
        assertEq(vm.parseJsonString(json, ".description"), "Sepolia test toy. Badges are not credentials.");
        string memory svg = string(DataURI.decode(vm.parseJsonString(json, ".image"), "data:image/svg+xml;base64,"));
        assertTrue(DataURI.contains(svg, '<svg xmlns="http://www.w3.org/2000/svg"'));
        assertTrue(DataURI.contains(svg, string.concat(">", expectedName, "</text>")));
        assertTrue(DataURI.contains(svg, string.concat("Type #", Strings.toString(typeId), "</text>")));
        string memory hue = Strings.toString(uint256(keccak256(abi.encode(typeId))) % 360);
        assertTrue(DataURI.contains(svg, string.concat('fill="hsl(', hue, ',60%,32%)"')));
        assertTrue(DataURI.contains(svg, "</svg>"));
    }

    function _assertNonexistent(uint256 id) private {
        bytes memory err = abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, id);
        vm.expectRevert(err);
        badges.ownerOf(id);
        vm.expectRevert(err);
        badges.tokenURI(id);
        vm.expectRevert(err);
        badges.typeOf(id);
        vm.expectRevert(err);
        badges.locked(id);
        vm.expectRevert(err);
        badges.burn(id);
    }
}
