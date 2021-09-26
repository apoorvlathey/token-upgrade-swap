// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/access/Ownable.sol';

contract TokenSwap is Ownable {
    using SafeERC20 for IERC20;

    address private constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    IERC20 public immutable v1Token;
    IERC20 public immutable v2Token;

    constructor(IERC20 _v1Token, IERC20 _v2Token) {
        v1Token = _v1Token;
        v2Token = _v2Token;
    }

    // convert user's entire v1 token balance to v2
    // v1 tokens must be approved beforehand
    function bridgeAll() external {
        bridge(v1Token.balanceOf(msg.sender));
    }

    // convert `amount` of user's v1 tokens to v2
    // v1 tokens must be approved beforehand
    function bridge(uint256 amount) public {
        v1Token.safeTransferFrom(msg.sender, BURN_ADDRESS, amount);
        
        // 1. if feeOnTransfer == 0, then user would receive 1:1 v2 tokens
        // 2. due to rebase, contract's v2 token balance would fluctuate over time.
        //    so some excess v2 tokens can get stuck here --OR-- contract might not have sufficient V2 tokens to send.
        v2Token.safeTransfer(msg.sender, amount);
    }

    // withdraws remaining v2 tokens from this contract
    function withdrawRemaining() onlyOwner external {
        v2Token.safeTransfer(msg.sender, v2Token.balanceOf(address(this)));
    }
}
