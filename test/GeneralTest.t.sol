import {BaseTest} from "./BaseTest.t.sol";
import {LaunchPadUtils} from "../src/Utils/LaunchPadUtils.sol";
import {IStableNGFactory} from "../src/interfaces/Curve/IStableNGFactory.sol";
import {IUniswapV2Router01} from "../src/interfaces/Uniswap/IUniswapV2Router01.sol";
import {IStableNGPool} from "../src/interfaces/Curve/IStableNGPool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregationRouterV6, IWETH} from "../src/libraries/1inchV6.sol";
import "forge-std/console2.sol";

contract GeneralTest is BaseTest {

    function setUp() public override {
        super.setUp();
    }

    function test_changeOwnerToMultisigner() public {
        address NewMultiSigAdmin = 0x9E1823aCf0D1F2706F35Ea9bc1566719B4DE54B8;
        vm.startPrank(multiSigAdmin);
        vETH.transferOwnership(NewMultiSigAdmin);
        vm.stopPrank();
    }

    function test_lamboFactoryChangeOwner() public {
        address NewMultiSigAdmin = 0x9E1823aCf0D1F2706F35Ea9bc1566719B4DE54B8;
        
        vm.startPrank(multiSigAdmin);
        factory.transferOwnership(NewMultiSigAdmin);
        vm.stopPrank();

        // check owner
        vm.startPrank(NewMultiSigAdmin);
        factory.removeVTokenWhiteList(address(vETH));
        factory.addVTokenWhiteList(address(vETH));
        bytes32 salt = bytes32(vm.randomUint());
        (address quoteToken, address pool) = factory.createLaunchPad("LamboToken", "LAMBO", salt, 10 ether, address(vETH));

        bytes32 salt1 = bytes32(vm.randomUint());
        (address quoteToken2, address pool2) = factory.createLaunchPad("LamboToken", "LAMBO", salt1, 10 ether, address(vETH));
 
        vm.stopPrank();
    }

    function test_createLaunchPad_exceeding_100ETH() public {
        vm.expectRevert("Loan limit per block exceeded");
        bytes32 salt = bytes32(vm.randomUint());
        factory.createLaunchPad("LamboToken", "LAMBO", salt, 300 ether + 1, address(vETH));

        vm.roll(block.number + 1);
        bytes32 salt1 = bytes32(vm.randomUint());

        factory.createLaunchPad("LamboToken", "LAMBO", salt1, 300 ether, address(vETH));
        
    }
    
    // vETH <-> Meme into Uniswap
    function test_createLaunchPad_with_virtual_token_and_buy_sell() public {
        bytes32 salt = bytes32(vm.randomUint());
        (address quoteToken, address pool) = factory.createLaunchPad("LamboToken", "LAMBO", salt, 10 ether, address(vETH));
        
        uint256 amountQuoteOut = lamboRouter.getBuyQuote(quoteToken, 10 ether);
        uint256 gasStart = gasleft();
        uint256 amountOut = lamboRouter.buyQuote{value: 10 ether}(quoteToken, 10 ether, 0);
        uint256 gasUsed = gasStart - gasleft();

        require(amountOut == amountQuoteOut, "getBuyQuote error");

        // Check buy fee
        uint256 fee = 10 ether * lamboRouter.feeRate() / lamboRouter.feeDenominator();
        uint256 multisigBalanceBefore = address(multiSigAdmin).balance;
        console2.log("BuyQuote Fee: ", fee);

        console2.log("BuyQuote Gas Used: ", gasUsed);
        vm.assertEq(IERC20(quoteToken).balanceOf(address(this)), amountOut);

        IERC20(quoteToken).approve(address(lamboRouter), amountOut);
        
        amountQuoteOut = lamboRouter.getSellQuote(quoteToken, amountOut);
        gasStart = gasleft();
        uint256 amountXOut = lamboRouter.sellQuote(quoteToken, amountOut, 0);
        gasUsed = gasStart - gasleft();

        console2.log("amountQuoteOut: ", amountQuoteOut);
        console2.log("amountXOut: ", amountXOut);
        require(amountQuoteOut == amountXOut);

        // Check sell fee
        fee = amountXOut * lamboRouter.feeDenominator() / (  lamboRouter.feeDenominator() - lamboRouter.feeRate() ) - amountXOut;
        console2.log("SellQuote Fee: ", fee);

        // Check multisig balance
        uint256 multisigBalanceAfter = address(multiSigAdmin).balance;
        require(multisigBalanceAfter == multisigBalanceBefore + fee, "Fee not transferred to multisig");

        console2.log("SellQuote Gas Used: ", gasUsed);
        console2.log("amountXOut: ", amountXOut);
    }

    // vETH <-> Meme into Uniswap
    function test_createLaunchPadWithInitalBuy() public {
        bytes32 salt = bytes32(vm.randomUint());
        (address quoteToken, address pool, uint256 amountYOut) = lamboRouter.createLaunchPadAndInitialBuy{value: 10 ether}(address(factory), "LamboToken", "LAMBO", 10 ether, 10 ether, salt);
  
        console2.log("amountYOut: ", amountYOut);
        vm.assertEq(IERC20(quoteToken).balanceOf(address(this)), amountYOut);
        IERC20(quoteToken).approve(address(lamboRouter), amountYOut);
        
        uint256 gasStart = gasleft();
        uint256 amountXOut = lamboRouter.sellQuote(quoteToken, amountYOut, 0);
        uint256 gasUsed = gasStart - gasleft();
        console2.log("SellQuote Gas Used: ", gasUsed);
        console2.log("amountXOut: ", amountXOut);
    }

    function test_cashIn_and_buyQuote() public {
        bytes32 salt = bytes32(vm.randomUint());

        (address quoteToken, address pool) = factory.createLaunchPad("LamboToken", "LAMBO", salt, 10 ether, address(vETH));
        uint256 amountQuoteOut = lamboRouter.getBuyQuote(quoteToken, 10 ether);
        uint256 amountOut = lamboRouter.buyQuote{value: 10 ether}(quoteToken, 10 ether, 0);
    }

    function test_cashIn_and_sellQuote() public {
        bytes32 salt = bytes32(vm.randomUint());
        (address quoteToken, address pool) = factory.createLaunchPad("LamboToken", "LAMBO", salt, 10 ether, address(vETH));
        uint256 amountQuoteOut = lamboRouter.getBuyQuote(quoteToken, 10 ether);
        uint256 amountOut0 = lamboRouter.buyQuote{value: 10 ether}(quoteToken, 10 ether, 0);
        require(amountOut0 == amountQuoteOut, "getBuyQuote error");

        IERC20(quoteToken).approve(address(lamboRouter), amountOut0);
        uint256 amountOut1 = lamboRouter.sellQuote(quoteToken, amountOut0, 0);
        console2.log("amountOut0: ", amountOut0);
        console2.log("amountOut1: ", amountOut1);
    }

    receive() external payable {}
}
