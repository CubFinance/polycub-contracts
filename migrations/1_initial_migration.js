const Token = artifacts.require("POLYCUB");
const MasterChef = artifacts.require("MasterChef");
const Staker = artifacts.require("xStaker");

const SushiVault = artifacts.require("CubPolygon_SushiVault");
const QuickVault = artifacts.require("QuickSwapVault");

const MockSushiVault = artifacts.require("MockSushiVault");
const MockERC20 = artifacts.require("MockToken");

// WETH-WMATIC (Sushi) - DONE
// WETH-WBTC (Sushi)
// WETH-DAI (Sushi)
// WMATIC-QUICK (Quickswap)
// USD-BTC-ETH LP (atricrypto3) (Curve)
// DAI-USDC-USDT LP (Aave / Curve)

let wmatic = '0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270'
let govAddress = '0xA1982835170d0C2ba789370918F19122D63943A2'
let lionsDenAddress = '0xC11E1b8225a0eeEf5AA1fD2B88170D470dB82386'
let cub = '0x173848c59b3eb6f72c213ad64c0312f0acae21eb'
let sushiEarned = '0x0b3F868E0BE5597D5DB7fEB59E1CADBb0fdDa50a'
let sushiFarm = '0x0769fd68dFb93167989C6f7254cd0D766Fb2841F'
let sushiRouter = '0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506'
let rewardsAddress = '0x2CAA7b86767969048029c27C1A62612c980eB4b8'
let deadAddress = '0x000000000000000000000000000000000000dEaD'

let quickEarned = '0x831753DD7087CaC61aB5644b308642cc1c33Dc13'
let quickRouter = '0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff'
let quickFarm = '0x7Ca29F0DB5Db8b88B332Aa1d67a2e89DfeC85E7E'

let sushiEarnedToCub = [sushiEarned, wmatic, cub]
let quickEarnedToCub = [quickEarned, wmatic, cub]

let weth_wbtc_addresses = [
  wmatic, govAddress, lionsDenAddress, cub,
  '0xE62Ec2e799305E0D367b0Cc3ee2CdA135bF89816', '0x1BFD67037B42Cf73acF2047067bd4F2C47D9BfD6', '0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619', sushiEarned,
  sushiFarm, sushiRouter, rewardsAddress, deadAddress
]
let weth_dai_addresses = [
  wmatic, govAddress, lionsDenAddress, cub,
  '0x6FF62bfb8c12109E8000935A6De54daD83a4f39f', '0x7ceb23fd6bc0add59e62ac25578270cff1b9f619', '0x8f3cf7ad23cd3cadbd9735aff958023239c6a063', sushiEarned,
  sushiFarm, sushiRouter, rewardsAddress, deadAddress
]
let wmatic_quick_addresses = [
  wmatic, govAddress, lionsDenAddress, cub,
  '0x019ba0325f1988213D448b3472fA1cf8D07618d7', '0x0d500b1d8e8ef31e21c99d1db9a6444d3adf1270', '0x831753dd7087cac61ab5644b308642cc1c33dc13', quickEarned,
  quickFarm, quickRouter, rewardsAddress, deadAddress
]

const testAdminAddress = '0x3eCBE3F53D3DeAebEBb4336Aa269afdff23da3FA'

module.exports = async function (deployer, network, accounts) {
  // deploy contracts
  await deployer.deploy(Token);
  await deployer.deploy(MasterChef, adminAddress, 0, Token.address)
  await deployer.deploy(Staker, Token.address, adminAddress, MasterChef.address)

  //mint 1.3M tokens
  const tokenInstance = await Token.deployed();
  await tokenInstance.mint(adminAddress, '1300000000000000000000000').sendTransaction()

  // transfer token ownership
  await tokenInstance.transferOwnership(MasterChef.address).sendTransaction()

  // WETH-WBTC vault
  await deployer.deploy(
    SushiVault, weth_wbtc_addresses, 3, false, true, sushiEarnedToCub,
    [sushiEarned, wmatic, weth_wbtc_addresses[5]], [sushiEarned, wmatic, weth_wbtc_addresses[6]],
    [weth_wbtc_addresses[5], wmatic, sushiEarned], [weth_wbtc_addresses[6], wmatic, sushiEarned],
    1000, 0, 9990, 10000, govAddress
  )

  // WETH-DAI vault
  await deployer.deploy(
    SushiVault, weth_dai_addresses, 5, false, true, sushiEarnedToCub,
    [sushiEarned, wmatic, weth_dai_addresses[5]], [sushiEarned, wmatic, weth_dai_addresses[6]],
    [weth_dai_addresses[5], wmatic, sushiEarned], [weth_dai_addresses[6], wmatic, sushiEarned],
    1000, 0, 9990, 10000, govAddress
  )

  // WMATIC-QUICK vault
  await deployer.deploy(
    QuickVault, wmatic_quick_addresses, false, true, quickEarnedToCub,
    [quickEarned, wmatic, wmatic_quick_addresses[5]], [quickEarned, wmatic, wmatic_quick_addresses[6]],
    [wmatic_quick_addresses[5], wmatic, quickEarned], [wmatic_quick_addresses[6], wmatic, quickEarned],
    1000, 0, 9990, 10000, govAddress
  )
};
