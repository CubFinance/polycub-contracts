// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

interface ICurveVault {
  function earn() external;
  function inCaseTokensGetStuck(address _token, uint256 _amount, address _to) external;
}

contract CurveVaultGovernance {
  address public gov;
  address public vault;
  address public forbidden; //address that cannot be rescued

  modifier onlyGov(){
    require(msg.sender == gov, "!gov");
    _;
  }

  constructor(address _gauge, address _vault){
    gov = msg.sender;
    forbidden = _gauge;
    vault = _vault;
  }

  function earn() external onlyGov {
    ICurveVault(vault).earn();
  }

  function inCaseTokensGetStuck(address _token, uint256 _amount, address _to) external onlyGov {
    require(_token != forbidden, "forbidden token");

    ICurveVault(vault).inCaseTokensGetStuck(_token, _amount, _to);
  }

  function call(uint value, string memory signature, bytes memory data) external onlyGov {
    require(signature != "inCaseTokensGetStuck(address,uint256,address)", "Cannot use call for inCaseTokensGetStuck");
    require(signature != "setGov(address)", "Cannot use call for setGov");

    bytes32 txHash = keccak256(abi.encode(vault, value, signature, data));

    bytes memory callData;

    if (bytes(signature).length == 0) {
        callData = data;
    } else {
        callData = abi.encodePacked(bytes4(keccak256(bytes(signature))), data);
    }

    // solium-disable-next-line security/no-call-value
    (bool success, bytes memory returnData) = target.call{value: value}(callData);
  }
}
