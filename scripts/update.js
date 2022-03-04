
init()
async function init(){
  const MasterChef = await ethers.getContractFactory("MasterChef");
  masterChef = await MasterChef.attach("0x84bd9703f42aeaf956c93ab2e42404934a7b3396");

  await masterChef.updateEmissionRateSchedule(
    25616000,
    ["5000000000000000000", "4000000000000000000", "3000000000000000000", "2000000000000000000"],
    [0, 302400, 604800, 907200]
  )
}
