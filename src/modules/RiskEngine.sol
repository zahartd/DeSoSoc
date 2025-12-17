// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {Types} from "../utils/Types.sol";
import {ICreditScoreSBT} from "../interfaces/ICreditScoreSBT.sol";
import {IDefaultBadgeSBT} from "../interfaces/IDefaultBadgeSBT.sol";
import {IIdentityVerifier} from "../interfaces/IIdentityVerifier.sol";
import {IPriceOracle} from "../interfaces/IPriceOracle.sol";
import {IRiskEngine} from "../interfaces/IRiskEngine.sol";

/// @title RiskEngine
/// @notice v0 risk engine: score-based collateral ratio + oracle-based maxBorrow + optional identity proof.
contract RiskEngine is IRiskEngine, Ownable {
    uint256 internal constant BPS = 10_000;

    /// @notice Credit score SBT dependency (optional).
    ICreditScoreSBT public scoreSbt;

    /// @notice Default badge SBT dependency (optional).
    IDefaultBadgeSBT public badgeSbt;

    /// @notice Identity verifier dependency (optional).
    IIdentityVerifier public verifier;

    /// @notice Price oracle dependency (optional).
    IPriceOracle public oracle;

    /// @notice If true, a non-empty proof is required when `verifier` is set.
    bool public requireProof;

    /// @notice Max borrow allowed when `collateralRatioBps == 0` (i.e., no-collateral tier).
    uint256 public maxBorrowNoCollateral;

    /// @notice Emitted when dependencies are updated.
    event DependenciesUpdated(address scoreSbt, address badgeSbt, address verifier, address oracle);

    /// @notice Emitted when configuration is updated.
    event ConfigUpdated(bool requireProof, uint256 maxBorrowNoCollateral);

    constructor(address initialOwner, address scoreSbt_, address badgeSbt_, address verifier_, address oracle_)
        Ownable(initialOwner)
    {
        scoreSbt = ICreditScoreSBT(scoreSbt_);
        badgeSbt = IDefaultBadgeSBT(badgeSbt_);
        verifier = IIdentityVerifier(verifier_);
        oracle = IPriceOracle(oracle_);

        emit DependenciesUpdated(scoreSbt_, badgeSbt_, verifier_, oracle_);
    }

    /// @notice Updates module dependencies.
    function setDependencies(address scoreSbt_, address badgeSbt_, address verifier_, address oracle_)
        external
        onlyOwner
    {
        scoreSbt = ICreditScoreSBT(scoreSbt_);
        badgeSbt = IDefaultBadgeSBT(badgeSbt_);
        verifier = IIdentityVerifier(verifier_);
        oracle = IPriceOracle(oracle_);

        emit DependenciesUpdated(scoreSbt_, badgeSbt_, verifier_, oracle_);
    }

    /// @notice Updates policy configuration.
    function setConfig(bool requireProof_, uint256 maxBorrowNoCollateral_) external onlyOwner {
        requireProof = requireProof_;
        maxBorrowNoCollateral = maxBorrowNoCollateral_;
        emit ConfigUpdated(requireProof_, maxBorrowNoCollateral_);
    }

    /// @inheritdoc IRiskEngine
    function isDefaulter(address borrower) public view returns (bool) {
        if (address(badgeSbt) == address(0)) return false;

        try badgeSbt.hasBadge(borrower) returns (bool has) {
            return has;
        } catch {
            return false;
        }
    }

    /// @inheritdoc IRiskEngine
    function collateralRatioBps(address borrower) public view returns (uint16) {
        uint16 score = 0;

        if (address(scoreSbt) != address(0)) {
            try scoreSbt.scoreOf(borrower) returns (uint16 s) {
                score = s;
            } catch {}
        }

        return _ratioFromScore(score);
    }

    /// @inheritdoc IRiskEngine
    function maxBorrow(address borrower, address) external view returns (uint256) {
        if (isDefaulter(borrower)) return 0;

        uint16 ratioBps = collateralRatioBps(borrower);
        if (ratioBps == 0) return maxBorrowNoCollateral;

        return type(uint256).max;
    }

    /// @inheritdoc IRiskEngine
    function assessBorrow(address borrower, Types.BorrowRequest calldata req)
        external
        view
        returns (Types.RiskResult memory)
    {
        if (isDefaulter(borrower)) {
            return Types.RiskResult({
                allowed: false, collateralRatioBps: collateralRatioBps(borrower), maxBorrow: 0, reason: "DEFAULTER"
            });
        }

        if (address(verifier) != address(0)) {
            if (requireProof && req.proof.length == 0) {
                return Types.RiskResult({
                    allowed: false,
                    collateralRatioBps: collateralRatioBps(borrower),
                    maxBorrow: 0,
                    reason: "MISSING_PROOF"
                });
            }

            if (req.proof.length != 0) {
                bool ok = false;
                try verifier.verify(borrower, req.proof) returns (bool v) {
                    ok = v;
                } catch {}

                if (!ok) {
                    return Types.RiskResult({
                        allowed: false,
                        collateralRatioBps: collateralRatioBps(borrower),
                        maxBorrow: 0,
                        reason: "BAD_PROOF"
                    });
                }
            }
        }

        uint16 ratioBps = collateralRatioBps(borrower);
        (bool okCollateral, uint256 maxBorrowAmount, string memory reason) =
            _maxBorrowFromCollateral(req.asset, req.collateralAsset, req.collateralAmount, ratioBps);

        if (!okCollateral) {
            return Types.RiskResult({allowed: false, collateralRatioBps: ratioBps, maxBorrow: 0, reason: reason});
        }

        if (req.amount > maxBorrowAmount) {
            return Types.RiskResult({
                allowed: false, collateralRatioBps: ratioBps, maxBorrow: maxBorrowAmount, reason: "LIMIT"
            });
        }

        return Types.RiskResult({allowed: true, collateralRatioBps: ratioBps, maxBorrow: maxBorrowAmount, reason: ""});
    }

    function _ratioFromScore(uint16 score) internal pure returns (uint16) {
        // Simple linear curve:
        // score 0     -> 150% collateral
        // score >=800 -> 0% collateral (no-collateral tier)
        uint256 scoreFree = 800;
        if (score >= scoreFree) return 0;

        uint256 ratioMax = 15_000;
        uint256 remaining = scoreFree - uint256(score);

        // Ceil division to avoid reaching "too lenient" ratios early due to integer rounding.
        uint256 numerator = ratioMax * remaining;
        uint256 ratio = (numerator + scoreFree - 1) / scoreFree;

        return uint16(ratio);
    }

    function _maxBorrowFromCollateral(
        address debtAsset,
        address collateralAsset,
        uint256 collateralAmount,
        uint16 collateralRatioBps_
    ) internal view returns (bool ok, uint256 maxBorrowAmount, string memory reason) {
        if (collateralRatioBps_ == 0) {
            return (true, maxBorrowNoCollateral, "");
        }

        if (collateralAsset == address(0) || collateralAmount == 0) {
            return (false, 0, "NO_COLLATERAL");
        }

        if (address(oracle) == address(0)) {
            return (false, 0, "NO_ORACLE");
        }

        (bool okPrice, uint256 price, uint8 decimals) = _getOraclePrice(collateralAsset, debtAsset);
        if (!okPrice) return (false, 0, "BAD_PRICE");

        uint256 scale = _pow10(decimals);
        if (scale == 0) return (false, 0, "BAD_DECIMALS");

        uint256 collateralValueInDebtAsset = Math.mulDiv(collateralAmount, price, scale);
        uint256 maxByCollateral = Math.mulDiv(collateralValueInDebtAsset, BPS, uint256(collateralRatioBps_));

        return (true, maxByCollateral, "");
    }

    function _getOraclePrice(address base, address quote)
        internal
        view
        returns (bool ok, uint256 price, uint8 decimals)
    {
        try oracle.getPrice(base, quote) returns (uint256 p, uint8 d) {
            if (p == 0) return (false, 0, 0);
            return (true, p, d);
        } catch {
            return (false, 0, 0);
        }
    }

    function _pow10(uint8 decimals) internal pure returns (uint256) {
        if (decimals > 77) return 0;
        return 10 ** uint256(decimals);
    }
}
