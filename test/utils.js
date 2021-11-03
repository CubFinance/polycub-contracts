const util = require('util');
const { ethers } = require("hardhat");

async function mineBlocks(blockNumber) {
  while (blockNumber > 0) {
    blockNumber--;
    await hre.network.provider.request({
      method: "evm_mine",
      params: [],
    });
  }
}

module.exports.mineBlocks = mineBlocks
