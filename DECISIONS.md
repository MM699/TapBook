# DECISIONS.md — TapBook Architecture Decision Records

This document records key technical and product decisions made for **TapBook** and the rationale behind them.

---

## ADR-001: Apple Wallet Auto-Logging via iOS Shortcuts + `AppIntents`

- **Status**: Accepted
- **Context**: iOS does not expose a public SDK (`PassKit` or `FinanceKit` outside US Apple Card/Cash) for third-party apps to read Apple Wallet / Apple Pay transactions in the background.
- **Decision**: Expose `LogWalletTransactionIntent` (`openAppWhenRun = false`) via Apple's `AppIntents` framework, paired with an in-app step-by-step guide for configuring iOS Shortcuts' **Transaction (Wallet)** personal automation (`Run Immediately`).
- **Consequences**:
  - Works natively in the background on physical NFC Apple Pay taps without opening the app.
  - Requires a one-time manual automation setup by the user in Apple's Shortcuts app (Apple restricts apps from programmatically creating automations).
  - Online/in-app Apple Pay and Apple Watch taps are not triggered by iPhone Shortcuts Transaction automations (platform limitation).

---

## ADR-002: Optional Parameters in `LogWalletTransactionIntent`

- **Status**: Accepted
- **Context**: Real-world Hong Kong POS terminals (especially American Express / AE terminals and offline readers) occasionally omit `Merchant` or pass empty strings when firing Shortcuts Transaction automations. Non-optional `@Parameter` properties cause `AppIntents` to stall or silently fail in the background while waiting for user input.
- **Decision**: Declare `amount`, `merchant`, `cardName`, and `category` as optional parameters in `LogWalletTransactionIntent`, with resilient string parsing (`HK$`, `$`, commas, regex fallback) and a safe default merchant (`"Apple Pay"`).
- **Consequences**: Background automations always reach `perform()` cleanly instead of hanging silently.

---

## ADR-003: Hong Kong Octopus (八達通) Strategy

- **Status**: Accepted
- **Context**: In Hong Kong, iPhone Octopus triggers Shortcuts Transaction automations inconsistently: non-deducting taps (MTR gate entry, building door access, fare saver stations) emit `$0` or empty amounts, while retail/exit taps may or may not pass complete merchant data.
- **Decision**:
  1. Ignore `$0` / empty-amount taps by default to avoid polluting the ledger with MTR entries and door-access taps.
  2. Provide **1-Tap Quick Templates** on the Home screen (MTR, Bus, 7-Eleven, Lunch) and **Siri Quick Log** (`LogQuickExpenseIntent`) for fast manual fallback.
  3. Restrict default `octopusTopUp` auto-categorization rules to explicit top-up keywords (`add value`, `top up`, `top-up`, `aavs`, `增值`) so regular Octopus spending is not misclassified as top-ups.
- **Consequences**: Clean ledger with zero door-access noise and accurate top-up vs. spending categorization.

---

## ADR-004: Live Bilingual Localization (`zh-HK` + `en`) via `LanguageStore`

- **Status**: Accepted
- **Context**: The app targets Hong Kong users who want both Traditional Chinese (Hong Kong vocabulary) and English, with the ability to switch languages easily inside the app.
- **Decision**: Implement an `@Observable` `LanguageStore` persisted in `UserDefaults` supporting `跟隨系統 / System`, `繁體中文（香港）`, and `English`, paired with `zh_HK` / `en_HK` locale formatters for dates and `HK$` currency.
- **Consequences**: Instant language switching in Settings without restarting the app; zero risk of missing `.strings` bundle lookup mismatches.

---

## ADR-005: Shared SwiftData Container with Idempotent Migrations

- **Status**: Accepted
- **Context**: Both the foreground SwiftUI app and background `AppIntents` executions read and write transactions, accounts, and merchant rules.
- **Decision**: Centralize storage in `PersistenceController.shared` (SwiftData `ModelContainer`) and run versioned `UserDefaults`-gated migrations on startup (e.g., migrating legacy Octopus rules, adding default `AE` account).
- **Consequences**: Single source of truth across UI and background Intents, with safe incremental upgrades on already-installed iPhones.

---

## ADR-006: Xcode `PBXFileSystemSynchronizedRootGroup` Project Format

- **Status**: Accepted
- **Context**: Maintaining manual UUID file references in `project.pbxproj` is error-prone when adding or refactoring Swift files.
- **Decision**: Use Xcode 16+ `objectVersion = 77` with `PBXFileSystemSynchronizedRootGroup` pointing at `TapBook/`.
- **Consequences**: Adding/moving Swift files or assets under `TapBook/` automatically syncs with Xcode without editing `project.pbxproj`.

---

## ADR-007: In-App Shortcuts Trigger Debug Log

- **Status**: Accepted
- **Context**: Background iOS Shortcuts automations fail silently when `Notify` is disabled, making it hard to tell whether iOS failed to fire the trigger or TapBook failed to parse the input.
- **Decision**: Record the last 15 raw `LogWalletTransactionIntent` invocations (timestamp, raw `amount`, `merchant`, `cardName`, and outcome) in `UserDefaults` and surface them in **Settings → Shortcuts Trigger Log (Debug)**.
- **Consequences**: Immediate visibility on physical devices when diagnosing card-specific issues (e.g., AE, Visa, Octopus).

---

## ADR-008: Native `IntentCurrencyAmount?` Parameter & Pending `$0` Octopus Fallback

- **Status**: Accepted
- **Context**: Using `String?` for `LogWalletTransactionIntent.amount` caused iOS Shortcuts' Wallet `Transaction.Amount` (a native currency amount object) to coerce to an empty string on device, resulting in missed logs for both credit cards and Octopus. Additionally, Hong Kong Octopus taps often omit `Amount` entirely.
- **Decision**:
  1. Type `LogWalletTransactionIntent.amount` as `IntentCurrencyAmount?` so Apple Wallet's `Amount` (`Decimal` + `currencyCode`) binds natively without string coercion loss, keeping an optional `amountText: String?` fallback.
  2. Add a configurable **"Log $0 / Pending Amount Taps"** option (default ON) that saves a `$0` transaction badged **"待補金額 / Needs Amount"** on the Home screen and sends a reminder notification whenever a tap (such as Octopus) arrives without an amount.
- **Consequences**: Credit card Apple Pay taps preserve exact amount and currency code (including foreign currencies), and Octopus taps are captured as 1-tap editable reminders instead of being silently dropped.

---

## ADR-009: Multi-Card Specificity Scoring & Optional Cascade on Account Rename

- **Status**: Accepted
- **Context**: Users commonly hold multiple cards on the same payment network (e.g., `HSBC Visa` and `Hang Seng Visa`, or `HSBC Visa` and `HSBC Mastercard`). First-match substring matching on `"visa"` or `"hsbc"` misrouted cards, and unconditionally renaming all past `"Visa"` records upon renaming `"Visa"` → `"HSBC Visa"` corrupted historical records from other Visa cards.
- **Decision**:
  1. Keep default network accounts (`Visa`, `Mastercard`) limited to network-only keywords (`visa`, `mastercard,master`) instead of bank names.
  2. Score candidate accounts in `matchAccount` by specificity: exact name > full account name substring > bank-specific keywords > generic network fallback (only allowed on generic network buckets or accounts that already matched their bank).
  3. Prompt the user with a confirmation dialog when renaming an account that has historical records: either cascade-rename all past records or rename the account only while preserving historical record labels.
- **Consequences**: Multiple Visa/Mastercard accounts from different banks match accurately and historical data stays safe when splitting a generic card bucket into bank-specific cards.
