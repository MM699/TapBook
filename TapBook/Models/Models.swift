import Foundation
import SwiftData
import SwiftUI

// MARK: - Spending Category

enum SpendingCategory: String, CaseIterable, Codable, Identifiable {
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

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .dining: return "fork.knife"
        case .transport: return "tram.fill"
        case .shopping: return "bag.fill"
        case .groceries: return "cart.fill"
        case .convenience: return "storefront.fill"
        case .coffee: return "cup.and.saucer.fill"
        case .entertainment: return "film.fill"
        case .bills: return "doc.text.fill"
        case .health: return "cross.case.fill"
        case .octopusTopUp: return "creditcard.and.123"
        case .other: return "ellipsis.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .dining: return .orange
        case .transport: return .blue
        case .shopping: return .pink
        case .groceries: return .green
        case .convenience: return .teal
        case .coffee: return .brown
        case .entertainment: return .purple
        case .bills: return .indigo
        case .health: return .red
        case .octopusTopUp: return .yellow
        case .other: return .gray
        }
    }

    func displayName(isChinese: Bool) -> String {
        switch self {
        case .dining: return isChinese ? "餐飲" : "Dining"
        case .transport: return isChinese ? "交通" : "Transport"
        case .shopping: return isChinese ? "購物" : "Shopping"
        case .groceries: return isChinese ? "超市日用" : "Groceries"
        case .convenience: return isChinese ? "便利店" : "Convenience"
        case .coffee: return isChinese ? "咖啡飲品" : "Coffee & Drinks"
        case .entertainment: return isChinese ? "娛樂" : "Entertainment"
        case .bills: return isChinese ? "帳單雜費" : "Bills"
        case .health: return isChinese ? "醫療保健" : "Health"
        case .octopusTopUp: return isChinese ? "八達通增值" : "Octopus Top-Up"
        case .other: return isChinese ? "其他" : "Other"
        }
    }
}

// MARK: - Transaction Source

enum TransactionSource: String, Codable, CaseIterable {
    case manual
    case appleWallet
    case quickTemplate
    case siri

    var icon: String {
        switch self {
        case .manual: return "square.and.pencil"
        case .appleWallet: return "wave.3.right.circle.fill"
        case .quickTemplate: return "bolt.fill"
        case .siri: return "waveform.circle.fill"
        }
    }

    func badgeLabel(isChinese: Bool) -> String {
        switch self {
        case .manual: return isChinese ? "手動" : "Manual"
        case .appleWallet: return isChinese ? "Apple Wallet 自動" : "Apple Wallet"
        case .quickTemplate: return isChinese ? "快捷記帳" : "Quick Tap"
        case .siri: return "Siri"
        }
    }
}

// MARK: - Account Type

enum AccountType: String, Codable, CaseIterable, Identifiable {
    case creditCard
    case octopus
    case debitCard
    case cash
    case fps

    var id: String { rawValue }

    var defaultIcon: String {
        switch self {
        case .creditCard: return "creditcard.fill"
        case .octopus: return "wave.3.right"
        case .debitCard: return "banknote.fill"
        case .cash: return "dollarsign.circle.fill"
        case .fps: return "qrcode"
        }
    }

    func displayName(isChinese: Bool) -> String {
        switch self {
        case .creditCard: return isChinese ? "信用卡 (Apple Pay)" : "Credit Card (Apple Pay)"
        case .octopus: return isChinese ? "八達通" : "Octopus"
        case .debitCard: return isChinese ? "扣帳卡" : "Debit Card"
        case .cash: return isChinese ? "現金" : "Cash"
        case .fps: return isChinese ? "轉數快 / PayMe" : "FPS / PayMe"
        }
    }
}

// MARK: - SwiftData Models

@Model
final class TransactionRecord {
    var id: UUID
    var amount: Double
    var merchant: String
    var note: String
    var date: Date
    var categoryRaw: String
    var accountName: String
    var sourceRaw: String
    var currencyCode: String

    init(
        id: UUID = UUID(),
        amount: Double,
        merchant: String,
        note: String = "",
        date: Date = .now,
        category: SpendingCategory = .other,
        accountName: String = "Visa",
        source: TransactionSource = .manual,
        currencyCode: String = "HKD"
    ) {
        self.id = id
        self.amount = amount
        self.merchant = merchant
        self.note = note
        self.date = date
        self.categoryRaw = category.rawValue
        self.accountName = accountName
        self.sourceRaw = source.rawValue
        self.currencyCode = currencyCode
    }

    var category: SpendingCategory {
        get { SpendingCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    var source: TransactionSource {
        get { TransactionSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }
}

@Model
final class PaymentAccount {
    var id: UUID
    var name: String
    var walletMatchKeywords: String
    var typeRaw: String
    var colorHex: String
    var iconName: String
    var sortOrder: Int

    init(
        id: UUID = UUID(),
        name: String,
        walletMatchKeywords: String = "",
        type: AccountType = .creditCard,
        colorHex: String = "#1D4ED8",
        iconName: String? = nil,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.walletMatchKeywords = walletMatchKeywords
        self.typeRaw = type.rawValue
        self.colorHex = colorHex
        self.iconName = iconName ?? type.defaultIcon
        self.sortOrder = sortOrder
    }

    var type: AccountType {
        get { AccountType(rawValue: typeRaw) ?? .creditCard }
        set { typeRaw = newValue.rawValue }
    }

    var keywordsList: [String] {
        walletMatchKeywords
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
    }
}

@Model
final class MerchantRule {
    var id: UUID
    var keyword: String
    var categoryRaw: String
    var isDefault: Bool

    init(
        id: UUID = UUID(),
        keyword: String,
        category: SpendingCategory,
        isDefault: Bool = false
    ) {
        self.id = id
        self.keyword = keyword
        self.categoryRaw = category.rawValue
        self.isDefault = isDefault
    }

    var category: SpendingCategory {
        get { SpendingCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }
}

@Model
final class QuickTemplate {
    var id: UUID
    var titleZh: String
    var titleEn: String
    var amount: Double
    var merchant: String
    var categoryRaw: String
    var accountName: String
    var iconName: String
    var sortOrder: Int

    init(
        id: UUID = UUID(),
        titleZh: String,
        titleEn: String,
        amount: Double,
        merchant: String,
        category: SpendingCategory,
        accountName: String,
        iconName: String,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.titleZh = titleZh
        self.titleEn = titleEn
        self.amount = amount
        self.merchant = merchant
        self.categoryRaw = category.rawValue
        self.accountName = accountName
        self.iconName = iconName
        self.sortOrder = sortOrder
    }

    var category: SpendingCategory {
        get { SpendingCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    func title(isChinese: Bool) -> String {
        isChinese ? titleZh : titleEn
    }
}
