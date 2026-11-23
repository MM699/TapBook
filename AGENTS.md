# AGENTS.md — TapBook

Guidance for AI coding agents and contributors working on **TapBook**.

## Project Overview

**TapBook** is a native iOS expense tracking app designed for Hong Kong users, built with SwiftUI, SwiftData, Swift Charts, and App Intents. It supports background auto-logging from Apple Wallet via iOS Shortcuts Transaction Automation, 1-tap quick logging for Octopus (八達通), Hong Kong merchant auto-categorization, and live bilingual switching (**繁體中文（香港）** / **English**).

## Tech Stack & Requirements

- **Language / Frameworks**: Swift 5, SwiftUI, SwiftData, Swift Charts, AppIntents, UserNotifications
- **Minimum Deployment Target**: iOS 17.0
- **Project Format**: Xcode 16+ (`objectVersion = 77`, `PBXFileSystemSynchronizedRootGroup`) — files placed under `TapBook/` are automatically included in the target without editing `project.pbxproj`.
- **Default Currency**: HKD (`HK$`)
- **Languages**: Traditional Chinese (Hong Kong, `zh-HK`) and English (`en`)

## Repository Structure

```text
TapBook/
├── TapBook.xcodeproj/          # Xcode project (file-system synchronized)
├── TapBook/
│   ├── TapBookApp.swift        # App entry point, TabView, notification delegate
│   ├── Models/
│   │   └── Models.swift        # SwiftData @Model types & domain enums
│   ├── Services/
│   │   ├── PersistenceController.swift  # Shared ModelContainer, seeding, migrations, auto-categorizer, notifications, CSV export, debug log
│   │   └── Localization.swift  # LanguageStore (zh-HK / en / system), currency & date formatting
│   ├── Intents/
│   │   └── WalletIntents.swift # LogWalletTransactionIntent, LogQuickExpenseIntent, TapBookShortcuts
│   ├── Views/
│   │   ├── HomeView.swift      # Overview, monthly budget card, quick templates, search/filter, transaction editor
│   │   ├── AnalyticsView.swift # Monthly Swift Charts breakdown by category & account
│   │   ├── AccountsView.swift  # Cards/accounts with Apple Wallet match keywords & quick template manager
│   │   └── SettingsView.swift  # Shortcuts setup guide, simulator tap test, debug log, rules, budget, language, CSV export
│   └── Assets.xcassets/        # AppIcon (1024x1024) & AccentColor
├── README.md
├── AGENTS.md
└── DECISIONS.md
```

## Build & Verification

Verify builds for iOS Simulator from the repository root:

```bash
xcodebuild \
  -project TapBook.xcodeproj \
  -scheme TapBook \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/TapBookDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## Coding Conventions & Invariants

1. **Bilingual UI**: Every user-facing string MUST provide both Hong Kong Traditional Chinese and English via `lang.t("繁體中文", "English")` or `displayName(isChinese:)`. Use authentic Hong Kong phrasing (e.g., 尋日、八達通、港鐵、九巴、增值、餐飲、記帳).
2. **Background AppIntents Resilience**: All parameters in `LogWalletTransactionIntent` (`amount`, `merchant`, `cardName`, `category`) MUST remain **optional** so background Shortcuts automations never stall waiting for user input when a POS terminal omits merchant or card metadata.
3. **Shared Persistence**: Both SwiftUI views and `AppIntents` MUST use `PersistenceController.shared.container` to prevent split stores or stale reads.
4. **Idempotent Migrations**: When updating seeded accounts or default merchant rules, add a versioned `UserDefaults` migration in `PersistenceController` so existing iPhone installs upgrade cleanly without deleting user data.
5. **Debuggability**: Any change to `LogWalletTransactionIntent` should preserve `PersistenceController.shared.appendDebugLog(...)` entries so physical-device Shortcuts issues remain diagnosable in Settings.
6. **Zero External Dependencies**: Prefer Apple first-party frameworks only (no SPM/CocoaPods dependencies unless explicitly requested).

## Git Workflow

- Default branch: `main`
- Keep `.DS_Store`, `xcuserdata/`, and build artifacts out of version control (enforced by `.gitignore`).
- Record significant architectural or behavioral changes in `DECISIONS.md`.
