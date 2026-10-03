import Foundation

enum AmountInputFormatter {
    static let maximumTransactionPaise: Int64 = 100_000_000
    static let transactionLimitMessage = "Amount cannot exceed Rs 10,00,000."

    static func normalized(_ value: String) -> String {
        value.replacingOccurrences(of: ",", with: "")
    }

    static func exceedsTransactionLimit(_ value: String) -> Bool {
        let normalizedValue = normalized(value)
        guard normalizedValue.range(of: #"^[0-9]+(?:\.[0-9]*)?$"#, options: .regularExpression) != nil else {
            return false
        }
        let parts = normalizedValue.split(separator: ".", omittingEmptySubsequences: false)
        let trimmedWhole = parts[0].drop(while: { $0 == "0" })
        let whole = trimmedWhole.isEmpty ? "0" : String(trimmedWhole)
        let maximumWhole = "1000000"
        if whole.count != maximumWhole.count {
            return whole.count > maximumWhole.count
        }
        if whole != maximumWhole {
            return whole > maximumWhole
        }
        return parts.count == 2 && parts[1].contains(where: { $0 != "0" })
    }

    static func formatted(_ value: String) -> String {
        let normalizedValue = normalized(value)
        guard !normalizedValue.isEmpty else { return "" }
        guard normalizedValue.range(of: #"^[0-9]*(?:\.[0-9]*)?$"#, options: .regularExpression) != nil else {
            return value
        }

        let parts = normalizedValue.split(separator: ".", omittingEmptySubsequences: false)
        let groupedInteger = indianGroupedDigits(String(parts[0]))
        guard parts.count == 2 else { return groupedInteger }
        return groupedInteger + "." + String(parts[1])
    }

    private static func indianGroupedDigits(_ digits: String) -> String {
        guard digits.count > 3 else { return digits }
        let finalGroup = String(digits.suffix(3))
        let leadingDigits = String(digits.dropLast(3))
        var groups: [String] = []
        var end = leadingDigits.endIndex

        while end > leadingDigits.startIndex {
            let start = leadingDigits.index(end, offsetBy: -2, limitedBy: leadingDigits.startIndex)
                ?? leadingDigits.startIndex
            groups.insert(String(leadingDigits[start..<end]), at: 0)
            end = start
        }
        return groups.joined(separator: ",") + "," + finalGroup
    }
}
