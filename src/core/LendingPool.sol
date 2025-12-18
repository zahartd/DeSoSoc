// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

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
    uint16 internal constant DEFAULT_SCORE_FREE = 800;
    uint64 internal constant DEFAULT_MIN_DURATION = 4 hours;
    uint64 internal constant DEFAULT_MAX_DURATION = 72 hours;

    IERC20 public token;
    IRiskEngine public riskEngine;
    ICreditScoreSBT public scoreSbt;
    IBlackBadgeSBT public badgeSbt;
    IInterestModel public interestModel;

    uint16 public scoreIncrement;
    uint16 public protocolFeeBps;
    uint16 public originationFeeBps;
    address public treasury;
    uint16 public defaultBountyBps;
    uint32 public gracePeriod;

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
    uint16 public scoreFree;
    uint64 public minDuration;
    uint64 public maxDuration;

    modifier nonReentrant() {
        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    function _nonReentrantBefore() internal {
        if (locked) revert Errors.Reentrancy();
        locked = true;
    }

    function _nonReentrantAfter() internal {
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
    event DefaultBountyUpdated(uint16 defaultBountyBps);
    event DefaultBountyPaid(address indexed borrower, address indexed caller, uint256 bounty);
    event DurationBoundsUpdated(uint64 minDuration, uint64 maxDuration);
    event ScoreFreeUpdated(uint16 scoreFree);

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
    ) external initializer {
        if (owner_ == address(0)) revert Errors.InvalidAddress(owner_);
        if (token_ == address(0)) revert Errors.InvalidAddress(token_);
        if (riskEngine_ == address(0)) revert Errors.InvalidAddress(riskEngine_);
        if (scoreSbt_ == address(0)) revert Errors.InvalidAddress(scoreSbt_);
        if (badgeSbt_ == address(0)) revert Errors.InvalidAddress(badgeSbt_);
        if (interestModel_ == address(0)) revert Errors.InvalidAddress(interestModel_);
        if (treasury_ == address(0)) revert Errors.InvalidAddress(treasury_);

        __Ownable_init(owner_);
        __Pausable_init();

        token = IERC20(token_);
        riskEngine = IRiskEngine(riskEngine_);
        scoreSbt = ICreditScoreSBT(scoreSbt_);
        badgeSbt = IBlackBadgeSBT(badgeSbt_);
        interestModel = IInterestModel(interestModel_);

        scoreIncrement = 250;
        treasury = treasury_;

        protocolFeeBps = 1000; // 10% of interest
        originationFeeBps = 100; // 1% of principal
        defaultBountyBps = 50; // 0.5% of collateral to incentivize keepers
        gracePeriod = 24 hours;
        scoreFree = DEFAULT_SCORE_FREE;
        minDuration = DEFAULT_MIN_DURATION;
        maxDuration = DEFAULT_MAX_DURATION;

        emit RiskEngineUpdated(riskEngine_);
        emit InterestModelUpdated(interestModel_);
        emit FeesUpdated(protocolFeeBps, originationFeeBps, treasury_);
        emit DefaultBountyUpdated(defaultBountyBps);
        emit DurationBoundsUpdated(minDuration, maxDuration);
        emit ScoreFreeUpdated(scoreFree);
    }

    function setRiskEngine(address newRiskEngine) external onlyOwner {
        if (newRiskEngine == address(0)) revert Errors.InvalidAddress(newRiskEngine);
        riskEngine = IRiskEngine(newRiskEngine);
        emit RiskEngineUpdated(newRiskEngine);
    }

    function setInterestModel(address newInterestModel) external onlyOwner {
        if (newInterestModel == address(0)) revert Errors.InvalidAddress(newInterestModel);
        interestModel = IInterestModel(newInterestModel);
        emit InterestModelUpdated(newInterestModel);
    }

    function setScoreIncrement(uint16 newScoreIncrement) external onlyOwner {
        scoreIncrement = newScoreIncrement;
    }

    function setFees(uint16 newProtocolFeeBps, uint16 newOriginationFeeBps, address newTreasury) external onlyOwner {
        if (newProtocolFeeBps > BPS) revert Errors.InvalidBps(newProtocolFeeBps, BPS);
        if (newOriginationFeeBps > BPS) revert Errors.InvalidBps(newOriginationFeeBps, BPS);
        if (newTreasury == address(0)) revert Errors.InvalidAddress(newTreasury);

        protocolFeeBps = newProtocolFeeBps;
        originationFeeBps = newOriginationFeeBps;
        treasury = newTreasury;

        emit FeesUpdated(newProtocolFeeBps, newOriginationFeeBps, newTreasury);
    }

    function setDefaultBountyBps(uint16 newDefaultBountyBps) external onlyOwner {
        if (newDefaultBountyBps > BPS) revert Errors.InvalidBps(newDefaultBountyBps, BPS);
        defaultBountyBps = newDefaultBountyBps;
        emit DefaultBountyUpdated(newDefaultBountyBps);
    }

    function setGracePeriod(uint32 newGracePeriod) external onlyOwner {
        gracePeriod = newGracePeriod;
    }

    function setDurationBounds(uint64 newMinDuration, uint64 newMaxDuration) external onlyOwner {
        if (newMinDuration == 0 || newMinDuration > newMaxDuration) {
            revert Errors.InvalidDurationBounds(newMinDuration, newMaxDuration);
        }

        minDuration = newMinDuration;
        maxDuration = newMaxDuration;
        emit DurationBoundsUpdated(newMinDuration, newMaxDuration);
    }

    function setScoreFree(uint16 newScoreFree) external onlyOwner {
        if (newScoreFree == 0) revert Errors.InvalidScoreFree(newScoreFree);
        scoreFree = newScoreFree;
        emit ScoreFreeUpdated(newScoreFree);
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
        if (amount == 0) revert Errors.InvalidAmount(amount);
        token.safeTransferFrom(msg.sender, address(this), amount);
        emit LiquidityDeposited(msg.sender, amount);
    }

    function withdrawLiquidity(uint256 amount, address to) external onlyOwner whenNotPaused nonReentrant {
        if (to == address(0)) revert Errors.InvalidAddress(to);
        if (amount == 0) revert Errors.InvalidAmount(amount);
        uint256 available = availableLiquidity();
        if (available < amount) revert Errors.InsufficientLiquidity(available, amount);
        token.safeTransfer(to, amount);
        emit LiquidityWithdrawn(to, amount);
    }

    function borrow(uint256 amount, uint256 collateralAmount, uint64 duration) external whenNotPaused nonReentrant {
        if (amount == 0) revert Errors.InvalidAmount(amount);
        uint64 minD = minDuration;
        uint64 maxD = maxDuration;
        if (duration < minD || duration > maxD) revert Errors.InvalidDuration(duration, minD, maxD);

        Loan storage loan = loanOf[msg.sender];
        if (loan.active) revert Errors.LoanAlreadyActive(msg.sender);

        uint16 ratioBps = riskEngine.collateralRatioBps(msg.sender);
        uint256 maxBorrow = riskEngine.maxBorrow(msg.sender);
        if (amount > maxBorrow) revert Errors.BorrowNotAllowed(msg.sender, amount, maxBorrow);

        if (ratioBps != 0) {
            uint256 required = Math.mulDiv(amount, ratioBps, BPS, Math.Rounding.Ceil);
            if (collateralAmount < required) revert Errors.LowCollateral(collateralAmount, required);
        }

        uint256 available = availableLiquidity();
        if (available < amount) revert Errors.InsufficientLiquidity(available, amount);

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
        uint64 nowTs = uint64(block.timestamp);
        loan.start = nowTs;
        loan.due = nowTs + duration;
        loan.active = true;

        emit Borrowed(msg.sender, amount, collateralAmount, loan.due, originationFee);
    }

    function repay(uint256 amount) external whenNotPaused nonReentrant {
        if (amount == 0) revert Errors.InvalidAmount(amount);

        Loan storage loan = loanOf[msg.sender];
        if (!loan.active) revert Errors.LoanNotActive(msg.sender);

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
        if (!loan.active) revert Errors.LoanNotActive(borrower);
        if (block.timestamp <= (uint256(loan.due) + gracePeriod)) {
            revert Errors.NotPastDue(loan.due, gracePeriod, uint64(block.timestamp));
        }

        loan.active = false;

        if (loan.collateral != 0) {
            lockedCollateral -= loan.collateral;
            uint256 bounty = _feeAmount(loan.collateral, defaultBountyBps);
            if (bounty != 0) {
                token.safeTransfer(msg.sender, bounty);
                emit DefaultBountyPaid(borrower, msg.sender, bounty);
            }
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
        uint16 cap = scoreFree;
        uint16 s = scoreSbt.scoreOf(borrower);
        if (s >= cap) return;

        uint256 next = uint256(s) + uint256(scoreIncrement);
        if (next > cap) next = cap;

        scoreSbt.setScore(borrower, SafeCast.toUint16(next));
    }

    function _feeAmount(uint256 amount, uint16 feeBps) internal pure returns (uint256) {
        if (amount == 0 || feeBps == 0) return 0;
        return Math.mulDiv(amount, uint256(feeBps), BPS);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
