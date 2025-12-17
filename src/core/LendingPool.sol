// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import {IBlackBadgeSBT} from "../interfaces/IBlackBadgeSBT.sol";
import {ICreditScoreSBT} from "../interfaces/ICreditScoreSBT.sol";
import {IInterestModel} from "../interfaces/IInterestModel.sol";
import {IRiskEngine} from "../interfaces/IRiskEngine.sol";
import {Errors} from "../utils/Errors.sol";

/// @title LendingPool
/// @notice Minimal undercollateralized lending prototype (single ERC20 + modules + UUPS proxy).
contract LendingPool is Initializable, UUPSUpgradeable, OwnableUpgradeable, PausableUpgradeable {
    using SafeERC20 for IERC20;

    uint16 internal constant BPS = 10_000;
    uint16 internal constant SCORE_FREE = 800;

    IERC20 public token;
    IRiskEngine public riskEngine;
    ICreditScoreSBT public scoreSbt;
    IBlackBadgeSBT public badgeSbt;
    IInterestModel public interestModel;

    uint16 public scoreIncrement;
    uint16 public protocolFeeBps;
    uint16 public originationFeeBps;
    address public treasury;

    uint256 public lockedCollateral;

    struct Loan {
        uint256 principal;
        uint256 collateral;
        uint256 repaid;
        uint64 start;
        uint64 due;
        bool active;
    }

    mapping(address borrower => Loan loan) public loanOf;

    bool private locked;

    modifier nonReentrant() {
        if (locked) revert Errors.Reentrancy();
        locked = true;
        _;
        locked = false;
    }

    event LiquidityDeposited(address indexed from, uint256 amount);
    event LiquidityWithdrawn(address indexed to, uint256 amount);
    event Borrowed(address indexed borrower, uint256 principal, uint256 collateral, uint64 dueTs, uint256 fee);
    event Repaid(address indexed borrower, uint256 paid, uint256 totalRepaid, uint256 totalDebt, bool fullyRepaid);
    event Defaulted(address indexed borrower);
    event RiskEngineUpdated(address riskEngine);
    event InterestModelUpdated(address interestModel);
    event FeesUpdated(uint16 protocolFeeBps, uint16 originationFeeBps, address treasury);

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address owner_,
        address token_,
        address riskEngine_,
        address scoreSbt_,
        address badgeSbt_,
        address interestModel_,
        address treasury_
    )
        external
        initializer
    {
        if (
            owner_ == address(0) || token_ == address(0) || riskEngine_ == address(0) || scoreSbt_ == address(0)
                || badgeSbt_ == address(0) || interestModel_ == address(0) || treasury_ == address(0)
        ) revert Errors.InvalidAddress();

        __Ownable_init(owner_);
        __Pausable_init();

        token = IERC20(token_);
        riskEngine = IRiskEngine(riskEngine_);
        scoreSbt = ICreditScoreSBT(scoreSbt_);
        badgeSbt = IBlackBadgeSBT(badgeSbt_);
        interestModel = IInterestModel(interestModel_);

        scoreIncrement = 250; // v0 example
        treasury = treasury_;

        protocolFeeBps = 1000; // 10% of interest
        originationFeeBps = 100; // 1% of principal

        emit RiskEngineUpdated(riskEngine_);
        emit InterestModelUpdated(interestModel_);
        emit FeesUpdated(protocolFeeBps, originationFeeBps, treasury_);
    }

    function setRiskEngine(address newRiskEngine) external onlyOwner {
        if (newRiskEngine == address(0)) revert Errors.InvalidAddress();
        riskEngine = IRiskEngine(newRiskEngine);
        emit RiskEngineUpdated(newRiskEngine);
    }

    function setInterestModel(address newInterestModel) external onlyOwner {
        if (newInterestModel == address(0)) revert Errors.InvalidAddress();
        interestModel = IInterestModel(newInterestModel);
        emit InterestModelUpdated(newInterestModel);
    }

    function setScoreIncrement(uint16 newScoreIncrement) external onlyOwner {
        scoreIncrement = newScoreIncrement;
    }

    function setFees(uint16 newProtocolFeeBps, uint16 newOriginationFeeBps, address newTreasury) external onlyOwner {
        if (newProtocolFeeBps > BPS || newOriginationFeeBps > BPS) revert Errors.InvalidBps();
        if (newTreasury == address(0)) revert Errors.InvalidAddress();

        protocolFeeBps = newProtocolFeeBps;
        originationFeeBps = newOriginationFeeBps;
        treasury = newTreasury;

        emit FeesUpdated(newProtocolFeeBps, newOriginationFeeBps, newTreasury);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function availableLiquidity() public view returns (uint256) {
        return token.balanceOf(address(this)) - lockedCollateral;
    }

    function depositLiquidity(uint256 amount) external onlyOwner whenNotPaused nonReentrant {
        if (amount == 0) revert Errors.InvalidAmount();
        token.safeTransferFrom(msg.sender, address(this), amount);
        emit LiquidityDeposited(msg.sender, amount);
    }

    function withdrawLiquidity(uint256 amount, address to) external onlyOwner whenNotPaused nonReentrant {
        if (to == address(0)) revert Errors.InvalidAddress();
        if (amount == 0) revert Errors.InvalidAmount();
        if (availableLiquidity() < amount) revert Errors.InsufficientLiquidity();
        token.safeTransfer(to, amount);
        emit LiquidityWithdrawn(to, amount);
    }

    function borrow(uint256 amount, uint256 collateralAmount, uint64 duration) external whenNotPaused nonReentrant {
        if (amount == 0) revert Errors.InvalidAmount();
        if (duration == 0) revert Errors.InvalidDuration();

        Loan storage loan = loanOf[msg.sender];
        if (loan.active) revert Errors.LoanAlreadyActive();

        uint16 ratioBps = riskEngine.collateralRatioBps(msg.sender);
        uint256 maxBorrow = riskEngine.maxBorrow(msg.sender);
        if (amount > maxBorrow) revert Errors.BorrowNotAllowed();

        if (ratioBps != 0) {
            uint256 required = Math.mulDiv(amount, ratioBps, BPS, Math.Rounding.Ceil);
            if (collateralAmount < required) revert Errors.LowCollateral();
        }

        if (availableLiquidity() < amount) revert Errors.InsufficientLiquidity();

        if (collateralAmount != 0) {
            token.safeTransferFrom(msg.sender, address(this), collateralAmount);
            lockedCollateral += collateralAmount;
        }

        uint256 originationFee = _feeAmount(amount, originationFeeBps);
        token.safeTransfer(msg.sender, amount - originationFee);
        if (originationFee != 0) {
            token.safeTransfer(treasury, originationFee);
        }

        loan.principal = amount;
        loan.collateral = collateralAmount;
        loan.repaid = 0;
        loan.start = uint64(block.timestamp);
        loan.due = uint64(block.timestamp) + duration;
        loan.active = true;

        emit Borrowed(msg.sender, amount, collateralAmount, loan.due, originationFee);
    }

    function repay(uint256 amount) external whenNotPaused nonReentrant {
        if (amount == 0) revert Errors.InvalidAmount();

        Loan storage loan = loanOf[msg.sender];
        if (!loan.active) revert Errors.LoanNotActive();

        token.safeTransferFrom(msg.sender, address(this), amount);
        loan.repaid += amount;

        uint64 nowTs = uint64(block.timestamp);
        uint256 totalDebt = interestModel.debtWithPenalty(loan.principal, loan.start, loan.due, nowTs);

        bool fullyRepaid = loan.repaid >= totalDebt;
        uint256 paidNet = amount;

        if (fullyRepaid) {
            uint256 overpay = loan.repaid - totalDebt;
            if (overpay != 0) {
                paidNet = amount - overpay;
                loan.repaid = totalDebt;
                token.safeTransfer(msg.sender, overpay);
            }

            loan.active = false;

            if (loan.collateral != 0) {
                lockedCollateral -= loan.collateral;
                token.safeTransfer(msg.sender, loan.collateral);
            }

            uint256 interestAccrued = totalDebt > loan.principal ? totalDebt - loan.principal : 0;
            uint256 fee = _feeAmount(interestAccrued, protocolFeeBps);
            if (fee != 0) {
                token.safeTransfer(treasury, fee);
            }

            _increaseScore(msg.sender);
        }

        emit Repaid(msg.sender, paidNet, loan.repaid, totalDebt, fullyRepaid);
    }

    function markDefault(address borrower) external whenNotPaused nonReentrant {
        Loan storage loan = loanOf[borrower];
        if (!loan.active) revert Errors.LoanNotActive();
        if (block.timestamp <= loan.due) revert Errors.NotPastDue();

        loan.active = false;

        if (loan.collateral != 0) {
            lockedCollateral -= loan.collateral; // seized collateral becomes pool liquidity
        }

        badgeSbt.mintBadge(borrower);
        emit Defaulted(borrower);
    }

    function getLoan(address borrower) external view returns (Loan memory) {
        return loanOf[borrower];
    }

    function getDebt(address borrower) external view returns (uint256) {
        Loan memory loan = loanOf[borrower];
        if (!loan.active) return 0;
        return interestModel.debtWithPenalty(loan.principal, loan.start, loan.due, uint64(block.timestamp));
    }

    function isDefaulter(address borrower) external view returns (bool) {
        return riskEngine.isDefaulter(borrower);
    }

    function _increaseScore(address borrower) internal {
        uint16 s = scoreSbt.scoreOf(borrower);
        if (s >= SCORE_FREE) return;

        uint256 next = uint256(s) + uint256(scoreIncrement);
        if (next > SCORE_FREE) next = SCORE_FREE;

        scoreSbt.setScore(borrower, uint16(next));
    }

    function _feeAmount(uint256 amount, uint16 feeBps) internal pure returns (uint256) {
        if (amount == 0 || feeBps == 0) return 0;
        return Math.mulDiv(amount, uint256(feeBps), BPS);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
