import Foundation

struct AmountMatch: Equatable {
    let value: Decimal
    let range: Range<String.Index>
}

/// Finds money amounts in a row of text.
///
/// Only numbers with exactly two decimals count, so quantities ("2"), weights
/// ("1.500") and street numbers are ignored. Handles "12.50", "9,99",
/// "1 234,56", "1,234.56" and "1.234,56".
enum AmountParser {
    private static var amountRegex: Regex<Substring> {
        #/-?\d{1,3}(?:[ ,.]\d{3})*[.,]\d{2}(?!\d)|-?\d+[.,]\d{2}(?!\d)/#
    }

    static func matches(in text: String) -> [AmountMatch] {
        text.matches(of: amountRegex).compactMap { match in
            decimal(from: match.output).map { AmountMatch(value: $0, range: match.range) }
        }
    }

    static func decimal(from raw: Substring) -> Decimal? {
        var digits = String(raw).replacingOccurrences(of: " ", with: "")
        let isNegative = digits.hasPrefix("-")
        if isNegative { digits.removeFirst() }

        // The last separator is the decimal one; any earlier ones are thousands separators.
        guard let separator = digits.lastIndex(where: { $0 == "." || $0 == "," }) else { return nil }
        let integerPart = digits[..<separator].filter { $0.isASCII && $0.isNumber }
        let fractionPart = digits[digits.index(after: separator)...]

        guard !integerPart.isEmpty,
              fractionPart.count == 2,
              fractionPart.allSatisfy({ $0.isASCII && $0.isNumber }),
              let value = Decimal(string: "\(integerPart).\(fractionPart)", locale: Locale(identifier: "en_US_POSIX"))
        else { return nil }

        return isNegative ? -value : value
    }
}
