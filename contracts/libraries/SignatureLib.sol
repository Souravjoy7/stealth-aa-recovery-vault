// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library SignatureLib {
    error InvalidSignatureLength();

    function recover(bytes32 digest, bytes calldata signature) internal pure returns (address signer) {
        if (signature.length != 65) revert InvalidSignatureLength();

        bytes32 r;
        bytes32 s;
        uint8 v;

        assembly ("memory-safe") {
            r := calldataload(signature.offset)
            s := calldataload(add(signature.offset, 0x20))
            v := byte(0, calldataload(add(signature.offset, 0x40)))
        }

        if (v < 27) v += 27;
        signer = ecrecover(digest, v, r, s);
    }

    function toEthSignedMessageHash(bytes32 hash) internal pure returns (bytes32 digest) {
        assembly ("memory-safe") {
            mstore(0x00, "\x19Ethereum Signed Message:\n32")
            mstore(0x1c, hash)
            digest := keccak256(0x00, 0x3c)
        }
    }
}
