test()

function test(){
  let blockNumber = 150;
  let pending = {
    startBlock: 100,
    endBlock: 200,
    amount: 1000,
    alreadyClaimed: 0
  }

  let duration = pending.endBlock - pending.startBlock > 0 ? pending.endBlock - pending.startBlock : 1;
  let amountPerBlock = pending.amount / duration;
  let unlocked = (blockNumber - pending.startBlock) * amountPerBlock;
  console.log(`Locked: ${pending.amount - unlocked}`)
  console.log(`Unlocked: ${unlocked - pending.alreadyClaimed}`)
  console.log(`Claimed: ${pending.alreadyClaimed}`)

  pending.alreadyClaimed = 500;

  blockNumber = 199;
  duration = pending.endBlock - pending.startBlock > 0 ? pending.endBlock - pending.startBlock : 1;
  amountPerBlock = pending.amount / duration;
  unlocked = (blockNumber - pending.startBlock) * amountPerBlock;
  console.log(`Locked: ${pending.amount - unlocked}`)
  console.log(`Unlocked: ${unlocked - pending.alreadyClaimed}`)
  console.log(`Claimed: ${pending.alreadyClaimed}`)
}
