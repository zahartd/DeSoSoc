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
# Возьми адреса из вывода anvil (Accounts) или через: cast rpc eth_accounts --rpc-url $RPC_URL
export OWNER="0x..."
export BORROWER="0x..."
export TREASURY=$OWNER

# Если деплоишь не в Anvil (аккаунты не unlocked), используй приватные ключи:
# export OWNER_PK="0x..."
# export BORROWER_PK="0x..."
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

### Команды (по шагам)
1) `ERC20Mock`
```bash
forge create lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol:ERC20Mock \
  --rpc-url $RPC_URL --unlocked --from $OWNER --broadcast

export TOKEN="0x..."
```

2) `CreditScoreSBT` + `BlackBadgeSBT`
```bash
forge create src/tokens/CreditScoreSBT.sol:CreditScoreSBT \
  --rpc-url $RPC_URL --unlocked --from $OWNER --broadcast \
  --constructor-args $OWNER
export SCORE_SBT="0x..."

forge create src/tokens/BlackBadgeSBT.sol:BlackBadgeSBT \
  --rpc-url $RPC_URL --unlocked --from $OWNER --broadcast \
  --constructor-args $OWNER
export BADGE_SBT="0x..."
```

3) `RiskEngine` + `InterestModelLinear`
```bash
export MAX_BORROW_NO_COLLATERAL=1000000000000000000000

forge create src/modules/RiskEngine.sol:RiskEngine \
  --rpc-url $RPC_URL --unlocked --from $OWNER --broadcast \
  --constructor-args $SCORE_SBT $BADGE_SBT $MAX_BORROW_NO_COLLATERAL
export RISK_ENGINE="0x..."

forge create src/modules/InterestModelLinear.sol:InterestModelLinear \
  --rpc-url $RPC_URL --unlocked --from $OWNER --broadcast \
  --constructor-args 1000 2000
export INTEREST_MODEL="0x..."
```

4) `LendingPool` implementation
```bash
forge create src/core/LendingPool.sol:LendingPool \
  --rpc-url $RPC_URL --unlocked --from $OWNER --broadcast
export POOL_IMPL="0x..."
```

5) `ERC1967Proxy` + initialize calldata
```bash
export INIT_DATA=$(cast calldata \
  "initialize(address,address,address,address,address,address,address)" \
  $OWNER $TOKEN $RISK_ENGINE $SCORE_SBT $BADGE_SBT $INTEREST_MODEL $TREASURY)

forge create lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy \
  --rpc-url $RPC_URL --unlocked --from $OWNER --broadcast \
  --constructor-args $POOL_IMPL $INIT_DATA
export POOL="0x..."
```

Проверка, что прокси инициализировался:
```bash
cast call $POOL "owner()(address)" --rpc-url $RPC_URL
```

6) Передать ownership SBT → `LendingPool` (proxy)
```bash
cast send $SCORE_SBT "transferOwnership(address)" $POOL --rpc-url $RPC_URL --unlocked --from $OWNER
cast send $BADGE_SBT "transferOwnership(address)" $POOL --rpc-url $RPC_URL --unlocked --from $OWNER
```

7) Liquidity + borrow/repay (минимальный smoke)
```bash
cast send $TOKEN "mint(address,uint256)" $OWNER 1000000000000000000000 --rpc-url $RPC_URL --unlocked --from $OWNER
cast send $TOKEN "approve(address,uint256)" $POOL 1000000000000000000000 --rpc-url $RPC_URL --unlocked --from $OWNER
cast send $POOL "depositLiquidity(uint256)" 1000000000000000000000 --rpc-url $RPC_URL --unlocked --from $OWNER

cast send $TOKEN "mint(address,uint256)" $BORROWER 1000000000000000000000 --rpc-url $RPC_URL --unlocked --from $OWNER
cast send $TOKEN "approve(address,uint256)" $POOL 1000000000000000000000 --rpc-url $RPC_URL --unlocked --from $BORROWER

cast send $POOL "borrow(uint256,uint256,uint64)" 100000000000000000000 150000000000000000000 172800 --rpc-url $RPC_URL --unlocked --from $BORROWER

cast call $POOL "getDebt(address)(uint256)" $BORROWER --rpc-url $RPC_URL
cast send $POOL "repay(uint256)" 200000000000000000000 --rpc-url $RPC_URL --unlocked --from $BORROWER
```

## Notes (v0 assumptions)
- Один активный займ на заёмщика (`loanOf[borrower]`).
- Один ERC20 `token` используется и для займа, и для залога.