import {BaseTest} from "./BaseTest.t.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "forge-std/console2.sol";

contract LiquidityManage is BaseTest {

    function setUp() public override {
        super.setUp();

        vm.startPrank(multiSigAdmin);
        vETH.addToWhiteList(multiSigAdmin);
        vm.stopPrank();
    }

    function test_mint_and_redeem() public {
        deal(multiSigAdmin, 100 ether);
        uint256 beforeAmount = payable(multiSigAdmin).balance;
        vm.startPrank(multiSigAdmin);

        vETH.cashIn{value: 10 ether}(10 ether);
        vm.assertEq(vETH.balanceOf(multiSigAdmin), 10 ether);

        uint256 beforeCashOutBalance = payable(multiSigAdmin).balance;

        vETH.cashOut(10 ether);

        vm.assertEq(payable(multiSigAdmin).balance, beforeCashOutBalance + 10 ether) ;
        vm.stopPrank();
    }

    function test_liquidityV3() public {
        bytes32 salt = bytes32(vm.randomUint());
        (address quoteToken, address pool) = factory.createLaunchPad("LamboToken", "LAMBO", salt, 10 ether, address(vETH));

        // create VETH <-> WETH uniswapV3 Pool
        deal(multiSigAdmin, 100 ether);
        uint256 beforeAmount = payable(multiSigAdmin).balance;
        vm.startPrank(multiSigAdmin);

        vETH.cashIn{value: 10 ether}(10 ether);
        vm.assertEq(vETH.balanceOf(multiSigAdmin), 10 ether);

        vm.stopPrank();
    }

}
