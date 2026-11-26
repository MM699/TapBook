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

    static func parse(title: String, subtitle: String = "", body: String, appName: String = "") -> ParsedNotification? {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSubtitle = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedApp = appName.trimmingCharacters(in: .whitespacesAndNewlines)

        let combined = [trimmedTitle, trimmedSubtitle, trimmedBody, trimmedApp]
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
        let accountHint = detectAccountHint(title: trimmedTitle, subtitle: trimmedSubtitle, body: trimmedBody, appName: trimmedApp)
        let isOctopus = accountHint == "八達通"
        let isPayMe = accountHint == "PayMe"
        let isAlipay = accountHint == "AlipayHK"

        // Always track Octopus new balance if present (enables balance-diff fallback if Subtitle wasn't mapped)
        let detectedNewBalance: Double? = isOctopus ? extractBalanceAmount(from: combined) : nil
        let previousOctopusBalance = UserDefaults.standard.object(forKey: "tapbook_last_octopus_balance") as? Double
        if let detectedNewBalance {
            UserDefaults.standard.set(detectedNewBalance, forKey: "tapbook_last_octopus_balance")
        }

        // 3. Extract spend amount (prioritize Subtitle first — Apple Wallet Octopus puts "消費：HK$31.00" in Subtitle!)
        let primaryText = [trimmedSubtitle, trimmedBody].filter { !$0.isEmpty }.joined(separator: "\n")
        var resolvedAmountAndCurrency = extractSpendAmount(from: primaryText.isEmpty ? combined : primaryText, fallbackText: combined)
        var inferredTopUp = isTopUp

        // Fallback for Octopus if user didn't map Subtitle yet: compute diff from previous balance
        if resolvedAmountAndCurrency == nil, isOctopus, let newBal = detectedNewBalance, let oldBal = previousOctopusBalance {
            let diff = ((oldBal - newBal) * 100).rounded() / 100
            if diff > 0 {
                resolvedAmountAndCurrency = (diff, "HKD")
            } else if diff < 0 {
                resolvedAmountAndCurrency = (abs(diff), "HKD")
                inferredTopUp = true
            }
        }

        guard let (amount, currency) = resolvedAmountAndCurrency, amount > 0 else {
            return nil
        }

        // 4. Determine merchant & optional category override
        let categoryOverride: SpendingCategory? = (isOctopus && inferredTopUp) ? .octopusTopUp : nil

        let merchant: String
        if isOctopus && inferredTopUp {
            merchant = "八達通增值"
        } else if let extracted = extractMerchant(title: trimmedTitle, subtitle: trimmedSubtitle, body: trimmedBody, isPayMe: isPayMe, isAlipay: isAlipay) {
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

    private static func detectAccountHint(title: String, subtitle: String, body: String, appName: String) -> String {
        let lower = "\(appName) \(title) \(subtitle) \(body)".lowercased()
        if lower.contains("octopus") || lower.contains("八達通") {
            return "八達通"
        }
        if lower.contains("payme") {
            return "PayMe"
        }
        if lower.contains("alipay") || lower.contains("支付寶") {
            return "AlipayHK"
        }
        // For Apple Wallet / Bank notifications, `title` is usually the card or bank name
        // (e.g. "American Express", "HSBC", "Hang Seng"). Never concatenate `body` (which contains merchant + amount)
        // so unmatched banks stay clean (e.g. "HSBC" instead of "HSBC merchant.X HK$103.00").
        if !title.isEmpty {
            return title
        }
        if !appName.isEmpty {
            return appName
        }
        return "Visa"
    }

    private static func extractBalanceAmount(from text: String) -> Double? {
        let pattern = #"(?:新餘額為|新餘額|餘額為|餘額|new balance is|new balance|balance)\s*[:：]?\s*(?:HK\$|HKD|\$)?\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let nsRange = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: nsRange),
              match.range(at: 1).location != NSNotFound,
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        let numStr = String(text[range]).replacingOccurrences(of: ",", with: "")
        return Double(numStr)
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

    private static func extractMerchant(title: String, subtitle: String, body: String, isPayMe: Bool, isAlipay: Bool) -> String? {
        let searchable = [subtitle, body].filter { !$0.isEmpty }.joined(separator: "\n")
        // Check body/subtitle patterns first (PayMe, AlipayHK, HK banks)
        let patterns = [
            #"(?:支付|付款|轉帳|過數).*?(?:給|予|向|to)\s+([^\n。.,，!！]{1,36})"#,
            #"(?:向|於)\s*([^\n。.,，!！]{1,36}?)\s*(?:付款|支付|消費|簽帳|簽賬)"#,
            #"(?:paid|payment|spent|charged|approved).*?\b(?:to|at)\s+([^\n.,!]{1,36})"#
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let nsRange = NSRange(searchable.startIndex..., in: searchable)
                if let match = regex.firstMatch(in: searchable, options: [], range: nsRange),
                   match.range(at: 1).location != NSNotFound,
                   let range = Range(match.range(at: 1), in: searchable) {
                    let candidate = String(searchable[range])
                        .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
                    if !candidate.isEmpty && !genericAppTitles.contains(candidate.lowercased()) {
                        return candidate
                    }
                }
            }
        }

        // Apple Wallet card notification format:
        // Title = "American Express" / "HSBC", Body (or Subtitle) = "宜家，香港銅鑼灣 HK$19.90" or "merchant.ApplePayDeepvert HK$103.00"
        if !isPayMe && !isAlipay {
            let sanitized = stripBalanceClauses(from: searchable)
            let beforeAmountPattern = #"^([^\n]+?)\s+(?:HK\$|HKD|US\$|USD|JP¥|JPY|CN¥|CNY|RMB|GBP|£|EUR|€|TWD|NT\$|MOP|港幣|\$)\s*[0-9][0-9,]*(?:\.[0-9]{1,2})?"#
            if let regex = try? NSRegularExpression(pattern: beforeAmountPattern, options: [.caseInsensitive, .anchorsMatchLines]) {
                let nsRange = NSRange(sanitized.startIndex..., in: sanitized)
                if let match = regex.firstMatch(in: sanitized, options: [], range: nsRange),
                   match.range(at: 1).location != NSNotFound,
                   let range = Range(match.range(at: 1), in: sanitized) {
                    var candidate = String(sanitized[range])
                        .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
                    if candidate.lowercased().hasPrefix("merchant.") {
                        candidate = String(candidate.dropFirst("merchant.".count))
                    }
                    let spendPrefixes = ["消費", "扣款", "付款", "支付", "簽帳", "簽賬", "增值", "自動增值", "paid", "spent", "payment"]
                    let isJustSpendLabel = spendPrefixes.contains { candidate.lowercased() == $0 || candidate.lowercased().hasPrefix("\($0):") || candidate.lowercased().hasPrefix("\($0)：") }
                    if !candidate.isEmpty && !isJustSpendLabel && !genericAppTitles.contains(candidate.lowercased()) {
                        return candidate
                    }
                }
            }
        }

        // Fallback: Some Wallet notifications put the merchant name directly in `title` (e.g. "Starbucks")
        if !isPayMe && !isAlipay && !title.isEmpty && !genericAppTitles.contains(title.lowercased()) {
            return title
        }
        return nil
    }
}
