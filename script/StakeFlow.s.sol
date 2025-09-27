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
    address constant TOKEN = 0x0000000000000000000000000000000000000000;
    address constant STAKING = 0x0000000000000000000000000000000000000000;
    uint256 constant APPROVE_AMOUNT = 1 ether;
    uint256 constant STAKE_AMOUNT = 5e17; // 0.5 ether
    uint256 constant WITHDRAW_AMOUNT = 25e16; // 0.25 ether

    function run() external {
        // approve
        IERC20(TOKEN).approve(STAKING, APPROVE_AMOUNT);

        // stake
        ISimpleStaking(STAKING).stake(STAKE_AMOUNT);

        // withdraw
        ISimpleStaking(STAKING).withdraw(WITHDRAW_AMOUNT);
    }
}
