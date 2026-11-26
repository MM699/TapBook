import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(LanguageStore.self) private var lang

    @Query(sort: \TransactionRecord.date, order: .reverse)
    private var allTransactions: [TransactionRecord]

    @AppStorage("tapbook_monthly_budget") private var monthlyBudget: Double = 8000
    @AppStorage("tapbook_notifications") private var notificationsEnabled: Bool = true
    @AppStorage("tapbook_log_pending_zero") private var logPendingZero: Bool = true
    @AppStorage("tapbook_exclude_topup_from_total") private var excludeTopUpFromTotal: Bool = true

    @State private var budgetInput: String = ""
    @State private var showingBudgetAlert = false
    @State private var simulatedToast: String?

    var body: some View {
        @Bindable var bindableLang = lang

        NavigationStack {
            List {
                // Apple Wallet Setup
                Section {
                    NavigationLink {
                        WalletSetupGuideView()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "wave.3.right.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.blue)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(lang.t("自動記帳設定（推薦：通知自動化）", "Auto-Log Setup (Recommended: Notifications)"))
                                    .font(.body.weight(.semibold))
                                Text(lang.t("支援八達通真銀碼、PayMe、AlipayHK、Visa / AE", "Octopus exact amount, PayMe, AlipayHK, Visa / AE"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    Button {
                        simulateApplePayTap()
                    } label: {
                        Label(
                            lang.t("測試模擬 Apple Pay 拍卡記帳", "Simulate Apple Pay Tap"),
                            systemImage: "sparkles"
                        )
                    }

                    Button {
                        simulatePaymentNotification()
                    } label: {
                        Label(
                            lang.t("測試模擬通知記帳（八達通 / PayMe / AlipayHK）", "Simulate Payment Notification (Octopus/PayMe/Alipay)"),
                            systemImage: "bell.and.waves.left.and.right.fill"
                        )
                    }

                    Toggle(isOn: $logPendingZero) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(lang.t("記錄 $0 / 待補金額拍卡", "Log $0 / Pending Amount Taps"))
                            Text(lang.t("八達通未回傳金額時記為「待補金額」", "Saves a tappable reminder when Octopus omits amount"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    NavigationLink {
                        ShortcutsDebugLogView()
                    } label: {
                        Label(
                            lang.t("捷徑觸發紀錄（診斷用）", "Shortcuts Trigger Log (Debug)"),
                            systemImage: "doc.text.magnifyingglass"
                        )
                    }
                } header: {
                    Text(lang.t("自動記帳", "Auto-Logging"))
                } footer: {
                    if let simulatedToast {
                        Text(simulatedToast)
                            .foregroundStyle(.green)
                    } else {
                        Text(lang.t(
                            "可按上方「測試模擬」立即體驗自動分類同記帳效果。",
                            "Tap Simulate above to test auto-categorization and background logging right away."
                        ))
                    }
                }

                // Rules & Budget
                Section(lang.t("記帳設定", "Preferences")) {
                    NavigationLink {
                        MerchantRulesView()
                    } label: {
                        Label(lang.t("商戶自動分類規則", "Merchant Auto-Category Rules"), systemImage: "wand.and.stars")
                    }

                    Button {
                        budgetInput = String(Int(monthlyBudget))
                        showingBudgetAlert = true
                    } label: {
                        HStack {
                            Label(lang.t("每月預算", "Monthly Budget"), systemImage: "chart.bar.fill")
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(lang.formatCurrency(monthlyBudget))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Toggle(isOn: $excludeTopUpFromTotal) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(lang.t("「八達通增值」不計入總支出", "Exclude Octopus Top-Up from Total"))
                            Text(lang.t("避免信用卡增值同八達通實際消費重複計算", "Prevents double-counting card top-ups and Octopus spending"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Toggle(isOn: $notificationsEnabled) {
                        Label(lang.t("自動記帳通知", "Auto-Log Notifications"), systemImage: "bell.badge.fill")
                    }
                    .onChange(of: notificationsEnabled) { _, enabled in
                        if enabled {
                            Task {
                                _ = await PersistenceController.shared.requestNotificationPermission()
                            }
                        }
                    }
                }

                // Language
                Section(lang.t("語言 / Language", "Language / 語言")) {
                    Picker(lang.t("介面語言", "App Language"), selection: $bindableLang.selectedLanguage) {
                        ForEach(AppLanguage.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                }

                // Export
                Section(lang.t("資料匯出", "Data Export")) {
                    let csv = PersistenceController.generateCSV(from: allTransactions, isChinese: lang.isChinese)
                    ShareLink(
                        item: csv,
                        preview: SharePreview("TapBook_Export.csv")
                    ) {
                        Label(
                            lang.t("匯出 CSV 帳單（\(allTransactions.count) 筆）", "Export CSV (\(allTransactions.count) records)"),
                            systemImage: "square.and.arrow.up"
                        )
                    }
                }

                Section {
                    HStack {
                        Text(lang.t("版本", "Version"))
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(lang.t("設定", "Settings"))
            .alert(lang.t("設定每月預算 (HK$)", "Set Monthly Budget (HK$)"), isPresented: $showingBudgetAlert) {
                TextField("8000", text: $budgetInput)
                    .keyboardType(.numberPad)
                Button(lang.t("取消", "Cancel"), role: .cancel) {}
                Button(lang.t("儲存", "Save")) {
                    if let val = Double(budgetInput), val >= 0 {
                        monthlyBudget = val
                    }
                }
            }
        }
    }

    private func simulateApplePayTap() {
        let samples: [(String, String, String)] = [
            ("HK$42.00", "Starbucks", "HSBC Visa"),
            ("HK$68.50", "大家樂 Cafe de Coral", "Hang Seng Visa"),
            ("HK$129.00", "DON DON DONKI", "Mox Mastercard"),
            ("HK$24.00", "7-Eleven", "HSBC Visa"),
            ("HK$250.00", "Octopus Auto Add Value", "HSBC Visa")
        ]
        let pick = samples.randomElement()!
        if let record = PersistenceController.shared.autoLogWalletTransaction(
            rawAmount: pick.0,
            merchant: pick.1,
            cardName: pick.2,
            source: .appleWallet
        ) {
            simulatedToast = lang.t(
                "已模擬記帳：\(record.merchant) \(lang.formatCurrency(record.amount)) → \(record.category.displayName(isChinese: true))（\(record.accountName)）",
                "Simulated: \(record.merchant) \(lang.formatCurrency(record.amount)) → \(record.category.displayName(isChinese: false)) (\(record.accountName))"
            )
        }
    }

    private func simulatePaymentNotification() {
        let samples: [(String, String, String)] = [
            ("Octopus", "消費：HK$8.00\n你的新餘額為 HK$95.10。", "Wallet"),
            ("PayMe", "你已支付 HK$45.00 給 7-Eleven", "PayMe"),
            ("AlipayHK", "你已成功向 大家樂 付款 HK$62.00", "AlipayHK"),
            ("Octopus", "消費：HK$40.00\n你的新餘額為 HK$182.10。", "Wallet"),
            ("PayMe", "You paid HK$38.00 to Starbucks", "PayMe")
        ]
        let pick = samples.randomElement()!
        if let parsed = NotificationParser.parse(title: pick.0, body: pick.1, appName: pick.2),
           let record = PersistenceController.shared.autoLogWalletTransaction(
            numericAmount: parsed.amount,
            merchant: parsed.merchant,
            cardName: parsed.accountHint,
            explicitCategory: parsed.categoryOverride,
            source: .appleWallet,
            currencyCode: parsed.currencyCode,
            allowPendingZero: false
           ) {
            simulatedToast = lang.t(
                "已解析通知：\(record.merchant) \(lang.formatCurrency(record.amount)) → \(record.category.displayName(isChinese: true))（\(record.accountName)）",
                "Parsed Notification: \(record.merchant) \(lang.formatCurrency(record.amount)) → \(record.category.displayName(isChinese: false)) (\(record.accountName))"
            )
        }
    }
}

// MARK: - Apple Wallet Shortcuts Setup Guide

struct WalletSetupGuideView: View {
    @Environment(LanguageStore.self) private var lang

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Intro Banner
                VStack(alignment: .leading, spacing: 8) {
                    Label(
                        lang.t("用「通知自動化」實現全自動記帳（推薦）", "Full Auto-Log via Notification Automation (Recommended)"),
                        systemImage: "bell.badge.fill"
                    )
                    .font(.headline)
                    .foregroundStyle(.blue)

                    Text(lang.t(
                        "透過 iOS 捷徑嘅「通知」觸發器，可同時自動讀取「錢包（八達通真銀碼 + Visa / Mastercard / AE）」、「PayMe」、「AlipayHK」及銀行 App 付款通知，100% 本機離線解析，完全唔使登入銀行！",
                        "Using iOS Shortcuts' Notification trigger, TapBook automatically parses exact amounts from Wallet (Octopus + Visa / Mastercard / AE), PayMe, AlipayHK, and HK bank alerts — 100% offline with zero bank logins."
                    ))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                // Steps
                stepCard(
                    number: "1",
                    title: lang.t("打開 iPhone「捷徑」App → 自動化", "Open Apple Shortcuts → Automation"),
                    detail: lang.t(
                        "點選底部「自動化」分頁，按右上角「＋」新增個人自動化。",
                        "Go to the 'Automation' tab and tap '+' to create a new personal automation."
                    )
                )

                stepCard(
                    number: "2",
                    title: lang.t("揀選「通知」(Notification)", "Choose 'Notification'"),
                    detail: lang.t(
                        "在 App 列表勾選「錢包 (Wallet)」（包晒八達通同 Apple Pay 信用卡）、「PayMe」、「AlipayHK」，以及你有開消費通知嘅銀行 App → 開啟「立即執行」並關閉「通知我」。",
                        "Select 'Wallet' (covers Octopus & Apple Pay cards), 'PayMe', 'AlipayHK', and any HK bank apps → turn ON Run Immediately and turn OFF Notify When Run."
                    )
                )

                stepCard(
                    number: "3",
                    title: lang.t("加入 TapBook「從付款通知自動記帳」", "Add TapBook 'Log From Payment Notification'"),
                    detail: lang.t(
                        "搜尋「TapBook」→ 揀選「從付款通知自動記帳」，展開選項並關閉「Show When Run」（執行時顯示）。",
                        "Search 'TapBook' → choose 'Log From Payment Notification', expand options, and turn OFF 'Show When Run'."
                    )
                )

                stepCard(
                    number: "4",
                    title: lang.t("填入通知嘅「標題」同「內文」", "Map Notification Title & Body"),
                    detail: lang.t(
                        "• 通知標題 → 揀通知觸發器嘅「Title / 標題」\n• 通知內容 → 揀通知觸發器嘅「Body / 內文」\n完成後返回儲存即刻生效！如果之前整過舊嘅「交易」自動化可以關閉，免得重覆。",
                        "• Notification Title → Notification (Title)\n• Notification Body → Notification (Body)\nGo back to save! You can turn off the older Transaction automation to keep things clean."
                    )
                )

                // Octopus & E-Wallet note
                VStack(alignment: .leading, spacing: 8) {
                    Label(
                        lang.t("自動過濾餘額、驗證碼同收款", "Smart Filtering Built-In"),
                        systemImage: "checkmark.shield.fill"
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)

                    Text(lang.t(
                        "• 八達通通知「消費：HK$8.00 / 新餘額 HK$95.10」只會抽消費額 $8.00，唔會誤讀餘額。\n• PayMe / AlipayHK 收到錢、銀行 OTP 驗證碼、退款都會自動略過，只記真正消費。",
                        "• Octopus alerts ('Spent HK$8.00 / New balance HK$95.10') extract $8.00 only and ignore balance.\n• Incoming PayMe/Alipay transfers, refunds, and OTP verification codes are automatically ignored."
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(lang.t("自動記帳教學", "Setup Guide"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func stepCard(number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(number)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Color(hex: "#2563EB"), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Merchant Rules Manager

struct MerchantRulesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(LanguageStore.self) private var lang

    @Query(sort: \MerchantRule.keyword)
    private var rules: [MerchantRule]

    @State private var newKeyword: String = ""
    @State private var newCategory: SpendingCategory = .dining

    var body: some View {
        List {
            Section(lang.t("新增自訂規則", "Add Custom Rule")) {
                TextField(lang.t("商戶關鍵字（例如：壽司郎、aeon）", "Merchant keyword (e.g. sushiro, aeon)"), text: $newKeyword)
                Picker(lang.t("自動歸類為", "Auto-Categorize As"), selection: $newCategory) {
                    ForEach(SpendingCategory.allCases) { cat in
                        Label(cat.displayName(isChinese: lang.isChinese), systemImage: cat.icon).tag(cat)
                    }
                }
                Button {
                    let trimmed = newKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    modelContext.insert(MerchantRule(keyword: trimmed, category: newCategory, isDefault: false))
                    try? modelContext.save()
                    newKeyword = ""
                } label: {
                    Label(lang.t("加入規則", "Add Rule"), systemImage: "plus.circle.fill")
                }
                .disabled(newKeyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Section(lang.t("現有規則（\(rules.count) 條）", "Active Rules (\(rules.count))")) {
                ForEach(rules) { rule in
                    HStack {
                        Image(systemName: rule.category.icon)
                            .foregroundStyle(rule.category.color)
                            .frame(width: 24)
                        Text(rule.keyword)
                            .font(.body)
                        Spacer()
                        Text(rule.category.displayName(isChinese: lang.isChinese))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete { offsets in
                    for index in offsets {
                        modelContext.delete(rules[index])
                    }
                    try? modelContext.save()
                }
            }
        }
        .navigationTitle(lang.t("自動分類規則", "Auto-Category Rules"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Shortcuts Debug Log View

struct ShortcutsDebugLogView: View {
    @Environment(LanguageStore.self) private var lang
    @State private var logs: [String] = []

    var body: some View {
        List {
            if logs.isEmpty {
                Section {
                    Text(lang.t(
                        "暫時未收到任何捷徑觸發。\n\n如果拍卡後呢度依然係空白，代表 iOS 捷徑本身未觸發到 TapBook（例如網上／App 內付款、用 Apple Watch 拍卡、或者捷徑變數未填好）。",
                        "No Shortcuts triggers received yet.\n\nIf this stays empty after tapping, iOS Shortcuts did not invoke TapBook (e.g. online/in-app Apple Pay, Apple Watch tap, or unmapped variables)."
                    ))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
                }
            } else {
                Section(lang.t("最近 15 次收到嘅原始資料", "Last 15 Raw Inputs Received")) {
                    ForEach(logs, id: \.self) { line in
                        Text(line)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .navigationTitle(lang.t("捷徑觸發紀錄", "Shortcuts Trigger Log"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    logs = PersistenceController.shared.fetchDebugLogs()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                Button(lang.t("清除", "Clear")) {
                    PersistenceController.shared.clearDebugLogs()
                    logs = []
                }
                .disabled(logs.isEmpty)
            }
        }
        .onAppear {
            logs = PersistenceController.shared.fetchDebugLogs()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            logs = PersistenceController.shared.fetchDebugLogs()
        }
    }
}
