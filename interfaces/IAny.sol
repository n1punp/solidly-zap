// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import 'OpenZeppelin/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';

interface IAny is IERC20 {
  function owner() external view returns (address);

  function Swapin(
    bytes32,
    address,
    uint
  ) external returns (bool);

  function minter_mint(address, uint) external;

  function minters(address) external view returns (bool);

  function addMinter(address) external;

  function decimals() external view returns (uint8);
}
