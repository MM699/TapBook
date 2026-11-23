import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case zhHK
    case en

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "跟隨系統 / System"
        case .zhHK: return "繁體中文（香港）"
        case .en: return "English"
        }
    }
}

@Observable
final class LanguageStore {
    var selectedLanguage: AppLanguage {
        didSet {
            UserDefaults.standard.set(selectedLanguage.rawValue, forKey: "tapbook_language")
        }
    }

    init() {
        let saved = UserDefaults.standard.string(forKey: "tapbook_language") ?? AppLanguage.zhHK.rawValue
        self.selectedLanguage = AppLanguage(rawValue: saved) ?? .zhHK
    }

    var isChinese: Bool {
        switch selectedLanguage {
        case .zhHK:
            return true
        case .en:
            return false
        case .system:
            let preferred = Locale.preferredLanguages.first ?? "zh-HK"
            return preferred.hasPrefix("zh")
        }
    }

    var locale: Locale {
        isChinese ? Locale(identifier: "zh_HK") : Locale(identifier: "en_HK")
    }

    func t(_ zh: String, _ en: String) -> String {
        isChinese ? zh : en
    }

    func formatCurrency(_ amount: Double, currencyCode: String = "HKD") -> String {
        let symbol = currencyCode == "HKD" ? "HK$" : "\(currencyCode) "
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = amount.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 2
        formatter.maximumFractionDigits = 2
        let numberStr = formatter.string(from: NSNumber(value: amount)) ?? String(format: "%.2f", amount)
        return "\(symbol)\(numberStr)"
    }

    func formatDayHeader(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return isChinese ? "今日" : "Today"
        } else if calendar.isDateInYesterday(date) {
            return isChinese ? "尋日" : "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.dateFormat = isChinese ? "M月d日 (E)" : "EEE, d MMM"
            return formatter.string(from: date)
        }
    }

    func formatMonthTitle(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = isChinese ? "yyyy年M月" : "MMMM yyyy"
        return formatter.string(from: date)
    }

    func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)
        let r, g, b: UInt64
        switch cleaned.count {
        case 6:
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (29, 78, 216)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255.0,
            green: Double(g) / 255.0,
            blue: Double(b) / 255.0,
            opacity: 1.0
        )
    }
}
