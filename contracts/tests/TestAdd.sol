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
import '../SolidlyZap.sol';

contract TestAdd is DSTest, stdCheats {
  /// @notice x is in 1e18
  function sqrt(uint x) private pure returns (uint) {
    unchecked {
      x = x * 1e18; // multiply by 1e18 to keep 1e18 multiplier
      if (x == 0) return 0;
      else {
        uint xx = x;
        uint r = 1;
        if (xx >= 0x100000000000000000000000000000000) {
          xx >>= 128;
          r <<= 64;
        }
        if (xx >= 0x10000000000000000) {
          xx >>= 64;
          r <<= 32;
        }
        if (xx >= 0x100000000) {
          xx >>= 32;
          r <<= 16;
        }
        if (xx >= 0x10000) {
          xx >>= 16;
          r <<= 8;
        }
        if (xx >= 0x100) {
          xx >>= 8;
          r <<= 4;
        }
        if (xx >= 0x10) {
          xx >>= 4;
          r <<= 2;
        }
        if (xx >= 0x8) {
          r <<= 1;
        }
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1; // Seven iterations should be enough
        uint r1 = x / r;
        return r < r1 ? r : r1;
      }
    }
  }

  using SafeERC20 for IERC20;
  Vm cheats = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
  BaseV1Pair pair;
  SolidlyZap zap;
  IRouter router;
  uint feeBps;
  address token0;
  address token1;
  Vm vm;

  function setUp() public {
    zap = new SolidlyZap(0xa38cd27185a464914D3046f0AB9d43356B34829D);
    vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
    // pair = BaseV1Pair(0x154eA0E896695824C87985a52230674C2BE7731b); // USDC/FRAX stable pool
    pair = BaseV1Pair(0xCc7311Ac0aD11702ad674FB40f8E6E09D49C13e3); // DAI/MIM stable pool
    router = IRouter(0xa38cd27185a464914D3046f0AB9d43356B34829D);
    feeBps = 1;
    token0 = pair.token0();
    token1 = pair.token1();
  }

  function testOptimalAdd0To1Fuzzy(uint ratio0, uint ratio1) public {
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

    // approve tokens
    IERC20(token0).safeApprove(address(zap), type(uint).max);
    IERC20(token1).safeApprove(address(zap), type(uint).max);

    // calculate approx lp shares received
    uint lpSupply = pair.totalSupply();
    uint ratio = ((((((r0 + amt0) * (r0 + amt0)) / r0) * (r1 + amt1)) / r1) * (r0 + amt0) * 1e18) /
      (r0 * r0 + r1 * r1) +
      ((((((r1 + amt1) * (r1 + amt1)) / r1) * (r0 + amt0)) / r0) * (r1 + amt1) * 1e18) /
      (r0 * r0 + r1 * r1); // (s0^3 s1 + s0 s1^3) / (r0^3 r1 + r0 r1^3) in 1e18
    ratio = sqrt(ratio);
    ratio = sqrt(ratio); // expected lp shares = raise to the power of 1/4 (to make scaling linear)
    uint expShares = (ratio * lpSupply) / 1e18 - lpSupply;

    console.log('total supply', lpSupply);
    console.log('expected shares', expShares);

    // add
    (, , uint liquidity) = zap.addLiquidityStable(
      token0,
      token1,
      amt0,
      amt1,
      0,
      address(this),
      type(uint).max
    );
    console.log('liquidity', liquidity);
    console.log('new total supply', pair.totalSupply());

    // check approx liquidity (within 0.01% fee)
    require(liquidity >= (expShares * 9999) / 10000 && liquidity <= expShares, 'shares too far');
  }
}
