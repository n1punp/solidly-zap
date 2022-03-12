// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

/// @title Optimal swap calculation for Solidly stable pool (x^3y + xy^3 = k)
/// @author Alpha Finance Lab
/// @notice The contract is unaudited. Use at your own risk.
library SolidlyOptimalSwap {
  uint private constant BPS = 1e4;

  /// @notice A -> B
  ///         for consistency, all inputs MUST have decimals 18
  ///         method: binary search
  /// @dev Get optimal swap amount using binary search method
  /// @param resA Reserve A amount
  /// @param resB Reserve B amount
  /// @param amtA Supply A amount
  /// @param amtB Supply B amount
  /// @param feeBps Swap fee in bps
  /// @return Swap amount for tokenA (assuming swap direction is A -> B)
  function getOptimalSwapAmountBinarySearch(
    uint resA,
    uint resB,
    uint amtA,
    uint amtB,
    uint feeBps
  ) external pure returns (uint) {
    require(amtA < resA, 'Invalid amtA');
    require(amtA * resB > amtB * resA, '!swap direction');
    uint lower = 1;
    uint upper = amtA; // initial upperbound

    // binary search
    while (upper > lower) {
      uint s = (lower + upper) / 2;
      uint A = resA + ((BPS - feeBps) * s) / BPS;
      uint B = (A * (amtB + resB)) / (amtA + resA - (feeBps * s) / BPS);

      uint term1 = ((((A * A + B * B) / resA) * B) / resB) * A; // ordering to ensure it's within uint256 size
      uint term2 = resA * resA + resB * resB;

      if (term1 > term2) {
        // too large
        upper = s - 1;
      } else if (term1 < term2) {
        // too small
        lower = s + 1;
      } else {
        return s;
      }
    }
    return lower;
  }

  /// @notice A -> B
  ///         for consistency, all inputs MUST have decimals 18
  ///         method: Newton's
  /// @dev Get optimal swap amount using Newton's iterative method
  /// @param resA Reserve A amount
  /// @param resB Reserve B amount
  /// @param amtA Supply A amount
  /// @param amtB Supply B amount
  /// @param feeBps Swap fee in bps
  /// @return Swap amount for tokenA (assuming swap direction is A -> B)
  function getOptimalSwapAmountNewton(
    uint resA,
    uint resB,
    uint amtA,
    uint amtB,
    uint feeBps
  ) external pure returns (uint) {
    require(amtA * resB > amtB * resA, '!swap direction');
    uint s = resA / 2; // initial guess

    uint A;
    uint B;
    uint dA = BPS - feeBps; // in BPS
    uint dB; // in 1e18
    uint f1;
    uint f2;
    uint df;
    for (uint i = 0; i < 256; i++) {
      A = resA + ((BPS - feeBps) * s) / BPS;
      B = (A * (resB + amtB)) / (amtA + resA - (feeBps * s) / BPS);
      f1 = A * A + B * B;
      f2 = resB * resB + resA * resA;
      f2 = (((f2 / A) * resB) / B) * resA;
      dB = ((((BPS - feeBps) * amtA) / BPS + resA) * (amtB + resB));
      dB = dB / (amtA + resA - (feeBps * s) / BPS);
      dB = (dB * 1e18) / (amtA + resA - (feeBps * s) / BPS);
      df = (3 * A * dA) / BPS + (((A * dB) / B) * A) / 1e18;
      df = df + (((B * dA) / A) * B) / BPS + (3 * B * dB) / 1e18;
      uint newS;
      if (f1 > f2) {
        newS = (f1 - f2) / df > s ? 0 : s - (f1 - f2) / df;
      } else {
        newS = s + (f2 - f1) / df;
      }
      if (s > newS) {
        if (s - newS <= 1) return newS;
      } else {
        if (newS - s <= 1) return newS;
      }
      s = newS;
    }

    return s;
  }
}
