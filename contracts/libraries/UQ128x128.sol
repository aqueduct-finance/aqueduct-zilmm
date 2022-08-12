pragma solidity >=0.5.16;

// a library for handling binary fixed point numbers (https://en.wikipedia.org/wiki/Q_(number_format))

// range: [0, 2**128 - 1]
// resolution: 1 / 2**128

library UQ128x128 {

    uint256 constant Q128 = 2**128;

    // decode a UQ128x128 to a uint128
    function decode(uint256 z) internal pure returns (uint256 y) {
        y = z / Q128;
    }

    // encode a uint128 as a UQ128x128
    function encode(uint128 y) internal pure returns (uint256 z) {
        z = uint256(y) * Q128; // never overflows
    }

    // divide a UQ128x128 by a uint128, returning a UQ128x128
    function uqdiv(uint256 x, uint128 y) internal pure returns (uint256 z) {
        z = x / uint256(y);
    }
}