// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ISimpleStaking {
    function stake(uint256 amount) external;
    function withdraw(uint256 amount) external;
}

contract StakeFlow is Script {
    // Hardcoded params - edit these or replace at build time
    address constant TOKEN = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant STAKING = 0xDa8a7077419BE118Dff07d30fAb27610D5225516;
    uint256 constant APPROVE_AMOUNT = 200000;
    uint256 constant STAKE_AMOUNT = 100000;
    uint256 constant WITHDRAW_AMOUNT = 100000;

    function run() external {
        // approve
        IERC20(TOKEN).approve(STAKING, APPROVE_AMOUNT);

        // stake
        ISimpleStaking(STAKING).stake(STAKE_AMOUNT);

        // withdraw
        ISimpleStaking(STAKING).withdraw(WITHDRAW_AMOUNT);
    }
}
