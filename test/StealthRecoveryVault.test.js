const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("StealthRecoveryVault", function () {
  async function deployFixture() {
    const [owner, guardianA, guardianB, guardianC, sessionKey, newOwner] = await ethers.getSigners();

    const EntryPoint = await ethers.getContractFactory("MockEntryPoint");
    const entryPoint = await EntryPoint.deploy();

    const Vault = await ethers.getContractFactory("StealthRecoveryVault");
    const vault = await Vault.deploy(owner.address, await entryPoint.getAddress(), 2, {
      value: ethers.parseEther("1")
    });

    const Target = await ethers.getContractFactory("MockTarget");
    const target = await Target.deploy();

    return { owner, guardianA, guardianB, guardianC, sessionKey, newOwner, entryPoint, vault, target };
  }

  async function signRecovery(vault, guardian, proposedOwner, salt, secret) {
    const digest = await vault.recoveryDigest(proposedOwner, salt, secret);
    const sig = await guardian.signMessage(ethers.getBytes(digest));
    return sig;
  }

  it("allows the owner to execute arbitrary calls", async function () {
    const { owner, vault, target } = await deployFixture();

    const data = target.interface.encodeFunctionData("setValue", [42]);
    await expect(vault.connect(owner).execute(await target.getAddress(), 0, data))
      .to.emit(target, "ValueChanged")
      .withArgs(await vault.getAddress(), 42);

    expect(await target.value()).to.equal(42);
  });

  it("allows temporary session keys and rejects expired keys", async function () {
    const { owner, sessionKey, vault, target } = await deployFixture();

    await vault.connect(owner).setSessionKey(sessionKey.address, Math.floor(Date.now() / 1000) + 3600);

    const data = target.interface.encodeFunctionData("setValue", [77]);
    await vault.connect(sessionKey).execute(await target.getAddress(), 0, data);
    expect(await target.value()).to.equal(77);

    await vault.connect(owner).setSessionKey(sessionKey.address, 1);
    await expect(vault.connect(sessionKey).execute(await target.getAddress(), 0, data))
      .to.be.revertedWithCustomError(vault, "OnlyOwnerOrSessionKey");
  });

  it("recovers ownership through hidden guardian commitments", async function () {
    const { owner, guardianA, guardianB, newOwner, vault } = await deployFixture();

    const secretA = ethers.keccak256(ethers.toUtf8Bytes("guardian-a-private-salt"));
    const secretB = ethers.keccak256(ethers.toUtf8Bytes("guardian-b-private-salt"));
    const salt = ethers.keccak256(ethers.toUtf8Bytes("recovery-round-1"));

    await vault.connect(owner).setGuardianCommitment(await vault.guardianCommitment(guardianA.address, secretA), true);
    await vault.connect(owner).setGuardianCommitment(await vault.guardianCommitment(guardianB.address, secretB), true);

    const sigA = await signRecovery(vault, guardianA, newOwner.address, salt, secretA);
    const sigB = await signRecovery(vault, guardianB, newOwner.address, salt, secretB);

    const tx = await vault.proposeRecovery(newOwner.address, salt, [secretA, secretB], [sigA, sigB]);
    const receipt = await tx.wait();
    const event = receipt.logs
      .map((log) => {
        try {
          return vault.interface.parseLog(log);
        } catch (_) {
          return null;
        }
      })
      .find((log) => log && log.name === "RecoveryProposed");

    const recoveryId = event.args.recoveryId;

    await expect(vault.executeRecovery(recoveryId)).to.be.revertedWithCustomError(vault, "RecoveryNotReady");

    await ethers.provider.send("evm_increaseTime", [2 * 24 * 60 * 60 + 1]);
    await ethers.provider.send("evm_mine");

    await expect(vault.executeRecovery(recoveryId))
      .to.emit(vault, "RecoveryExecuted")
      .withArgs(recoveryId, owner.address, newOwner.address);

    expect(await vault.owner()).to.equal(newOwner.address);
  });

  it("rejects duplicate guardian recovery proofs", async function () {
    const { owner, guardianA, newOwner, vault } = await deployFixture();

    const secret = ethers.keccak256(ethers.toUtf8Bytes("guardian-a-private-salt"));
    const salt = ethers.keccak256(ethers.toUtf8Bytes("recovery-round-duplicate"));

    await vault.connect(owner).setGuardianCommitment(await vault.guardianCommitment(guardianA.address, secret), true);
    const sig = await signRecovery(vault, guardianA, newOwner.address, salt, secret);

    await expect(vault.proposeRecovery(newOwner.address, salt, [secret, secret], [sig, sig]))
      .to.be.revertedWithCustomError(vault, "DuplicateGuardianProof");
  });
});
