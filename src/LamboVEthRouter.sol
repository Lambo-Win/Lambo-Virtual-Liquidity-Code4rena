// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import './libraries/UniswapV2Library.sol';
import {LaunchPadUtils} from "./Utils/LaunchPadUtils.sol";

import {IPool} from "./interfaces/Uniswap/IPool.sol";
import {VirtualToken} from "./VirtualToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {LamboFactory} from "./LamboFactory.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract LamboVEthRouter is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public constant NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    uint256 public constant feeDenominator = 10000;

    uint256 public feeRate;
    address public immutable vETH;

    event BuyQuote(address quoteToken, uint256 amountXIn, uint256 amountXOut);
    event SellQuote(address quoteToken, uint256 amountYIn, uint256 amountXOut);
    event UpdateFeeRate(uint256 newFeeRate);

    constructor(address _vETH, address _multiSign) Ownable(_multiSign) public {
        require(_vETH != address(0), "Invalid vETH address");

        feeRate = 100;
        vETH = _vETH;
    }

    function updateFeeRate(uint256 newFeeRate) external onlyOwner {
        require(newFeeRate <= feeDenominator, "Fee rate must be less than or equal to feeDenominator");
        feeRate = newFeeRate;
        emit UpdateFeeRate(newFeeRate);
    }

    function createLaunchPadAndInitialBuy(
        address lamboFactory,
        string memory name, 
        string memory tickname,
        uint256 virtualLiquidityAmount,
        uint256 buyAmount,
        bytes32 salt
    ) 
        public 
        payable 
        nonReentrant
        returns (address quoteToken, address pool, uint256 amountYOut) 
    {
        require(VirtualToken(vETH).isValidFactory(lamboFactory), "only Validfactory");
        (quoteToken, pool) = LamboFactory(lamboFactory).createLaunchPad(
            name, 
            tickname, 
            salt,
            virtualLiquidityAmount, 
            address(vETH)
        );

        amountYOut = _buyQuote(quoteToken, buyAmount, 0);
    }

    function getBuyQuote(
        address targetToken,
        uint256 amountIn
    ) 
        public 
        view 
        returns (uint256 amount) 
    {

        // TIPs: ETH -> vETH = 1:1
        (uint256 reserveIn, uint256 reserveOut) = UniswapV2Library.getReserves(LaunchPadUtils.UNISWAP_POOL_FACTORY_, vETH, targetToken);

        // Calculate the amount of Meme to be received
        amountIn = amountIn - amountIn * feeRate / feeDenominator;
        amount = UniswapV2Library.getAmountOut(amountIn, reserveIn, reserveOut);
    }

    function getSellQuote(
        address targetToken,
        uint256 amountIn
    ) 
        public 
        view 
        returns (uint256 amount) 
    {
        // TIPS: vETH -> ETH = 1: 1 - fee
        (uint256 reserveIn, uint256 reserveOut) = UniswapV2Library.getReserves(LaunchPadUtils.UNISWAP_POOL_FACTORY_, targetToken, vETH);

        // get vETH Amount
        amount = UniswapV2Library.getAmountOut(amountIn, reserveIn, reserveOut);
        amount = amount - amount * feeRate / feeDenominator;
    }

    function buyQuote(
        address quoteToken,
        uint256 amountXIn,
        uint256 minReturn
    ) 
        public 
        payable 
        nonReentrant
        returns (uint256 amountYOut) 
    {
        amountYOut = _buyQuote(quoteToken, amountXIn, minReturn);
    }

    function sellQuote(
        address quoteToken,
        uint256 amountYIn,
        uint256 minReturn
    ) 
        public 
        nonReentrant
        returns (uint256 amountXOut) 
    {
        amountXOut = _sellQuote(quoteToken, amountYIn, minReturn);
    }



    //  ====================  internal ====================
    function _sellQuote(
        address quoteToken,
        uint256 amountYIn,
        uint256 minReturn
    )   internal          
        returns (uint256 amountXOut) {

        IERC20(quoteToken).safeTransferFrom(msg.sender, address(this), amountYIn);

        address pair = UniswapV2Library.pairFor(LaunchPadUtils.UNISWAP_POOL_FACTORY_, quoteToken, vETH);
        (uint256 reserveIn, uint256 reserveOut) = UniswapV2Library.getReserves(
            LaunchPadUtils.UNISWAP_POOL_FACTORY_, 
            quoteToken, 
            vETH
        );

        // Calculate the amount of vETH to be received
        amountXOut = UniswapV2Library.getAmountOut(amountYIn, reserveIn, reserveOut);

        // Transfer quoteToken to the pair
        IERC20(quoteToken).safeTransfer(pair, amountYIn);

        // Perform the swap
        (uint256 amount0Out, uint256 amount1Out) = quoteToken < vETH 
            ? (uint256(0), amountXOut) 
            : (amountXOut, uint256(0));
        IUniswapV2Pair(pair).swap(amount0Out, amount1Out, address(this), new bytes(0));

        // Convert vETH to ETH and send to the user
        VirtualToken(vETH).cashOut(amountXOut);

        // caculate fee
        uint256 fee = amountXOut * feeRate / feeDenominator;
        amountXOut = amountXOut - fee;
        require(amountXOut >= minReturn, "Insufficient output amount. MinReturn Error.");

        // handle amountOut
        (bool success, ) = msg.sender.call{value: amountXOut}("");
        require(success, "Transfer to User failed");
   
        // handle fee
        (success, ) = payable(owner()).call{value: fee}("");
        require(success, "Transfer to owner() failed");

        // Emit the swap event
        emit SellQuote(quoteToken, amountYIn, amountXOut);
    }
    

    function _buyQuote(
        address quoteToken,
        uint256 amountXIn,
        uint256 minReturn
    ) 
        internal 
        returns (uint256 amountYOut) 
    {
        require(msg.value >= amountXIn, "Insufficient msg.value");

        // handle fee
        uint256 fee = amountXIn * feeRate / feeDenominator;
        amountXIn = amountXIn - fee;
        (bool success, ) = payable(owner()).call{value: fee}("");
        require(success, "Transfer to Owner failed");
        
        // handle swap
        address pair = UniswapV2Library.pairFor(LaunchPadUtils.UNISWAP_POOL_FACTORY_, vETH, quoteToken);

        (uint256 reserveIn, uint256 reserveOut) = UniswapV2Library.getReserves(
            LaunchPadUtils.UNISWAP_POOL_FACTORY_, 
            vETH, 
            quoteToken
        );

        // Calculate the amount of quoteToken to be received
        amountYOut = UniswapV2Library.getAmountOut(amountXIn, reserveIn, reserveOut);
        require(amountYOut >= minReturn, "Insufficient output amount");

        // Transfer vETH to the pair
        VirtualToken(vETH).cashIn{value: amountXIn}(amountXIn);
        IERC20(vETH).safeTransfer(pair, amountXIn);

        // Perform the swap
        (uint256 amount0Out, uint256 amount1Out) = vETH < quoteToken 
            ? (uint256(0), amountYOut) 
            : (amountYOut, uint256(0));
        IUniswapV2Pair(pair).swap(amount0Out, amount1Out, msg.sender, new bytes(0));

        if (msg.value > (amountXIn + fee + 1)) {
            (bool success, ) = payable(msg.sender).call{value: msg.value - amountXIn - fee - 1}("");
            require(success, "ETH transfer failed");
        }
        
        emit BuyQuote(quoteToken, amountXIn, amountYOut);
    }

    receive() external payable {}
}
