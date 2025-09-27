// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract SimpleStaking {
    IERC20 public immutable stakingToken;

    mapping(address => uint256) public balances;

    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);

    constructor(address _token) {
        require(_token != address(0), "invalid token");
        stakingToken = IERC20(_token);
    }

    function stake(uint256 amount) external {
        require(amount > 0, "amount = 0");

        // pull tokens from user
        require(
            stakingToken.transferFrom(msg.sender, address(this), amount),
            "transfer failed"
        );

        balances[msg.sender] += amount;

        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount) external {
        require(amount > 0, "amount = 0");
        require(balances[msg.sender] >= amount, "not enough staked");

        balances[msg.sender] -= amount;

        require(stakingToken.transfer(msg.sender, amount), "transfer failed");

        emit Withdrawn(msg.sender, amount);
    }

    function balanceOf(address user) external view returns (uint256) {
        return balances[user];
    }
}
