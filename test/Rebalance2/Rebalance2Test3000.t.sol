// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {IWETH} from "../../src/interfaces/IWETH.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {VirtualToken} from "../../src/VirtualToken.sol";
import {LaunchPadUtils} from "../../src/Utils/LaunchPadUtils.sol";
import {IDexRouter} from "../../src/interfaces/OKX/IDexRouter.sol";
import {IUniswapV3Pool} from "../../src/interfaces/Uniswap/IUniswapV3Pool.sol";

import {LamboRebalanceOnUniswap2} from "../../src/rebalance/LamboRebalanceOnUniswap2.sol";
import {ILiquidityManager} from  "../../src/interfaces/Uniswap/ILiquidityManager.sol";
import {INonfungiblePositionManager} from "../../src/interfaces/Uniswap/INonfungiblePositionManager.sol";
import {IPoolInitializer} from "../../src/interfaces/Uniswap/IPoolInitializer.sol";
import {console} from "forge-std/console.sol";

contract Rebalance2Test3000 is Test {
    address public VETH;
    address public uniswapPool ;
    LamboRebalanceOnUniswap2 public lamboRebalance;
    uint256 private constant _ONE_FOR_ZERO_MASK = 1 << 255; // Mask for identifying if the swap is one-for-zero

    address public WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public multiSign = 0x9E1823aCf0D1F2706F35Ea9bc1566719B4DE54B8;
    address public NonfungiblePositionManager = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    address public OKXRouter = 0x7D0CcAa3Fac1e5A943c5168b6CEd828691b46B36;
    address public OKXTokenApprove = 0x40aA958dd87FC8305b97f2BA922CDdCa374bcD7f;

    // price = 1, targetPrice = 1 * 2^96 = 2^96
    uint160 public constant targetPrice = 79228162514264337593543950336;

    function setUp() public {
        vm.createSelectFork("https://rpc.ankr.com/eth");

        uint24 fee = 3000;

        vm.startPrank(multiSign);
        VETH = address(new VirtualToken("vETH", "vETH", LaunchPadUtils.NATIVE_TOKEN));
        VirtualToken(VETH).addToWhiteList(address(this));
        vm.stopPrank();

        _createUniswapPool();

        lamboRebalance = new LamboRebalanceOnUniswap2(multiSign, address(this), address(VETH), address(uniswapPool));

        vm.startPrank(multiSign);
        VirtualToken(VETH).addToWhiteList(address(lamboRebalance));
        vm.stopPrank();
    }

    function _createUniswapPool() internal {
        VirtualToken(VETH).cashIn{value: 1000 ether}(1000 ether);
        VirtualToken(VETH).approve(NonfungiblePositionManager, 1000 ether);

        IWETH(WETH).deposit{value: 1000 ether}();
        IWETH(WETH).approve(NonfungiblePositionManager,  1000 ether);
        
        // uniswap only have several fee tial (1%, 0.3%, 0.05%, 0.03%), we select 0.3%
        uniswapPool = IPoolInitializer(NonfungiblePositionManager).createAndInitializePoolIfNecessary(VETH, WETH, uint24(3000), uint160(79228162514264337593543950336));

        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: VETH,
            token1: WETH,
            fee: 3000,
            tickLower: -120,
            tickUpper: 120,
            amount0Desired: 450 ether,
            amount1Desired: 450 ether,
            amount0Min: 450 ether,
            amount1Min: 450 ether,
            recipient: multiSign,
            deadline: block.timestamp + 1 hours
        });

        INonfungiblePositionManager(NonfungiblePositionManager).mint(params);
    }

    function test0() public {
        uint256 amount = 230 ether;
        uint256 _v3pool = uint256(uint160(uniswapPool)) | (_ONE_FOR_ZERO_MASK);
        uint256[] memory pools = new uint256[](1);
        pools[0] = _v3pool;
        uint256 amountOut0 = IDexRouter(OKXRouter).uniswapV3SwapTo{value: amount}(uint256(uint160(multiSign)), amount, 0, pools);
        (uint160 sqrtPriceX96, int24 tick, , , , , ) = IUniswapV3Pool(uniswapPool).slot0();
        console.log(sqrtPriceX96);
        // 1.0061056125537582

        lamboRebalance.rebalnce();

        (sqrtPriceX96, tick, , , , , ) = IUniswapV3Pool(uniswapPool).slot0();
        require(sqrtPriceX96 == targetPrice, "rebalance target error");

        console.log(IERC20(WETH).balanceOf(address(lamboRebalance)));
    }

    function test1() public {
        uint256 amount = 230 ether;
        uint256 _v3pool = uint256(uint160(uniswapPool));
        uint256[] memory pools = new uint256[](1);
        pools[0] = _v3pool;

        deal(VETH, address(this), amount);
        IERC20(VETH).approve(address(OKXTokenApprove), amount);
        uint256 amountOut0 = IDexRouter(OKXRouter).uniswapV3SwapTo(uint256(uint160(multiSign)), amount, 0, pools);
        (uint160 sqrtPriceX96, int24 tick, , , , , ) = IUniswapV3Pool(uniswapPool).slot0();
        console.log(sqrtPriceX96);
        // 0.9939314397240459

        lamboRebalance.rebalnce();

        (sqrtPriceX96,  tick, , , , , ) = IUniswapV3Pool(uniswapPool).slot0();
        require(sqrtPriceX96 == targetPrice, "rebalance target error");
        console.log(IERC20(WETH).balanceOf(address(lamboRebalance)));

    }
}