// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {Types} from "../utils/Types.sol";
import {ICreditScoreSBT} from "../interfaces/ICreditScoreSBT.sol";
import {IDefaultBadgeSBT} from "../interfaces/IDefaultBadgeSBT.sol";
import {IIdentityVerifier} from "../interfaces/IIdentityVerifier.sol";
import {IPriceOracle} from "../interfaces/IPriceOracle.sol";
import {IRiskEngine} from "../interfaces/IRiskEngine.sol";

/// @title RiskEngineSimple
/// @notice v0 placeholder risk engine with a score->collateral ratio ladder.
contract RiskEngineSimple is IRiskEngine, Ownable {
    /// @notice Credit score SBT dependency (optional).
    ICreditScoreSBT public scoreSbt;

    /// @notice Default badge SBT dependency (optional).
    IDefaultBadgeSBT public badgeSbt;

    /// @notice Identity verifier dependency (optional).
    IIdentityVerifier public verifier;

    /// @notice Price oracle dependency (optional).
    IPriceOracle public oracle;

    /// @notice Emitted when dependencies are updated.
    event DependenciesUpdated(address scoreSbt, address badgeSbt, address verifier, address oracle);

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

        if (address(verifier) != address(0) && req.proof.length != 0) {
            bool ok = verifier.verify(borrower, req.proof);
            if (!ok) {
                return Types.RiskResult({
                    allowed: false, collateralRatioBps: collateralRatioBps(borrower), maxBorrow: 0, reason: "BAD_PROOF"
                });
            }
        }

        uint256 maxBorrowAmount = req.amount;
        if (maxBorrowAmount <= type(uint256).max / 10) {
            maxBorrowAmount = req.amount * 10;
        } else {
            maxBorrowAmount = type(uint256).max;
        }

        return Types.RiskResult({
            allowed: true, collateralRatioBps: collateralRatioBps(borrower), maxBorrow: maxBorrowAmount, reason: ""
        });
    }

    function _ratioFromScore(uint16 score) internal pure returns (uint16) {
        if (score < 100) return 15_000;
        if (score < 300) return 12_000;
        if (score < 600) return 10_000;
        if (score < 800) return 8_000;
        return 0;
    }
}
