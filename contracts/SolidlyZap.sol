// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import 'OpenZeppelin/openzeppelin-contracts@4.3.0/contracts/token/ERC20/IERC20.sol';
import 'OpenZeppelin/openzeppelin-contracts@4.3.0/contracts/token/ERC20/utils/SafeERC20.sol';

import '../interfaces/IRouter.sol';
import '../interfaces/IFactory.sol';
import './utils/BaseV1Pair.sol';
import './SolidlyOptimalSwap.sol';

/// @title Zap contract for adding any amounts of tokens for Solidly stable pool (x^3y + xy^3 = k)
/// @author Alpha Finance Lab
/// @notice The contract is unaudited. Use at your own risk.
contract SolidlyZap {
  using SafeERC20 for IERC20;

  uint public constant feeBps = 1; // 0.01% for all stable pools
  IRouter public immutable router;
  address public immutable factory;
  bytes32 public immutable pairCodeHash;

  constructor(address _router) {
    router = IRouter(_router);
    factory = IRouter(_router).factory();
    pairCodeHash = IFactory(factory).pairCodeHash();
  }

  /// @notice Add liquidity to Solidly stable pool
  /// @param _tokenA Token A address
  /// @param _tokenB Token B address
  /// @param _amtA Input token A amount
  /// @param _amtB Input token B amount
  /// @param _minLiquidity Minimum liquidity (LP) received (slippage control)
  /// @param _to Target address to receive LP tokens
  /// @param _deadline Tx deadline
  /// @return amountA Amount of token A used
  ///         amountB Amount of token B used
  ///         liquidity Amount of LP tokens minted (received)
  function addLiquidityStable(
    address _tokenA,
    address _tokenB,
    uint _amtA,
    uint _amtB,
    uint _minLiquidity,
    address _to,
    uint _deadline
  )
    external
    returns (
      uint amountA,
      uint amountB,
      uint liquidity
    )
  {
    // transfer in tokens
    if (_amtA > 0) IERC20(_tokenA).safeTransferFrom(msg.sender, address(this), _amtA);
    if (_amtB > 0) IERC20(_tokenB).safeTransferFrom(msg.sender, address(this), _amtB);

    // ensure tokens are approved
    ensureApprove(_tokenA);
    ensureApprove(_tokenB);

    // get swap info
    (bool aToB, uint swapAmt) = _getSwapInfo(_tokenA, _tokenB, _amtA, _amtB);

    // optimal swap
    _swap(aToB, swapAmt, _tokenA, _tokenB, _deadline);

    // add liquidity
    (amountA, amountB, liquidity) = _addLiquidity(_tokenA, _tokenB, _to, _deadline);

    // slippage check
    require(liquidity >= _minLiquidity, 'INSUFFICIENT LIQUIDITY');
  }

  /// @notice Helper function to get swap info
  /// @param _tokenA Token A
  /// @param _tokenB Token B
  /// @param _amtA Input tokenA amount
  /// @param _amtB Input tokenB amount
  /// @return aToB Boolean whether swap direction is A to B
  ///         swapAmt Swap amount
  function _getSwapInfo(
    address _tokenA,
    address _tokenB,
    uint _amtA,
    uint _amtB
  ) internal view returns (bool aToB, uint swapAmt) {
    address pair = pairFor(_tokenA, _tokenB, true);
    (address token0, ) = sortTokens(_tokenA, _tokenB);
    uint resA;
    uint resB;
    if (token0 == _tokenA) {
      (resA, resB, ) = BaseV1Pair(pair).getReserves();
    } else {
      (resB, resA, ) = BaseV1Pair(pair).getReserves();
    }

    // compute swap amounts
    aToB = _amtA * resB > _amtB * resA; // swap direction
    swapAmt = aToB
      ? SolidlyOptimalSwap.getOptimalSwapAmountNewton(resA, resB, _amtA, _amtB, feeBps)
      : SolidlyOptimalSwap.getOptimalSwapAmountNewton(resB, resA, _amtB, _amtA, feeBps);
  }

  /// @notice Helper function to optimally swap tokens
  /// @param _aToB Boolean whether swap direction is from A to B
  /// @param _swapAmt Swap amount
  /// @param _tokenA Token A
  /// @param _tokenB Token B
  /// @param _deadline Tx deadline
  function _swap(
    bool _aToB,
    uint _swapAmt,
    address _tokenA,
    address _tokenB,
    uint _deadline
  ) internal {
    if (_aToB) {
      router.swapExactTokensForTokensSimple(
        _swapAmt,
        0,
        _tokenA,
        _tokenB,
        true,
        address(this),
        _deadline
      );
    } else {
      router.swapExactTokensForTokensSimple(
        _swapAmt,
        0,
        _tokenB,
        _tokenA,
        true,
        address(this),
        _deadline
      );
    }
  }

  /// @notice Helper function to add liquidity
  /// @param _tokenA Token A
  /// @param _tokenB Token B
  /// @param _to Target address to receive LP token
  /// @param _deadline Tx deadline
  /// @return Token A amount used
  ///         Token B amount used
  ///         LP amount minted
  function _addLiquidity(
    address _tokenA,
    address _tokenB,
    address _to,
    uint _deadline
  )
    internal
    returns (
      uint,
      uint,
      uint
    )
  {
    return
      router.addLiquidity(
        _tokenA,
        _tokenB,
        true,
        IERC20(_tokenA).balanceOf(address(this)),
        IERC20(_tokenB).balanceOf(address(this)),
        0,
        0,
        _to,
        _deadline
      );
  }

  // https://github.com/solidlyexchange/solidly/blob/master/contracts/BaseV1-periphery.sol#91
  // calculates the CREATE2 address for a pair without making any external calls
  function pairFor(
    address _tokenA,
    address _tokenB,
    bool _stable
  ) public view returns (address pair) {
    (address token0, address token1) = sortTokens(_tokenA, _tokenB);
    pair = address(
      uint160(
        uint(
          keccak256(
            abi.encodePacked(
              hex'ff',
              factory,
              keccak256(abi.encodePacked(token0, token1, _stable)),
              pairCodeHash // init code hash
            )
          )
        )
      )
    );
  }

  /// @dev Ensure token is approved to the router
  /// @param _token The token to approve
  function ensureApprove(address _token) internal {
    if (IERC20(_token).allowance(address(this), address(router)) == 0) {
      IERC20(_token).safeApprove(address(router), type(uint).max);
    }
  }

  // https://github.com/solidlyexchange/solidly/blob/master/contracts/BaseV1-periphery.sol#L85
  function sortTokens(address _tokenA, address _tokenB)
    public
    pure
    returns (address token0, address token1)
  {
    require(_tokenA != _tokenB, 'BaseV1Router: IDENTICAL_ADDRESSES');
    (token0, token1) = _tokenA < _tokenB ? (_tokenA, _tokenB) : (_tokenB, _tokenA);
    require(token0 != address(0), 'BaseV1Router: ZERO_ADDRESS');
  }
}
