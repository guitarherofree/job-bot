import Foundation

/// General patterns from a professional example the person is allowed to use (a colleague's
/// resume shared with permission, a sample from a career center). Only the patterns are kept:
/// the example's text is discarded after analysis, and names, contact details and distinctive
/// wording are never stored.
public struct ExamplePatterns: Codable, Equatable, Hashable, Identifiable {
    public var id: UUID
    public var label: String
    public var analyzed: Date
    public var roleTitles: [String]
    public var credentials: [String]
    public var skills: [String]
    /// Observations about how achievements are described ("4 of 9 bullets give a count").
    public var achievementPatterns: [String]
    public var commonVerbs: [String]
    public var sectionOrder: [String]

    public init(id: UUID = UUID(), label: String, analyzed: Date = Date(), roleTitles: [String] = [], credentials: [String] = [],
                skills: [String] = [], achievementPatterns: [String] = [], commonVerbs: [String] = [], sectionOrder: [String] = []) {
        self.id = id
        self.label = label
        self.analyzed = analyzed
        self.roleTitles = roleTitles
        self.credentials = credentials
        self.skills = skills
        self.achievementPatterns = achievementPatterns
        self.commonVerbs = commonVerbs
        self.sectionOrder = sectionOrder
    }
}

public enum ExampleAnalyzer {
    static let credentialPatterns = [
        "ph\\.?d\\.?", "ed\\.?d\\.?", "m\\.?ed\\.?", "m\\.a\\.", "m\\.s\\.", "mba", "b\\.a\\.", "b\\.s\\.", "cptd", "aptd", "pmp",
        "capm", "cpacc", "qm[- ]certified", "appqmr", "iste certified", "google certified", "national board certified",
        "teaching (?:license|certificate|certification)", "certificate in [a-z]+(?: [a-z]+){0,3}", "certified [a-z]+(?: [a-z]+){0,2}",
    ]

    public static func analyze(_ text: String, label: String, now: Date = Date()) -> ExamplePatterns {
        let parsed = ResumeParser.parse(text).profile
        var result = ExamplePatterns(label: label.trimmed.isEmpty ? "Example" : label.trimmed, analyzed: now)

        // Role titles: only generic job titles (no employer names, no people).
        var titles: [String] = []
        for s in parsed.sections where s.kind == .experience || s.kind == .volunteer {
            for e in s.entries {
                let t = genericTitle(e.title)
                if !t.isEmpty && !titles.contains(t) { titles.append(t) }
            }
        }
        result.roleTitles = titles

        // Credentials: recognized credential names only.
        let lower = text.lowercased()
        var creds: [String] = []
        for p in credentialPatterns {
            for m in Rx("(?<![a-z])(\(p))(?![a-z])").allMatches(lower) {
                let c = m[1].trimmed
                let shown = c.count <= 6 ? c.uppercased() : c.capitalized
                if !creds.contains(shown) && shown.count <= 50 { creds.append(shown) }
            }
        }
        result.credentials = Array(creds.prefix(15))

        // Skills from the shared vocabulary (generic terms, not the example's wording).
        result.skills = Array(Lexicon.skills(in: text).prefix(25))

        // Achievement patterns
        let bullets = parsed.sections.flatMap { $0.entries }.flatMap { $0.bullets }.map { $0.text }
        if !bullets.isEmpty {
            let n = bullets.count
            func count(_ test: (String) -> Bool) -> Int { bullets.filter(test).count }
            let withCount = count { b in Rx("\\b\\d[\\d,]*\\+?\\s+(?:items|passages|students|teachers|schools|districts|courses|lessons|modules|writers|reviewers|assessments|questions|units|states|clients|projects|people)").matches(b) }
            let withPercent = count { $0.contains("%") || $0.lowercased().contains("percent") }
            let withMoney = count { $0.contains("$") }
            let withTime = count { b in Rx("\\b(?:weeks?|months?|days?|hours?|ahead of schedule|on time|deadline)").matches(b) }
            let withScope = count { b in Rx("\\b(?:team of|led|managed|supervised|mentored|trained)\\b").matches(b) }
            let startsVerb = count { b in TextTools.words(b).first.map { Lexicon.actionVerbs.contains($0) } ?? false }
            func line(_ k: Int, _ what: String) -> String? { k == 0 ? nil : "\(k) of \(n) bullets \(what)." }
            result.achievementPatterns = [
                line(startsVerb, "start with an action verb"),
                line(withCount, "give a count of what was produced or who was served (items, students, schools)"),
                line(withPercent, "state a percentage change"),
                line(withMoney, "mention a dollar amount"),
                line(withTime, "mention time or deadlines"),
                line(withScope, "describe leading, managing or training others"),
            ].compactMap { $0 }
            // Most common opening verbs (generic words).
            var verbs: [String: Int] = [:]
            for b in bullets {
                if let w = TextTools.words(b).first, Lexicon.actionVerbs.contains(w) { verbs[w, default: 0] += 1 }
            }
            result.commonVerbs = verbs.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
                .prefix(8).map { $0.key.capitalized }
        }
        result.sectionOrder = parsed.sections.filter { !$0.isEmpty }.map { $0.kind == .other ? "Other" : $0.kind.defaultTitle }
        return result
    }

    /// Keeps a job title only if it reads like a generic title (strips "at Company", names, numbers).
    static func genericTitle(_ s: String) -> String {
        var t = s.trimmed
        for sep in [" at ", " @ ", " | ", ", "] {
            if let r = t.range(of: sep) { t = String(t[..<r.lowerBound]) }
        }
        t = t.trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespaces))
        guard !t.isEmpty, t.count <= 60, !t.contains(where: { $0.isNumber }), !t.contains("@") else { return "" }
        let lower = " " + t.lowercased() + " "
        guard ResumeParser.titleCues.contains(where: { lower.contains(" " + $0) }) else { return "" }
        return t
    }
}
