// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract MockEntryPoint {
    mapping(address => uint256) public balanceOf;

    receive() external payable {}

    function depositTo(address account) external payable {
        balanceOf[account] += msg.value;
    }

    function withdrawTo(address payable withdrawAddress, uint256 withdrawAmount) external {
        uint256 balance = balanceOf[msg.sender];
        require(balance >= withdrawAmount, "INSUFFICIENT_DEPOSIT");
        unchecked {
            balanceOf[msg.sender] = balance - withdrawAmount;
        }
        withdrawAddress.transfer(withdrawAmount);
    }
}
