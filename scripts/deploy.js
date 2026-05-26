const { ethers } = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();
  const entryPoint = process.env.ENTRY_POINT;

  if (!entryPoint) {
    throw new Error("Set ENTRY_POINT to the chain's ERC-4337 EntryPoint address");
  }

  const Vault = await ethers.getContractFactory("StealthRecoveryVault");
  const vault = await Vault.deploy(deployer.address, entryPoint, 2);
  await vault.waitForDeployment();

  console.log(`StealthRecoveryVault deployed to ${await vault.getAddress()}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
