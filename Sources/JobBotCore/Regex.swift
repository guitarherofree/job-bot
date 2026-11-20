import Foundation

/// Thin wrapper over NSRegularExpression (works the same on every platform Foundation runs on).
public struct Rx {
    public let regex: NSRegularExpression

    public init(_ pattern: String, caseInsensitive: Bool = true) {
        var options: NSRegularExpression.Options = []
        if caseInsensitive { options.insert(.caseInsensitive) }
        // Patterns are written by us and covered by tests; a bad one is a programming error.
        regex = try! NSRegularExpression(pattern: pattern, options: options)
    }

    public func matches(_ s: String) -> Bool {
        regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    /// The whole match and its groups (empty strings for groups that didn't take part).
    public func firstMatch(_ s: String) -> [String]? {
        guard let m = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
        return groups(m, in: s)
    }

    public func allMatches(_ s: String) -> [[String]] {
        regex.matches(in: s, range: NSRange(s.startIndex..., in: s)).map { groups($0, in: s) }
    }

    /// Ranges of whole matches.
    public func ranges(_ s: String) -> [Range<String.Index>] {
        regex.matches(in: s, range: NSRange(s.startIndex..., in: s)).compactMap { Range($0.range, in: s) }
    }

    public func replace(_ s: String, with template: String) -> String {
        regex.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: template)
    }

    private func groups(_ m: NSTextCheckingResult, in s: String) -> [String] {
        (0..<m.numberOfRanges).map { i in
            let r = m.range(at: i)
            guard r.location != NSNotFound, let range = Range(r, in: s) else { return "" }
            return String(s[range])
        }
    }
}

public enum Patterns {
    static let month = "(?:jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*\\.?"
    static let season = "(?:spring|summer|fall|autumn|winter)"
    static let datePart = "(?:(?:\(month)|\(season))\\s+|\\d{1,2}/)?(?:19|20)\\d{2}"
    static let endPart = "(?:\(datePart)|present|current|now|today|ongoing)"

    /// "Jan 2019 – Present", "2017-2019", "03/2018 to 06/2020".
    public static let dateRange = Rx("(\(datePart))\\s*(?:-|–|—|to|through|until)\\s*(\(endPart))")
    /// A single date such as "May 2014" or "2014".
    public static let singleDate = Rx("(?<![\\d/])(\(datePart))(?![\\d])")
    public static let email = Rx("[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}")
    public static let phone = Rx("(?:\\+?1[\\s.-]?)?\\(?\\d{3}\\)?[\\s.-]?\\d{3}[\\s.-]?\\d{4}")
    public static let url = Rx("(?:https?://[^\\s|,]+|www\\.[^\\s|,]+|(?:linkedin|github)\\.com/[^\\s|,]+)")
    /// "Atlanta, GA" or "New York, NY".
    public static let cityState = Rx("\\b([A-Z][A-Za-z.'\\-]+(?:\\s[A-Z][A-Za-z.'\\-]+){0,3}),\\s?([A-Z]{2})\\b", caseInsensitive: false)
}
