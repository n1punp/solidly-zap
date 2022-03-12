// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import 'OpenZeppelin/openzeppelin-contracts@4.3.0/contracts/token/ERC20/IERC20.sol';
import 'OpenZeppelin/openzeppelin-contracts@4.3.0/contracts/token/ERC20/utils/SafeERC20.sol';

import '../../interfaces/Vm.sol';
import '../../interfaces/IRouter.sol';
import '../../interfaces/IAny.sol';
import '../utils/DSTest.sol';
import '../utils/StdCheats.sol';
import '../utils/BaseV1Pair.sol';
import '../utils/console.sol';
import '../SolidlyOptimalSwap.sol';

contract TestSwap is DSTest, stdCheats {
  using SafeERC20 for IERC20;
  Vm cheats = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
  BaseV1Pair pair;
  IRouter router;
  uint feeBps;
  address token0;
  address token1;
  Vm vm;

  function setUp() public {
    vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
    pair = BaseV1Pair(0x154eA0E896695824C87985a52230674C2BE7731b); // USDC/FRAX stable pool
    // pair = BaseV1Pair(0xCc7311Ac0aD11702ad674FB40f8E6E09D49C13e3); // DAI/MIM stable pool
    router = IRouter(0xa38cd27185a464914D3046f0AB9d43356B34829D);
    feeBps = 1;
    token0 = pair.token0();
    token1 = pair.token1();
  }

  function testOptimalSwap0To1Fuzzy(uint ratio0, uint ratio1) public {
    uint token0Decimal = IAny(token0).decimals();
    uint token1Decimal = IAny(token1).decimals();

    (uint r0, uint r1, ) = pair.getReserves();
    vm.assume(ratio0 > type(uint).max / 10000);
    vm.assume(ratio1 > type(uint).max / 10000);

    uint amt0 = (((ratio0 >> 128) * r0) >> 128) / 2;
    uint amt1 = (((ratio1 >> 128) * r1) >> 128) / 2;
    console.log('pool bal:', r0, r1);
    console.log('amt0:', amt0, 'amt1:', amt1);
    // mint tokens
    tip(token0, address(this), amt0);
    tip(token1, address(this), amt1);
    // calculate swap amount
    vm.assume(amt0 > 0);
    vm.assume(amt1 > 0);
    vm.assume(amt0 * r1 > amt1 * r0); // ensure swap direction 0 -> 1

    uint swapAmt = SolidlyOptimalSwap.getOptimalSwapAmountBinarySearch(
      (r0 * 10**18) / 10**token0Decimal,
      (r1 * 10**18) / 10**token1Decimal,
      (amt0 * 10**18) / 10**token0Decimal,
      (amt1 * 10**18) / 10**token1Decimal,
      feeBps
    );
    uint swapAmt2 = SolidlyOptimalSwap.getOptimalSwapAmountNewton(
      (r0 * 10**18) / 10**token0Decimal,
      (r1 * 10**18) / 10**token1Decimal,
      (amt0 * 10**18) / 10**token0Decimal,
      (amt1 * 10**18) / 10**token1Decimal,
      feeBps
    );

    console.log('swapAmt', swapAmt);
    console.log('swapAmt2', swapAmt2);
    require(swapAmt < swapAmt2 + 10 && swapAmt2 < swapAmt + 10, 'too far apart');

    swapAmt = (swapAmt * 10**token0Decimal) / 10**18;
    console.log('swapAmt', swapAmt);

    // perform swap
    console.log(
      'pre swap bals:',
      IERC20(token0).balanceOf(address(this)),
      IERC20(token1).balanceOf(address(this))
    );
    IERC20(token0).safeApprove(address(router), type(uint).max);
    IERC20(token1).safeApprove(address(router), type(uint).max);
    router.swapExactTokensForTokensSimple(
      swapAmt,
      0,
      token0,
      token1,
      true,
      address(this),
      type(uint).max
    );
    console.log(
      'pos swap bals:',
      IERC20(token0).balanceOf(address(this)),
      IERC20(token1).balanceOf(address(this))
    );

    // add liquidity
    uint balance0 = IERC20(token0).balanceOf(address(this));
    uint balance1 = IERC20(token1).balanceOf(address(this));
    console.log('pre add bals:', balance0, balance1);
    (r0, r1, ) = pair.getReserves();
    console.log('pool bal:', r0, r1);
    if (balance0 == 0 || balance1 == 0) {
      vm.expectRevert('BaseV1Router: INSUFFICIENT_AMOUNT');
    }
    router.addLiquidity(
      token0,
      token1,
      true,
      balance0,
      balance1,
      0,
      0,
      address(this),
      type(uint).max
    );
    // check result
    balance0 = IERC20(token0).balanceOf(address(this));
    balance1 = IERC20(token1).balanceOf(address(this));
    console.log('pos add bals:', balance0, balance1);
    uint decOffset0 = token0Decimal > token1Decimal ? token0Decimal - token1Decimal : 0;
    uint decOffset1 = token1Decimal > token0Decimal ? token1Decimal - token0Decimal : 0;

    require(balance0 < 10 * 10**decOffset0, 'too many token0s left');
    require(balance1 < 10 * 10**decOffset1, 'too many token1s left');
  }
}
