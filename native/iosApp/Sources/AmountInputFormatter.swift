import SwiftUI

enum AmountInputFormatter {
    static func binding(_ binding: Binding<String>) -> Binding<String> {
        Binding(
            get: { binding.wrappedValue },
            set: { binding.wrappedValue = Self.formatted($0) }
        )
    }

    static func normalized(_ value: String) -> String {
        value.replacingOccurrences(of: ",", with: "")
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
