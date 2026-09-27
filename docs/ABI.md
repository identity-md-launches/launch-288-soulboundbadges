# ABI reference

The files under `docs/abi/` are complete compiler-generated JSON ABI arrays including inherited ERC-20/721 interfaces, events and custom errors. Regenerate from the pinned compiler after source changes:

```sh
forge build
forge inspect src/LaunchToken.sol:LaunchToken abi --json > docs/abi/LaunchToken.json
forge inspect src/SoulboundBadges.sol:SoulboundBadges abi --json > docs/abi/SoulboundBadges.json
```

## LaunchToken

Constructor: no arguments, nonpayable. `name() = "Badges"`, `symbol() = "BDGE"`, `decimals() = 18`. `totalSupply()` is fixed at `10^27`. Standard `balanceOf`, `allowance`, `transfer`, `approve` and `transferFrom` use minor units. Transfers have no token fee. An allowance of `type(uint256).max` is not decremented by the OpenZeppelin ERC-20. No public mint, burn, role or upgrade interface exists.

## SoulboundBadges

Constructor: `address token_`, nonpayable. The factory must pass the address of the accepted launch token (`$token`). The contract exposes the following application interface in addition to OpenZeppelin ERC-721 metadata and enumeration.

| Function | Returns | Semantics |
| --- | --- | --- |
| `token()` | `address` | Immutable fee token |
| `CREATION_FEE()` | `uint256` | `100000000000000000000` |
| `BURN_ADDRESS()` | `address` | `0x000000000000000000000000000000000000dEaD` |
| `createBadgeType(bytes32 name_)` | `uint256 typeId` | Validated ASCII name; caller pays fee and becomes issuer |
| `setIssuer(uint256 typeId, address newIssuer)` | — | Current issuer only; nonzero destination; immediate handover |
| `award(uint256 typeId, address to)` | `uint256 tokenId` | Current issuer only; nonzero holder; one live badge per type/holder; safe mint |
| `burn(uint256 tokenId)` | — | Current holder only; clears lookup and enumeration; permits later re-award |
| `badgeType(uint256 typeId)` | `(bytes32 name_, address issuer)` | Unknown type reverts |
| `typeCount()` | `uint256` | Total types ever created; IDs range from 1 through this value |
| `badgeOf(uint256 typeId, address holder)` | `uint256 tokenId` | Zero when no live badge, including unknown type or zero holder |
| `typeOf(uint256 tokenId)` | `uint256 typeId` | Burned/unminted ID reverts |
| `locked(uint256 tokenId)` | `bool` | Always true for live badges; burned/unminted ID reverts |
| `tokenURI(uint256 tokenId)` | `string` | `data:application/json;base64,...`; burned/unminted ID reverts |
| `totalSupply()` | `uint256` | Number of live badges, unlike the type count |
| `tokenByIndex(uint256 index)` | `uint256 tokenId` | Zero-based global enumeration; out-of-bounds reverts |
| `tokenOfOwnerByIndex(address holder, uint256 index)` | `uint256 tokenId` | Zero-based owner enumeration; out-of-bounds reverts |

`approve` and `setApprovalForAll` always revert with `Soulbound()`. `getApproved` returns zero for live badges and reverts for nonexistent badges; `isApprovedForAll` is always false. `transferFrom` and both `safeTransferFrom` variants revert, even for self-transfers; invalid inputs may surface a standard ERC-721 error instead of `Soulbound()`.

`supportsInterface` supports ERC-165 (`0x01ffc9a7`), ERC-721 (`0x80ac58cd`), ERC-721 metadata (`0x5b5e139f`), ERC-721 enumerable (`0x780e9d63`) and ERC-5192 (`0xb45a3c0e`). It rejects `0xffffffff`.

## Events

| Event signature | Indexed fields | Meaning |
| --- | --- | --- |
| `TypeCreated(uint256 typeId, bytes32 name, address issuer)` | `typeId`, `issuer` | Successful payment and creation |
| `IssuerChanged(uint256 typeId, address previousIssuer, address newIssuer)` | All three | Current issuer handover, including a no-op handover to itself |
| `Transfer(address from, address to, uint256 tokenId)` | All three | Mint from zero, burn to zero; there are no holder-to-holder transfers |
| `Locked(uint256 tokenId)` | None (ERC-5192) | Emitted immediately after the mint's Transfer, before a receiver callback |

`Unlocked(uint256)` is part of the ERC-5192 ABI but is never emitted. Inherited ERC-721 approval events are also never emitted through public application actions. The ERC-20 emits its standard `Transfer` and `Approval` events. Creation fee transfers can be observed on LaunchToken and correlated to `TypeCreated` in the same transaction.

## Metadata and errors

Decode the outer data URI as UTF-8 JSON, then decode `image`'s `data:image/svg+xml;base64,` payload as UTF-8 SVG. JSON fields are `name` (trimmed at zero padding, preserving spaces), `typeId` (number), `issuer` (lowercase hex address of the **current** type issuer), `description` and `image`. Names contain no JSON/XML metacharacters. Avoid lossy number conversion when passing on-chain IDs to clients. The SVG colour hue is `uint256(keccak256(abi.encode(typeId))) % 360`.

Application errors are `InvalidToken`, `InvalidName`, `UnknownType(typeId)`, `NotIssuer(typeId, caller)`, `ZeroAddress`, `AlreadyAwarded(typeId, holder)`, `NotHolder(tokenId, caller)` and `Soulbound`. Standard OpenZeppelin ERC-20, ERC-721, enumerable, SafeERC20 and ReentrancyGuard errors also appear in the generated ABI. Failed safe-mint callbacks may propagate recipient revert data. All reverted calls roll back state and fee transfers atomically.
