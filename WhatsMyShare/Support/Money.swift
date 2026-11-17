import Foundation

/// Converts between stored minor units (cents) and what people see/type.
enum Money {
    /// Number of decimal places for a currency (2 for USD/EUR/INR, 0 for JPY…).
    static func minorDigits(_ code: String) -> Int {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        return formatter.maximumFractionDigits
    }

    static func decimal(_ minor: Int, code: String) -> Decimal {
        Decimal(minor) / pow(Decimal(10), minorDigits(code))
    }

    static func format(_ minor: Int, code: String) -> String {
        decimal(minor, code: code).formatted(.currency(code: code))
    }

    /// Plain number for editing, e.g. "12.50" (uses the user's decimal separator).
    static func editingString(_ minor: Int, code: String) -> String {
        let digits = minorDigits(code)
        return decimal(minor, code: code).formatted(
            .number.precision(.fractionLength(digits)).grouping(.never)
        )
    }

    /// Parses user input like "12.5", "12,50" or "1,234.56" into minor units.
    static func parseMinor(_ text: String, code: String) -> Int? {
        guard let value = parseDecimal(text) else { return nil }
        var scaled = value * pow(Decimal(10), minorDigits(code))
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)
        return NSDecimalNumber(decimal: rounded).intValue
    }

    /// Lenient number parsing that accepts either "." or "," as the decimal mark.
    static func parseDecimal(_ text: String) -> Decimal? {
        var cleaned = text.filter { $0.isNumber || $0 == "." || $0 == "," }
        guard !cleaned.isEmpty else { return nil }

        let separator = Locale.current.decimalSeparator ?? "."
        let grouping = separator == "," ? "." : ","
        // If only the "other" mark appears once with 1–2 digits after it, treat
        // it as the decimal mark too (people type 12.50 on a comma keyboard).
        let groupingCount = cleaned.filter { String($0) == grouping }.count
        if !cleaned.contains(separator), groupingCount == 1,
           let tail = cleaned.split(separator: Character(grouping)).last, tail.count <= 2,
           cleaned.last.map({ String($0) }) != grouping {
            cleaned = cleaned.replacingOccurrences(of: grouping, with: ".")
        } else {
            cleaned = cleaned.replacingOccurrences(of: grouping, with: "")
            cleaned = cleaned.replacingOccurrences(of: separator, with: ".")
        }
        return Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX"))
    }

    static func symbol(for code: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        return formatter.currencySymbol ?? code
    }

    static var defaultCurrencyCode: String {
        Locale.current.currency?.identifier ?? "USD"
    }

    /// Common currencies first, then the rest alphabetically.
    static var allCurrencyCodes: [String] {
        let preferred = [defaultCurrencyCode, "USD", "EUR", "GBP", "INR", "CAD", "AUD", "JPY"]
        var seen = Set<String>()
        let rest = Locale.commonISOCurrencyCodes.sorted()
        return (preferred + rest).filter { seen.insert($0).inserted }
    }

    static func currencyName(_ code: String) -> String {
        Locale.current.localizedString(forCurrencyCode: code) ?? code
    }
}
