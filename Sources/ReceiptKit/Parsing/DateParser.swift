import Foundation

/// Finds the purchase date. Assumes day-first order (21.10.2026, 21/10/26),
/// plus ISO yyyy-MM-dd.
enum DateParser {
    static var dateRegex: Regex<Substring> {
        #/\b\d{4}-\d{1,2}-\d{1,2}\b|\b\d{1,2}[./-]\d{1,2}[./-]\d{2,4}\b/#
    }

    static func date(in text: String) -> Date? {
        for match in text.matches(of: dateRegex) {
            if let date = parse(String(match.output)) { return date }
        }
        return nil
    }

    static func removingDates(from text: String) -> String {
        text.replacing(dateRegex, with: " ")
    }

    private static func parse(_ raw: String) -> Date? {
        let parts = raw.split(whereSeparator: { $0 == "." || $0 == "/" || $0 == "-" })
        guard parts.count == 3 else { return nil }

        let format: String
        if parts[0].count == 4 {
            format = "yyyy.M.d"
        } else if parts[2].count == 4 {
            format = "d.M.yyyy"
        } else if parts[2].count == 2 {
            format = "d.M.yy"
        } else {
            return nil
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.isLenient = false
        formatter.dateFormat = format
        return formatter.date(from: parts.joined(separator: "."))
    }
}
