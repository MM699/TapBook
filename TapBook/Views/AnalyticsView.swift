import Charts
import SwiftData
import SwiftUI

struct AnalyticsView: View {
    @Environment(LanguageStore.self) private var lang

    @Query(sort: \TransactionRecord.date, order: .reverse)
    private var allTransactions: [TransactionRecord]

    @AppStorage("tapbook_exclude_topup_from_total") private var excludeTopUpFromTotal: Bool = true

    @State private var selectedMonth: Date = .now

    private var monthTransactions: [TransactionRecord] {
        let cal = Calendar.current
        return allTransactions.filter {
            cal.isDate($0.date, equalTo: selectedMonth, toGranularity: .month)
        }
    }

    private var effectiveTransactions: [TransactionRecord] {
        monthTransactions.filter {
            $0.amount > 0 && (!excludeTopUpFromTotal || $0.category != .octopusTopUp)
        }
    }

    private var totalSpent: Double {
        effectiveTransactions.reduce(0) { $0 + $1.amount }
    }

    private var categoryBreakdown: [(category: SpendingCategory, total: Double, ratio: Double)] {
        guard totalSpent > 0 else { return [] }
        let grouped = Dictionary(grouping: effectiveTransactions, by: \.category)
        return grouped.compactMap { key, items in
            let sum = items.reduce(0) { $0 + $1.amount }
            guard sum > 0 else { return nil }
            return (category: key, total: sum, ratio: sum / totalSpent)
        }
        .sorted { $0.total > $1.total }
    }

    private var accountBreakdown: [(account: String, total: Double, count: Int)] {
        let nonZero = monthTransactions.filter { $0.amount > 0 }
        let grouped = Dictionary(grouping: nonZero, by: \.accountName)
        return grouped.compactMap { key, items in
            let sum = items.reduce(0) { $0 + $1.amount }
            guard sum > 0 else { return nil }
            return (account: key, total: sum, count: items.count)
        }
        .sorted { $0.total > $1.total }
    }

    private var autoLoggedRatio: Double {
        guard !monthTransactions.isEmpty else { return 0 }
        let autoCount = monthTransactions.filter { $0.source == .appleWallet }.count
        return Double(autoCount) / Double(monthTransactions.count)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    monthSelector
                    if totalSpent <= 0 {
                        emptyState
                    } else {
                        summaryMetricsRow
                        categoryChartCard
                        if !accountBreakdown.isEmpty {
                            accountBreakdownCard
                        }
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(lang.t("消費統計", "Analytics"))
        }
    }

    private var monthSelector: some View {
        HStack {
            Button {
                shiftMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }

            Spacer()
            Text(lang.formatMonthTitle(selectedMonth))
                .font(.headline)
            Spacer()

            Button {
                shiftMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var summaryMetricsRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(lang.t("總支出", "Total Spent"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(lang.formatCurrency(totalSpent))
                    .font(.title3.weight(.bold))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(lang.t("筆數 / 自動記帳", "Count / Auto"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(monthTransactions.count) · \(Int(autoLoggedRatio * 100))%")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.blue)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var categoryChartCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(lang.t("分類佔比", "By Category"))
                .font(.headline)

            Chart(categoryBreakdown, id: \.category) { item in
                SectorMark(
                    angle: .value("Amount", item.total),
                    innerRadius: .ratio(0.58),
                    angularInset: 2
                )
                .foregroundStyle(item.category.color)
                .cornerRadius(5)
            }
            .frame(height: 210)
            .overlay {
                VStack(spacing: 2) {
                    Text(lang.t("總計", "Total"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(lang.formatCurrency(totalSpent))
                        .font(.headline.weight(.bold))
                }
            }

            VStack(spacing: 10) {
                ForEach(categoryBreakdown, id: \.category) { item in
                    HStack {
                        Image(systemName: item.category.icon)
                            .foregroundStyle(item.category.color)
                            .frame(width: 24)
                        Text(item.category.displayName(isChinese: lang.isChinese))
                            .font(.subheadline)
                        Spacer()
                        Text("\(Int(item.ratio * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 40, alignment: .trailing)
                        Text(lang.formatCurrency(item.total))
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var accountBreakdownCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(lang.t("按帳戶／卡片分析", "By Card / Account"))
                .font(.headline)

            Chart(accountBreakdown, id: \.account) { item in
                BarMark(
                    x: .value("Amount", item.total),
                    y: .value("Account", item.account)
                )
                .foregroundStyle(Color(hex: "#2563EB").gradient)
                .cornerRadius(6)
                .annotation(position: .trailing) {
                    Text(lang.formatCurrency(item.total))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: CGFloat(max(accountBreakdown.count * 44, 100)))
            .chartXAxis(.hidden)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.pie.fill")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text(lang.t("今個月暫無消費數據", "No data for this month"))
                .font(.headline)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func shiftMonth(by value: Int) {
        if let next = Calendar.current.date(byAdding: .month, value: value, to: selectedMonth) {
            selectedMonth = next
        }
    }
}
