# Undercollateralized Lending v0 (Architecture Decision Record)

## Контекст и цель
Мы делаем учебный прототип lending-протокола, который:
- стартует с **overcollateralized** займов;
- затем, по мере накопления репутации, снижает требования к залогу вплоть до **undercollateralized / zero-collateral**;
- хранит репутацию через **SBT** (Soulbound Tokens);
- использует модульные политики (risk / interest / oracle / identity), чтобы легко добавлять новые метрики, оракулы и ZK-верификацию.

## Решение v0 (ключевые решения)
### 1) Модульная архитектура (Policy Layer)
**Core (LendingPool)** отвечает только за жизненный цикл займа и хранение state.

Вся “логика политики” вынесена в модули по интерфейсам:
- `IRiskEngine` — требования по залогу / лимитам / проверка допуска к займу
- `IInterestModel` — расчет долга во времени (APR/penalty/прочее)
- `IPriceOracle` — (опционально) цены залога/долга
- `IIdentityVerifier` — (опционально) KYC/ZK/anti-sybil (верификация proof)

**Почему:** позволяет расширять систему (oracle/ZK/новые метрики) заменой модулей без переписывания Core.

### 2) Репутация через SBT
Мы используем два SBT:
1) **CreditScoreSBT** — 1 токен на адрес; хранит/экспортирует `score`.
   - Mint один раз
   - Score обновляется протоколом (или уполномоченным модулем)
2) **DefaultBadgeSBT** — “чёрная метка” для дефолтера (1 токен на адрес)
   - Mint при дефолте
   - По v0: не снимается (в будущем можно добавить амнистию/выкуп как отдельную политику)

**SBT-совместимость:** реализуем non-transferable ERC-721 + (опционально) интерфейс **EIP-5192** “Minimal Soulbound NFTs” (`locked(tokenId)` + событие `Locked`). EIP-5192 описывает минимальный интерфейс soulbound NFT как расширение ERC-721. https://eips.ethereum.org/EIPS/eip-5192

### 3) Upgradeability
Core (`LendingPool`) делаем **upgradeable через proxy** (выбран UUPS), потому что:
- хотим показывать best practices proxy-pattern;
- хотим иметь возможность менять storage/flow, если потребуется.

Правила для upgradeable-контрактов:
- **нет конструкторов**, вместо них **initializer**;
- важно соблюдать ограничения upgradeable-контрактов и storage layout;
- рекомендуется защищать имплементацию от повторной инициализации (например `_disableInitializers()` в имплементации).

### 4) Access Control (RBAC)
Используем `AccessControlUpgradeable` и роли:
- `DEFAULT_ADMIN_ROLE` — выдача ролей
- `UPGRADER_ROLE` — апгрейды (в `_authorizeUpgrade`)
- `RISK_ADMIN_ROLE` — смена RiskEngine/настройки шкал
- `TREASURY_ROLE` — управление источниками ликвидности (если будет нужно)
- `PAUSER_ROLE` — аварийная пауза (опционально)

### 5) Минимальный протокольный flow (MVP)
- Пользователь **без репутации** берёт займ только с высоким collateral ratio (например 150%)
- После 1..N успешных погашений `score` растёт -> `IRiskEngine` снижает требование по залогу
- При достижении порога -> допускаем undercollateralized или zero-collateral
- При дефолте:
  - mint `DefaultBadgeSBT`
  - `IRiskEngine` запрещает будущие займы (или переводит в самый строгий режим)

## Диаграмма (v0)
```mermaid
flowchart LR
  User((Borrower / Lender)) -->|deposit, borrow, repay| Pool[LendingPool<br/>Proxy + Impl]
  Pool --> Risk[IRiskEngine]
  Pool --> Interest[IInterestModel]
  Risk --> Score[CreditScoreSBT]
  Risk --> Badge[DefaultBadgeSBT]
  Risk -. optional .-> Oracle[IPriceOracle]
  Risk -. optional .-> ID[IIdentityVerifier<br/>ZK or KYC]
  Pool -->|mint / update| Score
  Pool -->|mint| Badge
