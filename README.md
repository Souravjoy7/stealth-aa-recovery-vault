# Stealth AA Recovery Vault

An ERC-4337-inspired smart account vault that combines hidden guardian recovery, session keys, and sponsored gas policy controls.

This project is designed as a senior Web3 portfolio artifact: it demonstrates smart account architecture, commit-reveal security design, EIP-1271 signature validation, account-abstraction-style validation, gas-conscious Solidity, and testable recovery flows.

## Why This Exists

Most wallet recovery demos expose guardian addresses directly on-chain. That creates privacy and targeting risk: an attacker can identify social recovery guardians before attempting account takeover.

This vault stores only guardian commitments:

```text
commitment = keccak256(vault, chainId, guardian, secret)
```

During recovery, guardians reveal a private secret and sign a recovery digest. The contract verifies the guardian without storing the guardian address in advance.

## Architecture

```text
                     +--------------------------+
                     | ERC-4337 EntryPoint-like |
                     | validateUserOp caller    |
                     +------------+-------------+
                                  |
                                  v
+-------------+      +------------+-------------+      +----------------+
| Owner       | ---> | StealthRecoveryVault      | ---> | Target calls   |
| Session Key |      | - execute / batch         |      | DeFi, NFTs, AA |
+-------------+      | - EIP-1271 signatures    |      +----------------+
                     | - sponsor gas budget     |
                     | - hidden guardians       |
                     +------------+-------------+
                                  |
                                  v
                     +--------------------------+
                     | Commit-reveal recovery   |
                     | threshold + timelock     |
                     +--------------------------+
```

## Core Features

- Hidden guardian set using salted commitments instead of public guardian lists.
- Commit-reveal recovery with threshold approvals, replay protection, delay, and expiry.
- EIP-1271 `isValidSignature` support for smart-account integrations.
- ERC-4337-style `validateUserOp` flow with owner/session-key validation.
- Temporary session keys for limited-time automated operations.
- Sponsored gas budget accounting for controlled missing-fund top-ups.
- Batch execution for advanced wallet workflows.
- Yul-assisted signature recovery and Ethereum signed message hashing.

## Repository Layout

```text
contracts/
  StealthRecoveryVault.sol
  interfaces/
    IERC1271.sol
    IEntryPointLike.sol
  libraries/
    SignatureLib.sol
  mocks/
    MockEntryPoint.sol
    MockTarget.sol
test/
  StealthRecoveryVault.test.js
scripts/
  deploy.js
docs/
  SECURITY.md
  RECRUITER_NOTES.md
```

## Quick Start

```bash
npm install
npm test
```

Deploy:

```bash
ENTRY_POINT=0x0000000071727de22e5e9d8baf0edac6f37da032 npx hardhat run scripts/deploy.js --network <network>
```

## Security Model

This project is a research-grade portfolio implementation. Before production use:

- Replace `toEthSignedMessageHash` recovery approvals with typed EIP-712 domain-separated signatures.
- Integrate the canonical ERC-4337 `EntryPoint` interfaces for the target version.
- Add guardian rotation cooldowns and emergency cancellation paths.
- Add per-session-key spend limits and function selectors.
- Formally verify recovery digest uniqueness and replay resistance.
- Audit sponsor-budget semantics against the selected EntryPoint implementation.

## Recruiter Signal

This repo is intentionally not a basic token or NFT demo. It shows:

- Account abstraction concepts.
- Signature validation standards.
- Recovery protocol design.
- Privacy-aware smart contract architecture.
- Tests covering execution, session keys, recovery delay, and duplicate proofs.
- Gas-aware Solidity patterns with optimizer and `viaIR`.

## License

MIT
