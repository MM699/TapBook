import Foundation
import SwiftData
import UserNotifications

@MainActor
final class PersistenceController {
    static let shared = PersistenceController()

    let container: ModelContainer

    private init() {
        let schema = Schema([
            TransactionRecord.self,
            PaymentAccount.self,
            MerchantRule.self,
            QuickTemplate.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            self.container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create TapBook ModelContainer: \(error)")
        }
        seedInitialDataIfNeeded()
        migrateDefaultOctopusRulesIfNeeded()
        migrateDefaultAEAccountIfNeeded()
        migrateAppleStoreRuleIfNeeded()
        migrateOctopusApplePayTitlesIfNeeded()
    }

    private func migrateOctopusApplePayTitlesIfNeeded() {
        let migrationKey = "tapbook_migrated_octopus_titles_v1"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }

        let context = container.mainContext
        let descriptor = FetchDescriptor<TransactionRecord>()
        if let records = try? context.fetch(descriptor) {
            var didModify = false
            for record in records {
                let isOctopus = record.accountName.localizedCaseInsensitiveContains("八達通") ||
                    record.accountName.localizedCaseInsensitiveContains("octopus")
                if isOctopus && record.merchant == "Apple Pay" {
                    record.merchant = "八達通消費"
                    if record.category == .shopping {
                        record.category = .other
                    }
                    didModify = true
                }
                if record.amount > 0 && record.note.contains("待補金額") {
                    record.note = record.note
                        .components(separatedBy: " · ")
                        .filter { !$0.isEmpty && $0 != "待補金額" }
                        .joined(separator: " · ")
                    didModify = true
                }
            }
            if didModify {
                try? context.save()
            }
        }
        UserDefaults.standard.set(true, forKey: migrationKey)
    }

    private func migrateAppleStoreRuleIfNeeded() {
        let migrationKey = "tapbook_migrated_apple_store_rule_v1"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }

        let context = container.mainContext
        let descriptor = FetchDescriptor<MerchantRule>()
        if let rules = try? context.fetch(descriptor) {
            var didModify = false
            for rule in rules where rule.isDefault && rule.keyword.lowercased() == "apple" {
                rule.keyword = "apple store"
                didModify = true
            }
            if didModify {
                try? context.save()
            }
        }
        UserDefaults.standard.set(true, forKey: migrationKey)
    }

    private func migrateDefaultAEAccountIfNeeded() {
        let migrationKey = "tapbook_migrated_ae_account_v1"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }

        let context = container.mainContext
        let descriptor = FetchDescriptor<PaymentAccount>()
        if let accounts = try? context.fetch(descriptor) {
            let hasAE = accounts.contains {
                let lower = ($0.name + " " + $0.walletMatchKeywords).lowercased()
                return lower.contains("amex") || lower.contains("american express") || $0.name.uppercased() == "AE"
            }
            if !hasAE {
                let aeAccount = PaymentAccount(
                    name: "AE",
                    walletMatchKeywords: "amex,american express,ae,explorer,platinum,blue cash,美國運通",
                    type: .creditCard,
                    colorHex: "#0284C7",
                    iconName: "creditcard.fill",
                    sortOrder: 2
                )
                context.insert(aeAccount)
                try? context.save()
            }
        }
        UserDefaults.standard.set(true, forKey: migrationKey)
    }

    // MARK: - Shortcuts Debug Log

    private static let debugLogKey = "tapbook_shortcuts_debug_log"

    func appendDebugLog(_ entry: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm:ss"
        let line = "[\(formatter.string(from: .now))] \(entry)"
        var logs = UserDefaults.standard.stringArray(forKey: Self.debugLogKey) ?? []
        logs.insert(line, at: 0)
        if logs.count > 15 {
            logs = Array(logs.prefix(15))
        }
        UserDefaults.standard.set(logs, forKey: Self.debugLogKey)
    }

    func fetchDebugLogs() -> [String] {
        UserDefaults.standard.stringArray(forKey: Self.debugLogKey) ?? []
    }

    func clearDebugLogs() {
        UserDefaults.standard.removeObject(forKey: Self.debugLogKey)
    }

    private func migrateDefaultOctopusRulesIfNeeded() {
        let migrationKey = "tapbook_migrated_octopus_rules_v1"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }

        let context = container.mainContext
        let descriptor = FetchDescriptor<MerchantRule>()
        if let rules = try? context.fetch(descriptor) {
            let legacyKeywords: Set<String> = ["octopus", "八達通"]
            var didModify = false
            for rule in rules where rule.isDefault && legacyKeywords.contains(rule.keyword.lowercased()) {
                context.delete(rule)
                didModify = true
            }

            let existing = Set(rules.map { $0.keyword.lowercased() })
            for keyword in ["add value", "top up", "top-up", "aavs", "增值"] where !existing.contains(keyword) {
                context.insert(MerchantRule(keyword: keyword, category: .octopusTopUp, isDefault: true))
                didModify = true
            }
            if didModify {
                try? context.save()
            }
        }
        UserDefaults.standard.set(true, forKey: migrationKey)
    }

    func seedInitialDataIfNeeded() {
        let context = container.mainContext

        // 1. Seed Default Payment Accounts
        let accountDescriptor = FetchDescriptor<PaymentAccount>()
        if (try? context.fetchCount(accountDescriptor)) == 0 {
            let defaults: [PaymentAccount] = [
                PaymentAccount(
                    name: "Visa",
                    walletMatchKeywords: "visa,hsbc,hang seng,scb,standard chartered,citibank,citi,bochk,中銀,滙豐,恒生",
                    type: .creditCard,
                    colorHex: "#1E3A8A",
                    iconName: "creditcard.fill",
                    sortOrder: 0
                ),
                PaymentAccount(
                    name: "Mastercard",
                    walletMatchKeywords: "mastercard,master,mox,livi,za,red,dbs",
                    type: .creditCard,
                    colorHex: "#B91C1C",
                    iconName: "creditcard.fill",
                    sortOrder: 1
                ),
                PaymentAccount(
                    name: "AE",
                    walletMatchKeywords: "amex,american express,ae,explorer,platinum,blue cash,美國運通",
                    type: .creditCard,
                    colorHex: "#0284C7",
                    iconName: "creditcard.fill",
                    sortOrder: 2
                ),
                PaymentAccount(
                    name: "八達通",
                    walletMatchKeywords: "octopus,八達通",
                    type: .octopus,
                    colorHex: "#EA580C",
                    iconName: "wave.3.right",
                    sortOrder: 3
                ),
                PaymentAccount(
                    name: "現金",
                    walletMatchKeywords: "cash,現金",
                    type: .cash,
                    colorHex: "#15803D",
                    iconName: "banknote.fill",
                    sortOrder: 4
                )
            ]
            defaults.forEach { context.insert($0) }
        }

        // 2. Seed Default Hong Kong Merchant Categorization Rules
        let ruleDescriptor = FetchDescriptor<MerchantRule>()
        if (try? context.fetchCount(ruleDescriptor)) == 0 {
            let rules: [(String, SpendingCategory)] = [
                // Coffee & Drinks
                ("starbucks", .coffee),
                ("pacific coffee", .coffee),
                ("arabica", .coffee),
                ("heytea", .coffee),
                ("喜茶", .coffee),
                ("天仁茗茶", .coffee),
                ("coffee", .coffee),
                ("cafe", .coffee),
                // Dining
                ("mcdonald", .dining),
                ("麥當勞", .dining),
                ("kfc", .dining),
                ("大家樂", .dining),
                ("cafe de coral", .dining),
                ("大快活", .dining),
                ("fairwood", .dining),
                ("美心", .dining),
                ("maxim", .dining),
                ("譚仔", .dining),
                ("tamjai", .dining),
                ("sushiro", .dining),
                ("壽司郎", .dining),
                ("foodpanda", .dining),
                ("deliveroo", .dining),
                ("keeta", .dining),
                ("吉野家", .dining),
                ("薩莉亞", .dining),
                ("saizeriya", .dining),
                ("太興", .dining),
                // Convenience
                ("7-eleven", .convenience),
                ("7eleven", .convenience),
                ("circle k", .convenience),
                ("ok便利店", .convenience),
                // Groceries
                ("parknshop", .groceries),
                ("百佳", .groceries),
                ("fusion", .groceries),
                ("taste", .groceries),
                ("wellcome", .groceries),
                ("惠康", .groceries),
                ("market place", .groceries),
                ("donki", .groceries),
                ("don don donki", .groceries),
                ("aeon", .groceries),
                ("hktvmall", .groceries),
                ("759", .groceries),
                ("marks & spencer", .groceries),
                // Transport
                ("mtr", .transport),
                ("港鐵", .transport),
                ("kmb", .transport),
                ("九巴", .transport),
                ("citybus", .transport),
                ("城巴", .transport),
                ("uber", .transport),
                ("taxi", .transport),
                ("的士", .transport),
                // Octopus Top-Up (only match top-up / AAVS, not normal Octopus spending)
                ("add value", .octopusTopUp),
                ("top up", .octopusTopUp),
                ("top-up", .octopusTopUp),
                ("aavs", .octopusTopUp),
                ("增值", .octopusTopUp),
                // Shopping
                ("uniqlo", .shopping),
                ("zara", .shopping),
                ("apple store", .shopping),
                ("apple.com", .shopping),
                ("log-on", .shopping),
                ("sogo", .shopping),
                ("ikea", .shopping),
                ("decathlon", .shopping),
                ("mannings", .shopping),
                ("萬寧", .shopping),
                ("watsons", .shopping),
                ("屈臣氏", .shopping),
                // Entertainment
                ("netflix", .entertainment),
                ("spotify", .entertainment),
                ("disney", .entertainment),
                ("cinema", .entertainment),
                ("戲院", .entertainment),
                ("mcl", .entertainment),
                ("emperor", .entertainment)
            ]
            for (keyword, category) in rules {
                context.insert(MerchantRule(keyword: keyword, category: category, isDefault: true))
            }
        }

        // 3. Seed Default Quick Templates (especially handy for 八達通)
        let templateDescriptor = FetchDescriptor<QuickTemplate>()
        if (try? context.fetchCount(templateDescriptor)) == 0 {
            let templates: [QuickTemplate] = [
                QuickTemplate(
                    titleZh: "八達通搭港鐵",
                    titleEn: "Octopus MTR",
                    amount: 12.5,
                    merchant: "MTR 港鐵",
                    category: .transport,
                    accountName: "八達通",
                    iconName: "tram.fill",
                    sortOrder: 0
                ),
                QuickTemplate(
                    titleZh: "八達通搭巴士",
                    titleEn: "Octopus Bus",
                    amount: 7.4,
                    merchant: "KMB 九巴",
                    category: .transport,
                    accountName: "八達通",
                    iconName: "bus.fill",
                    sortOrder: 1
                ),
                QuickTemplate(
                    titleZh: "便利店買嘢",
                    titleEn: "7-Eleven",
                    amount: 22,
                    merchant: "7-Eleven",
                    category: .convenience,
                    accountName: "八達通",
                    iconName: "storefront.fill",
                    sortOrder: 2
                ),
                QuickTemplate(
                    titleZh: "午餐",
                    titleEn: "Lunch",
                    amount: 65,
                    merchant: "茶餐廳",
                    category: .dining,
                    accountName: "八達通",
                    iconName: "fork.knife",
                    sortOrder: 3
                ),
                QuickTemplate(
                    titleZh: "買咖啡",
                    titleEn: "Coffee",
                    amount: 42,
                    merchant: "Starbucks",
                    category: .coffee,
                    accountName: "Visa",
                    iconName: "cup.and.saucer.fill",
                    sortOrder: 4
                )
            ]
            templates.forEach { context.insert($0) }
        }

        try? context.save()
    }

    // MARK: - Auto-Logging Engine (called by AppIntent & Simulator test)

    func autoLogWalletTransaction(
        rawAmount: String,
        merchant: String,
        cardName: String?,
        explicitCategory: SpendingCategory? = nil,
        source: TransactionSource = .appleWallet,
        currencyCode: String = "HKD",
        allowPendingZero: Bool = false
    ) -> TransactionRecord? {
        let parsed = Self.parseAmount(from: rawAmount)
        return autoLogWalletTransaction(
            numericAmount: parsed,
            merchant: merchant,
            cardName: cardName,
            explicitCategory: explicitCategory,
            source: source,
            currencyCode: currencyCode,
            allowPendingZero: allowPendingZero
        )
    }

    func autoLogWalletTransaction(
        numericAmount: Double?,
        merchant: String,
        cardName: String?,
        explicitCategory: SpendingCategory? = nil,
        source: TransactionSource = .appleWallet,
        currencyCode: String = "HKD",
        allowPendingZero: Bool = false
    ) -> TransactionRecord? {
        let finalAmount: Double
        let isPendingAmount: Bool

        if let numericAmount, numericAmount > 0 {
            finalAmount = numericAmount
            isPendingAmount = false
        } else if allowPendingZero {
            finalAmount = 0
            isPendingAmount = true
        } else {
            return nil
        }

        let context = container.mainContext
        let trimmedMerchant = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCard = cardName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let matchedAccount: String
        if trimmedCard.isEmpty && isPendingAmount {
            // Hong Kong Octopus taps omit both Amount and Card in iOS Shortcuts
            matchedAccount = "八達通"
        } else {
            matchedAccount = matchAccount(for: cardName, in: context)
        }

        let finalMerchant: String
        if !trimmedMerchant.isEmpty {
            finalMerchant = trimmedMerchant
        } else if matchedAccount.localizedCaseInsensitiveContains("八達通") || matchedAccount.localizedCaseInsensitiveContains("octopus") {
            finalMerchant = "八達通消費"
        } else {
            finalMerchant = "Apple Pay"
        }

        let matchedCategory = explicitCategory ?? categorize(merchant: finalMerchant, in: context)
        let finalCurrency = currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "HKD" : currencyCode.uppercased()

        var noteParts: [String] = []
        if let cardName, !cardName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            noteParts.append("Apple Wallet · \(cardName)")
        }
        if isPendingAmount {
            noteParts.append("待補金額")
        }

        let record = TransactionRecord(
            amount: finalAmount,
            merchant: finalMerchant,
            note: noteParts.joined(separator: " · "),
            date: .now,
            category: matchedCategory,
            accountName: matchedAccount,
            source: source,
            currencyCode: finalCurrency
        )

        context.insert(record)
        do {
            try context.save()
        } catch {
            appendDebugLog("SwiftData save error: \(error.localizedDescription)")
            return nil
        }

        sendAutoLogNotification(record: record, isPendingAmount: isPendingAmount)
        return record
    }

    func matchAccount(for cardName: String?, in context: ModelContext) -> String {
        guard let cardName = cardName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !cardName.isEmpty else {
            return "Visa"
        }

        let lower = cardName.lowercased()
        let descriptor = FetchDescriptor<PaymentAccount>(sortBy: [SortDescriptor(\.sortOrder)])
        if let accounts = try? context.fetch(descriptor) {
            if let exact = accounts.first(where: { $0.name.lowercased() == lower }) {
                return exact.name
            }
            if let keywordMatch = accounts.first(where: { account in
                account.keywordsList.contains(where: { lower.contains($0) })
            }) {
                return keywordMatch.name
            }
        }
        return cardName
    }

    func categorize(merchant: String, in context: ModelContext) -> SpendingCategory {
        let lower = merchant.lowercased()
        let descriptor = FetchDescriptor<MerchantRule>()
        if let rules = try? context.fetch(descriptor) {
            // Prefer custom rules first, then default rules
            let sortedRules = rules.sorted { !$0.isDefault && $1.isDefault }
            for rule in sortedRules {
                let key = rule.keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if !key.isEmpty && lower.contains(key) {
                    return rule.category
                }
            }
        }
        return .other
    }

    static func parseAmount(from input: String) -> Double? {
        let cleaned = input
            .replacingOccurrences(of: "HK$", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "HKD", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let direct = Double(cleaned) {
            return abs(direct)
        }
        // Fallback regex to extract first decimal number
        let pattern = #"[0-9]+(\.[0-9]+)?"#
        if let range = cleaned.range(of: pattern, options: .regularExpression) {
            return Double(cleaned[range])
        }
        return nil
    }

    // MARK: - Local Notifications

    func requestNotificationPermission() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    func sendAutoLogNotification(record: TransactionRecord, isPendingAmount: Bool = false) {
        let notificationsEnabled = UserDefaults.standard.object(forKey: "tapbook_notifications") as? Bool ?? true
        guard notificationsEnabled else { return }

        let savedLang = UserDefaults.standard.string(forKey: "tapbook_language") ?? AppLanguage.zhHK.rawValue
        let isChinese = savedLang == AppLanguage.zhHK.rawValue ||
            (savedLang == AppLanguage.system.rawValue && (Locale.preferredLanguages.first?.hasPrefix("zh") ?? true))

        let content = UNMutableNotificationContent()
        if isPendingAmount {
            if isChinese {
                content.title = "TapBook 偵測到拍卡（待補金額）"
                content.body = "\(record.merchant)（\(record.accountName)）未回傳金額，點此打開補填。"
            } else {
                content.title = "TapBook Tap Detected (Needs Amount)"
                content.body = "\(record.merchant) (\(record.accountName)) had no amount. Tap to fill in."
            }
        } else {
            let symbol = record.currencyCode == "HKD" ? "HK$" : "\(record.currencyCode) "
            let formattedAmount = String(format: "\(symbol)%.2f", record.amount)
            if isChinese {
                content.title = "TapBook 已自動記帳"
                content.body = "\(record.merchant) · \(formattedAmount)（\(record.category.displayName(isChinese: true)) · \(record.accountName)）"
            } else {
                content.title = "TapBook Auto-Logged"
                content.body = "\(record.merchant) · \(formattedAmount) (\(record.category.displayName(isChinese: false)) · \(record.accountName))"
            }
        }
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "tapbook-autolog-\(record.id.uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - CSV Export

    static func generateCSV(from records: [TransactionRecord], isChinese: Bool) -> String {
        let header = isChinese
            ? "日期,時間,商戶,金額,貨幣,分類,帳戶,來源,備註"
            : "Date,Time,Merchant,Amount,Currency,Category,Account,Source,Note"
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"

        var rows = [header]
        for r in records {
            let d = dateFormatter.string(from: r.date)
            let t = timeFormatter.string(from: r.date)
            let merchant = escapeCSV(r.merchant)
            let amount = String(format: "%.2f", r.amount)
            let currency = escapeCSV(r.currencyCode)
            let category = escapeCSV(r.category.displayName(isChinese: isChinese))
            let account = escapeCSV(r.accountName)
            let source = escapeCSV(r.source.badgeLabel(isChinese: isChinese))
            let note = escapeCSV(r.note)
            rows.append("\(d),\(t),\(merchant),\(amount),\(currency),\(category),\(account),\(source),\(note)")
        }
        return rows.joined(separator: "\n")
    }

    private static func escapeCSV(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }
}
