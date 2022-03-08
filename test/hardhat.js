const { expect } = require("chai");
const { ethers } = require("hardhat");

const { mineBlocks } = require('./utils.js')

describe("MasterChef", function () {
  let accounts;
  let token;
  let masterChef;
  let staker;
  let mockERC20;
  let vault;

  let depositBlockNumber;

  async function init() {
    accounts = await ethers.getSigners();

    const Token = await ethers.getContractFactory("POLYCUB");
    token = await Token.deploy();
    await token.deployed()

    const MasterChef = await ethers.getContractFactory("MasterChef");
    masterChef = await MasterChef.deploy('0x000000000000000000000000000000000000dEaD', 0, token.address)
    await masterChef.deployed()

    const Staker = await ethers.getContractFactory("xStaker");
    staker = await Staker.deploy(token.address, accounts[0].address, masterChef.address)
    await staker.deployed()

    await token.mint(accounts[0].address, '1300000000000000000000000')
    await token.transferOwnership(masterChef.address)

    //change pealty address
    await masterChef.setPenaltyAddress(staker.address);

    //depoly mock token

    const MockToken = await ethers.getContractFactory("MockToken");
    mockERC20 = await MockToken.deploy();
    await mockERC20.deployed()

    //deploy mock vault, only care about wantAddress[4](mockToken) and lionsDenAddress[2](MasterChef)
    let mockVaultAddresses = Array.apply(null, Array(12)).map(_ => '0x000000000000000000000000000000000000dEaD')
    mockVaultAddresses[2] = masterChef.address
    mockVaultAddresses[4] = mockERC20.address
    const SushiVault = await ethers.getContractFactory("MockSushiVault");
    mockVault = await SushiVault.deploy(mockVaultAddresses, 0, false, true, [], [], [], [], [], 1000, 0, 9990, 10000, accounts[0].address)
    await mockVault.deployed()

    await (await masterChef.updateEmissionRateSchedule(
      100,
      ["5000000000000000000", "4000000000000000000", "3000000000000000000", "2000000000000000000"],
      [0, 100, 200, 300])
    ).wait()
  }

  it("shoud add a new vault", async function () {
    await init()

    let addPoolTx = await masterChef.add(1000, mockERC20.address, true, mockVault.address);
    await addPoolTx.wait();
    let poolInfo = await masterChef.poolInfo(0)


    expect(poolInfo.want).to.equal(mockERC20.address)
    expect(poolInfo.allocPoint.toNumber()).to.equal(1000)
    expect(poolInfo.accTokensPerShare.toNumber()).to.equal(0)
    expect(poolInfo.strat).to.equal(mockVault.address)
  });

  it("shoud deposit token to a vault", async function () {
    let approveTx = await mockERC20.approve(masterChef.address, 420)
    await approveTx.wait()
    let depositTx = await masterChef.deposit(0, 420);
    await depositTx.wait();
    depositBlockNumber = depositTx.blockNumber
    let userInfo = await masterChef.userInfo(0, accounts[0].address)

    expect(userInfo.shares.toNumber()).to.equal(420)
  });

  it("shoud get rewards", async function () {
    let blocksToAdvance = 10
    await mineBlocks(blocksToAdvance);
    let currentBlockNumber = await ethers.provider.getBlockNumber()
    let blockNumberDifference = currentBlockNumber - depositBlockNumber

    //calculate rexpected rewards
    let tokensPerBlock = await masterChef.tokensPerBlock()
    let expectedReward = tokensPerBlock * blocksToAdvance

    let rewards = await masterChef.pendingTokens(0, accounts[0].address)

    expect(rewards / Math.pow(10, 16)).to.equal(expectedReward / Math.pow(10, 16))
  });

  it("shoud harvest rewards", async function () {
    let tokensPerBlock = await masterChef.tokensPerBlock()
    let rewards = await masterChef.pendingTokens(0, accounts[0].address)

    let harvestPending = await masterChef.deposit(0, 0)
    await harvestPending.wait()

    let pendingLength = await masterChef.pendingLength(accounts[0].address)
    let lockedTokens = await masterChef.lockedTokens(accounts[0].address)
    let unlockedTokens = await masterChef.unlockedTokens(accounts[0].address)
    let pendingAfterClaim = await masterChef.pendingTokens(0, accounts[0].address)


    expect(lockedTokens.toString()).to.equal(rewards.add(tokensPerBlock).toString()) //harvest is one block later, so we add 1 block wirth of rewards
    expect(pendingLength.toNumber()).to.equal(1)
    expect(unlockedTokens.toNumber()).to.equal(0)
    expect(pendingAfterClaim.toNumber()).to.equal(0)
  });

  it("shoud claim rewards before unlock", async function () {
    let beforeUserBalance = await token.balanceOf(accounts[0].address)
    let beforePenaltyBalance = await token.balanceOf(staker.address)

    let lockedTokensBeforeClaim = await masterChef.lockedTokens(accounts[0].address)

    let claimTx = await masterChef.claim(true, 0)
    claimTx.wait()

    let lockedTokensAfterClaim = await masterChef.lockedTokens(accounts[0].address)
    let unlockedTokensAfterClaim = await masterChef.unlockedTokens(accounts[0].address)

    let userBalance = await token.balanceOf(accounts[0].address)
    let penaltyBalance = await token.balanceOf(staker.address)

    expect(lockedTokensAfterClaim.toString()).to.equal("0")
    expect(unlockedTokensAfterClaim.toString()).to.equal("0")
    expect(userBalance.toString()).to.equal(beforeUserBalance.add(lockedTokensBeforeClaim.div(2)).toString())
    expect(penaltyBalance.toString()).to.equal(beforePenaltyBalance.add(lockedTokensBeforeClaim.div(2)).toString())
  });

  it("shoud update emission rate", async function () {
    await init()

    await (await masterChef.updateEmissionRateSchedule(
      100,
      ["5000000000000000000", "4000000000000000000", "3000000000000000000", "2000000000000000000"],
      [0, 100, 200, 300])
    ).wait()

    //get emission rate
    let emissionStart = await masterChef.tokensPerBlock()

    await mineBlocks(101)
    await (await masterChef.deposit(0, 0)).wait()


  });

  // Since we need to mine 3,888,000 blocks to run this test, we skip it most of the time
  // it("shoud claim rewards after unlock", async function () {
  //   let beforeUserBalance = await token.balanceOf(accounts[0].address)
  //   let beforePenaltyBalance = await token.balanceOf(staker.address)
  //
  //   await mineBlocks(10)
  //   let addPendingRewardsTx = await masterChef.collectPendingRewards()
  //   addPendingRewardsTx.wait()
  //
  //   let lockedTokensBeforeClaim = await masterChef.lockedTokens(accounts[0].address)
  //   let unlockedTokensBeforeClaim = await masterChef.unlockedTokens(accounts[0].address)
  //
  //   let lockupPeriod = await masterChef.LOCKUP_PERIOD_BLOCKS()
  //   await mineBlocks(lockupPeriod + 1);
  //
  //   let claimTx = await masterChef.claim(true, 0)
  //   claimTx.wait()
  //
  //   let lockedTokensAfterClaim = await masterChef.lockedTokens(accounts[0].address)
  //   let unlockedTokensAfterClaim = await masterChef.unlockedTokens(accounts[0].address)
  //
  //   let userBalance = await token.balanceOf(accounts[0].address)
  //   let penaltyBalance = await token.balanceOf(staker.address)
  //
  //   expect(unlockedTokensBeforeClaim.toNumber()).to.equal(0)
  //   expect(lockedTokensAfterClaim.toNumber()).to.equal(0)
  //   expect(unlockedTokensAfterClaim.toNumber()).to.equal(0)
  //   expect(penaltyBalance.toString()).to.equal(beforePenaltyBalance.toString())
  //   expect(userBalance.toString()).to.equal(beforeUserBalance.add(lockedTokensBeforeClaim).toString())
  // });

  // it("shoud update emission schedule", async function () {
  //   await init() //start with clean state
  //
  //   let startEmissionRate = await masterChef.tokensPerBlock()
  //   let blockPerDay = await masterChef.blockPerDay()
  //
  //   let addPoolTx = await masterChef.add(1000, mockERC20.address, true, mockVault.address);
  //   await addPoolTx.wait();
  //
  //   check emissions for first month (not checking first week)
  //   for (i = 0; i < 3; i++){
  //     //change contract to use uint blockPerWeek = blockPerDay / 10; to speed up the testing
  //     await mineBlocks(blockPerDay + 1)
  //
  //     //call it twice, for some reason it's not updated if it's only once
  //     let updatePoolTx = await masterChef.updatePool(0);
  //     await updatePoolTx.wait()
  //     let updatePoolTx1 = await masterChef.updatePool(0);
  //     await updatePoolTx1.wait()
  //
  //     let emissionRate = await masterChef.tokensPerBlock()
  //     let expectedEmission = await masterChef.emissionScheduleArray(i + 1)
  //
  //     expect(emissionRate.toString()).is.equal(expectedEmission[0].toString())
  //   }
  // });
});
