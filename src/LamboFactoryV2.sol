// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {LamboToken} from "./LamboToken.sol";
import {VirtualToken} from "./VirtualToken.sol";
import {LaunchPadUtils} from "./Utils/LaunchPadUtils.sol";
import {IPool} from "./interfaces/Uniswap/IPool.sol";
import {IPoolFactory} from "./interfaces/Uniswap/IPoolFactory.sol";
import {UniswapV2Library} from "./libraries/UniswapV2Library.sol";
import {LamboVEthRouter} from "./LamboVEthRouter.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract LamboFactoryV2 is Ownable {
    address public immutable lamboTokenImplementation;
    address public lamboRouter;
    mapping(address => bool) public whiteList;

    event TokenDeployed(address quoteToken);
    event PoolCreated(address virtualLiquidityToken, address quoteToken, address pool, uint256 virtualLiquidityAmount);
    event LiquidityAdded(address virtualLiquidityToken, address quoteToken, uint256 amountVirtualDesired, uint256 amountQuoteOptimal);

    constructor(address _lamboTokenImplementation) Ownable(msg.sender) {
        lamboTokenImplementation = _lamboTokenImplementation;
    }

    modifier onlyWhiteListed(address virtualLiquidityToken) {
        require(whiteList[virtualLiquidityToken], "virtualLiquidityToken is not in the whitelist");
        _;
    }

    function setLamboRouter(address _lamboRouter) public onlyOwner {
        lamboRouter = _lamboRouter;
    }

    function addVTokenWhiteList(address virtualLiquidityToken) public onlyOwner {
        whiteList[virtualLiquidityToken] = true;
    }

    function removeVTokenWhiteList(address virtualLiquidityToken) public onlyOwner {
        whiteList[virtualLiquidityToken] = false;
    }

    function _deployLamboToken(string memory name, string memory tickname) internal returns (address quoteToken) {
        // Create a clone of the LamboToken implementation
        quoteToken = Clones.clone(lamboTokenImplementation);

        // Initialize the cloned LamboToken
        LamboToken(quoteToken).initialize(name, tickname);

        emit TokenDeployed(quoteToken);
    }

    function createLaunchPad(
        string memory name,
        string memory tickname,
        uint256 virtualLiquidityAmount,
        address virtualLiquidityToken
    ) public onlyWhiteListed(virtualLiquidityToken) returns (address quoteToken, address pool) {
        quoteToken = _deployLamboToken(name, tickname);
        pool = IPoolFactory(LaunchPadUtils.UNISWAP_POOL_FACTORY_).createPair(virtualLiquidityToken, quoteToken);

        VirtualToken(virtualLiquidityToken).takeLoan(pool, virtualLiquidityAmount);
        IERC20(quoteToken).transfer(pool, LaunchPadUtils.TOTAL_AMOUNT_OF_QUOTE_TOKEN);

        IPool(pool).mint(address(0x0));

        emit PoolCreated(virtualLiquidityToken, quoteToken, pool, virtualLiquidityAmount);
    }

    function addVirtualLiquidity(
        address virtualLiquidityToken,
        address quoteToken,
        uint256 amountVirtualDesired,
        uint256 amountQuoteMin
    ) public onlyWhiteListed(virtualLiquidityToken) returns (uint256 amountQuoteOptimal) {
        address pool = UniswapV2Library.pairFor(LaunchPadUtils.UNISWAP_POOL_FACTORY_, virtualLiquidityToken, quoteToken);
        (uint256 reserveA, uint256 reserveB) = UniswapV2Library.getReserves(LaunchPadUtils.UNISWAP_POOL_FACTORY_, virtualLiquidityToken, quoteToken);

        amountQuoteOptimal = UniswapV2Library.quote(amountVirtualDesired, reserveA, reserveB);
        require(amountQuoteOptimal >= amountQuoteMin, "LamboFactory addVirtualLiquidity: INSUFFICIENT_Quote_AMOUNT");

        VirtualToken(virtualLiquidityToken).takeLoan(pool, amountVirtualDesired);
        IERC20(quoteToken).transferFrom(msg.sender, pool, amountQuoteOptimal);

        IPool(pool).mint(address(0x0));

        emit LiquidityAdded(virtualLiquidityToken, quoteToken, amountVirtualDesired, amountQuoteOptimal);
    }


    
}