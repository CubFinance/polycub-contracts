// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

interface IToken {
    function mint(address user, uint256 amount) external;
}
