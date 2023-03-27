// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

uint256 constant RAD = 10 ** 45;
uint256 constant RAY = 10 ** 27;
uint256 constant WAD = 10 ** 18;
uint256 constant HUNDRED = 100;
uint256 constant FIFTY = 50;

library Math {
  function add(uint256 x, int256 y) internal pure returns (uint256 z) {
    if (y >= 0) {
      z = x + uint256(y);
    } else {
      z = x - uint256(-y);
    }
  }

  function sub(uint256 x, int256 y) internal pure returns (uint256 z) {
    if (y >= 0) {
      z = x - uint256(y);
    } else {
      z = x + uint256(-y);
    }
  }

  function sub(uint256 x, uint256 y) internal pure returns (int256 z) {
    z = int256(x) - int256(y);
    require(int256(x) >= 0 && int256(y) >= 0, 'Math/sub-uint-uint-invalid-numbers');
  }

  function mul(uint256 x, int256 y) internal pure returns (int256 z) {
    z = int256(x) * y;
    require(int256(x) >= 0, 'Math/mul-uint-int-invalid-x');
  }

  function rmul(uint256 x, uint256 y) internal pure returns (uint256 z) {
    z = (x * y) / RAY;
  }

  function wmul(uint256 x, uint256 y) internal pure returns (uint256 z) {
    z = (x * y) / WAD;
  }

  function rdiv(uint256 x, uint256 y) internal pure returns (uint256 z) {
    z = (x * RAY) / y;
  }

  function wdiv(uint256 x, uint256 y) internal pure returns (uint256 z) {
    z = (x * WAD) / y;
  }

  function rpow(uint256 x, uint256 n) internal pure returns (uint256 z) {
    assembly {
      switch x
      case 0 {
        switch n
        case 0 { z := RAY }
        default { z := 0 }
      }
      default {
        switch mod(n, 2)
        case 0 { z := RAY }
        default { z := x }
        let half := div(RAY, 2) // for rounding.
        for { n := div(n, 2) } n { n := div(n, 2) } {
          let xx := mul(x, x)
          if iszero(eq(div(xx, x), x)) { revert(0, 0) }
          let xxRound := add(xx, half)
          if lt(xxRound, xx) { revert(0, 0) }
          x := div(xxRound, RAY)
          if mod(n, 2) {
            let zx := mul(z, x)
            if and(iszero(iszero(x)), iszero(eq(div(zx, x), z))) { revert(0, 0) }
            let zxRound := add(zx, half)
            if lt(zxRound, zx) { revert(0, 0) }
            z := div(zxRound, RAY)
          }
        }
      }
    }
  }

  function max(uint256 x, uint256 y) internal pure returns (uint256 z) {
    z = (x >= y) ? x : y;
  }

  function min(uint256 x, uint256 y) internal pure returns (uint256 z) {
    z = (x <= y) ? x : y;
  }
}
