import Foundation

/// Small text utilities shared by the parsers and the matcher. Deliberately simple and
/// predictable: no hidden models, so every match can be explained.
public enum TextTools {
    public static let stopwords: Set<String> = [
        "a", "about", "above", "across", "after", "again", "all", "also", "am", "an", "and", "any", "are", "as", "at",
        "be", "because", "been", "being", "both", "but", "by", "can", "could", "did", "do", "does", "doing", "during",
        "each", "either", "etc", "every", "for", "from", "further", "had", "has", "have", "having", "he", "her", "here",
        "hers", "him", "his", "how", "i", "if", "in", "into", "is", "it", "its", "itself", "just", "may", "me", "might",
        "more", "most", "must", "my", "no", "nor", "not", "of", "off", "on", "once", "one", "only", "or", "other", "our",
        "ours", "out", "over", "own", "per", "same", "she", "should", "so", "some", "such", "than", "that", "the",
        "their", "theirs", "them", "then", "there", "these", "they", "this", "those", "through", "to", "too", "under",
        "until", "up", "upon", "us", "very", "via", "was", "we", "were", "what", "when", "where", "which", "while", "who",
        "whom", "why", "will", "with", "within", "without", "would", "you", "your", "yours", "yourself",
        // Job-posting filler that says nothing about the work itself.
        "ability", "able", "strong", "excellent", "including", "include", "includes", "related", "relevant", "required",
        "preferred", "plus", "bonus", "candidate", "candidates", "role", "position", "team", "work", "working", "years",
        "year", "experience", "experienced", "knowledge", "understanding", "skills", "skill", "demonstrated", "proven",
        "familiarity", "familiar", "proficiency", "proficient", "ideal", "ideally", "using", "use", "new", "well",
        "highly", "good", "great", "minimum", "least", "equivalent", "combination", "similar", "various", "multiple",
        "across", "ensure", "ensuring", "based", "level", "areas", "area", "etc.", "e.g", "i.e", "like", "within",
        "responsible", "responsibilities", "duties", "tasks", "help", "helps", "support", "supporting", "provide",
        "providing", "other", "others", "ongoing", "need", "needs", "needed", "want", "looking", "join",
    ]

    /// Equivalent phrasings. The first entry of each group is the canonical form used for
    /// matching; any entry can be shown to people. Only true equivalents belong here, because
    /// the tailoring rules may offer to swap one for another.
    public static let synonymGroups: [[String]] = [
        ["english language arts", "ela"],
        ["item writing", "item authoring", "item development", "item writer", "item writers"],
        ["assessment development", "test development"],
        ["assessment", "assessments", "test", "tests", "testing"],
        ["standards alignment", "alignment to standards", "standards-aligned", "standards aligned", "aligned to standards"],
        ["quality assurance", "qa", "quality control", "qc"],
        ["subject matter expert", "sme", "smes", "subject matter experts"],
        ["k-12", "k12", "k–12", "kindergarten through 12th grade", "k through 12"],
        ["learning management system", "lms"],
        ["instructional design", "instructional designer", "instructional designers"],
        ["curriculum development", "curriculum design", "curriculum writing", "curriculum writer", "curriculum developer",
         "curriculum designer"],
        ["professional development"],
        ["universal design for learning", "udl"],
        ["common core state standards", "common core", "ccss"],
        ["english learners", "english language learners", "ell", "ells", "multilingual learners"],
        ["project management", "project manager", "managing projects"],
        ["content development", "content creation", "content developer", "content developers"],
        ["copyediting", "copy editing", "copyedit", "copy edit"],
        ["proofreading", "proofread"],
        ["psychometrics", "psychometric", "psychometrician"],
        ["rubric", "rubrics", "scoring guide", "scoring guides"],
        ["reading passage", "reading passages", "passage", "passages", "stimulus", "stimuli"],
        ["bachelor's degree", "bachelors degree", "bachelor degree", "bachelor's", "bachelors", "ba", "b.a.", "bs", "b.s.",
         "undergraduate degree", "four-year degree"],
        ["master's degree", "masters degree", "master degree", "master's", "masters", "m.a.", "m.s.", "m.ed.",
         "graduate degree"],
        ["edtech", "ed tech", "education technology", "educational technology"],
        ["accessibility", "accessible", "wcag", "a11y"],
        ["microsoft office", "ms office", "office 365", "microsoft 365"],
        ["google workspace", "g suite", "google suite"],
        ["teaching", "teacher", "taught", "classroom instruction", "educator"],
        ["editing", "editor", "edited", "editorial"],
        ["review", "reviewed", "reviewing", "reviews", "reviewer"],
        ["writing", "writer", "wrote", "written", "authored", "drafted"],
        ["collaborate", "collaborated", "collaboration", "collaborating", "partnered", "worked closely"],
        ["data analysis", "analyze data", "analyzed data", "data analytics", "item analysis", "item statistics"],
        ["blueprint", "test blueprint", "test blueprints", "blueprints", "test specifications", "test specs"],
        ["formative assessment", "formative assessments", "interim assessment", "interim assessments", "benchmark assessment"],
        ["summative assessment", "summative assessments", "state assessment", "state assessments", "end-of-course"],
        ["bias and sensitivity", "bias review", "sensitivity review", "fairness review", "bias/sensitivity"],
        ["style guide", "style guides", "chicago manual of style", "ap style", "house style"],
    ]

    /// phrase → canonical phrase.
    public static let canonical: [String: String] = {
        var map: [String: String] = [:]
        for group in synonymGroups {
            guard let first = group.first else { continue }
            for p in group { map[p] = first }
        }
        return map
    }()

    /// Longest phrases first, so "item writing" wins over "writing".
    static let phrasesByLength: [String] = canonical.keys.sorted { a, b in
        let wa = a.split(separator: " ").count, wb = b.split(separator: " ").count
        return wa != wb ? wa > wb : a.count > b.count
    }

    /// Lowercased word tokens (letters, digits, and inner ' - + . # /).
    public static func words(_ text: String) -> [String] {
        var out: [String] = []
        var current = ""
        let lowered = text.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "–", with: "-")
        for ch in lowered {
            if ch.isLetter || ch.isNumber || ch == "+" || ch == "#" {
                current.append(ch)
            } else if (ch == "'" || ch == "-" || ch == "." || ch == "/") && !current.isEmpty {
                current.append(ch)
            } else {
                flush(&current, into: &out)
            }
        }
        flush(&current, into: &out)
        return out
    }

    private static func flush(_ current: inout String, into out: inout [String]) {
        while let last = current.last, last == "'" || last == "-" || last == "." || last == "/" {
            current.removeLast()
        }
        if current.hasSuffix("'s") { current.removeLast(2) }
        if !current.isEmpty { out.append(current) }
        current = ""
    }

    /// A light stemmer: enough to treat "reviews/reviewed/reviewing" alike without mangling words.
    public static func stem(_ word: String) -> String {
        var w = word
        if w.count <= 3 || w.contains(where: { $0.isNumber }) { return w }
        for suffix in ["ations", "ation", "ments", "ment", "ingly", "ings", "ing", "edly", "ies", "ied", "ers", "er", "ed", "es", "s"] {
            if w.hasSuffix(suffix) && w.count - suffix.count >= 3 {
                if suffix == "s" && (w.hasSuffix("ss") || w.hasSuffix("us") || w.hasSuffix("is")) { return w }
                if suffix == "es" && !(w.hasSuffix("ses") || w.hasSuffix("xes") || w.hasSuffix("ches") || w.hasSuffix("shes")) {
                    w.removeLast(1)
                    return dropFinalE(w)
                }
                w.removeLast(suffix.count)
                if suffix == "ies" || suffix == "ied" { w.append("y") }
                return dropFinalE(w)
            }
        }
        return dropFinalE(w)
    }

    /// "create"/"created" and "manage"/"managed" end up the same.
    private static func dropFinalE(_ w: String) -> String {
        if w.count > 4 && w.hasSuffix("e") && !w.hasSuffix("ee") { return String(w.dropLast()) }
        return w
    }

    /// Canonical phrases found in the text (synonym groups), e.g. "item writing", "k-12".
    public static func phrases(in text: String) -> Set<String> {
        let normalized = " " + words(text).joined(separator: " ") + " "
        var found: Set<String> = []
        var remaining = normalized
        for p in phrasesByLength {
            let needle = " " + words(p).joined(separator: " ") + " "
            guard needle.count > 2 else { continue }
            if remaining.contains(needle) {
                found.insert(canonical[p] ?? p)
                // Blank it out so shorter phrases inside it don't also count.
                remaining = remaining.replacingOccurrences(of: needle, with: " | ")
            }
        }
        return found
    }

    /// Meaningful stemmed terms (stopwords removed), plus canonical phrases with spaces.
    public static func terms(_ text: String) -> Set<String> {
        var out = phrases(in: text)
        for w in words(text) {
            let bare = w.trimmingCharacters(in: CharacterSet(charactersIn: ".'-/"))
            guard bare.count >= 2, !stopwords.contains(bare) else { continue }
            if bare.allSatisfy({ $0.isNumber }) { continue }
            out.insert(stem(bare))
        }
        return out
    }

    /// Splits text into sentences (keeps abbreviations like "e.g." together, mostly).
    public static func sentences(_ text: String) -> [String] {
        var out: [String] = []
        var current = ""
        let chars = Array(text.replacingOccurrences(of: "\n", with: " "))
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            current.append(ch)
            if ch == "." || ch == "!" || ch == "?" {
                let nextIsSpace = i + 1 < chars.count && chars[i + 1] == " "
                let nextNextUpper = i + 2 < chars.count && (chars[i + 2].isUppercase || chars[i + 2].isNumber)
                let lastWord = current.split(separator: " ").last.map(String.init) ?? ""
                let isAbbrev = ["e.g.", "i.e.", "etc.", "vs.", "Dr.", "Mr.", "Ms.", "Mrs.", "Inc.", "St.", "U.S."].contains(lastWord)
                    || (lastWord.count <= 3 && lastWord.dropLast().allSatisfy { $0.isUppercase || $0 == "." })
                if (i + 1 == chars.count) || (nextIsSpace && nextNextUpper && !isAbbrev) {
                    let s = current.trimmed
                    if !s.isEmpty { out.append(s) }
                    current = ""
                }
            }
            i += 1
        }
        let rest = current.trimmed
        if !rest.isEmpty { out.append(rest) }
        return out
    }

    static let bulletMarkers: Set<Character> = ["•", "-", "*", "·", "▪", "◦", "●", "○", "■", "□", "➢", "►", "▶", "\u{F0B7}", "\u{F0A7}", "\u{F076}", "‣", "⁃", "–", "—"]

    /// "• Did a thing" → "Did a thing". Returns nil when the line isn't a bullet.
    public static func bulletText(_ line: String) -> String? {
        let t = line.trimmed
        guard let first = t.first else { return nil }
        if bulletMarkers.contains(first) {
            let rest = t.dropFirst().trimmed
            return rest.isEmpty ? nil : rest
        }
        // "1." "2)" "a." numbered lists
        let scalars = Array(t)
        var i = 0
        while i < scalars.count && i < 3 && scalars[i].isNumber { i += 1 }
        if i > 0 && i < scalars.count && (scalars[i] == "." || scalars[i] == ")") && i + 1 < scalars.count && scalars[i + 1] == " " {
            let rest = String(scalars[(i + 2)...]).trimmed
            return rest.isEmpty ? nil : rest
        }
        return nil
    }

    /// True for lines that look like a heading: short, no final period, mostly capitals or
    /// title words.
    public static func looksLikeHeading(_ line: String) -> Bool {
        let t = line.trimmed.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
        guard !t.isEmpty, t.count <= 60, !t.hasSuffix("."), !t.hasSuffix(","), bulletText(line) == nil else { return false }
        let letters = t.filter { $0.isLetter }
        guard !letters.isEmpty else { return false }
        let upper = letters.filter { $0.isUppercase }.count
        if Double(upper) / Double(letters.count) > 0.8 { return true }
        return line.trimmed.hasSuffix(":") && t.split(separator: " ").count <= 6
    }

    /// Lowercase and strip everything but letters and digits, for duplicate checks.
    public static func key(_ text: String) -> String {
        String(text.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }
}
