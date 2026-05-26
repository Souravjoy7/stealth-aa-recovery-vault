require("@nomicfoundation/hardhat-toolbox");

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.24",
    settings: {
      optimizer: {
        enabled: true,
        runs: 10_000
      },
      viaIR: true
    }
  },
  networks: {
    hardhat: {
      chainId: 31337
    }
  },
  mocha: {
    timeout: 60_000
  }
};
