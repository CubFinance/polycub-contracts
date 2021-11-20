// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "./interfaces/ERC20.sol";
import "./interfaces/Address.sol";
import "./interfaces/EnumerableSet.sol";
import "./interfaces/Ownable.sol";
import "./interfaces/ReentrancyGuard.sol";

import "./interfaces/IStrategy.sol";
import "./interfaces/IToken.sol";

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
        /// @Notice How many LP tokens the user has provided.
        uint256 shares;
        /// @@notice Reward debt. See explanation below.
        uint256 rewardDebt;

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
        /// @notice Address of the want token.
        IERC20 want;
        /// @notice How many allocation points assigned to this pool.
        uint256 allocPoint;
        /// @notice Last block number that reward token distribution occurs.
        uint256 lastRewardBlock;
        /// @notice Accumulated tokens per share, times 1e12. See below.
        uint256 accTokensPerShare;
        /// @notice Strategy vault address that will auto compound want tokens
        address strat;
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
      uint256 amount;
      uint256 unlockBlock;
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
     * @notice Helper function return length of the valiators array.
     * @return Length of the validators array
     */
    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    mapping(IERC20 => bool) public poolExistence;
    modifier nonDuplicated(IERC20 _want) {
        require(poolExistence[_want] == false, "nonDuplicated: duplicated");
        _;
    }

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

    // Update the given pool's reward token allocation point. Can only be called by the owner.
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

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to)
        public
        pure
        returns (uint256)
    {
        return _to.sub(_from);
    }

    // see pending tokens that have not entered waiting period yet (user need to call updatePool())
    // use lockedTokens & unlockedTokens to see pending tokens that are already in the unlock queue or were already unlocked
    // View function to see pending rewards tokens on frontend.
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

    // View function to see staked Want tokens on frontend.
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

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        //update emission schedule if we are not at the last yet
        //only first month we use emissionSchedule
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
            //mint new token
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

    // Safe reward tokens transfer function, just in case if rounding error causes pool to not have enough
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

    //add tokens to pending queue, for 1k claims, ~6M gas is used when claimimg them
    function collectPendingRewards() external {
        uint256 totalPending;
        for (uint256 i = 0; i < poolInfo.length; i++){
            updatePool(i);
            PoolInfo storage pool = poolInfo[i];
            UserInfo storage user = userInfo[i][msg.sender];
            uint256 pendingTokensVariable = user.shares.mul(pool.accTokensPerShare).div(1e12).sub(user.rewardDebt);
            if(pendingTokensVariable > 0) {
                totalPending += pendingTokensVariable;
            }
            user.rewardDebt = user.shares.mul(pool.accTokensPerShare).div(1e12);
        }
        pending[msg.sender].push(pendingRewards(totalPending, block.number + lockupPeriodBlocks));
    }

    //claim locked rewards
    //if _all is true, unlocked tokens will also be claimed (but 50% will be sent to penalty address)
    //in case if gas limit is lower than gas required to claim entire array of pendingRewards, use _limt
    //to claim just limited number of pendingRewards
    function claim(bool _all, uint256 _limit) external nonReentrant {
      uint256 sumLocked;
      uint256 sumUnlocked;

      if (_limit == 0) _limit = pending[msg.sender].length;

      for (uint256 i = 0; i < _limit; i++){
        if (pending[msg.sender][i].unlockBlock <= block.number){
          sumUnlocked += pending[msg.sender][i].amount;
          if (!_all){
            pending[msg.sender][i] = pending[msg.sender][pending[msg.sender].length-1];
            pending[msg.sender].pop();
          }
        } else {
          sumLocked += pending[msg.sender][i].amount;
        }
      }

      if (_all){
        uint256 totalAmount = sumUnlocked + sumLocked.div(2);
        uint256 penalty = sumLocked.div(2);

        //delete array
        for (uint256 i = 0; i < _limit; i++){
            pending[msg.sender].pop();
        }

        safeTokensTransfer(msg.sender, totalAmount);
        safeTokensTransfer(penaltyAddress, penalty);
      } else {
        safeTokensTransfer(msg.sender, sumUnlocked);
      }

      Claim(msg.sender, sumUnlocked + sumLocked.div(2), sumLocked.div(2));
    }

    //get sum of all pending unlocked tokens
    function unlockedTokens(address _user) external view returns (uint256) {
      uint256 sumUnlocked;
      for (uint256 i = 0; i < pending[_user].length; i++){
        if (pending[_user][i].unlockBlock <= block.number){
          sumUnlocked += pending[_user][i].amount;
        }
      }

      return sumUnlocked;
    }

    //get sum of all pending locked tokens
    function lockedTokens(address _user) external view returns (uint256) {
      uint256 sumLocked = 0;
      for (uint256 i = 0; i < pending[_user].length; i++){
        if (pending[_user][i].unlockBlock > block.number){
          sumLocked += pending[_user][i].amount;
        }
      }

      return sumLocked;
    }

    function pendingLength(address user) external view returns (uint256) {
      return pending[user].length;
    }

    // Want tokens moved from user -> This contract -> Strategy (compounding)
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
              pending[msg.sender].push(pendingRewards(_pending, block.number + lockupPeriodBlocks));
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

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _wantAmt) public nonReentrant {
        updatePool(_pid);

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        uint256 wantLockedTotal =
            IStrategy(poolInfo[_pid].strat).wantLockedTotal();
        uint256 sharesTotal = IStrategy(poolInfo[_pid].strat).sharesTotal();

        require(user.shares > 0, "user.shares is 0");
        require(sharesTotal > 0, "sharesTotal is 0");

        // Withdraw pending CUB
        uint256 _pending =
            user.shares.mul(pool.accTokensPerShare).div(1e12).sub(
                user.rewardDebt
            );
        if (_pending > 0) {
          pending[msg.sender].push(pendingRewards(_pending, block.number + lockupPeriodBlocks));
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

    function withdrawAll(uint256 _pid) public nonReentrant {
        withdraw(_pid, uint256(-1));
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
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

    function rescueTokens(address _token, uint256 _amount)
        public
        onlyOwner
    {
        require(_token != rewardToken, "!safe");
        IERC20(_token).safeTransfer(msg.sender, _amount);
    }

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

    function updateEmissionRate(uint256 _tokensPerBlock) public onlyOwner {
        massUpdatePools();
        tokensPerBlock = _tokensPerBlock;

        emit UpdateEmissionRate(_tokensPerBlock);
    }

    function setLockupPeriod(uint256 _lockup) external onlyOwner {
      emit UpdateLockupPeriod(lockupPeriodBlocks, _lockup);
      lockupPeriodBlocks = _lockup;
    }

    function setPenaltyAddress(address _newPenaltyAddress) external onlyOwner {
      penaltyAddress = _newPenaltyAddress;
      emit updatePenaltyAddress(_newPenaltyAddress);
    }
}
