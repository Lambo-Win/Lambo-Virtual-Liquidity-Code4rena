// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {LaunchPadUtils} from "./Utils/LaunchPadUtils.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract VirtualToken is ERC20, Ownable {
    using SafeERC20 for IERC20;

    uint256 public lastLoanBlock;
    uint256 public loanedAmountThisBlock;

    // immutable and constant
    address public immutable underlyingToken;
    uint256 public constant MAX_LOAN_PER_BLOCK = 300 ether;

    mapping(address => uint256) public _debt;
    mapping(address => bool) public whiteList;
    mapping(address => bool) public validFactories;

    event LoanTaken(address user, uint256 amount);
    event LoanRepaid(address user, uint256 amount);
    event CashIn(address user, uint256 amount);
    event CashOut(address user, uint256 amount);
    event FactoryUpdated(address newFactory);
    event WhiteListAdded(address user);
    event WhiteListRemoved(address user);

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
        require(_underlyingToken != address(0), "Invalid underlying token address");
        underlyingToken = _underlyingToken;
    }

    function isValidFactory(address _factory) external view returns (bool) {
        return validFactories[_factory];
    }

    function updateFactory(address _factory, bool isValid) external onlyOwner {
        validFactories[_factory] = isValid;
        emit FactoryUpdated(_factory);
    }

    function addToWhiteList(address user) external onlyOwner {
        whiteList[user] = true;
        emit WhiteListAdded(user);
    }

    function removeFromWhiteList(address user) external onlyOwner {
        whiteList[user] = false;
        emit WhiteListRemoved(user);
    }

    function cashIn(uint256 amount) external payable onlyWhiteListed {
        if (underlyingToken == LaunchPadUtils.NATIVE_TOKEN) {
            require(msg.value == amount, "Invalid ETH amount");
        } else {
            _transferAssetFromUser(amount);
        }        
        _mint(msg.sender, amount);
        emit CashIn(msg.sender, amount);
    }

    function cashOut(uint256 amount) external onlyWhiteListed {
        _burn(msg.sender, amount);
        _transferAssetToUser(amount);
        emit CashOut(msg.sender, amount);
    }

    function takeLoan(address to, uint256 amount) external payable onlyValidFactory {
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
    function repayLoan(address to, uint256 amount) external onlyValidFactory {
        _decreaseDebt(to, amount);
        _burn(to, amount);
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
            IERC20(underlyingToken).safeTransferFrom(msg.sender, address(this), amount);
        }
    }

    function _transferAssetToUser(uint256 amount) internal {
        if (underlyingToken == LaunchPadUtils.NATIVE_TOKEN) {
            require(address(this).balance >= amount, "Insufficient ETH balance");
            (bool success, ) = msg.sender.call{value: amount}("");
            require(success, "Transfer failed");
        } else {
            IERC20(underlyingToken).safeTransfer(msg.sender, amount);
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
