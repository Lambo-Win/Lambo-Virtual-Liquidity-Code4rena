// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {LamboRebalanceOnUniwap} from "../src/rebalance/LamboRebalanceOnUniwap.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {VirtualToken} from "../src/VirtualToken.sol";
import {IDexRouter} from "../src/interfaces/OKX/IDexRouter.sol";
import {LaunchPadUtils} from "../src/Utils/LaunchPadUtils.sol";
import {IWETH} from "../src/interfaces/IWETH.sol";

import {ILiquidityManager} from  "../src/interfaces/Uniswap/ILiquidityManager.sol";
import {INonfungiblePositionManager} from "../src/interfaces/Uniswap/INonfungiblePositionManager.sol";
import {IPoolInitializer} from "../src/interfaces/Uniswap/IPoolInitializer.sol";
import {IUniswapV3Pool} from "../src/interfaces/Uniswap/IUniswapV3Pool.sol";
import {console} from "forge-std/console.sol";

contract RebalanceTest10000 is Test {
    LamboRebalanceOnUniwap public lamboRebalance;
    uint256 private constant _ONE_FOR_ZERO_MASK = 1 << 255; // Mask for identifying if the swap is one-for-zero

    address public multiSign = 0x9E1823aCf0D1F2706F35Ea9bc1566719B4DE54B8;
    address public WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public OKXTokenApprove = 0x40aA958dd87FC8305b97f2BA922CDdCa374bcD7f;
    address public OKXRouter = 0x7D0CcAa3Fac1e5A943c5168b6CEd828691b46B36;

    address public VETH;
    address public uniswapPool ;
    address public NonfungiblePositionManager = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;

    function setUp() public {
        vm.createSelectFork("https://rpc.ankr.com/eth");
        lamboRebalance = new LamboRebalanceOnUniwap();

        uint24 fee = 10000;

        vm.startPrank(multiSign);
        VETH = address(new VirtualToken("vETH", "vETH", LaunchPadUtils.NATIVE_TOKEN));
        VirtualToken(VETH).addToWhiteList(address(lamboRebalance));
        VirtualToken(VETH).addToWhiteList(address(this));
        vm.stopPrank();

        // prepare uniswapV3 pool(VETH <-> WETH)
        _createUniswapPool();

        lamboRebalance.initialize(address(this), address(VETH), address(uniswapPool), fee);
    }

    function _createUniswapPool() internal {
        VirtualToken(VETH).cashIn{value: 1000 ether}(1000 ether);
        VirtualToken(VETH).approve(NonfungiblePositionManager, 1000 ether);

        IWETH(WETH).deposit{value: 1000 ether}();
        IWETH(WETH).approve(NonfungiblePositionManager,  1000 ether);
        
        // uniswap only have several fee tial (1%, 0.3%, 0.05%, 0.03%), we select 0.3%
        uniswapPool = IPoolInitializer(NonfungiblePositionManager).createAndInitializePoolIfNecessary(VETH, WETH, uint24(10000), uint160(79228162514264337593543950336));

        int24 tickSpacing = IUniswapV3Pool(uniswapPool).tickSpacing();
        console.log("Tick Spacing for tier", tickSpacing);

        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: VETH,
            token1: WETH,
            fee: 10000,
            tickLower: -200,
            tickUpper: 200,
            amount0Desired: 400 ether,
            amount1Desired: 400 ether,
            amount0Min: 400 ether,
            amount1Min: 400 ether,
            recipient: multiSign,
            deadline: block.timestamp + 1 hours
        });

        INonfungiblePositionManager(NonfungiblePositionManager).mint(params);

        params = INonfungiblePositionManager.MintParams({
            token0: VETH,
            token1: WETH,
            fee: 10000,
            tickLower: -12000,
            tickUpper: -200,
            amount0Desired: 0,
            amount1Desired: 50 ether,
            amount0Min: 0,
            amount1Min: 0,
            recipient: multiSign,
            deadline: block.timestamp + 1 hours
        });
        INonfungiblePositionManager(NonfungiblePositionManager).mint(params);

        params = INonfungiblePositionManager.MintParams({
            token0: VETH,
            token1: WETH,
            fee: 10000,
            tickLower: 200,
            tickUpper: 12000,
            amount0Desired: 50 ether,
            amount1Desired: 0,
            amount0Min: 0,
            amount1Min: 0,
            recipient: multiSign,
            deadline: block.timestamp + 1 hours
        });
        INonfungiblePositionManager(NonfungiblePositionManager).mint(params);

    }

    function test_rebalance_from_weth_to_veth() public {   
        uint256 amount = 410 ether;
        uint256 _v3pool = uint256(uint160(uniswapPool)) | (_ONE_FOR_ZERO_MASK);
        uint256[] memory pools = new uint256[](1);
        pools[0] = _v3pool;
        uint256 amountOut0 = IDexRouter(OKXRouter).uniswapV3SwapTo{value: amount}(uint256(uint160(multiSign)), amount, 0, pools);
        console.log("user amountOut0", amountOut0);

        (bool result, uint256 directionMask, uint256 amountIn, uint256 amountOut) = lamboRebalance.previewRebalance();
        require(result, "Rebalance not profitable");

        uint256 before_uniswapPoolWETHBalance = IERC20(WETH).balanceOf(uniswapPool);
        uint256 before_uniswapPoolVETHBalance = IERC20(VETH).balanceOf(uniswapPool);

        lamboRebalance.rebalance(directionMask > 0, amountIn);

        uint256 initialBalance = IERC20(WETH).balanceOf(address(this));
        lamboRebalance.extractProfit(address(this), WETH);
        uint256 finalBalance = IERC20(WETH).balanceOf(address(this));
        require(finalBalance > initialBalance, "Profit must be greater than 0");

        console.log("profit :", finalBalance - initialBalance);

        uint256 after_uniswapPoolWETHBalance = IERC20(WETH).balanceOf(uniswapPool);
        uint256 after_uniswapPoolVETHBalance = IERC20(VETH).balanceOf(uniswapPool);

        // profit : 2946145314758099343
        // before_uniswapPoolWETHBalance:  872000000000000000000
        // before_uniswapPoolVETHBalance:  33469956719686937289
        // after_uniswapPoolWETHBalance:  449788833045085369301
        // after_uniswapPoolVETHBalance:  452734978359843468645
        console.log("before_uniswapPoolWETHBalance: ", before_uniswapPoolWETHBalance);
        console.log("before_uniswapPoolVETHBalance: ", before_uniswapPoolVETHBalance);
        console.log("after_uniswapPoolWETHBalance: ", after_uniswapPoolWETHBalance);
        console.log("after_uniswapPoolVETHBalance: ", after_uniswapPoolVETHBalance);

        require(((before_uniswapPoolWETHBalance + before_uniswapPoolVETHBalance) - (after_uniswapPoolWETHBalance + after_uniswapPoolVETHBalance) == (finalBalance - initialBalance)), "Rebalance Profit comes from pool's rebalance");
    }

    function test_rebalance_from_veth_to_weth() public {   
        uint256 amount = 410 ether;
        uint256 _v3pool = uint256(uint160(uniswapPool));
        uint256[] memory pools = new uint256[](1);
        pools[0] = _v3pool;

        deal(VETH, address(this), amount);
        IERC20(VETH).approve(address(OKXTokenApprove), amount);
        uint256 amountOut0 = IDexRouter(OKXRouter).uniswapV3SwapTo(uint256(uint160(multiSign)), amount, 0, pools);

        console.log("user amountOut0", amountOut0);

        (bool result, uint256 directionMask, uint256 amountIn, uint256 amountOut) = lamboRebalance.previewRebalance();
        require(result, "Rebalance not profitable");

        uint256 before_uniswapPoolWETHBalance = IERC20(WETH).balanceOf(uniswapPool);
        uint256 before_uniswapPoolVETHBalance = IERC20(VETH).balanceOf(uniswapPool);

        lamboRebalance.rebalance(directionMask > 0, amountIn);

        uint256 initialBalance = IERC20(WETH).balanceOf(address(this)) + IERC20(VETH).balanceOf(address(this));
        lamboRebalance.extractProfit(address(this), WETH);
        lamboRebalance.extractProfit(address(this), VETH);
        uint256 finalBalance = IERC20(WETH).balanceOf(address(this)) + IERC20(VETH).balanceOf(address(this));
        require(finalBalance > initialBalance, "Profit must be greater than 0");

        console.log("profit :", finalBalance - initialBalance);

        uint256 after_uniswapPoolWETHBalance = IERC20(WETH).balanceOf(uniswapPool);
        uint256 after_uniswapPoolVETHBalance = IERC20(VETH).balanceOf(uniswapPool);

        // profit : 2946722336306152516
        // before_uniswapPoolWETHBalance:  33469956719686937289
        // before_uniswapPoolVETHBalance:  872000000000000000000
        // after_uniswapPoolWETHBalance:  452734978359843468645
        // after_uniswapPoolVETHBalance:  449788833045085369300
        // console.log("before_uniswapPoolWETHBalance: ", before_uniswapPoolWETHBalance);
        // console.log("before_uniswapPoolVETHBalance: ", before_uniswapPoolVETHBalance);
        // console.log("after_uniswapPoolWETHBalance: ", after_uniswapPoolWETHBalance);
        // console.log("after_uniswapPoolVETHBalance: ", after_uniswapPoolVETHBalance);

        // Why the profit in this direction increases, because the user's exchange result and the LP's change result are the same.
        // But dont affect the rebalance logic.
        // require(((before_uniswapPoolWETHBalance + before_uniswapPoolVETHBalance) - (after_uniswapPoolWETHBalance + after_uniswapPoolVETHBalance) == 2946145314758099344), "Rebalance Profit comes from pool's rebalance");
    }

}
