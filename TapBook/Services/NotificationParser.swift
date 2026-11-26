import Foundation

struct ParsedNotification {
    let amount: Double
    let currencyCode: String
    let merchant: String
    let accountHint: String
    let categoryOverride: SpendingCategory?
}

enum NotificationParser {
    private static let ignoredKeywords: [String] = [
        "驗證碼", "一次性密碼", "登入密碼", "保安編碼", "otp", "verification code",
        "security code", "one-time password", "passcode",
        "你已收到", "您已收到", "已收到", "已存入", "已轉入", "已退款", "退款",
        "you received", "paid you", "sent you", "refunded", "refund"
    ]

    private static let topUpKeywords: [String] = [
        "增值", "自動增值", "top up", "top-up", "add value", "aavs", "reloaded"
    ]

    private static let genericAppTitles: Set<String> = [
        "octopus", "八達通", "payme", "alipay", "alipayhk", "支付寶", "支付寶香港",
        "wallet", "銀包", "錢包", "hsbc", "hsbc hk", "滙豐", "hang seng", "恒生",
        "bochk", "中銀", "中銀香港", "american express", "amex", "ae", "美國運通",
        "citi", "citibank", "scb", "standard chartered", "渣打", "mox", "dbs", "za bank", "livi"
    ]

    static func parse(title: String, body: String, appName: String = "") -> ParsedNotification? {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedApp = appName.trimmingCharacters(in: .whitespacesAndNewlines)

        let combined = [trimmedTitle, trimmedBody, trimmedApp]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        guard !combined.isEmpty else { return nil }
        let lowerCombined = combined.lowercased()

        // 1. Ignore OTPs, incoming transfers, refunds (unless it's an Octopus top-up)
        let isTopUp = topUpKeywords.contains { lowerCombined.contains($0) }
        if !isTopUp && ignoredKeywords.contains(where: { lowerCombined.contains($0) }) {
            return nil
        }

        // 2. Determine account source
        let accountHint = detectAccountHint(title: trimmedTitle, body: trimmedBody, appName: trimmedApp)
        let isOctopus = accountHint == "八達通"
        let isPayMe = accountHint == "PayMe"
        let isAlipay = accountHint == "AlipayHK"

        // 3. Extract spend amount (carefully ignoring balance / remaining credit text)
        guard let (amount, currency) = extractSpendAmount(from: trimmedBody.isEmpty ? combined : trimmedBody, fallbackText: combined),
              amount > 0 else {
            return nil
        }

        // 4. Determine merchant & optional category override
        let categoryOverride: SpendingCategory? = (isOctopus && isTopUp) ? .octopusTopUp : nil

        let merchant: String
        if isOctopus && isTopUp {
            merchant = "八達通增值"
        } else if let extracted = extractMerchant(title: trimmedTitle, body: trimmedBody, isPayMe: isPayMe, isAlipay: isAlipay) {
            merchant = extracted
        } else if isOctopus {
            merchant = "八達通消費"
        } else if isPayMe {
            merchant = "PayMe 消費"
        } else if isAlipay {
            merchant = "AlipayHK 消費"
        } else {
            merchant = "Apple Pay"
        }

        return ParsedNotification(
            amount: amount,
            currencyCode: currency,
            merchant: merchant,
            accountHint: accountHint,
            categoryOverride: categoryOverride
        )
    }

    // MARK: - Account Detection

    private static func detectAccountHint(title: String, body: String, appName: String) -> String {
        let lower = "\(appName) \(title) \(body)".lowercased()
        if lower.contains("octopus") || lower.contains("八達通") {
            return "八達通"
        }
        if lower.contains("payme") {
            return "PayMe"
        }
        if lower.contains("alipay") || lower.contains("支付寶") {
            return "AlipayHK"
        }
        if !title.isEmpty && !body.isEmpty {
            return "\(title) \(body)"
        }
        return !title.isEmpty ? title : (!appName.isEmpty ? appName : body)
    }

    // MARK: - Amount Extraction (ignores balance / available credit lines)

    private static func extractSpendAmount(from primaryText: String, fallbackText: String) -> (Double, String)? {
        // First strip lines/clauses that describe remaining balance or credit limit
        let sanitizedPrimary = stripBalanceClauses(from: primaryText)

        // Priority 1: Explicit spend/top-up keyword followed by currency + number
        let explicitPattern = #"(?:消費|扣款|付款|支付|簽帳|簽賬|交易金額|增值|自動增值|paid|spent|payment|purchase|charged|approved|deducted|top[- ]?up|add value)\s*[:：]?\s*(HK\$|HKD|US\$|USD|JP¥|JPY|CN¥|CNY|RMB|GBP|£|EUR|€|TWD|NT\$|MOP|港幣|\$)?\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)"#
        if let match = firstAmountMatch(pattern: explicitPattern, in: sanitizedPrimary, currencyGroup: 1, numberGroup: 2) {
            return match
        }

        // Priority 2: Currency-prefixed amount in sanitized primary text (e.g. "HK$8.00", "USD 12.50", "$45")
        let currencyPattern = #"(HK\$|HKD|US\$|USD|JP¥|JPY|CN¥|CNY|RMB|GBP|£|EUR|€|TWD|NT\$|MOP|港幣|\$)\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)"#
        if let match = firstAmountMatch(pattern: currencyPattern, in: sanitizedPrimary, currencyGroup: 1, numberGroup: 2) {
            return match
        }

        // Priority 3: Fallback across sanitized combined text
        let sanitizedFallback = stripBalanceClauses(from: fallbackText)
        if let match = firstAmountMatch(pattern: currencyPattern, in: sanitizedFallback, currencyGroup: 1, numberGroup: 2) {
            return match
        }

        return nil
    }

    private static func stripBalanceClauses(from text: String) -> String {
        let balanceMarkers = [
            "新餘額", "餘額", "結餘", "可用額度", "剩餘額度",
            "new balance", "balance", "remaining", "available credit"
        ]
        let lines = text.components(separatedBy: .newlines)
        let keptLines = lines.compactMap { line -> String? in
            let lower = line.lowercased()
            for marker in balanceMarkers {
                if let range = lower.range(of: marker) {
                    // Keep only the portion BEFORE the balance marker on the same line
                    let prefix = String(line[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                    return prefix.isEmpty ? nil : prefix
                }
            }
            return line
        }
        return keptLines.joined(separator: "\n")
    }

    private static func firstAmountMatch(
        pattern: String,
        in text: String,
        currencyGroup: Int,
        numberGroup: Int
    ) -> (Double, String)? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let nsRange = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: nsRange) else {
            return nil
        }

        var rawCurrency = ""
        let currRange = match.range(at: currencyGroup)
        if currRange.location != NSNotFound, let swiftRange = Range(currRange, in: text) {
            rawCurrency = String(text[swiftRange])
        }

        let numRange = match.range(at: numberGroup)
        guard numRange.location != NSNotFound, let swiftNumRange = Range(numRange, in: text) else {
            return nil
        }
        let numString = String(text[swiftNumRange]).replacingOccurrences(of: ",", with: "")
        guard let value = Double(numString), value > 0 else {
            return nil
        }

        return (value, normalizeCurrency(rawCurrency))
    }

    private static func normalizeCurrency(_ raw: String) -> String {
        let upper = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        switch upper {
        case "", "$", "HK$", "HKD", "港幣": return "HKD"
        case "US$", "USD": return "USD"
        case "JP¥", "JPY": return "JPY"
        case "CN¥", "CNY", "RMB": return "CNY"
        case "£", "GBP": return "GBP"
        case "€", "EUR": return "EUR"
        case "NT$", "TWD": return "TWD"
        case "MOP": return "MOP"
        default: return upper
        }
    }

    // MARK: - Merchant Extraction

    private static func extractMerchant(title: String, body: String, isPayMe: Bool, isAlipay: Bool) -> String? {
        // Check body patterns first (PayMe, AlipayHK, HK banks)
        let patterns = [
            #"(?:支付|付款|轉帳|過數).*?(?:給|予|向|to)\s+([^\n。.,，!！]{1,36})"#,
            #"(?:向|於)\s*([^\n。.,，!！]{1,36}?)\s*(?:付款|支付|消費|簽帳|簽賬)"#,
            #"(?:paid|payment|spent|charged|approved).*?\b(?:to|at)\s+([^\n.,!]{1,36})"#
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let nsRange = NSRange(body.startIndex..., in: body)
                if let match = regex.firstMatch(in: body, options: [], range: nsRange),
                   match.range(at: 1).location != NSNotFound,
                   let range = Range(match.range(at: 1), in: body) {
                    let candidate = String(body[range])
                        .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
                    if !candidate.isEmpty && !genericAppTitles.contains(candidate.lowercased()) {
                        return candidate
                    }
                }
            }
        }

        // Fallback: Apple Wallet credit card notifications put the merchant name directly in `title` (e.g. "Starbucks")
        if !isPayMe && !isAlipay && !title.isEmpty && !genericAppTitles.contains(title.lowercased()) {
            return title
        }
        return nil
    }
}
