import SwiftData
import SwiftUI

enum HomeFilter: String, CaseIterable, Identifiable {
    case all
    case appleWallet
    case octopus
    case manual

    var id: String { rawValue }

    func title(isChinese: Bool) -> String {
        switch self {
        case .all: return isChinese ? "全部" : "All"
        case .appleWallet: return isChinese ? "Apple Wallet" : "Apple Wallet"
        case .octopus: return isChinese ? "八達通" : "Octopus"
        case .manual: return isChinese ? "手動" : "Manual"
        }
    }
}

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(LanguageStore.self) private var lang

    @Query(sort: \TransactionRecord.date, order: .reverse)
    private var allTransactions: [TransactionRecord]

    @Query(sort: \QuickTemplate.sortOrder)
    private var quickTemplates: [QuickTemplate]

    @Query(sort: \PaymentAccount.sortOrder)
    private var accounts: [PaymentAccount]

    @AppStorage("tapbook_monthly_budget") private var monthlyBudget: Double = 8000

    @State private var selectedFilter: HomeFilter = .all
    @State private var searchText: String = ""
    @State private var showingAddSheet = false
    @State private var editingTransaction: TransactionRecord?
    @State private var toastMessage: String?

    private var currentMonthTransactions: [TransactionRecord] {
        let cal = Calendar.current
        let now = Date.now
        return allTransactions.filter { cal.isDate($0.date, equalTo: now, toGranularity: .month) }
    }

    private var monthlyTotal: Double {
        currentMonthTransactions.reduce(0) { $0 + $1.amount }
    }

    private var autoLoggedCount: Int {
        currentMonthTransactions.filter { $0.source == .appleWallet }.count
    }

    private var filteredTransactions: [TransactionRecord] {
        allTransactions.filter { record in
            let matchesFilter: Bool
            switch selectedFilter {
            case .all:
                matchesFilter = true
            case .appleWallet:
                matchesFilter = record.source == .appleWallet
            case .octopus:
                matchesFilter = record.accountName.localizedCaseInsensitiveContains("八達通") ||
                    record.accountName.localizedCaseInsensitiveContains("octopus")
            case .manual:
                matchesFilter = record.source == .manual
            }

            let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchesSearch = trimmed.isEmpty ||
                record.merchant.localizedCaseInsensitiveContains(trimmed) ||
                record.accountName.localizedCaseInsensitiveContains(trimmed) ||
                record.note.localizedCaseInsensitiveContains(trimmed)

            return matchesFilter && matchesSearch
        }
    }

    private var groupedTransactions: [(day: Date, items: [TransactionRecord])] {
        let cal = Calendar.current
        let dict = Dictionary(grouping: filteredTransactions) { record in
            cal.startOfDay(for: record.date)
        }
        return dict
            .map { (day: $0.key, items: $0.value) }
            .sorted { $0.day > $1.day }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    VStack(spacing: 16) {
                        monthlyHeroCard
                        quickTemplatesSection
                        filterBar
                        transactionsListSection
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 88)
                }
                .background(Color(.systemGroupedBackground))
                .searchable(
                    text: $searchText,
                    prompt: lang.t("搜尋商戶、卡片或備註", "Search merchant, card, or note")
                )

                // Floating Add Button
                Button {
                    showingAddSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 58, height: 58)
                        .background(
                            LinearGradient(
                                colors: [Color(hex: "#2563EB"), Color(hex: "#1D4ED8")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: Circle()
                        )
                        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                }
                .padding(.trailing, 20)
                .padding(.bottom, 20)
                .accessibilityLabel(lang.t("新增記帳", "Add Expense"))
            }
            .overlay(alignment: .top) {
                if let toastMessage {
                    Text(toastMessage)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.black.opacity(0.85), in: Capsule())
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .navigationTitle("TapBook")
            .sheet(isPresented: $showingAddSheet) {
                TransactionEditorSheet(transaction: nil)
            }
            .sheet(item: $editingTransaction) { record in
                TransactionEditorSheet(transaction: record)
            }
        }
    }

    // MARK: - Monthly Hero Card

    private var monthlyHeroCard: some View {
        let progress = monthlyBudget > 0 ? min(monthlyTotal / monthlyBudget, 1.0) : 0
        let remaining = max(monthlyBudget - monthlyTotal, 0)

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(lang.t("今月總支出", "This Month"))
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                    Text(lang.formatCurrency(monthlyTotal))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Label(
                        lang.t("\(autoLoggedCount) 筆自動", "\(autoLoggedCount) Auto"),
                        systemImage: "wave.3.right.circle.fill"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.2), in: Capsule())

                    Text(lang.formatMonthTitle(.now))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                }
            }

            if monthlyBudget > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(.white.opacity(0.25))
                            Capsule()
                                .fill(progress >= 0.9 ? Color.orange : Color.white)
                                .frame(width: geo.size.width * progress)
                        }
                    }
                    .frame(height: 7)

                    HStack {
                        Text(lang.t(
                            "預算 \(lang.formatCurrency(monthlyBudget))",
                            "Budget \(lang.formatCurrency(monthlyBudget))"
                        ))
                        Spacer()
                        Text(
                            monthlyTotal > monthlyBudget
                            ? lang.t("超支 \(lang.formatCurrency(monthlyTotal - monthlyBudget))", "Over by \(lang.formatCurrency(monthlyTotal - monthlyBudget))")
                            : lang.t("尚餘 \(lang.formatCurrency(remaining))", "\(lang.formatCurrency(remaining)) left")
                        )
                    }
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.9))
                }
            }
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [Color(hex: "#1E3A8A"), Color(hex: "#2563EB"), Color(hex: "#0EA5E9")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .shadow(color: Color(hex: "#1D4ED8").opacity(0.25), radius: 10, y: 5)
    }

    // MARK: - Quick Templates (Octopus 1-Tap)

    private var quickTemplatesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(lang.t("一鍵快記（八達通 / 常用）", "Quick Tap (Octopus & Frequent)"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(quickTemplates) { template in
                        Button {
                            logQuickTemplate(template)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: template.iconName)
                                    .font(.subheadline)
                                    .foregroundStyle(template.category.color)
                                    .frame(width: 28, height: 28)
                                    .background(template.category.color.opacity(0.14), in: Circle())

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(template.title(isChinese: lang.isChinese))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text("\(lang.formatCurrency(template.amount)) · \(template.accountName)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(HomeFilter.allCases) { filter in
                    let isSelected = selectedFilter == filter
                    Button {
                        withAnimation(.snappy) {
                            selectedFilter = filter
                        }
                    } label: {
                        Text(filter.title(isChinese: lang.isChinese))
                            .font(.subheadline.weight(isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? .white : .primary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                isSelected ? Color(hex: "#2563EB") : Color(.secondarySystemGroupedBackground),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Transactions List

    private var transactionsListSection: some View {
        Group {
            if groupedTransactions.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "creditcard.and.123")
                        .font(.system(size: 44))
                        .foregroundStyle(.secondary)
                    Text(lang.t("暫時未有消費紀錄", "No transactions yet"))
                        .font(.headline)
                    Text(lang.t(
                        "撳右下角 + 手動記帳，或者喺「設定」開啟 Apple Wallet 自動記帳。",
                        "Tap + to add manually, or set up Apple Wallet Auto-Log in Settings."
                    ))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 48)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                LazyVStack(spacing: 14) {
                    ForEach(groupedTransactions, id: \.day) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(lang.formatDayHeader(group.day))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                let daySum = group.items.reduce(0) { $0 + $1.amount }
                                Text(lang.formatCurrency(daySum))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 4)

                            VStack(spacing: 0) {
                                ForEach(group.items) { record in
                                    TransactionRowView(record: record)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            editingTransaction = record
                                        }
                                        .contextMenu {
                                            Button {
                                                editingTransaction = record
                                            } label: {
                                                Label(lang.t("編輯", "Edit"), systemImage: "pencil")
                                            }
                                            Button(role: .destructive) {
                                                deleteTransaction(record)
                                            } label: {
                                                Label(lang.t("刪除", "Delete"), systemImage: "trash")
                                            }
                                        }

                                    if record.id != group.items.last?.id {
                                        Divider().padding(.leading, 62)
                                    }
                                }
                            }
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func logQuickTemplate(_ template: QuickTemplate) {
        let record = TransactionRecord(
            amount: template.amount,
            merchant: template.merchant,
            note: template.title(isChinese: lang.isChinese),
            date: .now,
            category: template.category,
            accountName: template.accountName,
            source: .quickTemplate
        )
        modelContext.insert(record)
        try? modelContext.save()

        let feedback = UIImpactFeedbackGenerator(style: .medium)
        feedback.impactOccurred()

        withAnimation {
            toastMessage = lang.t(
                "已記帳：\(template.merchant) \(lang.formatCurrency(template.amount))",
                "Logged: \(template.merchant) \(lang.formatCurrency(template.amount))"
            )
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation {
                toastMessage = nil
            }
        }
    }

    private func deleteTransaction(_ record: TransactionRecord) {
        modelContext.delete(record)
        try? modelContext.save()
    }
}

// MARK: - Transaction Row View

struct TransactionRowView: View {
    @Environment(LanguageStore.self) private var lang
    let record: TransactionRecord

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: record.category.icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(record.category.color)
                .frame(width: 40, height: 40)
                .background(record.category.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(record.merchant)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    if record.source == .appleWallet {
                        Image(systemName: "wave.3.right.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                }
                HStack(spacing: 6) {
                    Text(record.category.displayName(isChinese: lang.isChinese))
                    Text("·")
                    Text(record.accountName)
                    Text("·")
                    Text(lang.formatTime(record.date))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer()

            Text("-\(lang.formatCurrency(record.amount, currencyCode: record.currencyCode))")
                .font(.body.weight(.semibold).monospacedDigit())
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

// MARK: - Add / Edit Transaction Sheet

struct TransactionEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(LanguageStore.self) private var lang

    @Query(sort: \PaymentAccount.sortOrder)
    private var accounts: [PaymentAccount]

    let transaction: TransactionRecord?

    @State private var amountText: String = ""
    @State private var merchant: String = ""
    @State private var note: String = ""
    @State private var date: Date = .now
    @State private var category: SpendingCategory = .dining
    @State private var selectedAccount: String = "Visa"

    var isEditing: Bool { transaction != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section(lang.t("金額與商戶", "Amount & Merchant")) {
                    HStack {
                        Text("HK$")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.secondary)
                        TextField("0.00", text: $amountText)
                            .keyboardType(.decimalPad)
                            .font(.title2.weight(.bold))
                    }

                    TextField(lang.t("商戶名稱（例如：大家樂、港鐵）", "Merchant (e.g. Starbucks, MTR)"), text: $merchant)
                        .onChange(of: merchant) { _, newValue in
                            if !isEditing && !newValue.isEmpty {
                                let suggested = PersistenceController.shared.categorize(merchant: newValue, in: modelContext)
                                if suggested != .other {
                                    category = suggested
                                }
                            }
                        }
                }

                Section(lang.t("分類與帳戶", "Category & Account")) {
                    Picker(lang.t("分類", "Category"), selection: $category) {
                        ForEach(SpendingCategory.allCases) { cat in
                            Label(cat.displayName(isChinese: lang.isChinese), systemImage: cat.icon)
                                .tag(cat)
                        }
                    }

                    Picker(lang.t("付款帳戶", "Payment Account"), selection: $selectedAccount) {
                        ForEach(accounts) { account in
                            Label(account.name, systemImage: account.iconName)
                                .tag(account.name)
                        }
                    }

                    DatePicker(lang.t("日期時間", "Date & Time"), selection: $date)
                }

                Section(lang.t("備註", "Note")) {
                    TextField(lang.t("可留空", "Optional note"), text: $note)
                }

                if let transaction {
                    Section {
                        Button(role: .destructive) {
                            modelContext.delete(transaction)
                            try? modelContext.save()
                            dismiss()
                        } label: {
                            HStack {
                                Spacer()
                                Text(lang.t("刪除此紀錄", "Delete Transaction"))
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? lang.t("編輯記帳", "Edit Expense") : lang.t("新增記帳", "Add Expense"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(lang.t("取消", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(lang.t("儲存", "Save")) { save() }
                        .disabled(Double(amountText) == nil || (Double(amountText) ?? 0) <= 0)
                }
            }
            .onAppear {
                if let transaction {
                    amountText = String(format: "%.2f", transaction.amount)
                    merchant = transaction.merchant
                    note = transaction.note
                    date = transaction.date
                    category = transaction.category
                    selectedAccount = transaction.accountName
                } else if let firstAccount = accounts.first {
                    selectedAccount = firstAccount.name
                }
            }
        }
    }

    private func save() {
        guard let amount = Double(amountText), amount > 0 else { return }
        let finalMerchant = merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? category.displayName(isChinese: lang.isChinese)
            : merchant.trimmingCharacters(in: .whitespacesAndNewlines)

        if let transaction {
            transaction.amount = amount
            transaction.merchant = finalMerchant
            transaction.note = note
            transaction.date = date
            transaction.category = category
            transaction.accountName = selectedAccount
        } else {
            let record = TransactionRecord(
                amount: amount,
                merchant: finalMerchant,
                note: note,
                date: date,
                category: category,
                accountName: selectedAccount,
                source: .manual
            )
            modelContext.insert(record)
        }
        try? modelContext.save()
        dismiss()
    }
}
