# Author test evidence and independent review handoff

This is implementation evidence prepared by the source author, **not an independent adversarial review**. The independent source-plus-manifest review is a separate stage. `launch.json` is intentionally owned by the manifest contributor.

| Required attack / property | Local test evidence |
| --- | --- |
| Badge movement by holder, issuer or stranger, including self-transfer | `SoulboundBadgesSecurityTest.test_allTransferAndApprovalRoutesRevertForHolderIssuerAndStranger` covers transferFrom, both safeTransferFrom overloads, approve, approval clearing and both setApprovalForAll values |
| Transfer to zero used as a burn bypass | `test_transferToZeroCannotSubstituteForHolderBurn` |
| JSON/SVG injection, empty name, bad padding, non-ASCII | `SoulboundBadgesTest.test_nameBoundariesAndCharset`, single-byte alphabet fuzzing, nonzero-after-padding fuzzing and valid-name metadata fuzzing with actual base64 decoding and JSON parsing |
| Award a type the caller does not issue | `test_awardAuthorizationZeroAndDuplicates` and `test_issuerHandoverChangesAuthorizationAndMetadataOnly` |
| Skip or underpay the creation fee | Missing/short allowance, absent balance, transfer returning false, atomic rollback and exact sender/dead-address accounting tests |
| Duplicate award; unauthorized burn; re-award after burn | `test_awardAuthorizationZeroAndDuplicates`, `test_holderOnlyBurnAndReawardMaintainEnumeration` |
| Malicious safe-mint receiver | `test_receiverReentrancyCannotMoveOrRewriteBadgeState`: receiver is both issuer and holder and has an approved fee balance; nine attempted mutations/movement routes revert |
| Failing safe mint strands a type or consumes an ID | Rejecting and non-receiver tests check rollback, later awards, lookups, supply and ID continuity |
| Fee-token callback reentrancy | Mock attempts nested type creation, asserts the guard error, then returns false; the entire payment/creation rolls back |
| Constructor supply and runtime restrictions | `DeploymentTest`: factory is the token recipient, app starts unfunded and usable, nonpayable construction, EIP-170 size and disallowed opcode scan |
| Fixed ERC-20 supply and ordinary transfer behavior | `LaunchTokenTest`: exact initial supply, fuzzed conservation, allowances, insufficient balance, zero recipient and absent admin selectors |
| Long sequences of creations, handovers, awards, burns, attempted movement | `BadgesInvariantTest`: 128 × 64 generated actions, two invariants, no unexpected reverts; fee accounting, ID continuity, unique enumeration, balances and authorization model |
| Literal zero-custody limitation | `test_unsolicitedTokenTransferDocumentsCustodyLimit` demonstrates a direct transfer can leave one minor unit while creation fees still pass directly to the dead address |

The supplied protected checks are read-only inputs. They use service environment and attested creation-code inputs, so they are not represented here as having independently passed. Local factory tests deliberately avoid environment dependencies and are reproducible in an empty environment.

Final local verification: Foundry 1.8.3 with Solidity 0.8.26; `forge build`, `forge test -j 4`, and `forge fmt --check` passed. Foundry reported 32 passing test entries, zero failures and zero skips, including its combined invariant entry (two invariants, 8,192 actions, zero unexpected reverts). A fresh copy without build/cache artifacts also passed `forge build --offline`, `forge test --offline -j 4` and formatting with an entirely empty process environment. Only the preinstalled Foundry/compiler tools and vendored source were used.

ABI arrays match their compiler artifacts. Vendored source checksums match the upstream files. Runtime sizes are 1,723 bytes for `LaunchToken` and 9,231 bytes for `SoulboundBadges`, both below EIP-170; the local deployment test's opcode scan passes. These results are author evidence and carry no independent review authority.

## Concrete assumption requiring review

The literal requirement that the application can **never hold BDGE** is impossible with unrestricted standard ERC-20 transfers and an ordinary receiving contract. A concrete counterexample is `LaunchToken.transfer(address(soulboundBadges), 1)` from a funded account: it succeeds and the application then holds one minor unit. All intended fee flows go directly to the dead address; the contract has zero balance after construction and throughout those flows. There is no sweep path. Resolve the wording as a fee-custody requirement or report this conflict; do not claim an absolute invariant for unsolicited transfers.

The dead-address fee transfer deliberately does not reduce `totalSupply`. The constructor accepts a code-bearing address, rather than authenticating its code hash. A malicious token can lie about transfer success. The deployment manifest must bind it to the accepted `LaunchToken`, using `["$token"]` with no privileged wallet or substitute token. The reviewer must inspect that actual manifest and accepted bytecode; passing mock-token tests does not establish correctness for arbitrary token addresses.

## Operational limits

There is no deployed address, published source attestation or reviewed manifest in this source contribution. Local tests establish local behavior only. Review and deployment services must check policy/signed artifact linkage, the actual constructor arguments, chain ID, accepted bytecode and deployed runtime before release. No wallet key, broadcast, production transaction, external oracle or hosted backend is part of this work.

Badges are a Sepolia test toy, not credentials. Issuers can issue without consent, re-award after a holder burns, and transfer issuance authority immediately. Metadata reflects the current issuer. Issuers cannot burn someone else's badge. Wallet control changes, unwanted awards, inaccessible issuer destinations, and accidental direct token transfers have no admin recovery. These are documented behavior and trust assumptions, not claims that independent review has cleared the deployment.
