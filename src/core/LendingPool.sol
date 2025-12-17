// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {IBlackBadgeSBT} from "../interfaces/IBlackBadgeSBT.sol";
import {ICreditScoreSBT} from "../interfaces/ICreditScoreSBT.sol";
import {IRiskEngine} from "../interfaces/IRiskEngine.sol";

/// @title LendingPool
/// @notice Minimal undercollateralized lending prototype (single ERC20 + modules + UUPS proxy).
contract LendingPool is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    uint16 internal constant BPS = 10_000;
    uint16 internal constant SCORE_FREE = 800;

    IERC20 public token;
    IRiskEngine public riskEngine;
    ICreditScoreSBT public scoreSbt;
    IBlackBadgeSBT public badgeSbt;

    uint16 public scoreIncrement;

    uint256 public lockedCollateral;

    struct Loan {
        uint256 principal;
        uint256 collateral;
        uint64 due;
        bool active;
    }

    mapping(address borrower => Loan loan) public loanOf;

    bool private locked;

    modifier nonReentrant() {
        require(!locked, "REENTRANCY");
        locked = true;
        _;
        locked = false;
    }

    event LiquidityDeposited(address indexed from, uint256 amount);
    event LiquidityWithdrawn(address indexed to, uint256 amount);
    event Borrowed(address indexed borrower, uint256 amount, uint256 collateral, uint64 dueTs);
    event Repaid(address indexed borrower, uint256 amount);
    event Defaulted(address indexed borrower);
    event RiskEngineUpdated(address riskEngine);

    constructor() {
        _disableInitializers();
    }

    function initialize(address owner_, address token_, address riskEngine_, address scoreSbt_, address badgeSbt_)
        external
        initializer
    {
        require(owner_ != address(0), "ZERO_OWNER");
        require(token_ != address(0), "ZERO_TOKEN");
        require(riskEngine_ != address(0), "ZERO_RISK");
        require(scoreSbt_ != address(0), "ZERO_SCORE");
        require(badgeSbt_ != address(0), "ZERO_BADGE");

        __Ownable_init(owner_);

        token = IERC20(token_);
        riskEngine = IRiskEngine(riskEngine_);
        scoreSbt = ICreditScoreSBT(scoreSbt_);
        badgeSbt = IBlackBadgeSBT(badgeSbt_);

        scoreIncrement = 250;
        emit RiskEngineUpdated(riskEngine_);
    }

    function setRiskEngine(address newRiskEngine) external onlyOwner {
        require(newRiskEngine != address(0), "ZERO_RISK");
        riskEngine = IRiskEngine(newRiskEngine);
        emit RiskEngineUpdated(newRiskEngine);
    }

    function setScoreIncrement(uint16 newScoreIncrement) external onlyOwner {
        scoreIncrement = newScoreIncrement;
    }

    function availableLiquidity() public view returns (uint256) {
        return token.balanceOf(address(this)) - lockedCollateral;
    }

    function depositLiquidity(uint256 amount) external onlyOwner nonReentrant {
        require(amount != 0, "ZERO_AMOUNT");
        token.safeTransferFrom(msg.sender, address(this), amount);
        emit LiquidityDeposited(msg.sender, amount);
    }

    function withdrawLiquidity(uint256 amount, address to) external onlyOwner nonReentrant {
        require(to != address(0), "ZERO_TO");
        require(amount != 0, "ZERO_AMOUNT");
        require(availableLiquidity() >= amount, "NO_LIQUIDITY");
        token.safeTransfer(to, amount);
        emit LiquidityWithdrawn(to, amount);
    }

    function borrow(uint256 amount, uint256 collateralAmount, uint64 duration) external nonReentrant {
        require(amount != 0, "ZERO_AMOUNT");
        require(duration != 0, "ZERO_DURATION");

        Loan storage loan = loanOf[msg.sender];
        require(!loan.active, "ACTIVE_LOAN");

        uint16 ratioBps = riskEngine.collateralRatioBps(msg.sender);
        uint256 maxBorrow = riskEngine.maxBorrow(msg.sender);
        require(amount <= maxBorrow, "NOT_ALLOWED");

        if (ratioBps != 0) {
            uint256 required = Math.mulDiv(amount, ratioBps, BPS, Math.Rounding.Ceil);
            require(collateralAmount >= required, "LOW_COLLATERAL");
        }

        require(availableLiquidity() >= amount, "NO_LIQUIDITY");

        if (collateralAmount != 0) {
            token.safeTransferFrom(msg.sender, address(this), collateralAmount);
            lockedCollateral += collateralAmount;
        }

        token.safeTransfer(msg.sender, amount);

        loan.principal = amount;
        loan.collateral = collateralAmount;
        loan.due = uint64(block.timestamp) + duration;
        loan.active = true;

        emit Borrowed(msg.sender, amount, collateralAmount, loan.due);
    }

    function repay() external nonReentrant {
        Loan storage loan = loanOf[msg.sender];
        require(loan.active, "NO_LOAN");

        uint256 amount = loan.principal;
        token.safeTransferFrom(msg.sender, address(this), amount);
        loan.active = false;

        if (loan.collateral != 0) {
            lockedCollateral -= loan.collateral;
            token.safeTransfer(msg.sender, loan.collateral);
        }

        _increaseScore(msg.sender);
        emit Repaid(msg.sender, amount);
    }

    function markDefault(address borrower) external nonReentrant {
        Loan storage loan = loanOf[borrower];
        require(loan.active, "NO_LOAN");
        require(block.timestamp > loan.due, "NOT_PAST_DUE");

        loan.active = false;

        if (loan.collateral != 0) {
            lockedCollateral -= loan.collateral; // seized collateral becomes pool liquidity
        }

        badgeSbt.mintBadge(borrower);
        emit Defaulted(borrower);
    }

    function _increaseScore(address borrower) internal {
        uint16 s = scoreSbt.scoreOf(borrower);
        if (s >= SCORE_FREE) return;

        uint256 next = uint256(s) + uint256(scoreIncrement);
        if (next > SCORE_FREE) next = SCORE_FREE;

        scoreSbt.setScore(borrower, uint16(next));
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
