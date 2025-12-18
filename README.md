# Undercollateralized Lending DeSoSoc

## Что это
Учебный прототип lending-протокола на Solidity (with Foundry), который:
- начинает с **overcollateralized** займов,
- постепенно снижает требования к залогу на основе **репутации**,
- поддерживает “чёрную метку” дефолтера,
- построен модульно, чтобы позже подключать **оракулы**, **новые метрики** и **ZK/KYC**.

## Основная идея
Репутация накапливается через успешные погашения. По мере роста `score` (через SBT) протокол снижает collateral ratio и повышает доступный лимит.

При дефолте адрес получает `BlackBadgeSBT` (SBT), после чего политика по умолчанию запрещает новые займы.

## Архитектура (high-level)
- `src/core/LendingPool.sol` — core (UUPS Proxy + Impl), lifecycle займа + money-flow
- `src/modules/RiskEngine.sol` — политика допуска/залога (можно заменить через интерфейс)
- `src/modules/InterestModelLinear.sol` — модель долга (APR + penalty APR)
- `src/tokens/CreditScoreSBT.sol` — soulbound “кредитный скор”
- `src/tokens/BlackBadgeSBT.sol` — soulbound “чёрная метка” дефолтера

Упрощения v0 (важно): один ERC20 `token` используется и как актив займа, и как залог; оракулы/верификаторы/хуки сейчас не включены.

## Быстрый старт (Foundry)
```bash
forge install
forge remappings > remappings.txt

forge fmt
forge build
forge test -vvv
```

Если среда без сети, можно добавить `--offline` к `forge build/test`.

## Документация
- [`docs/ADR.md`](docs/ADR.md) — принятые архитектурные решения
- [`docs/HOW_TO.md`](docs/HOW_TO.md) — окружение, тесты, локальный smoke-run
