// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC1271} from "./interfaces/IERC1271.sol";
import {IAccountLike, IEntryPointLike, PackedUserOperation} from "./interfaces/IEntryPointLike.sol";
import {SignatureLib} from "./libraries/SignatureLib.sol";

/// @title StealthRecoveryVault
/// @notice ERC-4337-inspired smart account vault with hidden guardians, session keys,
/// sponsored gas budgets, and delayed commit-reveal social recovery.
/// @dev This is a portfolio-grade reference implementation, not audited production code.
contract StealthRecoveryVault is IERC1271, IAccountLike {
    using SignatureLib for bytes32;

    bytes4 internal constant ERC1271_MAGICVALUE = 0x1626ba7e;
    bytes4 internal constant ERC1271_INVALID = 0xffffffff;

    uint256 public constant RECOVERY_DELAY = 2 days;
    uint256 public constant RECOVERY_EXPIRY = 7 days;
    uint256 public constant MIN_GUARDIAN_THRESHOLD = 2;

    address public immutable entryPoint;
    address public owner;
    uint256 public nonce;
    uint256 public guardianThreshold;

    mapping(bytes32 guardianCommitment => bool active) public guardians;
    mapping(address sessionKey => uint64 validUntil) public sessionKeyExpiry;
    mapping(address sponsor => uint256 remainingWei) public sponsorBudget;
    mapping(bytes32 recoveryId => PendingRecovery recovery) public pendingRecoveries;
    mapping(bytes32 digest => bool used) public usedRecoveryDigests;

    struct PendingRecovery {
        address proposedOwner;
        uint64 executeAfter;
        uint64 expiresAt;
        uint32 approvals;
        bool executed;
    }

    event Executed(address indexed target, uint256 value, bytes data, bytes result);
    event OwnerChanged(address indexed previousOwner, address indexed newOwner);
    event GuardianCommitmentSet(bytes32 indexed guardianCommitment, bool active);
    event GuardianThresholdChanged(uint256 oldThreshold, uint256 newThreshold);
    event RecoveryProposed(bytes32 indexed recoveryId, address indexed proposedOwner, uint256 approvals);
    event RecoveryExecuted(bytes32 indexed recoveryId, address indexed previousOwner, address indexed newOwner);
    event SessionKeySet(address indexed key, uint64 validUntil);
    event SponsorBudgetSet(address indexed sponsor, uint256 remainingWei);

    error OnlyOwner();
    error OnlyEntryPoint();
    error OnlyOwnerOrSessionKey();
    error CallFailed(bytes returndata);
    error InvalidAddress();
    error InvalidThreshold();
    error InvalidGuardianProof();
    error DuplicateGuardianProof();
    error RecoveryNotReady();
    error RecoveryExpired();
    error RecoveryAlreadyExecuted();
    error InvalidNonce();
    error InsufficientSponsorBudget();

    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    modifier onlyEntryPoint() {
        if (msg.sender != entryPoint) revert OnlyEntryPoint();
        _;
    }

    constructor(address initialOwner, address accountEntryPoint, uint256 initialThreshold) payable {
        if (initialOwner == address(0) || accountEntryPoint == address(0)) revert InvalidAddress();
        if (initialThreshold < MIN_GUARDIAN_THRESHOLD) revert InvalidThreshold();
        owner = initialOwner;
        entryPoint = accountEntryPoint;
        guardianThreshold = initialThreshold;
        emit OwnerChanged(address(0), initialOwner);
        emit GuardianThresholdChanged(0, initialThreshold);
    }

    receive() external payable {}

    function execute(address target, uint256 value, bytes calldata data)
        external
        payable
        returns (bytes memory result)
    {
        _requireOwnerOrSessionKey();
        if (target == address(0)) revert InvalidAddress();

        (bool ok, bytes memory returndata) = target.call{value: value}(data);
        if (!ok) revert CallFailed(returndata);

        emit Executed(target, value, data, returndata);
        return returndata;
    }

    function executeBatch(address[] calldata targets, uint256[] calldata values, bytes[] calldata payloads)
        external
        payable
        returns (bytes[] memory results)
    {
        _requireOwnerOrSessionKey();
        uint256 length = targets.length;
        if (length != values.length || length != payloads.length) revert InvalidAddress();

        results = new bytes[](length);
        for (uint256 i; i < length;) {
            if (targets[i] == address(0)) revert InvalidAddress();
            (bool ok, bytes memory returndata) = targets[i].call{value: values[i]}(payloads[i]);
            if (!ok) revert CallFailed(returndata);
            results[i] = returndata;
            emit Executed(targets[i], values[i], payloads[i], returndata);
            unchecked {
                ++i;
            }
        }
    }

    function validateUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash, uint256 missingAccountFunds)
        external
        override
        onlyEntryPoint
        returns (uint256 validationData)
    {
        if (userOp.nonce != nonce++) revert InvalidNonce();

        address signer = userOpHash.toEthSignedMessageHash().recover(userOp.signature);
        if (signer != owner && sessionKeyExpiry[signer] < block.timestamp) {
            return 1;
        }

        if (missingAccountFunds != 0) {
            if (sponsorBudget[signer] < missingAccountFunds) revert InsufficientSponsorBudget();
            unchecked {
                sponsorBudget[signer] -= missingAccountFunds;
            }
            (bool ok,) = payable(msg.sender).call{value: missingAccountFunds}("");
            if (!ok) revert CallFailed("");
        }

        return 0;
    }

    function isValidSignature(bytes32 hash, bytes calldata signature) external view override returns (bytes4) {
        address signer = hash.toEthSignedMessageHash().recover(signature);
        return signer == owner || sessionKeyExpiry[signer] >= block.timestamp ? ERC1271_MAGICVALUE : ERC1271_INVALID;
    }

    function setGuardianCommitment(bytes32 commitment, bool active) external onlyOwner {
        guardians[commitment] = active;
        emit GuardianCommitmentSet(commitment, active);
    }

    function setGuardianThreshold(uint256 newThreshold) external onlyOwner {
        if (newThreshold < MIN_GUARDIAN_THRESHOLD) revert InvalidThreshold();
        emit GuardianThresholdChanged(guardianThreshold, newThreshold);
        guardianThreshold = newThreshold;
    }

    function setSessionKey(address key, uint64 validUntil) external onlyOwner {
        if (key == address(0)) revert InvalidAddress();
        sessionKeyExpiry[key] = validUntil;
        emit SessionKeySet(key, validUntil);
    }

    function setSponsorBudget(address sponsor, uint256 amount) external payable onlyOwner {
        if (sponsor == address(0)) revert InvalidAddress();
        sponsorBudget[sponsor] = amount;
        emit SponsorBudgetSet(sponsor, amount);
    }

    function depositToEntryPoint() external payable onlyOwner {
        IEntryPointLike(entryPoint).depositTo{value: msg.value}(address(this));
    }

    function proposeRecovery(
        address proposedOwner,
        bytes32 salt,
        bytes32[] calldata guardianSecrets,
        bytes[] calldata guardianSignatures
    ) external returns (bytes32 recoveryId) {
        if (proposedOwner == address(0)) revert InvalidAddress();
        uint256 approvals = _countValidGuardianApprovals(proposedOwner, salt, guardianSecrets, guardianSignatures);
        if (approvals < guardianThreshold) revert InvalidGuardianProof();

        recoveryId = keccak256(abi.encode(address(this), block.chainid, proposedOwner, salt));
        PendingRecovery storage recovery = pendingRecoveries[recoveryId];

        recovery.proposedOwner = proposedOwner;
        recovery.executeAfter = uint64(block.timestamp + RECOVERY_DELAY);
        recovery.expiresAt = uint64(block.timestamp + RECOVERY_DELAY + RECOVERY_EXPIRY);
        recovery.approvals = uint32(approvals);

        emit RecoveryProposed(recoveryId, proposedOwner, approvals);
    }

    function executeRecovery(bytes32 recoveryId) external {
        PendingRecovery storage recovery = pendingRecoveries[recoveryId];
        if (recovery.executed) revert RecoveryAlreadyExecuted();
        if (block.timestamp < recovery.executeAfter) revert RecoveryNotReady();
        if (block.timestamp > recovery.expiresAt) revert RecoveryExpired();

        recovery.executed = true;
        address previous = owner;
        owner = recovery.proposedOwner;

        emit OwnerChanged(previous, recovery.proposedOwner);
        emit RecoveryExecuted(recoveryId, previous, recovery.proposedOwner);
    }

    function guardianCommitment(address guardian, bytes32 secret) public view returns (bytes32) {
        return keccak256(abi.encodePacked(address(this), block.chainid, guardian, secret));
    }

    function recoveryDigest(address proposedOwner, bytes32 salt, bytes32 guardianSecret)
        public
        view
        returns (bytes32)
    {
        return keccak256(
            abi.encodePacked("STEALTH_RECOVERY_V1", address(this), block.chainid, proposedOwner, salt, guardianSecret)
        );
    }

    function _requireOwnerOrSessionKey() internal view {
        if (msg.sender != owner && sessionKeyExpiry[msg.sender] < block.timestamp) revert OnlyOwnerOrSessionKey();
    }

    function _countValidGuardianApprovals(
        address proposedOwner,
        bytes32 salt,
        bytes32[] calldata guardianSecrets,
        bytes[] calldata guardianSignatures
    ) internal returns (uint256 approvals) {
        uint256 length = guardianSecrets.length;
        if (length != guardianSignatures.length) revert InvalidGuardianProof();

        bytes32[] memory seen = new bytes32[](length);
        for (uint256 i; i < length;) {
            bytes32 digest = recoveryDigest(proposedOwner, salt, guardianSecrets[i]);
            if (usedRecoveryDigests[digest]) revert DuplicateGuardianProof();

            address guardian = digest.toEthSignedMessageHash().recover(guardianSignatures[i]);
            bytes32 commitment = guardianCommitment(guardian, guardianSecrets[i]);
            if (!guardians[commitment]) revert InvalidGuardianProof();

            for (uint256 j; j < approvals;) {
                if (seen[j] == commitment) revert DuplicateGuardianProof();
                unchecked {
                    ++j;
                }
            }

            seen[approvals] = commitment;
            usedRecoveryDigests[digest] = true;
            unchecked {
                ++approvals;
                ++i;
            }
        }
    }
}
