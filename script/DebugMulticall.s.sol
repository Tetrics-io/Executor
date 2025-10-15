// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/UniExecutor.sol";
import "../src/adapters/ethereum/LidoAdapter.sol";
import "../src/adapters/ethereum/WstETHAdapter.sol";
import "../src/adapters/ethereum/MorphoAdapter.sol";

contract DebugMulticall is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(pk);

        UniExecutor executor = UniExecutor(payable(0xc1471ca4a909e34C575aa93505f373a5a6a901B6));

        bytes[] memory calls = new bytes[](5);
        uint256[] memory values = new uint256[](5);

        calls[0] = abi.encodeWithSelector(
            executor.directCall.selector,
            address(0x5F38C01C30DeAeF2a64FdDF4129e2638048262b4),
            abi.encodeWithSelector(LidoAdapter.depositETH.selector, address(0))
        );
        values[0] = 1 ether;

        calls[1] = abi.encodeWithSelector(
            executor.approveToken.selector,
            0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84,
            0x77399Eefc2D56bc0d730C3407de347E8DCdF18BB,
            type(uint256).max
        );

        calls[2] = abi.encodeWithSelector(
            executor.directCall.selector,
            address(0x373CAC07Be6a672BA1E91d982f2f7959f1813f68),
            abi.encodeWithSelector(WstETHAdapter.wrapStETH.selector, 0, address(0))
        );

        calls[3] = abi.encodeWithSelector(
            executor.approveToken.selector,
            0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0,
            address(0x47a8c22a20D2E759EedB9EF27CA127c868756f73),
            type(uint256).max
        );

        calls[4] = abi.encodeWithSelector(
            executor.directCall.selector,
            address(0x47a8c22a20D2E759EedB9EF27CA127c868756f73),
            abi.encodeWithSelector(MorphoAdapter.supplyAndBorrow.selector, 0, 200e6, vm.addr(pk))
        );

        executor.multicallWithValue{value: 1 ether}(calls, values);

        vm.stopBroadcast();
    }
}
