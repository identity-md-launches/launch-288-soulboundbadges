# Badges — contract stage

**Sepolia test toy. Badges are not credentials.** BDGE and the badges carry no identity verification or promise of value.

This repository delivers the fixed-supply launch token, one application contract, Foundry tests, and ABI exports. The separate manifest contributor produces `launch.json`; an independent contributor reviews the accepted source and manifest. Services subsequently publish, attest, admit and deploy, then start the frontend stage. This contribution neither deploys contracts nor claims an independent audit.

## Build and checks

Foundry and Solidity **0.8.26** are required. `foundry.toml` pins the compiler, Cancun EVM, optimizer (200 runs), and `bytecode_hash = "none"`. Dependencies are vendored as ordinary files under `lib/`; no submodules, package installation, FFI, filesystem cheatcode permissions, or network access are needed to build once that compiler is installed.

```sh
forge build
forge test
forge fmt --check
```

Tests use isolated local deployments and no environment variables, wallet keys, RPC connections, or broadcast scripts. Unit and fuzz tests cover both successful and failed actions; stateful invariants check ownership, enumeration, sequential IDs, issuer authorization and fee conservation over 128 sequences of 64 calls. The deployment test models constructor-only factory execution and scans runtime sizes/opcodes against the supplied project baseline. This model is not the protocol factory or the independent protected verifier.

Dependency versions, upstream archive hashes, licenses, and file hashes are recorded in [docs/DEPENDENCIES.md](docs/DEPENDENCIES.md).

## Contracts and deployment parameters

Deployment target: **Sepolia, chain ID 11155111**. Local Foundry execution uses its isolated test chain; the deployment service is responsible for selecting Sepolia.

| Artifact | Constructor arguments | Configuration |
| --- | --- | --- |
| `src/LaunchToken.sol:LaunchToken` | `[]` | ERC-20 `Badges` / `BDGE`, 18 decimals, exactly `1000000000000000000000000000` minor units (1 billion BDGE), minted once to the constructor caller |
| `src/SoulboundBadges.sol:SoulboundBadges` | `["$token"]` (one `address`) | ERC-721 `Soulbound Badges` / `SBADGE`, 100 BDGE creation fee, immutable token address |

The manifest handoff is kind `evm_project`, token identifier `LaunchToken`, and exactly one application identifier `SoulboundBadges`. Deploy the token first and pass its address to the application. Both constructors are nonpayable and need no initialization call. With factory deployment, all initial BDGE belongs to the factory; the application starts with zero BDGE and does not move the launch supply. There are no owner arguments, privileged beneficiary arguments, post-deployment setters for the token, or hard-coded privileged wallets.

The application rejects a zero or code-less token address. **Its constructor must receive this launch's actual `LaunchToken`.** It does not authenticate arbitrary ERC-20 bytecode: a malicious replacement could lie about payment. Binding `$token` to the accepted token artifact is part of manifest review and service deployment. Policy, pool configuration, signed artifact linkage, LP/reward allocation and admission belong to the services; they are not configured by these contracts.

## User operations

1. Obtain BDGE by swapping Sepolia ETH in the launch pool after deployment. This application does not sell tokens or accept ETH.
2. On **LaunchToken**, call `approve(soulboundBadgesAddress, 100000000000000000000)` (100 BDGE).
3. Call `createBadgeType(bytes32 name)`. It returns the next type ID, starting at 1, and makes the caller its issuer. Names contain 1–32 ASCII characters from `A-Z`, `a-z`, `0-9`, space, underscore and hyphen, right-padded with zero bytes. Spaces count as characters, including an all-space name. Embedded zeros followed by nonzero bytes, empty names, Unicode, quotes and markup are rejected. Names are immutable and need not be unique.
4. The current issuer calls `award(typeId, holder)`. A holder may have one live badge per type, but may hold multiple different types. Token IDs start at 1 and increase globally; successful burns never reuse IDs. A failed transaction consumes neither a type nor token ID. Contract recipients must implement `onERC721Received` and accept safe minting.
5. The current issuer may call `setIssuer(typeId, nonzeroAddress)`. Handover is immediate and requires no acceptance. The old issuer loses authority immediately. The new issuer may be a contract and must be able to call the application. An incorrect or inaccessible address can permanently strand that type's issuance authority.
6. Only the holder may `burn(tokenId)`. The live badge lookup and enumerable indexes are cleared. The current issuer can then re-award that type with a new ID. Issuers cannot revoke holders' badges.

Awards do not require recipient consent or a payment. A recipient can burn an unwanted badge; the issuer can award again. There is no blocklist, recipient opt-out, identity proof, or recovery mechanism. Changes to a wallet's own control are outside the ERC-721 transfer restriction.

All ERC-721 approvals, operator approvals (including revocation), transfers, self-transfers and both safe-transfer overloads revert. Burning through a transfer to the zero address also reverts; holders use `burn`. The shared ERC-721 state update enforces the restriction. Live badges report `locked = true` under [ERC-5192](https://eips.ethereum.org/EIPS/eip-5192); each mint emits `Transfer` then `Locked`. There is no unlock path. Reentrancy protection rejects nested application mutations during safe-mint callbacks, including a receiver attempting to burn during its callback; it can burn in a later call.

## Fee and custody assumptions

The fee uses OpenZeppelin `SafeERC20.safeTransferFrom(creator, 0x000000000000000000000000000000000000dEaD, 100e18)`. The application is the allowance spender but **never an intermediate fee recipient**. A failed payment reverts the whole creation. Creating a type is the only action charging BDGE; awards, handovers and badge burns charge no token fee. Users still pay transaction gas.

Here, “burn” means sending to the conventional dead address; BDGE's fixed `totalSupply()` remains 1 billion. It is not an ERC-20 supply reduction. The design assumes nobody can control the dead address.

**Literal custody limitation for independent review:** the requested “never holds BDGE” property holds for deployment and all application fee flows. A standard ERC-20 permits anyone to transfer directly to any nonzero address without recipient consent. An unsolicited transfer to this application therefore creates a balance; the application cannot prevent it. There is deliberately no rescue/admin function, so such tokens are stranded. Do not transfer BDGE to the badge contract; approve it as spender instead. Forced ETH is likewise outside normal call handling and has no withdrawal route.

There is no owner, pause, upgrade, mint-after-construction, fee setter, issuer override, sweep, or emergency recovery function. No oracles, randomness, keepers, signatures or off-chain custody are involved. No one can repair a deployed contract's code or undo an issuer's handover.

## ABI, metadata and frontend handoff

The generated ABI arrays are [LaunchToken.json](docs/abi/LaunchToken.json) and [SoulboundBadges.json](docs/abi/SoulboundBadges.json). See [docs/ABI.md](docs/ABI.md) for function, event and error semantics and regeneration commands.

`tokenURI` returns a base64 JSON data URI containing `name`, numeric `typeId`, current `issuer`, a toy disclaimer, and an `image` containing a base64 SVG. The SVG displays the badge name, type ID and a colour derived from the type ID. Metadata uses no remote URLs. The issuer field changes on handover; it is not a record of the original awarding issuer. A burned or unminted ID reverts for `ownerOf`, `typeOf`, `locked`, and `tokenURI`.

The later one-page static frontend, labeled `lab-soulbound-badges`, must export `dist/index.html` against the accepted live Sepolia deployment. It must display **“Sepolia test toy. Badges are not credentials.”**, the wallet's BDGE balance and allowance, and the explanation that BDGE comes from swapping Sepolia ETH in the launch pool. The create flow approves exactly 100 BDGE before creation; the award flow uses the current issuer. Show type ID and issuer beside every name because duplicate names are allowed. Re-fetch the issuer after handovers.

Use contract views and logs only: `typeCount`/`badgeType` for type lists, `balanceOf`/`tokenOfOwnerByIndex` for any address's profile, `typeOf`/`badgeType`/`tokenURI` for display, and `TypeCreated`, `IssuerChanged` and `Transfer` logs for refresh/history. Enumeration order may change after a burn; paginate RPC reads and refresh at a consistent block. There is no backend, indexer, aggregate unbounded list, production deployment address, or pool address in this contract-stage deliverable.

## Independent review and operations

[docs/REVIEW_HANDOFF.md](docs/REVIEW_HANDOFF.md) maps the adversarial checks to executable local tests and records the unresolved custody wording. These are author-written tests, not independent findings or an audit. The independent reviewer must inspect accepted source and the separately generated manifest, particularly the token constructor reference, all badge movement paths, name injection, unauthorized awards, and fee bypasses. Reviewers report concrete conflicts rather than edit implementation or emit ABI artifacts.

Services own source publication, signed attestation and linkage, admission, factory deployment, verification of deployed addresses/bytecode/chain, and distribution under the current pinned policy. They provide the final deployment and launch-pool addresses to the frontend stage. No service outcome is required to run this repository's local checks.
