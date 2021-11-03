const assert = require('assert');

const Token = artifacts.require("POLYCUB");
const MasterChef = artifacts.require("MasterChef");
const Staker = artifacts.require("xStaker");
const SushiVault = artifacts.require("MockSushiVault");
const ERC20 = artifacts.require("MockToken");

const { mineBlocks } = require('./utils.js')

// const tokenInstance = await Token.deployed();
// const masterChefInstance = await MasterChef.deployed();
// const stakerInstance = await Staker.deployed();
// const sushiVaultInstance = await SushiVault.deployed();

contract('MasterChef', async (accounts) => {
  it('shoud add a new pool', async function() {
    const masterChefInstance = await MasterChef.deployed();
    const sushiVaultInstance = await SushiVault.deployed();

    let addNewPool = await masterChefInstance.add(1000, ERC20.address, true, SushiVault.address, {from: accounts[0]});
    let pools = await masterChefInstance.poolInfo(0)

    assert.equal(pools.want, ERC20.address);
    assert.equal(pools.allocPoint.toString(), '1000');
    assert.equal(pools.accTokensPerShare.toString(), '0');
    assert.equal(pools.strat, SushiVault.address);
  });

  it('shoud deposit to new pool', async () => {
    const masterChefInstance = await MasterChef.deployed();
    const erc20Instance = await ERC20.deployed();

    let approveERC20 = await erc20Instance.approve(MasterChef.address, 10000, {from: accounts[0]});
    let deposit = await masterChefInstance.deposit(0, 10000, {from: accounts[0]});

    let stakedAmount = await masterChefInstance.stakedWantTokens(0, accounts[0])

    assert.equal(stakedAmount.toString(), '10000')
  });

  it('shoud get correct pending tokens', async () => {
    const masterChefInstance = await MasterChef.deployed();

    let pending = await masterChefInstance.pendingTokens(0, accounts[0]);
    let blockNumber = await web3.eth.getBlockNumber()

    console.log(pending.toString(), blockNumber)
  });
});
