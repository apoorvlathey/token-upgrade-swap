pragma solidity 0.8.7;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract V1Token is ERC20 {
  constructor(address _receiver) ERC20("V1Token", "V1Token") {
    _mint(_receiver, 12_000_000 ether);
  }
}