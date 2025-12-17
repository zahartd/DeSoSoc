// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import {LendingPoolStorage} from "./LendingPoolStorage.sol";
import {Errors} from "../utils/Errors.sol";
import {Types} from "../utils/Types.sol";
import {IInterestModel} from "../interfaces/IInterestModel.sol";
import {IReputationHook} from "../interfaces/IReputationHook.sol";
import {IRiskEngine} from "../interfaces/IRiskEngine.sol";

/// @title LendingPool
/// @notice Upgradeable core contract that stores loans and delegates policy to modules.
contract LendingPool is
    Initializable,
    UUPSUpgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuard,
    LendingPoolStorage
{
    using SafeCast for uint256;

    /// @notice Role allowed to authorize upgrades.
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    /// @notice Role allowed to update risk/interest modules.
    bytes32 public constant RISK_ADMIN_ROLE = keccak256("RISK_ADMIN_ROLE");

    /// @notice Role allowed to pause/unpause the protocol.
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @notice Emitted when risk/interest modules are updated.
    event ModulesUpdated(address riskEngine, address interestModel);

    /// @notice Emitted when reputation hook is updated.
    event ReputationHookUpdated(address reputationHook);

    /// @notice Emitted when treasury address is updated.
    event TreasuryUpdated(address treasury);

    /// @notice Emitted when a loan is opened.
    event LoanOpened(uint256 indexed loanId, address indexed borrower, address asset, uint256 amount, uint64 dueTs);

    /// @notice Emitted when a loan is repaid (partially or fully).
    event LoanRepaid(uint256 indexed loanId, address indexed borrower, uint256 paidAmount, uint256 totalRepaid);

    /// @notice Emitted when a loan is marked as defaulted.
    event LoanDefaulted(uint256 indexed loanId, address indexed borrower);

    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the contract (proxy initializer).
    /// @param admin Default admin (also receives upgrader/risk-admin/pauser roles).
    /// @param riskEngine_ Risk engine module address.
    /// @param interestModel_ Interest model module address.
    /// @param reputationHook_ Reputation hook module address.
    /// @param treasury_ Treasury address placeholder.
    function initialize(
        address admin,
        address riskEngine_,
        address interestModel_,
        address reputationHook_,
        address treasury_
    ) external initializer {
        if (admin == address(0)) revert Errors.InvalidAddress();

        __AccessControl_init();
        __Pausable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(UPGRADER_ROLE, admin);
        _grantRole(RISK_ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);

        _setRiskEngine(riskEngine_);
        _setInterestModel(interestModel_);
        _setReputationHook(reputationHook_);
        _setTreasury(treasury_);

        nextLoanId = 1;
    }

    /// @notice Sets a new risk engine module.
    /// @dev Only callable by `RISK_ADMIN_ROLE`.
    function setRiskEngine(address newRiskEngine) external onlyRole(RISK_ADMIN_ROLE) {
        _setRiskEngine(newRiskEngine);
    }

    /// @notice Sets a new interest model module.
    /// @dev Only callable by `RISK_ADMIN_ROLE`.
    function setInterestModel(address newInterestModel) external onlyRole(RISK_ADMIN_ROLE) {
        _setInterestModel(newInterestModel);
    }

    /// @notice Sets a new reputation hook module.
    /// @dev Only callable by `RISK_ADMIN_ROLE`.
    function setReputationHook(address newReputationHook) external onlyRole(RISK_ADMIN_ROLE) {
        _setReputationHook(newReputationHook);
    }

    /// @notice Sets a new treasury address.
    /// @dev Only callable by `DEFAULT_ADMIN_ROLE`.
    function setTreasury(address newTreasury) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setTreasury(newTreasury);
    }

    /// @notice Pauses borrowing/repaying flows.
    /// @dev Only callable by `PAUSER_ROLE`.
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @notice Unpauses borrowing/repaying flows.
    /// @dev Only callable by `PAUSER_ROLE`.
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /// @notice Opens a new loan (token transfers are TODO for v0).
    /// @param req Borrow request parameters.
    /// @return loanId Newly created loan id.
    function borrow(Types.BorrowRequest calldata req) external whenNotPaused nonReentrant returns (uint256 loanId) {
        if (
            address(riskEngine) == address(0) || address(interestModel) == address(0)
                || address(reputationHook) == address(0)
        ) revert Errors.ModuleNotSet();
        if (req.asset == address(0)) revert Errors.InvalidAddress();
        if (req.amount == 0) revert Errors.InvalidAmount();
        if (activeLoanIdOf[msg.sender] != 0) revert Errors.LoanAlreadyActive();

        Types.RiskResult memory result = riskEngine.assessBorrow(msg.sender, req);
        if (!result.allowed || req.amount > result.maxBorrow) revert Errors.BorrowNotAllowed();

        loanId = nextLoanId;
        nextLoanId = loanId + 1;

        uint64 startTs = block.timestamp.toUint64();
        uint64 dueTs = (uint256(startTs) + uint256(req.duration)).toUint64();

        loans[loanId] = Types.Loan({
            borrower: msg.sender,
            asset: req.asset,
            collateralAsset: req.collateralAsset,
            principal: req.amount,
            principalRepaid: 0,
            collateralAmount: req.collateralAmount,
            startTs: startTs,
            dueTs: dueTs,
            status: Types.LoanStatus.Active
        });

        activeLoanIdOf[msg.sender] = loanId;

        // TODO: transfer borrowed asset from liquidity source to borrower.
        // TODO: escrow collateral / validate collateral amount.

        reputationHook.onLoanOpened(loanId, msg.sender);

        emit LoanOpened(loanId, msg.sender, req.asset, req.amount, dueTs);
    }

    /// @notice Repays an active loan (token transfers are TODO for v0).
    /// @param loanId Loan id.
    /// @param amount Amount being repaid.
    function repay(uint256 loanId, uint256 amount) external whenNotPaused nonReentrant {
        if (amount == 0) revert Errors.InvalidAmount();
        if (address(interestModel) == address(0) || address(reputationHook) == address(0)) {
            revert Errors.ModuleNotSet();
        }

        Types.Loan storage loan = loans[loanId];
        if (loan.borrower == address(0)) revert Errors.LoanNotFound();
        if (loan.status != Types.LoanStatus.Active) revert Errors.LoanNotActive();
        if (loan.borrower != msg.sender) revert Errors.RepayNotAllowed();

        // TODO: transferFrom borrower -> treasury / pool.
        loan.principalRepaid += amount;

        uint64 nowTs = block.timestamp.toUint64();
        uint256 totalDebt = interestModel.debtWithPenalty(loan.principal, loan.startTs, loan.dueTs, nowTs);

        bool fullyRepaid = loan.principalRepaid >= totalDebt;
        reputationHook.onLoanRepaid(loanId, msg.sender, amount, loan.principalRepaid, totalDebt, fullyRepaid);

        emit LoanRepaid(loanId, msg.sender, amount, loan.principalRepaid);

        if (fullyRepaid) {
            loan.status = Types.LoanStatus.Repaid;
            activeLoanIdOf[msg.sender] = 0;

            // TODO: release collateral back to borrower.
        }
    }

    /// @notice Marks a loan as defaulted if it is past due.
    /// @param loanId Loan id.
    function markDefault(uint256 loanId) external whenNotPaused nonReentrant {
        if (address(reputationHook) == address(0)) revert Errors.ModuleNotSet();

        Types.Loan storage loan = loans[loanId];
        if (loan.borrower == address(0)) revert Errors.LoanNotFound();
        if (loan.status != Types.LoanStatus.Active) revert Errors.LoanNotActive();

        uint64 nowTs = block.timestamp.toUint64();
        if (nowTs <= loan.dueTs) revert Errors.NotPastDue();

        loan.status = Types.LoanStatus.Defaulted;
        activeLoanIdOf[loan.borrower] = 0;

        reputationHook.onLoanDefaulted(loanId, loan.borrower);

        emit LoanDefaulted(loanId, loan.borrower);

        // TODO: mint default badge, seize collateral, etc.
    }

    /// @notice Returns the full loan data by id.
    function getLoan(uint256 loanId) external view returns (Types.Loan memory) {
        Types.Loan memory loan = loans[loanId];
        if (loan.borrower == address(0)) revert Errors.LoanNotFound();
        return loan;
    }

    /// @notice Returns current debt for an active loan, including penalty after due date.
    function getDebt(uint256 loanId) external view returns (uint256) {
        if (address(interestModel) == address(0)) revert Errors.ModuleNotSet();

        Types.Loan memory loan = loans[loanId];
        if (loan.borrower == address(0)) revert Errors.LoanNotFound();
        if (loan.status != Types.LoanStatus.Active) return 0;

        return interestModel.debtWithPenalty(loan.principal, loan.startTs, loan.dueTs, block.timestamp.toUint64());
    }

    function _setRiskEngine(address newRiskEngine) internal {
        if (newRiskEngine == address(0)) revert Errors.InvalidAddress();
        riskEngine = IRiskEngine(newRiskEngine);
        emit ModulesUpdated(address(riskEngine), address(interestModel));
    }

    function _setInterestModel(address newInterestModel) internal {
        if (newInterestModel == address(0)) revert Errors.InvalidAddress();
        interestModel = IInterestModel(newInterestModel);
        emit ModulesUpdated(address(riskEngine), address(interestModel));
    }

    function _setReputationHook(address newReputationHook) internal {
        if (newReputationHook == address(0)) revert Errors.InvalidAddress();
        reputationHook = IReputationHook(newReputationHook);
        emit ReputationHookUpdated(newReputationHook);
    }

    function _setTreasury(address newTreasury) internal {
        if (newTreasury == address(0)) revert Errors.InvalidAddress();
        treasury = newTreasury;
        emit TreasuryUpdated(newTreasury);
    }

    function _authorizeUpgrade(address) internal override onlyRole(UPGRADER_ROLE) {}
}
