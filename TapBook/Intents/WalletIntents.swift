import AppIntents
import Foundation

// MARK: - AppEnum for Category Selection in Shortcuts / Siri

enum SpendingCategoryAppEnum: String, AppEnum {
    case dining
    case transport
    case shopping
    case groceries
    case convenience
    case coffee
    case entertainment
    case bills
    case health
    case octopusTopUp
    case other

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "分類 / Category")
    }

    static var caseDisplayRepresentations: [SpendingCategoryAppEnum: DisplayRepresentation] {
        [
            .dining: DisplayRepresentation(title: "餐飲 / Dining", image: .init(systemName: "fork.knife")),
            .transport: DisplayRepresentation(title: "交通 / Transport", image: .init(systemName: "tram.fill")),
            .shopping: DisplayRepresentation(title: "購物 / Shopping", image: .init(systemName: "bag.fill")),
            .groceries: DisplayRepresentation(title: "超市日用 / Groceries", image: .init(systemName: "cart.fill")),
            .convenience: DisplayRepresentation(title: "便利店 / Convenience", image: .init(systemName: "storefront.fill")),
            .coffee: DisplayRepresentation(title: "咖啡飲品 / Coffee", image: .init(systemName: "cup.and.saucer.fill")),
            .entertainment: DisplayRepresentation(title: "娛樂 / Entertainment", image: .init(systemName: "film.fill")),
            .bills: DisplayRepresentation(title: "帳單雜費 / Bills", image: .init(systemName: "doc.text.fill")),
            .health: DisplayRepresentation(title: "醫療保健 / Health", image: .init(systemName: "cross.case.fill")),
            .octopusTopUp: DisplayRepresentation(title: "八達通增值 / Octopus Top-Up", image: .init(systemName: "creditcard.and.123")),
            .other: DisplayRepresentation(title: "其他 / Other", image: .init(systemName: "ellipsis.circle.fill"))
        ]
    }

    var spendingCategory: SpendingCategory {
        SpendingCategory(rawValue: rawValue) ?? .other
    }
}

// MARK: - Apple Wallet Auto-Log Intent (used by iOS Shortcuts Transaction Automation)

struct LogWalletTransactionIntent: AppIntent {
    static var title: LocalizedStringResource = "記錄 Apple Wallet 交易 / Log Apple Wallet Transaction"
    static var description = IntentDescription(
        "配合 iOS「捷徑」的 Apple Wallet 交易自動化，在背景自動記帳並分類。/ Automatically log an Apple Wallet tap transaction in the background."
    )
    static var openAppWhenRun: Bool = false
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(
        title: "金額 / Amount",
        description: "直接填入 Apple Wallet 交易的「Amount」（原生貨幣格式）"
    )
    var amount: IntentCurrencyAmount?

    @Parameter(
        title: "商戶 / Merchant",
        description: "商戶名稱，會用來自動分類"
    )
    var merchant: String?

    @Parameter(
        title: "卡片或帳戶 / Card or Account",
        description: "Apple Wallet 卡片名稱（例如 Visa、Mastercard、AE、八達通）"
    )
    var cardName: String?

    @Parameter(
        title: "備用金額文字 / Amount Text (Optional)",
        description: "如使用純文字或數字格式金額可填此欄"
    )
    var amountText: String?

    @Parameter(
        title: "分類（可留空自動分類）/ Category (Optional)"
    )
    var category: SpendingCategoryAppEnum?

    static var parameterSummary: some ParameterSummary {
        Summary("自動記帳 \(\.$merchant) \(\.$amount)（\(\.$cardName)）") {
            \.$category
            \.$amountText
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let rawMerchant = merchant ?? ""
        let rawCard = cardName ?? ""
        let logPendingZero = UserDefaults.standard.object(forKey: "tapbook_log_pending_zero") as? Bool ?? true

        let resolvedAmount: Double?
        let resolvedCurrency: String

        if let currencyAmount = amount {
            resolvedAmount = abs(NSDecimalNumber(decimal: currencyAmount.amount).doubleValue)
            resolvedCurrency = currencyAmount.currencyCode
        } else if let text = amountText, !text.isEmpty {
            resolvedAmount = PersistenceController.parseAmount(from: text)
            resolvedCurrency = "HKD"
        } else {
            resolvedAmount = nil
            resolvedCurrency = "HKD"
        }

        let amountDebug = amount.map { "\($0.currencyCode) \($0.amount)" } ?? (amountText ?? "nil")

        let record = PersistenceController.shared.autoLogWalletTransaction(
            numericAmount: resolvedAmount,
            merchant: rawMerchant,
            cardName: rawCard,
            explicitCategory: category?.spendingCategory,
            source: .appleWallet,
            currencyCode: resolvedCurrency,
            allowPendingZero: logPendingZero
        )

        guard let record else {
            PersistenceController.shared.appendDebugLog(
                "Skipped | amount=\(amountDebug) merchant='\(rawMerchant)' card='\(rawCard)'"
            )
            return .result(dialog: "略過 $0 拍卡紀錄。/ Skipped $0 tap.")
        }

        if record.amount == 0 {
            PersistenceController.shared.appendDebugLog(
                "Pending $0 | amount=\(amountDebug) merchant='\(record.merchant)' card='\(rawCard)' -> \(record.accountName)"
            )
            return .result(
                dialog: "已記錄待補金額：\(record.merchant)（\(record.accountName)）"
            )
        }

        PersistenceController.shared.appendDebugLog(
            "Logged \(record.currencyCode) \(String(format: "%.2f", record.amount)) | merchant='\(record.merchant)' card='\(rawCard)' -> \(record.accountName)"
        )
        let symbol = record.currencyCode == "HKD" ? "HK$" : "\(record.currencyCode) "
        let formatted = String(format: "\(symbol)%.2f", record.amount)
        return .result(
            dialog: "已記帳 \(record.merchant) \(formatted)（\(record.accountName)）"
        )
    }
}

// MARK: - Payment Notification Auto-Log Intent (Octopus, Wallet, PayMe, AlipayHK, Banks)

struct LogFromNotificationIntent: AppIntent {
    static var title: LocalizedStringResource = "從付款通知自動記帳 / Log From Payment Notification"
    static var description = IntentDescription(
        "配合 iOS「捷徑」的通知自動化（錢包 / 八達通 / PayMe / AlipayHK / 銀行 App），自動解析消費金額與商戶並背景記帳。/ Parse payment notifications from Wallet, Octopus, PayMe, AlipayHK, or HK banks and log automatically."
    )
    static var openAppWhenRun: Bool = false
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(
        title: "通知標題 / Notification Title",
        description: "填入捷徑通知的「標題」（例如 Octopus、PayMe、AlipayHK、商戶名）"
    )
    var title: String?

    @Parameter(
        title: "通知副標題 / Notification Subtitle",
        description: "填入捷徑通知的「副標題」（Apple Wallet 八達通的「消費：HK$31.00」在此欄！）"
    )
    var subtitle: String?

    @Parameter(
        title: "通知內容 / Notification Body",
        description: "填入捷徑通知的「內文」（例如：你的新餘額為 HK$64.10。）"
    )
    var body: String?

    @Parameter(
        title: "來源 App（可選）/ Source App (Optional)",
        description: "如捷徑有提供 App 名稱可填入"
    )
    var appName: String?

    static var parameterSummary: some ParameterSummary {
        Summary("解析付款通知 \(\.$title) \(\.$subtitle) \(\.$body)") {
            \.$appName
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let rawTitle = title ?? ""
        let rawSubtitle = subtitle ?? ""
        let rawBody = body ?? ""
        let rawApp = appName ?? ""

        guard let parsed = NotificationParser.parse(
            title: rawTitle,
            subtitle: rawSubtitle,
            body: rawBody,
            appName: rawApp
        ) else {
            PersistenceController.shared.appendDebugLog(
                "Notif ignored | title='\(rawTitle)' sub='\(rawSubtitle)' body='\(rawBody.replacingOccurrences(of: "\n", with: " "))'"
            )
            return .result(dialog: "非消費通知，已略過。/ Non-expense notification ignored.")
        }

        let record = PersistenceController.shared.autoLogWalletTransaction(
            numericAmount: parsed.amount,
            merchant: parsed.merchant,
            cardName: parsed.accountHint,
            explicitCategory: parsed.categoryOverride,
            source: .appleWallet,
            currencyCode: parsed.currencyCode,
            allowPendingZero: false
        )

        guard let record else {
            return .result(dialog: "已略過重複紀錄。/ Duplicate skipped.")
        }

        PersistenceController.shared.appendDebugLog(
            "Notif Logged \(record.currencyCode) \(String(format: "%.2f", record.amount)) | merchant='\(record.merchant)' -> \(record.accountName)"
        )
        let symbol = record.currencyCode == "HKD" ? "HK$" : "\(record.currencyCode) "
        let formatted = String(format: "\(symbol)%.2f", record.amount)
        return .result(
            dialog: "已記帳 \(record.merchant) \(formatted)（\(record.accountName)）"
        )
    }
}

// MARK: - Quick Siri / Action Button Intent (Ideal for 八達通 / Cash)

struct LogQuickExpenseIntent: AppIntent {
    static var title: LocalizedStringResource = "快速記帳 / Quick Log Expense"
    static var description = IntentDescription(
        "用 Siri、捷徑或 Action Button 快速記一筆八達通或現金消費。/ Quickly log an Octopus or cash expense via Siri or Action Button."
    )
    static var openAppWhenRun: Bool = false
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(title: "金額 (HK$) / Amount", requestValueDialog: "今次使咗幾多錢？ / How much did you spend?")
    var amount: Double

    @Parameter(title: "商戶或項目 / Merchant", default: "八達通消費")
    var merchant: String

    @Parameter(title: "帳戶 / Account", default: "八達通")
    var accountName: String

    @Parameter(title: "分類 / Category")
    var category: SpendingCategoryAppEnum?

    static var parameterSummary: some ParameterSummary {
        Summary("用 \(\.$accountName) 記帳 \(\.$merchant) HK$\(\.$amount)") {
            \.$category
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let record = PersistenceController.shared.autoLogWalletTransaction(
            rawAmount: String(amount),
            merchant: merchant,
            cardName: accountName,
            explicitCategory: category?.spendingCategory,
            source: .siri
        )

        guard let record else {
            return .result(dialog: "金額無效。/ Invalid amount.")
        }

        let formatted = String(format: "HK$%.2f", record.amount)
        return .result(
            dialog: "已記錄 \(record.accountName) 消費：\(record.merchant) \(formatted)"
        )
    }
}

// MARK: - App Shortcuts Provider

struct TapBookShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogQuickExpenseIntent(),
            phrases: [
                "用 \(.applicationName) 記帳",
                "喺 \(.applicationName) 記一筆",
                "Log expense in \(.applicationName)",
                "Quick log with \(.applicationName)"
            ],
            shortTitle: "快速記帳 / Quick Log",
            systemImageName: "plus.circle.fill"
        )
    }
}
