// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

interface IFactory {
  function pairCodeHash() external view returns (bytes32);
}
