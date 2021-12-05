// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "./libs/Address.sol";
import "./libs/Context.sol";
import "./libs/Ownable.sol";
import "./libs/ReentrancyGuard.sol";
import "./libs/Pausable.sol";
import "./libs/IERC20.sol";
import "./libs/SafeMath.sol";
import "./libs/SafeERC20.sol";
import "./libs/ERC20.sol";

interface ICurveRewardsOnlyGauge {
  function reward_contract() external returns(address);
  function balanceOf(address _user) external returns (uint256);
  function claim_rewards() external;
  function deposit(uint256 _value) external;
  function withdraw(uint256 _value) external;
}

interface ICurveStableSwapAave {
  function add_liquidity(uint256[2] memory _amounts, uint256 _min_mint_amount) external;
}

interface IReward {
  function updateRewards(address userAddress, uint256 sharesChange, bool isSharesRemoved) external;
}

interface IRouter {
  function getAmountsOut(uint amountIn, address[] memory path) external view returns (uint[] memory amounts);
  function swapExactTokensForTokensSupportingFeeOnTransferTokens(  uint amountIn,  uint amountOutMin,  address[] calldata path,  address to,  uint deadline) external;
}

contract Curve_PolyCub_Vault is Ownable, ReentrancyGuard, Pausable {
  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  address public masterChefAddress;
  address public farmContractAddress;
  address public wantAddress;
  address public govAddress;
  address public rewardsAddress;

  address public uniRouterAddress;
  address public token0Address;
  address[] public earnedToToken0Path;

  address public earnedAddress;
  address public maticAddress = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;

  uint256 public wantLockedTotal;
  uint256 public sharesTotal;
  uint256 public lastEarnBlock;

  uint256 public entranceFeeFactor;
  uint256 public constant entranceFeeFactorMax = 10000;
  uint256 public constant entranceFeeFactorLL = 9950;

  uint256 public withdrawFeeFactor;
  uint256 public constant withdrawFeeFactorMax = 10000;
  uint256 public constant withdrawFeeFactorLL = 9950;

  uint256 public controllerFee = 1000;
  uint256 public constant controllerFeeMax = 10000; // 100 = 1%
  uint256 public constant controllerFeeUL = 1000;

  uint256 public buyBackRate = 0; // 250;
  uint256 public constant buyBackRateMax = 10000; // 100 = 1%
  uint256 public constant buyBackRateUL = 800;
  address public buyBackAddress = 0x000000000000000000000000000000000000dEaD;

  uint256 public slippageFactor = 0; // 5% default slippage tolerance
  uint256 public constant slippageFactorUL = 995;

  bool public isAutoComp = true;
  bool public isSameAssetDeposit = false;
  bool public onlyGov = true;

  address[] public rewarders;
  address[] public CRVToUSDCPath;

  address public curvePoolAddress;
  address public CRVAddress = 0x172370d5Cd63279eFa6d502DAB29171933a610AF;
  address public reward_contract;

  modifier onlyAllowGov() {
    require(msg.sender == govAddress, "!gov");
    _;
  }

  constructor(
    address _farmContractAddress,
    address[] memory _rewarders,
    address[] memory _CRVToUSDCPath,
    address _masterChefAddress,
    address _wantAddress,
    address _govAddress,
    address _rewardsAddress
    address _uniRouterAddress,
    address _token0Address,
    address[] _earnedToToken0Path,
    address _earnedAddress,
    uint256 _entranceFeeFactor,
    uint256 _withdrawFeeFactor,
    address[] _rewarders,
    address[] _CRVToUSDCPath,
    address _reward_contract,
    address _curvePoolAddress
  ) public {
    farmContractAddress = _farmContractAddress;
    rewarders = _rewarders;
    CRVToUSDCPath = _CRVToUSDCPath;
    reward_contract = ICurveRewardsOnlyGauge(farmContractAddress).reward_contract();
    masterChefAddress = _masterChefAddress;
    wantAddress = _wantAddress;
    govAddress = _govAddress;
    rewardsAddress = _rewardsAddress;
    uniRouterAddress = _uniRouterAddress;
    token0Address = _token0Address;
    earnedToToken0Path = _earnedToToken0Path;
    earnedAddress = _earnedAddress;
    entranceFeeFactor = _entranceFeeFactor;
    withdrawFeeFactor = _withdrawFeeFactor;
    rewarders = _rewarders;
    CRVToUSDCPath = _CRVToUSDCPath;
    reward_contract = _reward_contract;
    curvePoolAddress = _curvePoolAddress;
  }

  function updateRewarders(address[] memory _rewarders) public onlyAllowGov {
    rewarders = _rewarders;
  }

  function _harvestReward(
    address _userAddress,
    uint256 _sharesChange,
    bool _isSharesRemoved
  ) internal {
    for (uint256 i=0; i<rewarders.length; i++) {
      if (!Address.isContract(rewarders[i])) {
        continue;
      }
      IReward(rewarders[i]).updateRewards(
        _userAddress,
        _sharesChange,
        _isSharesRemoved
      );
    }
  }

  // Receives new deposits from user
  function deposit(address _userAddress, uint256 _wantAmt)
    public
    onlyOwner
    nonReentrant
    whenNotPaused
    returns (uint256)
  {
    IERC20(wantAddress).safeTransferFrom(
      address(msg.sender),
      address(this),
      _wantAmt
    );
    reward_contract = ICurveRewardsOnlyGauge(farmContractAddress).reward_contract();

    wantLockedTotal = ICurveRewardsOnlyGauge(farmContractAddress).balanceOf(
      address(this)
    );
    uint256 sharesAdded = _wantAmt;
    if (wantLockedTotal > 0 && sharesTotal > 0) {
      sharesAdded = _wantAmt
        .mul(sharesTotal)
        .mul(entranceFeeFactor)
        .div(wantLockedTotal)
        .div(entranceFeeFactorMax);
    }
    sharesTotal = sharesTotal.add(sharesAdded);

    if (isAutoComp) {
      _farm();
    }

    _harvestReward(_userAddress, sharesAdded, false);

    return sharesAdded;
  }

  function _farm() internal {
    require(isAutoComp, "!isAutoComp");
    uint256 wantAmt = IERC20(wantAddress).balanceOf(address(this));
    IERC20(wantAddress).safeIncreaseAllowance(farmContractAddress, wantAmt);
    ICurveRewardsOnlyGauge(farmContractAddress).deposit(wantAmt);
    wantLockedTotal = ICurveRewardsOnlyGauge(farmContractAddress).balanceOf(
      address(this)
    );
  }

  function _unfarm(uint256 _wantAmt) internal {
    if (_wantAmt == 0) {
      ICurveRewardsOnlyGauge(farmContractAddress).claim_rewards();
    } else {
      ICurveRewardsOnlyGauge(farmContractAddress).withdraw(_wantAmt);
    }
  }

  function withdraw(address _userAddress, uint256 _wantAmt)
    public
    onlyOwner
    nonReentrant
    returns (uint256)
  {
    require(_wantAmt > 0, "_wantAmt <= 0");

    wantLockedTotal = ICurveRewardsOnlyGauge(farmContractAddress).balanceOf(
      address(this)
    );

    uint256 sharesRemoved = _wantAmt.mul(sharesTotal).div(wantLockedTotal);
    if (sharesRemoved > sharesTotal) {
      sharesRemoved = sharesTotal;
    }
    sharesTotal = sharesTotal.sub(sharesRemoved);

    if (withdrawFeeFactor < withdrawFeeFactorMax) {
      _wantAmt = _wantAmt.mul(withdrawFeeFactor).div(
          withdrawFeeFactorMax
      );
    }

    if (isAutoComp) {
      _unfarm(_wantAmt);
    }

    uint256 wantAmt = IERC20(wantAddress).balanceOf(address(this));
    if (_wantAmt > wantAmt) {
      _wantAmt = wantAmt;
    }

    if (wantLockedTotal < _wantAmt) {
      _wantAmt = wantLockedTotal;
    }

    IERC20(wantAddress).safeTransfer(masterChefAddress, _wantAmt);

    wantLockedTotal = ICurveRewardsOnlyGauge(farmContractAddress).balanceOf(
      address(this)
    );

    _harvestReward(_userAddress, sharesRemoved, true);

    return sharesRemoved;
  }

  function earn() public nonReentrant whenNotPaused {
    require(isAutoComp, "!isAutoComp");
    if (onlyGov) {
      require(msg.sender == govAddress, "!gov");
    }

    // Harvest farm tokens
    _unfarm(0);

    // Converts farm tokens into want tokens
    uint256 earnedAmt = IERC20(earnedAddress).balanceOf(address(this));

    earnedAmt = distributeFees(earnedAmt);

    if (isSameAssetDeposit) {
      lastEarnBlock = block.number;
      _farm();
      return;
    }

    if (earnedAmt > 0){
      IERC20(earnedAddress).safeApprove(uniRouterAddress, 0);
      IERC20(earnedAddress).safeIncreaseAllowance(
        uniRouterAddress,
        earnedAmt
      );

      // Swap earned to token0
      _safeSwap(
        uniRouterAddress,
        earnedAmt,
        slippageFactor,
        earnedToToken0Path,
        address(this),
        block.timestamp.add(600)
      );
    }

    _convertCRVToUSDC();

    // Get want tokens, ie. add liquidity
    uint256 token0Amt = IERC20(token0Address).balanceOf(address(this));

    if (token0Amt > 0) {
      IERC20(token0Address).safeApprove(curvePoolAddress, 0);
      IERC20(token0Address).safeIncreaseAllowance(
        curvePoolAddress,
        token0Amt
      );

      ICurveStableSwapAave(curvePoolAddress).add_liquidity([0, token0Amt], 0);
    }

    lastEarnBlock = block.number;

    _farm();
  }

  function distributeFees(uint256 _earnedAmt)
      internal
      virtual
      returns (uint256)
  {
      if (_earnedAmt > 0) {
          // Performance fee
          if (controllerFee > 0) {
              uint256 fee =
                  _earnedAmt.mul(controllerFee).div(controllerFeeMax);
              IERC20(earnedAddress).safeTransfer(rewardsAddress, fee);
              _earnedAmt = _earnedAmt.sub(fee);
          }
      }

      return _earnedAmt;
  }

  function _convertCRVToUSDC() internal {
    uint256 CRVAmt = IERC20(CRVAddress).balanceOf(address(this));
    if (CRVAddress != earnedAddress && CRVAmt > 0) {
      IERC20(CRVAddress).safeIncreaseAllowance(uniRouterAddress, CRVAmt);
      // Swap all dust tokens to earned tokens
      _safeSwap(
        uniRouterAddress,
        CRVAmt,
        slippageFactor,
        CRVToUSDCPath,
        address(this),
        now.add(600)
      );
    }
  }

  function setSettings(
      uint256 _entranceFeeFactor,
      uint256 _withdrawFeeFactor,
      uint256 _controllerFee,
      uint256 _buyBackRate,
      uint256 _slippageFactor
  ) public virtual onlyAllowGov {
      require(
          _entranceFeeFactor >= entranceFeeFactorLL,
          "_entranceFeeFactor too low"
      );
      require(
          _entranceFeeFactor <= entranceFeeFactorMax,
          "_entranceFeeFactor too high"
      );
      entranceFeeFactor = _entranceFeeFactor;

      require(
          _withdrawFeeFactor >= withdrawFeeFactorLL,
          "_withdrawFeeFactor too low"
      );
      require(
          _withdrawFeeFactor <= withdrawFeeFactorMax,
          "_withdrawFeeFactor too high"
      );
      withdrawFeeFactor = _withdrawFeeFactor;

      require(_controllerFee <= controllerFeeUL, "_controllerFee too high");
      controllerFee = _controllerFee;

      require(_buyBackRate <= buyBackRateUL, "_buyBackRate too high");
      buyBackRate = _buyBackRate;

      require(
          _slippageFactor <= slippageFactorUL,
          "_slippageFactor too high"
      );
      slippageFactor = _slippageFactor;
  }

  function setGov(address _govAddress) public virtual onlyAllowGov {
      govAddress = _govAddress;
  }

  function setOnlyGov(bool _onlyGov) public virtual onlyAllowGov {
      onlyGov = _onlyGov;
  }

  function setUniRouterAddress(address _uniRouterAddress)
      public
      virtual
      onlyAllowGov
  {
      uniRouterAddress = _uniRouterAddress;
  }

  function setBuyBackAddress(address _buyBackAddress)
      public
      virtual
      onlyAllowGov
  {
      buyBackAddress = _buyBackAddress;
  }

  function setRewardsAddress(address _rewardsAddress)
      public
      virtual
      onlyAllowGov
  {
      rewardsAddress = _rewardsAddress;
  }

  function changePaused() external onlyAllowGov {
    if (paused()) _unpause();
    else _pause();
  }


  function inCaseTokensGetStuck(
      address _token,
      uint256 _amount,
      address _to
  ) public virtual onlyAllowGov {
      require(_token != earnedAddress, "!safe");
      require(_token != wantAddress, "!safe");
      IERC20(_token).safeTransfer(_to, _amount);
  }

  function _safeSwap(
      address _uniRouterAddress,
      uint256 _amountIn,
      uint256 _slippageFactor,
      address[] memory _path,
      address _to,
      uint256 _deadline
  ) internal virtual {
      uint256[] memory amounts =
          IRouter(_uniRouterAddress).getAmountsOut(_amountIn, _path);
      uint256 amountOut = amounts[amounts.length.sub(1)];

      IRouter(_uniRouterAddress)
          .swapExactTokensForTokensSupportingFeeOnTransferTokens(
          _amountIn,
          amountOut.mul(_slippageFactor).div(1000),
          _path,
          _to,
          _deadline
      );
  }
}
