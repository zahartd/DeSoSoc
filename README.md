# Undercollateralized Lending DeSoSoc

## Что это
Учебный прототип lending-протокола на Solidity (with Foundry), который:
- начинает с **overcollateralized** займов,
- постепенно снижает требования к залогу на основе **репутации**,
- поддерживает “чёрную метку” дефолтера,
- построен модульно, чтобы позже подключать **оракулы**, **новые метрики** и **ZK/KYC**.

## Основная идея
Репутация накапливается через успешные погашения. По мере роста `score` (через SBT) протокол снижает collateral ratio и повышает доступный лимит.

При дефолте адрес получает `DefaultBadge` (SBT), после чего политика по умолчанию запрещает новые займы.

## Архитектура (high-level)
- `LendingPool` — core (UUPS Proxy + Impl), хранит займы и исполняет операции
- `RiskEngine` — политика доступа/залога (легко заменить)
- `InterestModel` — модель начисления долга (например `InterestModelLinear`)
- `CreditScoreSBT` — soulbound “кредитный скор”
- `DefaultBadgeSBT` — soulbound “дефолтер” (в коде: `BlackBadgeSBT`)
- опционально: `PriceOracle` и `IdentityVerifier` (в текущей версии убрано)

## Документация
- [`docs/ADR.md`](docs/ADR.md) — принятые архитектурные решения
- [`docs/HOW_TO.md`](docs/HOW_TO.md) — окружение, тесты, деплой, верификация
