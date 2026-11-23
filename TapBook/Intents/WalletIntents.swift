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

    @Parameter(
        title: "金額 / Amount",
        description: "由 Apple Wallet 交易傳入的金額（支援 HK$45.00 或純數字）"
    )
    var amount: String?

    @Parameter(
        title: "商戶 / Merchant",
        description: "商戶名稱，會用來自動分類"
    )
    var merchant: String?

    @Parameter(
        title: "卡片或帳戶 / Card or Account",
        description: "Apple Wallet 卡片名稱（例如 Visa、Mastercard、AE、HSBC）"
    )
    var cardName: String?

    @Parameter(
        title: "分類（可留空自動分類）/ Category (Optional)"
    )
    var category: SpendingCategoryAppEnum?

    static var parameterSummary: some ParameterSummary {
        Summary("自動記帳 \(\.$merchant) \(\.$amount)（\(\.$cardName)）") {
            \.$category
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let rawAmount = amount ?? ""
        let rawMerchant = merchant ?? ""
        let rawCard = cardName ?? ""

        let record = PersistenceController.shared.autoLogWalletTransaction(
            rawAmount: rawAmount,
            merchant: rawMerchant,
            cardName: rawCard,
            explicitCategory: category?.spendingCategory,
            source: .appleWallet
        )

        guard let record else {
            PersistenceController.shared.appendDebugLog(
                "Skipped | amount='\(rawAmount)' merchant='\(rawMerchant)' card='\(rawCard)'"
            )
            return .result(dialog: "無法辨識金額（收到：\(rawAmount)），未記帳。/ Could not parse amount.")
        }

        PersistenceController.shared.appendDebugLog(
            "Logged HK$\(String(format: "%.2f", record.amount)) | merchant='\(record.merchant)' card='\(rawCard)' -> \(record.accountName)"
        )
        let formatted = String(format: "HK$%.2f", record.amount)
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
