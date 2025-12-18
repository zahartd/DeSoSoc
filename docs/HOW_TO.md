# HOW TO (Foundry)

## Setup
```bash
forge install
forge remappings > remappings.txt
```

## Format / Build / Test
```bash
forge fmt
forge build
forge test -vvv
```

Если среда без сети/доступ к RPC ограничен, можно запускать с `--offline`:
```bash
forge build --offline
forge test -vvv --offline
```

## Local smoke (Anvil)
Запуск локальной сети:
```bash
anvil
export RPC_URL=http://127.0.0.1:8545
export PRIVATE_KEY=0x<ANVIL_PRIVATE_KEY>
```

Дальше самый надёжный референс по деплою proxy‑сборки и порядку инициализации — это `test/LendingPool.t.sol`.

Минимальная последовательность (вручную через `forge create` / `cast`) выглядит так:
1) Деплой `ERC20Mock` (актив пула и одновременно collateral в v0).
2) Деплой `CreditScoreSBT` и `BlackBadgeSBT` (constructor принимает `initialOwner`).
3) Деплой `RiskEngine` и `InterestModelLinear`.
4) Деплой `LendingPool` (implementation).
5) Деплой `ERC1967Proxy` с `initData = abi.encodeCall(LendingPool.initialize, ...)`.
6) Передать ownership SBT → `LendingPool` proxy, чтобы core мог mint/update score/badge.
7) Mint/approve `token`, `depositLiquidity`, дальше `borrow/repay`.

## Notes (v0 assumptions)
- Один активный займ на заёмщика (`loanOf[borrower]`).
- Один ERC20 `token` используется и для займа, и для залога.
- Нет оракула/identity/hook’ов — это осознанное упрощение v0.
