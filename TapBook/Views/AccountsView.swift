import SwiftData
import SwiftUI

struct AccountsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(LanguageStore.self) private var lang

    @Query(sort: \PaymentAccount.sortOrder)
    private var accounts: [PaymentAccount]

    @Query(sort: \TransactionRecord.date, order: .reverse)
    private var transactions: [TransactionRecord]

    @Query(sort: \QuickTemplate.sortOrder)
    private var templates: [QuickTemplate]

    @State private var showingAddAccount = false
    @State private var editingAccount: PaymentAccount?
    @State private var showingAddTemplate = false

    private func monthlySpending(for accountName: String) -> Double {
        let cal = Calendar.current
        let now = Date.now
        return transactions
            .filter { $0.accountName == accountName && cal.isDate($0.date, equalTo: now, toGranularity: .month) }
            .reduce(0) { $0 + $1.amount }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(accounts) { account in
                        AccountCardRow(
                            account: account,
                            monthlySpent: monthlySpending(for: account.name)
                        )
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .onTapGesture {
                            editingAccount = account
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            modelContext.delete(accounts[index])
                        }
                        try? modelContext.save()
                    }
                } header: {
                    Text(lang.t("付款卡片與帳戶（對應 Apple Wallet）", "Cards & Accounts (Apple Wallet Matching)"))
                } footer: {
                    Text(lang.t(
                        "點選卡片可設定「Apple Wallet 關鍵字」，當捷徑傳入銀行卡名稱時會自動配對到對應帳戶。",
                        "Tap a card to customize Apple Wallet matching keywords so incoming Shortcuts transactions map automatically."
                    ))
                }

                Section {
                    ForEach(templates) { template in
                        HStack {
                            Image(systemName: template.iconName)
                                .foregroundStyle(template.category.color)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(template.title(isChinese: lang.isChinese))
                                    .font(.body.weight(.medium))
                                Text("\(template.merchant) · \(template.accountName)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(lang.formatCurrency(template.amount))
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            modelContext.delete(templates[index])
                        }
                        try? modelContext.save()
                    }

                    Button {
                        showingAddTemplate = true
                    } label: {
                        Label(lang.t("新增一鍵快記模板", "Add Quick Tap Template"), systemImage: "plus.circle.fill")
                    }
                } header: {
                    Text(lang.t("八達通／常用一鍵快記模板", "Octopus & Quick Tap Templates"))
                }
            }
            .navigationTitle(lang.t("帳戶與卡片", "Accounts"))
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddAccount = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddAccount) {
                AccountEditorSheet(account: nil, nextSortOrder: accounts.count)
            }
            .sheet(item: $editingAccount) { account in
                AccountEditorSheet(account: account, nextSortOrder: account.sortOrder)
            }
            .sheet(isPresented: $showingAddTemplate) {
                AddQuickTemplateSheet(nextSortOrder: templates.count)
            }
        }
    }
}

struct AccountCardRow: View {
    @Environment(LanguageStore.self) private var lang
    let account: PaymentAccount
    let monthlySpent: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(account.name, systemImage: account.iconName)
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Text(account.type.displayName(isChinese: lang.isChinese))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.2), in: Capsule())
            }

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(lang.t("今月支出", "This Month"))
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.8))
                    Text(lang.formatCurrency(monthlySpent))
                        .font(.title2.weight(.bold).monospacedDigit())
                        .foregroundStyle(.white)
                }
                Spacer()
                if !account.walletMatchKeywords.isEmpty {
                    Text(lang.t("關鍵字：\(account.walletMatchKeywords)", "Match: \(account.walletMatchKeywords)"))
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                        .frame(maxWidth: 160, alignment: .trailing)
                }
            }
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [Color(hex: account.colorHex), Color(hex: account.colorHex).opacity(0.78)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .shadow(color: Color(hex: account.colorHex).opacity(0.25), radius: 6, y: 3)
    }
}

struct AccountEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(LanguageStore.self) private var lang

    let account: PaymentAccount?
    let nextSortOrder: Int

    @State private var name: String = ""
    @State private var type: AccountType = .creditCard
    @State private var keywords: String = ""
    @State private var colorHex: String = "#1E3A8A"

    private let palette = ["#1E3A8A", "#B91C1C", "#EA580C", "#15803D", "#6D28D9", "#0F766E", "#334155"]

    var body: some View {
        NavigationStack {
            Form {
                Section(lang.t("基本資料", "Account Info")) {
                    TextField(lang.t("帳戶名稱（例如：HSBC Visa、八達通）", "Name (e.g. HSBC Visa, Octopus)"), text: $name)
                    Picker(lang.t("類型", "Type"), selection: $type) {
                        ForEach(AccountType.allCases) { item in
                            Text(item.displayName(isChinese: lang.isChinese)).tag(item)
                        }
                    }
                }

                Section {
                    TextField(lang.t("以逗號分隔，例如：visa, hsbc, red", "Comma-separated, e.g. visa, hsbc"), text: $keywords)
                } header: {
                    Text(lang.t("Apple Wallet 配對關鍵字", "Apple Wallet Match Keywords"))
                } footer: {
                    Text(lang.t(
                        "當 Apple Wallet 傳入嘅卡名包含呢啲字眼時，就會自動歸入此帳戶。",
                        "Incoming Apple Wallet card names containing these keywords will automatically match this account."
                    ))
                }

                Section(lang.t("卡片顏色", "Card Color")) {
                    HStack(spacing: 12) {
                        ForEach(palette, id: \.self) { hex in
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 30, height: 30)
                                .overlay {
                                    if colorHex == hex {
                                        Image(systemName: "checkmark")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                                .onTapGesture { colorHex = hex }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle(account == nil ? lang.t("新增帳戶", "Add Account") : lang.t("編輯帳戶", "Edit Account"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(lang.t("取消", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(lang.t("儲存", "Save")) { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                if let account {
                    name = account.name
                    type = account.type
                    keywords = account.walletMatchKeywords
                    colorHex = account.colorHex
                }
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let account {
            account.name = trimmed
            account.type = type
            account.walletMatchKeywords = keywords
            account.colorHex = colorHex
            account.iconName = type.defaultIcon
        } else {
            let newAccount = PaymentAccount(
                name: trimmed,
                walletMatchKeywords: keywords,
                type: type,
                colorHex: colorHex,
                iconName: type.defaultIcon,
                sortOrder: nextSortOrder
            )
            modelContext.insert(newAccount)
        }
        try? modelContext.save()
        dismiss()
    }
}

struct AddQuickTemplateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(LanguageStore.self) private var lang

    @Query(sort: \PaymentAccount.sortOrder)
    private var accounts: [PaymentAccount]

    let nextSortOrder: Int

    @State private var title: String = ""
    @State private var amountText: String = ""
    @State private var merchant: String = ""
    @State private var category: SpendingCategory = .transport
    @State private var accountName: String = "八達通"

    var body: some View {
        NavigationStack {
            Form {
                TextField(lang.t("按鈕名稱（例如：搭小巴）", "Button Title (e.g. Minibus)"), text: $title)
                TextField(lang.t("商戶名稱（例如：綠色專線小巴）", "Merchant (e.g. Green Minibus)"), text: $merchant)
                HStack {
                    Text("HK$")
                    TextField("0.00", text: $amountText)
                        .keyboardType(.decimalPad)
                }
                Picker(lang.t("分類", "Category"), selection: $category) {
                    ForEach(SpendingCategory.allCases) { cat in
                        Label(cat.displayName(isChinese: lang.isChinese), systemImage: cat.icon).tag(cat)
                    }
                }
                Picker(lang.t("帳戶", "Account"), selection: $accountName) {
                    ForEach(accounts) { acc in
                        Text(acc.name).tag(acc.name)
                    }
                }
            }
            .navigationTitle(lang.t("新增快記模板", "New Quick Template"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(lang.t("取消", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(lang.t("儲存", "Save")) {
                        guard let amount = Double(amountText), amount > 0 else { return }
                        let finalTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        let finalMerchant = merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? finalTitle : merchant
                        let template = QuickTemplate(
                            titleZh: finalTitle,
                            titleEn: finalTitle,
                            amount: amount,
                            merchant: finalMerchant,
                            category: category,
                            accountName: accountName,
                            iconName: category.icon,
                            sortOrder: nextSortOrder
                        )
                        modelContext.insert(template)
                        try? modelContext.save()
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (Double(amountText) ?? 0) <= 0)
                }
            }
        }
    }
}
