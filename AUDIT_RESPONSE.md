CFC-01

We are aware of risks that come with 3rd party contracts and are monitoring them.

---

CFC-02

We are aware of risks and will not support fee-on-transfer tokens.

---

MCC-01

Using `x =< 0` is 3 gas cheaper compared to `x == 0`

---

MCC-02

Resolved: https://github.com/CubFinance/polycub-contracts/commit/9e0f5255289ecff8cabf503ab92913f38f29e6c7

---

MCC-03

Resolved: https://github.com/CubFinance/polycub-contracts/commit/566783dd87482a40790a0542dc2a2466358f6c3c

---

MCC-04

`addPendingClaims` was deprecated in favor of adding `pendingRewards` when they would be harvested (`deposit` and `withdraw`).

See:
https://github.com/CubFinance/polycub-contracts/commit/b4bac4653cb55eab9be71cf6a8be5446f472959e
https://github.com/CubFinance/polycub-contracts/blob/master/contracts/MasterChef.sol#L473
https://github.com/CubFinance/polycub-contracts/blob/master/contracts/MasterChef.sol#L522

---

MCC-05

Already resolved on jan-19-2022

See:
https://github.com/CubFinance/polycub-contracts/blob/master/contracts/MasterChef.sol#L343
https://github.com/CubFinance/polycub-contracts/blob/master/contracts/MasterChef.sol#L389
https://github.com/CubFinance/polycub-contracts/commit/12912796a97ac94ade32ebf2bc9f8de7a06cade6

---

MCC-06

Already resolved

See:
https://github.com/CubFinance/polycub-contracts/blame/master/contracts/MasterChef.sol#L375
https://github.com/CubFinance/polycub-contracts/commit/12912796a97ac94ade32ebf2bc9f8de7a06cade6

---

MCC-07

`PENALTY_ADDRESS` will be set to `xStaker` contract (fees are ditributed back to stakers), while governance will be set to a timelock.

---

MCC-08

Already resolved, see:
https://github.com/CubFinance/polycub-contracts/blame/master/contracts/MasterChef.sol#L399

---

MCC-09

Resolved: https://github.com/CubFinance/polycub-contracts/commit/b324fa5a22591069d68d2c4ec98d485c7a2cf16a, instead of using `require` we just set limit to array length

---

MCC-10

Resolved: https://github.com/CubFinance/polycub-contracts/commit/9a029e2e61d1b69172b01f08aa8d647d442e7009

---

MCC-11

Function is now used here: https://github.com/CubFinance/polycub-contracts/blame/master/contracts/MasterChef.sol#L375

---

MCC-12

Resolved: https://github.com/CubFinance/polycub-contracts/commit/a10db844a4c658a9cfa5b467ca582190bf55f1f5

---

MCC-13

We are aware of dangers of centralization, ownership will be transferred to a timelock (and maybe DAO later).

---

SCF-01

Resolved: https://github.com/CubFinance/polycub-contracts/commit/38ef45c6f48b23f6f59fb12fe66b90530e20412a

---

SCF-02

Resolved: https://github.com/CubFinance/polycub-contracts/commit/7ff2001ee9e63c9e8e47070b032271041541a0bc

---

SCF-03

We are aware of centralization risks.

---

SCF-04

Tokens in xStaker are not meant to be deposited in MasterChef, see: https://docs.sushi.com/products/yield-farming/the-sushibar

xStaker contract is collecting penalty tokens, so by depositing tokens, users buy share of the penalty (+ part of the inflation).

---

SCF-05

Yes, users only deposit/withdraw Polycub tokens to xStaker. Only deposited token is "fake" token, so xStaker contract can also receive part of the inflation, which
is then distributed to xPolycub holders. Rewards from masterchef are claimed every time someone tries to withdraw.

---

SCF-06

Resolved: https://github.com/CubFinance/polycub-contracts/commit/ca5d2e8bd86467c34b5fda448e08359eae7c7f8e

---

SVC-01

We are aware of centralization risks.

---

SVC-02

We are aware of risks that come with integration of 3rd party contracts.

---

SVC-03

Resolved: https://github.com/CubFinance/polycub-contracts/commit/98d5c14a37da0acec2334894a610fdd254d014ab

---

SVC-04

We are aware of centralization risks.

---

SVC-05

Gov cannot get want and reward tokens (see: https://github.com/CubFinance/polycub-contracts/blob/master/contracts/vaults/SushiVault.sol#L2162), and underlying tokens should never stored in the contact, when compounding, they are immediately added to lp.

---

SVC-06

In my opinion, zero address checks in constructor are unnecessary, since they aren't deployed by anyone else than the team.

---

SVC-07

Yes

---

TCF-01

Owner is masterchef address.

---
