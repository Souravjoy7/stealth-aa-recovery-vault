// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract MockTarget {
    uint256 public value;
    address public lastCaller;

    event ValueChanged(address indexed caller, uint256 value);

    function setValue(uint256 newValue) external payable returns (uint256) {
        value = newValue;
        lastCaller = msg.sender;
        emit ValueChanged(msg.sender, newValue);
        return newValue;
    }
}
