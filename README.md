Chnages:

RENAME:
  - `PENALTY_ADDRESS` to `penaltyAddress`
  - `LOCKUP_PERIOD_BLOCKS` to `lockupPeriodBlocks`

Change `claim()` to add second param `limit`, can be set to 0 by default: `claim(bool, uint256)`


---

How contract works?

It's standard "vault" masterchef (fork of autofarm), with addition of locked rewards and automatic emission updates.


When user calls `deposit()` or `withdraw()`, pending tokens are stored to array together with unlock block. When `claim()` is called,
it calculates how many tokens are already past `unlock block` and sends them to the user. if tokens are not unlocked yet (and user specified to claim them too using `true` as first param), 50% of locked tokens is sent to `penaltyAddress`, 50% to the user.
