// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface Vm {
    function deal(address account, uint256 newBalance) external;
    function prank(address sender) external;
    function startPrank(address sender) external;
    function stopPrank() external;
    function expectRevert() external;
    function warp(uint256 timestamp) external;
}

abstract contract TestBase {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    function assertEq(uint256 actual, uint256 expected) internal pure { require(actual == expected, "assertEq uint failed"); }
    function assertEq(address actual, address expected) internal pure { require(actual == expected, "assertEq address failed"); }
    function assertTrue(bool condition) internal pure { require(condition, "assertTrue failed"); }
}
