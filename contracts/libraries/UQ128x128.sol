// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// a library for handling binary fixed point numbers (https://en.wikipedia.org/wiki/Q_(number_format))

// range: [0, 2**128 - 1]
// resolution: 1 / 2**128

library UQ128x128 {
    uint256 public constant Q128 = 2**128;

    // decode a UQ128x128 to a uint128
    function decode(uint256 z) internal pure returns (uint256 y) {
        y = z / Q128;
    }

    // halfway decode a UQ128x128 by dividing by 2^64
    // used to prevent overflow in certain circumstances
    function halfDecode(uint256 z) internal pure returns (uint256 y) {
        y = z / 2**64;
    }

    // encode a uint128 as a UQ128x128
    function encode(uint128 y) internal pure returns (uint256 z) {
        z = uint256(y) * Q128; // never overflows
    }

    // divide a UQ128x128 by a uint128, returning a UQ128x128
    function uqdiv(uint256 x, uint128 y) internal pure returns (uint256 z) {
        if (y > 0) {
            z = x / uint256(y);
        } else {
            z = 0;
        }
    }
}
