import Foundation

/// Rules every piece of generated writing passes through.
public enum WritingRules {
    /// Removes em dashes (and spaced en dashes used as dashes), tidies spacing and punctuation.
    /// Keeps unspaced en dashes in ranges such as "2019–2021" and "K–12".
    public static func clean(_ text: String) -> String {
        var s = text
        // Spaced dashes become commas: "work — and more" → "work, and more".
        for dash in [" — ", " – ", " ― ", " -- "] {
            s = s.replacingOccurrences(of: dash, with: ", ")
        }
        // Unspaced em dashes between words also become commas; at a line start they go away.
        s = s.replacingOccurrences(of: "—", with: ", ")
        s = s.replacingOccurrences(of: "―", with: ", ")
        // Tidy up what that may leave behind.
        while s.contains(" ,") { s = s.replacingOccurrences(of: " ,", with: ",") }
        while s.contains(",,") { s = s.replacingOccurrences(of: ",,", with: ",") }
        s = s.replacingOccurrences(of: ", .", with: ".")
        s = s.replacingOccurrences(of: ",.", with: ".")
        s = s.replacingOccurrences(of: ", ,", with: ",")
        s = s.replacingOccurrences(of: ":,", with: ":")
        let lines = s.components(separatedBy: "\n").map { line -> String in
            var l = line
            while l.contains("  ") { l = l.replacingOccurrences(of: "  ", with: " ") }
            while l.hasPrefix(", ") { l.removeFirst(2) }
            while l.hasPrefix(",") { l.removeFirst() }
            if l.hasSuffix(", ") { l.removeLast(2) }
            if l.hasSuffix(",") && !line.hasSuffix(",") { l.removeLast() }
            return l.trimmingCharacters(in: .whitespaces)
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func containsEmDash(_ text: String) -> Bool {
        text.contains("—") || text.contains("―") || text.contains(" – ")
    }
}

/// Checks generated text against the profile, so new "facts" can't slip in unnoticed.
///
/// It flags numbers, percentages, years, money and capitalized names that appear in the
/// generated text but nowhere in the profile (or, for names, the job description).
public enum FactGuard {
    public struct Finding: Equatable, Hashable {
        public enum Kind: String { case number, name }
        public var kind: Kind
        public var text: String
        public var message: String {
            switch kind {
            case .number: return "“\(text)” doesn't appear in your profile. Confirm it's accurate or remove it."
            case .name: return "“\(text)” doesn't appear in your profile or the job posting. Check it before using this."
            }
        }
    }

    public static func check(_ generated: String, profile: Profile, job: Job? = nil, extraAllowed: [String] = []) -> [Finding] {
        let source = profile.corpus + "\n" + extraAllowed.joined(separator: "\n")
        let sourceNumbers = Set(numbers(in: source))
        var findings: [Finding] = []
        var seen: Set<String> = []
        for n in numbers(in: generated) where !sourceNumbers.contains(n) && !seen.contains(n) {
            seen.insert(n)
            findings.append(Finding(kind: .number, text: n))
        }
        let known = (source + "\n" + (job.map { "\($0.title) \($0.employer) \($0.location) \($0.descriptionText)" } ?? "")).lowercased()
        for name in capitalizedNames(in: generated) {
            let lower = name.lowercased()
            if known.contains(lower) || seen.contains(lower) { continue }
            if commonCapitalized.contains(lower) { continue }
            seen.insert(lower)
            findings.append(Finding(kind: .name, text: name))
        }
        return findings
    }

    /// Numbers as written, normalized: "1,200" → "1200", "25%" → "25%", "$40K" → "40k".
    static func numbers(in text: String) -> [String] {
        var out: [String] = []
        var current = ""
        let chars = Array(text)
        var i = 0
        func flush() {
            var n = current.replacingOccurrences(of: ",", with: "")
            while n.hasSuffix(".") { n.removeLast() }
            if !n.isEmpty && n.contains(where: { $0.isNumber }) { out.append(n.lowercased()) }
            current = ""
        }
        while i < chars.count {
            let c = chars[i]
            if c.isNumber {
                current.append(c)
            } else if !current.isEmpty && (c == "," || c == ".") && i + 1 < chars.count && chars[i + 1].isNumber {
                current.append(c)
            } else if !current.isEmpty && (c == "%" || c == "+" || ((c == "k" || c == "K" || c == "m" || c == "M") && (i + 1 == chars.count || !chars[i + 1].isLetter))) {
                current.append(c)
                flush()
            } else if !current.isEmpty {
                flush()
            }
            i += 1
        }
        if !current.isEmpty { flush() }
        // "10+" also matches "10"; strip the plus for comparison.
        return out.map { $0.hasSuffix("+") ? String($0.dropLast()) : $0 }
    }

    /// Capitalized words or runs of them that aren't at the start of a sentence.
    static func capitalizedNames(in text: String) -> [String] {
        var out: [String] = []
        for sentence in TextTools.sentences(text) {
            let tokens = sentence.split(separator: " ").map(String.init)
            var run: [String] = []
            for (i, raw) in tokens.enumerated() {
                var word = raw.trimmingCharacters(in: CharacterSet.punctuationCharacters)
                for suffix in ["'s", "’s"] where word.hasSuffix(suffix) { word = String(word.dropLast(2)) }
                let isCap = word.first.map { $0.isUppercase } ?? false
                if isCap && i > 0 && word.count > 1 {
                    run.append(word)
                } else {
                    if !run.isEmpty { out.append(run.joined(separator: " ")) }
                    run = []
                }
                if raw.hasSuffix(",") || raw.hasSuffix(";") || raw.hasSuffix(":") {
                    if !run.isEmpty { out.append(run.joined(separator: " ")) }
                    run = []
                }
            }
            if !run.isEmpty { out.append(run.joined(separator: " ")) }
        }
        return out
    }

    /// Capitalized words that are fine anywhere.
    static let commonCapitalized: Set<String> = [
        "i", "i'm", "i've", "i'd", "dear", "hiring", "team", "manager", "sincerely", "thank", "thanks", "regards",
        "best", "english", "spanish", "january", "february", "march", "april", "may", "june", "july", "august",
        "september", "october", "november", "december", "monday", "tuesday", "wednesday", "thursday", "friday",
        "ela", "k-12", "k–12", "ai", "u.s.", "us", "american", "please", "my", "the", "in", "as", "at", "for", "with",
        "and", "to", "of", "on", "a", "an", "this", "that", "these", "those", "your", "our",
    ]
}
