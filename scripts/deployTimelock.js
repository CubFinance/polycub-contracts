const fs = require('fs')

let delay = 86400
let admin = "0x2CAA7b86767969048029c27C1A62612c980eB4b8"

async function main() {
  const Timelock = await ethers.getContractFactory("Timelock");
  timelock = await Timelock.deploy(admin, delay);
  await timelock.deployed()
  await queueVerifications(timelock.address, [admin, delay])
}

let queue = []

async function queueVerifications(address, arguments){
  queue.push({
    address: address,
    args: arguments
  })
  console.log("QUEUE", JSON.stringify(queue, null, "\t"))
  await fs.writeFileSync('./verify.json', JSON.stringify(queue, null, "\t"))
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
