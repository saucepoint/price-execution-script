// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console2} from "forge-std/Test.sol";

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {Constants} from "@uniswap/v4-core/test/utils/Constants.sol";
import {PositionInfoLibrary} from "@uniswap/v4-periphery/src/libraries/PositionInfoLibrary.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {PathKey} from "hookmate/interfaces/router/IUniswapV4Router04.sol";

import {EasyPosm} from "./utils/libraries/EasyPosm.sol";
import {Deployers} from "./utils/Deployers.sol";

import {Counter} from "../src/Counter.sol";

interface IPoolKeyRegistry {
    function poolKeys(bytes25) external view returns (PoolKey memory);
}

contract EulerSwapStableStableTest is Test, Deployers {
    using EasyPosm for IPositionManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    Currency currency0;
    Currency currency1;

    // USDCUSDT 0.01 bips
    PoolId poolId1 = PoolId.wrap(bytes32(0x77ea9d2be50eb3e82b62db928a1bcc573064dd2a14f5026847e755518c8659c9));

    PoolKey poolKey0 = PoolKey({
        currency0: Currency.wrap(address(0x078D782b760474a361dDA0AF3839290b0EF57AD6)),
        currency1: Currency.wrap(address(0x9151434b16b9763660705744891fA906F660EcC5)),
        fee: 10,
        tickSpacing: 1,
        hooks: IHooks(address(0x96C68a406187f8C86DEA6b3c6150ad5A176128A8))
    });
    PoolKey poolKey1;

    function setUp() public {
        vm.createSelectFork("unichain");
        assertEq(block.chainid, 130, "Must be on Unichain");
        deployArtifacts();

        poolKey1 = _getPoolKeyFromId(poolId1);
        assertEq(Currency.unwrap(poolKey1.currency0), address(0x078D782b760474a361dDA0AF3839290b0EF57AD6));
        assertEq(Currency.unwrap(poolKey1.currency1), address(0x9151434b16b9763660705744891fA906F660EcC5));
        assertEq(address(poolKey1.hooks), address(0));

        currency0 = poolKey0.currency0;
        currency1 = poolKey0.currency1;
        // deal(Currency.unwrap(currency0), address(poolManager), 10_000_000e6);
        // deal(Currency.unwrap(currency1), address(poolManager), 10_000e18);
        deal(Currency.unwrap(currency0), address(this), 10_000_000e6);
        deal(Currency.unwrap(currency1), address(this), 10_000_000e6);
        IERC20(Currency.unwrap(currency0)).approve(address(swapRouter), type(uint256).max);
        IERC20(Currency.unwrap(currency1)).approve(address(swapRouter), type(uint256).max);
    }

    /// @dev unsafe and hacky, fuggem
    function _getPoolKeyFromId(PoolId poolId) internal view returns (PoolKey memory) {
        bytes25 _poolId = bytes25(bytes32(PositionInfoLibrary.MASK_UPPER_200_BITS & uint256(PoolId.unwrap(poolId))));
        return IPoolKeyRegistry(address(positionManager)).poolKeys(_poolId);
    }

    function test_zeroForOne() public {
        uint256 amountIn = 1_000_000e6;
        bool zeroForOne = true;

        BalanceDelta swapDelta0 = swapRouter.swapExactTokensForTokens({
            amountIn: amountIn,
            amountOutMin: 0, // Very bad, but we want to allow for unlimited price impact
            zeroForOne: zeroForOne,
            poolKey: poolKey0,
            hookData: Constants.ZERO_BYTES,
            receiver: address(this),
            deadline: block.timestamp + 1
        });

        BalanceDelta swapDelta1 = swapRouter.swapExactTokensForTokens({
            amountIn: amountIn,
            amountOutMin: 0, // Very bad, but we want to allow for unlimited price impact
            zeroForOne: !zeroForOne,
            poolKey: poolKey1,
            hookData: Constants.ZERO_BYTES,
            receiver: address(this),
            deadline: block.timestamp + 1
        });

        console2.log("Swap 0: ", uint256(int256(swapDelta0.amount1())));
        console2.log("Swap 1: ", uint256(int256(swapDelta1.amount0())));

        swapDelta0.amount1() < swapDelta1.amount0()
            ? console2.log("Pool 1 produced more output tokens for zeroForOne swaps")
            : console2.log("Pool 0 produced more output tokens for zeroForOne swaps");
    }

    function test_oneForZero() public {
        uint256 amountIn = 1_000_000e6;
        bool zeroForOne = false;

        BalanceDelta swapDelta0 = swapRouter.swapExactTokensForTokens({
            amountIn: amountIn,
            amountOutMin: 0, // Very bad, but we want to allow for unlimited price impact
            zeroForOne: zeroForOne,
            poolKey: poolKey0,
            hookData: Constants.ZERO_BYTES,
            receiver: address(this),
            deadline: block.timestamp + 1
        });

        BalanceDelta swapDelta1 = swapRouter.swapExactTokensForTokens{value: amountIn}({
            amountIn: amountIn,
            amountOutMin: 0, // Very bad, but we want to allow for unlimited price impact
            zeroForOne: !zeroForOne,
            poolKey: poolKey1,
            hookData: Constants.ZERO_BYTES,
            receiver: address(this),
            deadline: block.timestamp + 1
        });

        console2.log("Swap 0: ", uint256(int256(swapDelta0.amount0())));
        console2.log("Swap 1: ", uint256(int256(swapDelta1.amount1())));

        swapDelta0.amount0() < swapDelta1.amount1()
            ? console2.log("Pool 1 produced more output tokens for oneForZero swaps")
            : console2.log("Pool 0 produced more output tokens for oneForZero swaps");
    }

    receive() external payable {}
}
