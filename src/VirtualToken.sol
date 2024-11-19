// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {LaunchPadUtils} from "./Utils/LaunchPadUtils.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract VirtualToken is ERC20, ReentrancyGuard, Ownable {
    uint256 public lastLoanBlock;
    address public underlyingToken;
    uint256 public loanedAmountThisBlock;
    uint256 public totalCashOutFeesCollected;
    uint256 public constant MAX_LOAN_PER_BLOCK = 300 ether;

    mapping(address => uint256) public _debt;
    mapping(address => bool) public whiteList;
    mapping(address => bool) public validFactories;

    event LoanTaken(address user, uint256 amount);
    event LoanRepaid(address user, uint256 amount);
    event CashIn(address user, uint256 amount);
    event CashOut(address user, uint256 amount);
    event Withdraw(address owner, uint256 amount);

    error DebtOverflow(address user, uint256 debt, uint256 value);

    modifier onlyWhiteListed() {
        require(whiteList[msg.sender], "Only WhiteList");
        _;
    }

    modifier onlyValidFactory() {
        require(validFactories[msg.sender], "Only valid factory can call this function");
        _;
    }

    constructor(
        string memory name,
        string memory symbol,
        address _underlyingToken
    ) ERC20(name, symbol) Ownable(msg.sender) {
        underlyingToken = _underlyingToken;
    }

    function isValidFactory(address _factory) external view returns (bool) {
        return validFactories[_factory];
    }

    function updateFactory(address _factory, bool isValid) external onlyOwner {
        validFactories[_factory] = isValid;
    }

    function addToWhiteList(address user) external onlyOwner {
        whiteList[user] = true;
    }

    function removeFromWhiteList(address user) external onlyOwner {
        whiteList[user] = false;
    }

    function cashIn() external payable onlyWhiteListed {
        _transferAssetFromUser(msg.value);
        _mint(msg.sender, msg.value);
        emit CashIn(msg.sender, msg.value);
    }

    function cashOut(uint256 amount) external onlyWhiteListed {
        _burn(msg.sender, amount);
        _transferAssetToUser(amount);
        emit CashOut(msg.sender, amount);
    }

    function takeLoan(address to, uint256 amount) external payable nonReentrant onlyValidFactory {
        if (block.number > lastLoanBlock) {
            lastLoanBlock = block.number;
            loanedAmountThisBlock = 0;
        }
        require(loanedAmountThisBlock + amount <= MAX_LOAN_PER_BLOCK, "Loan limit per block exceeded");

        loanedAmountThisBlock += amount;
        _mint(to, amount);
        _increaseDebt(to, amount);

        emit LoanTaken(to, amount);
    }

    /**
     * @notice This function is currently unused.
     */
    function repayLoan(address to, uint256 amount) external nonReentrant onlyValidFactory {
        _burn(to, amount);
        _decreaseDebt(to, amount);

        emit LoanRepaid(to, amount);
    }

    function getLoanDebt(address user) external view returns (uint256) {
        return _debt[user];
    }

    function _increaseDebt(address user, uint256 amount) internal {
        _debt[user] += amount;
    }

    function _decreaseDebt(address user, uint256 amount) internal {
        require(_debt[user] >= amount, "Decrease amount exceeds current debt");
        _debt[user] -= amount;
    }

    function _transferAssetFromUser(uint256 amount) internal {
        if (underlyingToken == LaunchPadUtils.NATIVE_TOKEN) {
            require(msg.value >= amount, "Invalid ETH amount");
        } else {
            IERC20(underlyingToken).transferFrom(msg.sender, address(this), amount);
        }
    }

    function _transferAssetToUser(uint256 amount) internal {
        if (underlyingToken == LaunchPadUtils.NATIVE_TOKEN) {
            require(address(this).balance >= amount, "Insufficient ETH balance");
            (bool success, ) = msg.sender.call{value: amount}("");
            require(success, "Transfer failed");
        } else {
            IERC20(underlyingToken).transfer(msg.sender, amount);
        }
    }

    // override the _update function to prevent overflow
    function _update(address from, address to, uint256 value) internal override {
        // check: balance - _debt < value
        if (from != address(0) && balanceOf(from) < value + _debt[from]) {
            revert DebtOverflow(from, _debt[from], value);
        }

        super._update(from, to, value);
    }
}
