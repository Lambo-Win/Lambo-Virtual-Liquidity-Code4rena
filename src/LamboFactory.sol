// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {LamboToken} from "./LamboToken.sol";
import {VirtualToken} from "./VirtualToken.sol";
import {LaunchPadUtils} from "./Utils/LaunchPadUtils.sol";
import {IPool} from "./interfaces/Uniswap/IPool.sol";
import {IPoolFactory} from "./interfaces/Uniswap/IPoolFactory.sol";
import {UniswapV2Library} from "./libraries/UniswapV2Library.sol";
import {LamboVEthRouter} from "./LamboVEthRouter.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract LamboFactory is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public immutable lamboTokenImplementation;
    mapping(address => bool) public whiteList;

    event TokenDeployed(address quoteToken);
    event PoolCreated(address virtualLiquidityToken, address quoteToken, address pool, uint256 virtualLiquidityAmount);
    event LiquidityAdded(address virtualLiquidityToken, address quoteToken, uint256 amountVirtualDesired, uint256 amountQuoteOptimal);
    event VTokenWhiteListAdded(address virtualLiquidityToken);
    event VTokenWhiteListRemoved(address virtualLiquidityToken);

    constructor(address _lamboTokenImplementation) Ownable(msg.sender) {
        require(_lamboTokenImplementation != address(0), "Invalid token implementation address");
        lamboTokenImplementation = _lamboTokenImplementation;
    }

    modifier onlyWhiteListed(address virtualLiquidityToken) {
        require(whiteList[virtualLiquidityToken], "virtualLiquidityToken is not in the whitelist");
        _;
    }

    function addVTokenWhiteList(address virtualLiquidityToken) public onlyOwner {
        whiteList[virtualLiquidityToken] = true;
        emit VTokenWhiteListAdded(virtualLiquidityToken);
    }

    function removeVTokenWhiteList(address virtualLiquidityToken) public onlyOwner {
        whiteList[virtualLiquidityToken] = false;
        emit VTokenWhiteListRemoved(virtualLiquidityToken);
    }

    function _deployLamboToken(string memory name, string memory tickname, bytes32 salt) internal returns (address quoteToken) {
        // Create a deterministic clone of the LamboToken implementation
        quoteToken = Clones.cloneDeterministic(lamboTokenImplementation, salt);

        // Initialize the cloned LamboToken
        LamboToken(quoteToken).initialize(name, tickname);

        emit TokenDeployed(quoteToken);
    }

    function createLaunchPad(
        string memory name,
        string memory tickname,
        bytes32 salt,
        uint256 virtualLiquidityAmount,
        address virtualLiquidityToken
    ) public onlyWhiteListed(virtualLiquidityToken) nonReentrant returns (address quoteToken, address pool) {
        quoteToken = _deployLamboToken(name, tickname, salt);
        pool = IPoolFactory(LaunchPadUtils.UNISWAP_POOL_FACTORY_).createPair(virtualLiquidityToken, quoteToken);

        VirtualToken(virtualLiquidityToken).takeLoan(pool, virtualLiquidityAmount);
        IERC20(quoteToken).safeTransfer(pool, LaunchPadUtils.TOTAL_AMOUNT_OF_QUOTE_TOKEN);

        // Directly minting to address(0) will cause Dexscreener to not display LP being burned
        // So, we have to mint to address(this), then send it to address(0).        
        IPool(pool).mint(address(this));
        IERC20(pool).safeTransfer(address(0), IERC20(pool).balanceOf(address(this)));

        emit PoolCreated(virtualLiquidityToken, quoteToken, pool, virtualLiquidityAmount);
    }

}
