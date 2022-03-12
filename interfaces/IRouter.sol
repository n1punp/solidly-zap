// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

interface IRouter {
  struct route {
    address from;
    address to;
    bool stable;
  }

  function swapExactTokensForTokensSimple(
    uint,
    uint,
    address,
    address,
    bool,
    address,
    uint
  ) external returns (uint[] memory);

  function addLiquidity(
    address,
    address,
    bool,
    uint,
    uint,
    uint,
    uint,
    address,
    uint
  )
    external
    returns (
      uint,
      uint,
      uint
    );

  function getAmountsOut(uint, route[] memory) external view returns (uint[] memory);

  function factory() external view returns (address);
}
