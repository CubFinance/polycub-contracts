const Web3 = require("web3")
const web3 = new Web3("https://polygon-rpc.com/")

let ABI = require("../build/abi/Curve_PolyCub_Vault.json")

let contracts = [
  {
    name: "USD_BTC_ETH_atricrypto3",
    contract: "0x7B4389660a2dC9BecF141B564b8c44Ed8C718cd7"
  }, {
    name: "DAI_USDC_USDT_aave",
    contract: "0xB747dC61bA6509Da426A3BDc69B69040dD916f87"
  }
]

init()
async function init(){
  for (i in contracts){
    await main(i)
  }
}

async function main(i){
  let instance = new web3.eth.Contract(ABI, contracts[i].contract)

  let farmContractAddress = await instance.methods.farmContractAddress().call()
  let wantAddress = await instance.methods.wantAddress().call()
  let rewardsAddress = await instance.methods.rewardsAddress().call()
  let token0Address = await instance.methods.token0Address().call()
  let earnedAddress = await instance.methods.earnedAddress().call()
  let isAutoComp = await instance.methods.isAutoComp().call()
  let isSameAssetDeposit = await instance.methods.isSameAssetDeposit().call()
  let rewarders = await instance.methods.rewarders(0).call()
  let curvePoolAddress = await instance.methods.curvePoolAddress().call()
  let CRVAddress = await instance.methods.CRVAddress().call()
  let reward_contract = await instance.methods.reward_contract().call()
  let uniRouter = await instance.methods.uniRouterAddress().call()
  let crvPath1;
  let crvPath2;
  let crvPath3;
  let crvPath4;
  try {
    crvPath1 = await instance.methods.CRVToUSDCPath(0).call()
    crvPath2 = await instance.methods.CRVToUSDCPath(1).call()
    crvPath3 = await instance.methods.CRVToUSDCPath(2).call()
    crvPath4 = await instance.methods.CRVToUSDCPath(4).call()
  } catch (e) {}

  console.log(`Fetching data from: ${contracts[i].name}`)
  console.log(`farmContractAddress: ${farmContractAddress}`)
  console.log(`wantAddress: ${wantAddress}`)
  console.log(`rewardsAddress: ${rewardsAddress}`)
  console.log(`token0Address: ${token0Address}`)
  console.log(`earnedAddress: ${earnedAddress}`)
  console.log(`isAutoComp: ${isAutoComp}`)
  console.log(`isSameAssetDeposit: ${isSameAssetDeposit}`)
  console.log(`rewarders 0: ${rewarders}`)
  console.log(`rewarders 1: ${await instance.methods.rewarders(1).call()}`)
  console.log(`curvePoolAddress: ${curvePoolAddress}`)
  console.log(`CRVAddress: ${CRVAddress}`)
  console.log(`reward_contract: ${reward_contract}`)
  console.log(`unirouter: ${uniRouter}`)
  crvPath1 ? console.log(`CRVToUSDCPath 1: ${crvPath1}`) : ''
  crvPath2 ? console.log(`CRVToUSDCPath 2: ${crvPath2}`) : ''
  crvPath3 ? console.log(`CRVToUSDCPath 3: ${crvPath3}`) : ''
  crvPath4 ? console.log(`CRVToUSDCPath 4: ${crvPath4}`) : ''
  console.log()
  return true;
}
