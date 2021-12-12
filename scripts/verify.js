const fs = require('fs')

verify()

async function verify(){
  let queue = await fs.readFileSync("./verify.json", 'utf8')
  queue = JSON.parse(queue)
  for (i in queue){
    try {
      console.log(`Verifying: ${queue[i].address}`)
      await hre.run("verify:verify", {
        address: queue[i].address,
        constructorArguments: queue[i].args,
      });
    } catch (e) { console.log(e) }
  }
}
