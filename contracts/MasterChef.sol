// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "./interfaces/ERC20.sol";
import "./interfaces/Address.sol";
import "./interfaces/EnumerableSet.sol";
import "./interfaces/Ownable.sol";
import "./interfaces/ReentrancyGuard.sol";

import "./interfaces/IStrategy.sol";
import "./interfaces/IToken.sol";

import "hardhat/console.sol";

/// @title MasterChef yield farming contract
/// @author CubFinance, @fbsloXBT

contract MasterChef is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /// @notice Address of the reward token
    address public rewardToken;
    /// @notice Maximum number of issued tokens, 24.7M issues, 1.3M minted at launch (200k dev fund, 1M airdrop, 100k initial liquidity) = 26M total
    uint256 public maxIssued = 24700000000000000000000000;

    /// @notice Info of each user.
    struct UserInfo {
        uint256 shares; //How many LP tokens the user has provided.
        uint256 rewardDebt; //Reward debt. See explanation below.

        // We do some fancy math here. Basically, any point in time, the amount of CUB
        // entitled to a user but is pending to be distributed is:
        //
        //   amount = user.shares / sharesTotal * wantLockedTotal
        //   pending reward = (amount * pool.accCubPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws want tokens to a pool. Here's what happens:
        //   1. The pool's `accCubPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    /// @notice Info about each pool
    struct PoolInfo {
        IERC20 want; //Address of the want token.
        uint256 allocPoint; //How many allocation points assigned to this pool.
        uint256 lastRewardBlock; //Last block number that reward token distribution occurs.
        uint256 accTokensPerShare; //Accumulated tokens per share, times 1e12.
        address strat; //Strategy vault address that will auto compound want tokens
    }

    /// @notice Number of tokens issued per block
    uint256 public tokensPerBlock = 5000000000000000;
    /// @notice Block number from where inflation schedule is counted
    uint256 public startBlock = 0;

    /// @notice Info of each pool.
    PoolInfo[] public poolInfo;
    /// @notice Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    /// @notice Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;

    /// @notice Store data about amount of locked reward tokens
    struct pendingRewards {
      uint256 startBlock;
      uint256 endBlock;
      uint256 amount;
      uint256 alreadyClaimed;
    }
    /// @notice An array of pendingRewards structs, storing data about user rewards
    mapping(address => pendingRewards[]) public pending;
    /// @notice Number of tokens already issued
    uint256 public totalIssuedTokens;

    /// @notice Contract where penalty (50% of claimed unlocked tokens) is sent
    address public penaltyAddress;
    /// @notice Number of blocks per day on Polygon network
    uint256 public blockPerDay = 43200;
    /// @notice reward lockup period, ~3 months
    uint256 public lockupPeriodBlocks = blockPerDay * 90;

    /// @notice Information about reward emission schedule
    struct EmissionSchedule {
      uint256 amount;
      uint256 startBlock;
    }
    /// @notice Array stroing EmissionSchedule structs that are string information about reward emissions
    EmissionSchedule[] public emissionScheduleArray;
    /// @notice Index of latest emission schedule update
    uint256 public emissionScheduleLatest = 0;
    /// @notice Number of latest monthly inflation cut
    uint256 public latestMonthlyInflationCut = 0;

    /// @notice Event emitted when new tokens are deposited
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    /// @notice Event emitted when new tokens are withdrawn
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    /// @notice Event emitted when new tokens are withdrawn without claiming rewards (using emergencyWithdraw function)
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    /// @notice Event emitted when new emission rate is updated
    event UpdateEmissionRate(uint256 tokenPerBlock);
    /// @notice Event emitted when lockup period is updated
    event UpdateLockupPeriod(uint256 oldPeriod, uint256 newPeriod);
    /// @notice Event emitted when penalty address is updated
    event updatePenaltyAddress(address indexed _newPenaltyAddress);
    /// @notice Event emitted when reward tokens are claimed
    event Claim(address indexed user, uint256 amount, uint256 penalty);

    /**
     * @notice Construct a new MasterChef contract
     * @param newPenaltyAddress An address where penaly tokens are sent
     * @param newStartBlock Block number from where inflation schedule is counted, if 0, it's current block number
     * @param newRewardToken The address of the reward token
     */
    constructor(address newPenaltyAddress, uint256 newStartBlock, address newRewardToken) public {
      penaltyAddress = newPenaltyAddress;
      rewardToken = newRewardToken;

      if (newStartBlock == 0) newStartBlock = block.number;

      uint256 blockPerWeek = blockPerDay * 7;

      uint64[4] memory _emissionAmounts = [5 ether, 4 ether, 3 ether, 2 ether];
      uint256[4] memory _emissionDelays = [0 * blockPerWeek, 1 * blockPerWeek, 2 * blockPerWeek, 3 * blockPerWeek];

      for (uint256 i = 0; i < _emissionAmounts.length; i++){
        emissionScheduleArray.push(EmissionSchedule(_emissionAmounts[i], newStartBlock + _emissionDelays[i]));
      }
    }

    /**
     * @notice Helper function return length of the poolInfo array.
     * @return Length of the poolInfo array
     */
    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    /// @notice A record of already existing want token addresses
    mapping(IERC20 => bool) public poolExistence;
    /// @notice A modifier to prevent same want token being added more than once
    modifier nonDuplicated(IERC20 _want) {
        require(poolExistence[_want] == false, "nonDuplicated: duplicated");
        _;
    }

    /**
     * @notice Function to add new pool, can be called  only by owner
     * @param _allocPoint Number of allocation points
     * @param _want Address of the wanted token
     * @param _withUpdate Boolean, if we want to update all pools first
     * @param _strat Address of startegy vault contract
     */
    function add(
        uint256 _allocPoint,
        IERC20 _want,
        bool _withUpdate,
        address _strat
    ) public onlyOwner nonDuplicated(_want) {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock =
            block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(
            PoolInfo({
                want: _want,
                allocPoint: _allocPoint,
                lastRewardBlock: lastRewardBlock,
                accTokensPerShare: 0,
                strat: _strat
            })
        );

        poolExistence[_want] = true;
    }

    /**
     * @notice Function to update the given pool's reward token allocation point. Can only be called by the owner.
     * @param _pid PID of the pool we want to update
     * @param _allocPoint Number of allocation points
     * @param _withUpdate Boolean, if we want to update all pools first
     */
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        bool _withUpdate
    ) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(
            _allocPoint
        );
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    /**
     * @notice Helper function return difference between 2 numbers
     * @return Difference between 2 numbers
     */
    function getMultiplier(uint256 _from, uint256 _to)
        public
        pure
        returns (uint256)
    {
        return _to.sub(_from);
    }


    /**
     * @notice View function to see pending tokens that have not entered waiting period yet (user need to call collectPendingRewards(), deposit(), withdraw())
     * @return Number of pending tokens not yet int the waiting period
     */
    function pendingTokens(uint256 _pid, address _user)
        external
        view
        returns (uint256)
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accTokensPerShare = pool.accTokensPerShare;
        uint256 sharesTotal = IStrategy(pool.strat).sharesTotal();
        if (block.number > pool.lastRewardBlock && sharesTotal != 0) {
            uint256 multiplier =
                getMultiplier(pool.lastRewardBlock, block.number);
            uint256 tokensReward =
                multiplier.mul(tokensPerBlock).mul(pool.allocPoint).div(
                    totalAllocPoint
                );
            accTokensPerShare = accTokensPerShare.add(
                tokensReward.mul(1e12).div(sharesTotal)
            );
        }
        return user.shares.mul(accTokensPerShare).div(1e12).sub(user.rewardDebt);
    }

    /**
     * @notice View function to see tokens staked in the strategy vault on the frontend
     * @return Number of tokens staked in the strategy vault
     */
    function stakedWantTokens(uint256 _pid, address _user)
        external
        view
        returns (uint256)
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];

        uint256 sharesTotal = IStrategy(pool.strat).sharesTotal();
        uint256 wantLockedTotal =
            IStrategy(poolInfo[_pid].strat).wantLockedTotal();
        if (sharesTotal == 0) {
            return 0;
        }
        return user.shares.mul(wantLockedTotal).div(sharesTotal);
    }


    /// @notice Function to update all pools
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    /**
     * @notice Function to update reward variables of the given pool to be up-to-date.
     * @param _pid PID of the pool we want to update
     */
    function updatePool(uint256 _pid) public {
        _updateEmission();

        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 sharesTotal = IStrategy(pool.strat).sharesTotal();
        if (sharesTotal == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        if (multiplier <= 0) {
            return;
        }
        uint256 tokensReward =
            multiplier.mul(tokensPerBlock).mul(pool.allocPoint).div(
                totalAllocPoint
            );

        if (totalIssuedTokens + tokensReward <= maxIssued){
            totalIssuedTokens += tokensReward;
            IToken(rewardToken).mint(address(this), tokensReward);
        } else if (totalIssuedTokens < maxIssued && totalIssuedTokens + tokensReward > maxIssued) {
            totalIssuedTokens += tokensReward;
            IToken(rewardToken).mint(address(this), maxIssued - totalIssuedTokens);
        }

        pool.accTokensPerShare = pool.accTokensPerShare.add(
            tokensReward.mul(1e12).div(sharesTotal)
        );
        pool.lastRewardBlock = block.number;
    }

    /**
     * @notice Internal function to update emission rate to match schedule
     */
    function _updateEmission() internal {
      //only for the first month we use emissionSchedule
      if (block.number < startBlock + (blockPerDay * 7 * 4)){
        if (emissionScheduleArray.length >= emissionScheduleLatest + 1){
          //update emission schedule
          if (emissionScheduleArray[emissionScheduleLatest].startBlock <= block.number){
            tokensPerBlock = emissionScheduleArray[emissionScheduleLatest].amount;
            emissionScheduleLatest += 1;
            emit UpdateEmissionRate(tokensPerBlock);
          }
        }
      } else {
        //after first month, we just cut inflation by 50% every month
        if (latestMonthlyInflationCut == 0 || latestMonthlyInflationCut < block.number - (blockPerDay * 4 * 7)){
          latestMonthlyInflationCut = block.number;
          tokensPerBlock = tokensPerBlock.div(2);
          emit UpdateEmissionRate(tokensPerBlock);
        }
      }
    }

    /**
     * @notice Claim tokens from pending queue
     * @param _claimLocked Claim locked tokens too and only receive 50% of them, the rest is sent to penalty address
     * @param _limit In case if gas limit is lower than gas required to claim entire array of pendingRewards, use _limit to claim just a limited number of pendingRewards
     */
    function claim(bool _claimLocked, uint256 _limit) external nonReentrant {
      uint256 sumLocked;
      uint256 sumUnlocked;

      if (_limit == 0) _limit = pending[msg.sender].length;

      for (uint256 i = 0; i < _limit; i++){
        //already fully unlocked
        if (block.number - pending[msg.sender][i].endBlock >= lockupPeriodBlocks){
          sumUnlocked += pending[msg.sender][i].amount - pending[msg.sender][i].alreadyClaimed;
          //reset the fully claimed element
          delete pending[msg.sender][i];
        } else {
          uint256 duration = pending[msg.sender][i].endBlock - pending[msg.sender][i].startBlock;
          uint256 amountPerBlock = pending[msg.sender][i].amount / duration;
          uint256 unlockedAmount = (block.number - pending[msg.sender][i].startBlock - lockupPeriodBlocks) * amountPerBlock;
          //remaining locked tokens
          sumLocked += pending[msg.sender][i].amount - unlockedAmount - pending[msg.sender][i].alreadyClaimed;

          sumUnlocked += unlockedAmount - pending[msg.sender][i].alreadyClaimed;
          pending[msg.sender][i].alreadyClaimed += unlockedAmount;

          //if we are also claiming locked rewards, delete every element
          if (_claimLocked){
            delete pending[msg.sender][i];
          }
        }
      }

      //remove only unlocked pendingRewards
      if (!_claimLocked){
        safeTokensTransfer(msg.sender, sumUnlocked);
      } else {
        safeTokensTransfer(msg.sender, sumUnlocked + sumLocked.div(2));
        safeTokensTransfer(penaltyAddress, sumLocked.div(2));
      }

      //Now remove deleted elements, so they won't stay in the array
      //Since using `delete` leaves a empty space, and using `for` loop could miss some elements,
      //we first check if element is deleted and if it is, we replace with with last element and then pop it
      //Since last element can also be deleted, we check, and retry again if it is
      //The issue is that it will change the order <fix required>
      uint256 i = 0;
      uint256 j = 0;
      while(j < _limit){
        if (pending[msg.sender][i].amount == 0){ //deleted element
          pending[msg.sender][i] = pending[msg.sender][pending[msg.sender].length - 1];
          pending[msg.sender].pop();
        } else {
          i++;
        }
        j++;
      }

      Claim(msg.sender, sumUnlocked + sumLocked.div(2), sumLocked.div(2));
    }

    /**
     * @notice Get the sum of all pending unlocked tokens
     * @return Number of unlocked tokens that can be claimed without penalty
     */
    function unlockedTokens(address _user) external view returns (uint256) {
      uint256 sumUnlocked;

      for (uint256 i = 0; i < pending[msg.sender].length; i++){
        //already fully unlocked
        if (block.number - pending[msg.sender][i].endBlock >= lockupPeriodBlocks){
          sumUnlocked += pending[msg.sender][i].amount;
        } else {
          uint256 duration = pending[msg.sender][i].endBlock - pending[msg.sender][i].startBlock;
          uint256 amountPerBlock = pending[msg.sender][i].amount / duration;
          uint256 unlockedAmount = (block.number - pending[msg.sender][i].startBlock - lockupPeriodBlocks) * amountPerBlock;
          sumUnlocked += unlockedAmount - pending[msg.sender][i].alreadyClaimed;
        }
      }

      return sumUnlocked;
    }

    /**
     * @notice Get the sum of all pending locked tokens
     * @return Number of locked tokens that will require paying 50% penalty if claimed
     */
    function lockedTokens(address _user) external view returns (uint256) {
      uint256 sumLocked = 0;

      for (uint256 i = 0; i < pending[msg.sender].length; i++){
        if (block.number - pending[msg.sender][i].endBlock >= lockupPeriodBlocks){
          //already fully unlocked
        } else {
          uint256 duration = pending[msg.sender][i].endBlock - pending[msg.sender][i].startBlock;
          uint256 amountPerBlock = pending[msg.sender][i].amount / duration;
          uint256 unlockedAmount = (block.number - pending[msg.sender][i].startBlock - lockupPeriodBlocks) * amountPerBlock;
          sumLocked += pending[msg.sender][i].amount - unlockedAmount - pending[msg.sender][i].alreadyClaimed;
        }
      }

      return sumLocked;
    }

    /**
     * @notice Get the number of pendingRewards not claimed yet
     * @param user Address of the user
     * @return Length of pending array
     */
    function pendingLength(address user) external view returns (uint256) {
      return pending[user].length;
    }

    /**
     * @notice Deposit Want tokens from user -> This contract -> Strategy (compounding)
     * @param _pid PID of the pool
     * @param _wantAmt Amount of tokens to deposit
     */
    function deposit(uint256 _pid, uint256 _wantAmt) public nonReentrant {
        updatePool(_pid);
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        if (user.shares > 0) {
            uint256 _pending =
                user.shares.mul(pool.accTokensPerShare).div(1e12).sub(
                    user.rewardDebt
                );
            if (_pending > 0) {
              pending[msg.sender].push(pendingRewards(
                  block.number,
                  block.number + lockupPeriodBlocks,
                  _pending,
                  0
              ));
            }
        }
        if (_wantAmt > 0) {
            pool.want.safeTransferFrom(
                address(msg.sender),
                address(this),
                _wantAmt
            );

            pool.want.safeIncreaseAllowance(pool.strat, _wantAmt);
            uint256 sharesAdded =
                IStrategy(poolInfo[_pid].strat).deposit(msg.sender, _wantAmt);
            user.shares = user.shares.add(sharesAdded);
        }
        user.rewardDebt = user.shares.mul(pool.accTokensPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _wantAmt);
    }

    /**
     * @notice Withdraw LP tokens from Strategy (compounding) -> This contract -> user
     * @param _pid PID of the pool
     * @param _wantAmt Amount of tokens to withdraw
     */
    function withdraw(uint256 _pid, uint256 _wantAmt) public nonReentrant {
        updatePool(_pid);

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        uint256 wantLockedTotal =
            IStrategy(poolInfo[_pid].strat).wantLockedTotal();
        uint256 sharesTotal = IStrategy(poolInfo[_pid].strat).sharesTotal();

        require(user.shares > 0, "user.shares is 0");
        require(sharesTotal > 0, "sharesTotal is 0");

        //collect rewards and add the to pending queue
        uint256 _pending =
            user.shares.mul(pool.accTokensPerShare).div(1e12).sub(
                user.rewardDebt
            );
        if (_pending > 0) {
          pending[msg.sender].push(pendingRewards(
              block.number,
              block.number + lockupPeriodBlocks,
              _pending,
              0
          ));
        }

        // Withdraw want tokens
        uint256 amount = user.shares.mul(wantLockedTotal).div(sharesTotal);
        if (_wantAmt > amount) {
            _wantAmt = amount;
        }
        if (_wantAmt > 0) {
            uint256 sharesRemoved =
                IStrategy(poolInfo[_pid].strat).withdraw(msg.sender, _wantAmt);

            if (sharesRemoved > user.shares) {
                user.shares = 0;
            } else {
                user.shares = user.shares.sub(sharesRemoved);
            }

            uint256 wantBal = IERC20(pool.want).balanceOf(address(this));
            if (wantBal < _wantAmt) {
                _wantAmt = wantBal;
            }
            pool.want.safeTransfer(address(msg.sender), _wantAmt);
        }
        user.rewardDebt = user.shares.mul(pool.accTokensPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _wantAmt);
    }

    /**
     * @notice Withdraw all tokens from the pool
     * @param _pid PID of the pool
     */
    function withdrawAll(uint256 _pid) public nonReentrant {
        withdraw(_pid, uint256(-1));
    }

    /**
     * @notice Withdraw all tokens from the pool, without caring about rewards. EMERGENCY ONLY.
     * @param _pid PID of the pool
     */
    function emergencyWithdraw(uint256 _pid) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        uint256 wantLockedTotal =
            IStrategy(poolInfo[_pid].strat).wantLockedTotal();
        uint256 sharesTotal = IStrategy(poolInfo[_pid].strat).sharesTotal();
        uint256 amount = user.shares.mul(wantLockedTotal).div(sharesTotal);

        IStrategy(poolInfo[_pid].strat).withdraw(msg.sender, amount);

        pool.want.safeTransfer(address(msg.sender), amount);
        emit EmergencyWithdraw(msg.sender, _pid, amount);
        user.shares = 0;
        user.rewardDebt = 0;
    }

    /**
     * @notice Safe reward tokens transfer function, just in case if rounding error causes pool to not have enough
     * @param _to  Address to send tokens to
     * @param _tokenAmount Amount of tokens to send
     */
    function safeTokensTransfer(address _to, uint256 _tokenAmount) internal {
        uint256 tokenBal = IERC20(rewardToken).balanceOf(address(this));
        bool transferSuccess = false;
        if (_tokenAmount > tokenBal) {
            transferSuccess = IERC20(rewardToken).transfer(_to, tokenBal);
        } else {
            transferSuccess = IERC20(rewardToken).transfer(_to, _tokenAmount);
        }
        require(transferSuccess, "safeTokensTransfer: transfer failed");
    }

    /**
     * @notice Function to transfer token from this contract, in case they are accidentally sent here. Only callable by owner!
     * @param _token Address of the token to transfer
     * @param _amount Amount to transfer
     */
    function rescueTokens(address _token, uint256 _amount)
        public
        onlyOwner
    {
        require(_token != rewardToken, "!safe");
        IERC20(_token).safeTransfer(msg.sender, _amount);
    }

    /**
     * @notice Change emission schedule by owner.
     * @param _startBlock Block number from where inflation schedule is counted, if 0, it's current block number
     * @param _emissionAmounts Array of emission amounts
     * @param _emissionDelays Array of delays for each amount
     */
    function updateEmissionRateSchedule(uint256 _startBlock, uint256[] calldata _emissionAmounts, uint256[] calldata _emissionDelays) public onlyOwner {
        if (_startBlock == 0) _startBlock = block.number;

        //delete previous emission schedule array
        for (uint256 i = 0; i < emissionScheduleArray.length; i++){
            delete emissionScheduleArray[i];
        }
        emissionScheduleLatest = 0;

        for (uint256 i = 0; i < _emissionAmounts.length; i++){
            emissionScheduleArray[i] = EmissionSchedule(_emissionAmounts[i], _startBlock + _emissionDelays[i]);
        }
    }

    /**
     * @notice Manually update emission rate
     * @notice It can't override `maxIssued`!
     * @param _tokensPerBlock Number of tokens per block.
     */
    function updateEmissionRate(uint256 _tokensPerBlock) public onlyOwner {
        massUpdatePools();
        tokensPerBlock = _tokensPerBlock;

        emit UpdateEmissionRate(_tokensPerBlock);
    }

    /**
     * @notice Manually update lockup period
     * @param _lockup Number of blocks.
     */
    function setLockupPeriod(uint256 _lockup) external onlyOwner {
      emit UpdateLockupPeriod(lockupPeriodBlocks, _lockup);
      lockupPeriodBlocks = _lockup;
    }

    /**
     * @notice Manually update penalty address
     * @param _newPenaltyAddress new penalty address
     */
    function setPenaltyAddress(address _newPenaltyAddress) external onlyOwner {
      penaltyAddress = _newPenaltyAddress;
      emit updatePenaltyAddress(_newPenaltyAddress);
    }
}
