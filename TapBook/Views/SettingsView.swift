import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(LanguageStore.self) private var lang

    @Query(sort: \TransactionRecord.date, order: .reverse)
    private var allTransactions: [TransactionRecord]

    @AppStorage("tapbook_monthly_budget") private var monthlyBudget: Double = 8000
    @AppStorage("tapbook_notifications") private var notificationsEnabled: Bool = true
    @AppStorage("tapbook_log_pending_zero") private var logPendingZero: Bool = true

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
                                Text(lang.t("Apple Wallet 自動記帳設定", "Apple Wallet Auto-Log Setup"))
                                    .font(.body.weight(.semibold))
                                Text(lang.t("3 分鐘設定捷徑自動化（Visa / Mastercard）", "3-minute Shortcuts automation guide"))
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
                        lang.t("用 iOS 捷徑實現背景自動記帳", "Background Auto-Log via iOS Shortcuts"),
                        systemImage: "wave.3.right.circle.fill"
                    )
                    .font(.headline)
                    .foregroundStyle(.blue)

                    Text(lang.t(
                        "只需要設定一次，之後每次用 Apple Pay（Visa / Mastercard 等）拍卡，TapBook 會喺背景自動記低金額、商戶同自動分類，完全唔使開 App。",
                        "Set it up once — every time you tap Apple Pay (Visa / Mastercard, etc.), TapBook automatically logs the amount, merchant, and category in the background."
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
                    title: lang.t("打開 iPhone「捷徑」App", "Open the Apple Shortcuts App"),
                    detail: lang.t(
                        "點選底部「自動化」分頁，再按右上角「＋」新增個人自動化。",
                        "Go to the 'Automation' tab at the bottom and tap '+' to create a new personal automation."
                    )
                )

                stepCard(
                    number: "2",
                    title: lang.t("揀選「交易」(Transaction)", "Choose 'Transaction'"),
                    detail: lang.t(
                        "搵到並點選「交易」→ 勾選你常用嘅 Visa / Mastercard → 揀選「立即執行」（唔好揀執行前詢問）→ 按「下一步」。",
                        "Select 'Transaction' → check your Visa / Mastercard cards → select 'Run Immediately' → tap Next."
                    )
                )

                stepCard(
                    number: "3",
                    title: lang.t("加入 TapBook 動作", "Add TapBook Action"),
                    detail: lang.t(
                        "點選「新增空白自動化」→ 搜尋「TapBook」→ 揀選「記錄 Apple Wallet 交易」。",
                        "Tap 'New Blank Automation' → search 'TapBook' → choose 'Log Apple Wallet Transaction'."
                    )
                )

                stepCard(
                    number: "4",
                    title: lang.t("填入 3 個捷徑變數", "Map the 3 Shortcut Variables"),
                    detail: lang.t(
                        "• 金額 → 揀「捷徑輸入（金額）」\n• 商戶 → 揀「捷徑輸入（商戶）」\n• 卡片或帳戶 → 揀「捷徑輸入（卡或票證）」\n完成後按「完成」即刻生效！",
                        "• Amount → Shortcut Input (Amount)\n• Merchant → Shortcut Input (Merchant)\n• Card or Account → Shortcut Input (Card or Pass)\nTap Done and you're all set!"
                    )
                )

                // Octopus note
                VStack(alignment: .leading, spacing: 8) {
                    Label(
                        lang.t("關於八達通 (Octopus)", "About Octopus"),
                        systemImage: "info.circle.fill"
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)

                    Text(lang.t(
                        "由於 iOS 系統限制，特快交通八達通拍卡時唔會觸發 Apple 捷徑「交易」事件（用信用卡增值八達通時就會觸發）。日常搭車或便利店用八達通，建議用首頁嘅「一鍵快記」按鈕或同 Siri 講「用 TapBook 記帳」！",
                        "Due to iOS system limits, Express Transit Octopus taps don't trigger Shortcuts Transaction automations (credit card top-ups do). For daily Octopus rides or snacks, use Home's 1-Tap Quick Templates or say 'Log expense in TapBook' to Siri!"
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
