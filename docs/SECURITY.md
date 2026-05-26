# Security Notes

## Threat Model

The vault assumes the owner key may be lost or compromised and that guardian identities should not be trivially discoverable on-chain before recovery.

The design protects against:

- Public guardian enumeration.
- Single guardian takeover.
- Immediate recovery execution without a delay.
- Reuse of guardian recovery proofs.
- Unauthorized execution by expired session keys.

The design does not fully protect against:

- Collusion by enough guardians to cross the threshold.
- Compromise of the owner plus all configured guardian secrets.
- Malicious EntryPoint behavior if a non-canonical EntryPoint is configured.
- Frontend phishing or unsafe off-chain recovery UX.

## Guardian Commitment Flow

1. Guardian privately receives or generates a secret.
2. Owner stores `keccak256(vault, chainId, guardian, secret)` on-chain.
3. Recovery reveals the secret and guardian signature.
4. Contract reconstructs the commitment and checks membership.

This means guardian addresses are not published as a plain on-chain array.

## Recommended Production Hardening

- Replace raw Ethereum signed messages with EIP-712 typed data.
- Add guardian add/remove delay.
- Add owner-triggered recovery cancellation.
- Add session key scopes: selector allowlist, spend cap, target allowlist.
- Add multi-chain replay domain fields to every signature path.
- Use the official ERC-4337 interfaces and test against a forked EntryPoint.
- Add Slither, Echidna, and invariant tests.
