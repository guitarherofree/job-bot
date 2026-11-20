import Foundation

/// Drafts cover letters and application answers from the profile only. Anything the profile
/// can't support is left out (cover letters) or left blank (answers), and noted for review.
public enum CoverLetterDrafter {
    public static func draft(profile: Profile, job: Job, report: MatchReport? = nil, now: Date = Date()) -> CoverLetter {
        let report = report ?? Matcher.compare(profile: profile, job: job, now: now)
        let employer = job.employer.trimmed
        let title = job.title.trimmed
        var paragraphs: [String] = []
        var notes: [String] = []

        // Opening
        var opening = "I am applying for the \(title.isEmpty ? "open" : title) position"
        opening += employer.isEmpty ? "." : " at \(employer)."
        if let intro = introSentence(from: profile) {
            opening += " " + intro
            notes.append("The second sentence of the opening is adapted from your summary. Check that it still reads the way you want.")
        } else if let years = report.profileYears, years >= 1, let recent = mostRecentRole(profile) {
            opening += " I bring about \(Int(years)) years of experience, most recently as \(recent.title) at \(recent.organization)."
            notes.append("“About \(Int(years)) years” was calculated from the dates in your experience section. Confirm it.")
        }
        paragraphs.append(opening)

        // Evidence
        let sentences = evidenceSentences(profile: profile, report: report)
        if !sentences.isEmpty {
            paragraphs.append(sentences.joined(separator: " "))
        } else {
            let skills = report.matchedKeywords.prefix(4)
            if !skills.isEmpty {
                paragraphs.append("My experience includes \(joinList(Array(skills))), all of which this role calls for.")
            }
            notes.append("Job Bot couldn't find bullets in your profile that clearly match this posting, so the middle paragraph is thin. Add specifics from your own experience.")
        }

        // Fit with responsibilities
        let respTerms = responsibilityTerms(job: job, report: report)
        if respTerms.count >= 2 {
            paragraphs.append("This role's focus on \(joinList(respTerms)) matches the work I have been doing, and I would bring that experience to \(employer.isEmpty ? "your team" : employer) from the start.")
        }

        // Closing
        paragraphs.append("I would welcome the chance to talk about how my experience could support \(employer.isEmpty ? "your team's" : employer + "'s") work. Thank you for your time and consideration.")

        for gap in report.gaps.prefix(6) where gap.kind == .required {
            notes.append("Not mentioned (no evidence in your profile): “\(gap.text)”.")
        }

        let body = paragraphs.map { WritingRules.clean($0) }.joined(separator: "\n\n")
        var letter = CoverLetter(jobID: job.id, name: "Cover letter: \(title.isEmpty ? "Untitled role" : title)\(employer.isEmpty ? "" : ", " + employer)",
                                 greeting: employer.isEmpty ? "Dear Hiring Team," : "Dear \(employer) Hiring Team,",
                                 body: body, closing: "Sincerely,", signature: profile.contact.name.trimmed,
                                 recipient: employer, reviewNotes: notes, created: now)
        let extra = report.profileYears.map { [String(Int($0))] } ?? []
        for finding in FactGuard.check(letter.body, profile: profile, job: job, extraAllowed: extra) {
            letter.reviewNotes.append(finding.message)
        }
        return letter
    }

    /// "Academic Content Specialist with 10+ years..." → "I am an academic content specialist with 10+ years..."
    static func introSentence(from profile: Profile) -> String? {
        guard let first = TextTools.sentences(profile.summary).first, first.split(separator: " ").count >= 4 else { return nil }
        var s = first.trimmed
        if s.hasPrefix("I ") || s.hasPrefix("I'm ") || s.hasPrefix("My ") { return ensurePeriod(s) }
        let firstWord = s.split(separator: " ").first.map(String.init) ?? ""
        if Lexicon.actionVerbs.contains(firstWord.lowercased()) { return nil }
        // Keep acronyms and names; lowercase an ordinary capitalized first word.
        if firstWord.count > 1 && firstWord.dropFirst().allSatisfy({ $0.isLowercase || !$0.isLetter }) {
            s = lowerFirst(s)
        }
        let article = "aeiou".contains(s.lowercased().first ?? "x") ? "an" : "a"
        return ensurePeriod("I am \(article) \(s)")
    }

    static func mostRecentRole(_ p: Profile) -> ResumeEntry? {
        p.sections.first { $0.kind == .experience }?.entries.first { !$0.hidden && !$0.title.trimmed.isEmpty && !$0.organization.trimmed.isEmpty }
    }

    static func evidenceSentences(profile: Profile, report: MatchReport) -> [String] {
        var used: Set<String> = []
        var out: [String] = []
        func rank(_ k: RequirementKind) -> Int {
            switch k {
            case .required: return 0
            case .responsibility: return 1
            case .preferred: return 2
            }
        }
        // Degrees and years are credentials, not accomplishments; they don't drive the examples.
        let ordered = report.requirements
            .filter { $0.strength == .strong && Matcher.requiredDegree(in: $0.text) == nil && Matcher.requiredYears(in: $0.text) == nil }
            .enumerated()
            .sorted { a, b in rank(a.element.kind) != rank(b.element.kind) ? rank(a.element.kind) < rank(b.element.kind) : a.offset < b.offset }
            .map { $0.element }
        for r in ordered {
            guard out.count < 3 else { break }
            guard let ev = r.evidence.first(where: { $0.unit.ref.field == .bullet && $0.score >= 0.3 && !used.contains($0.unit.text) && startsWithVerb($0.unit.text) }) else { continue }
            used.insert(ev.unit.text)
            let bullet = ensurePeriod(lowerFirst(ev.unit.text))
            if out.isEmpty, let entryID = ev.unit.ref.entryID, let entry = profile.entry(entryID)?.1, !entry.title.trimmed.isEmpty {
                let at = entry.organization.trimmed.isEmpty ? "" : " at \(entry.organization.trimmed)"
                out.append("In my work as \(entry.title.trimmed)\(at), I \(bullet)")
            } else if out.count == 1 {
                out.append("I also \(bullet)")
            } else {
                out.append("In addition, I \(bullet)")
            }
        }
        return out
    }

    static func responsibilityTerms(job: Job, report: MatchReport) -> [String] {
        let respText = job.parsed.responsibilities.joined(separator: " ").lowercased()
        var out: [String] = []
        for k in report.matchedKeywords where respText.contains(k.lowercased()) {
            out.append(k.uppercased() == k ? k : k.lowercased())
            if out.count >= 3 { break }
        }
        return out
    }

    static func startsWithVerb(_ s: String) -> Bool {
        guard let w = TextTools.words(s).first else { return false }
        return Lexicon.actionVerbs.contains(w)
    }

    static func lowerFirst(_ s: String) -> String {
        guard let f = s.first else { return s }
        let firstWord = s.split(separator: " ").first.map(String.init) ?? ""
        // Leave acronyms ("ELA") and words with inner capitals alone.
        if firstWord.count > 1 && firstWord.dropFirst().contains(where: { $0.isUppercase }) { return s }
        return f.lowercased() + s.dropFirst()
    }

    static func ensurePeriod(_ s: String) -> String {
        let t = s.trimmed
        guard let last = t.last else { return t }
        return ".!?".contains(last) ? t : t + "."
    }

    static func joinList(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        case 2: return "\(items[0]) and \(items[1])"
        default: return items.dropLast().joined(separator: ", ") + ", and " + items[items.count - 1]
        }
    }
}

public enum AnswerDrafter {
    /// Splits pasted application questions into separate questions.
    public static func questions(from text: String) -> [String] {
        let lines = text.replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n")
            .map { (TextTools.bulletText($0) ?? $0).trimmed }
            .filter { !$0.isEmpty }
        var out: [String] = []
        var pending = ""
        for line in lines {
            pending = pending.isEmpty ? line : pending + " " + line
            if line.hasSuffix("?") || line.hasSuffix(":") || line.hasSuffix("*") || line.split(separator: " ").count <= 8 {
                out.append(pending.trimmingCharacters(in: CharacterSet(charactersIn: " *")))
                pending = ""
            }
        }
        if !pending.isEmpty { out.append(pending) }
        return out
    }

    static let personalCues = ["authoriz", "sponsor", "visa", "citizen", "salary", "compensation", "pay expectation",
                               "desired pay", "expected pay", "start date", "available to start", "availability",
                               "relocat", "gender", "race", "ethnic", "hispanic", "latino", "veteran", "disabilit",
                               "pronoun", "sexual orientation", "age ", "date of birth", "birthday", "criminal", "convicted",
                               "felony", "background check", "drug", "reference", "how did you hear", "referred",
                               "referral", "non-compete", "noncompete", "agreement", "consent", "social security", "ssn",
                               "signature", "certify that", "acknowledge", "previously worked", "previously employed",
                               "family member", "relative", "travel", "willing to"]

    public static func draft(questions: [String], profile: Profile, job: Job, report: MatchReport? = nil,
                             preferences: Preferences? = nil, now: Date = Date()) -> [ApplicationAnswer] {
        let report = report ?? Matcher.compare(profile: profile, job: job, now: now)
        return questions.map { draftOne($0, profile: profile, job: job, report: report, preferences: preferences) }
    }

    static func draftOne(_ q: String, profile: Profile, job: Job, report: MatchReport, preferences: Preferences?) -> ApplicationAnswer {
        let l = q.lowercased()
        var a = ApplicationAnswer(question: q)
        let c = profile.contact

        func fromProfile(_ value: String, _ what: String) -> ApplicationAnswer {
            var x = a
            if value.trimmed.isEmpty {
                x.state = .unknown
                x.note = "Your profile has no \(what). Add it under Contact, or fill this in yourself."
            } else {
                x.answer = value
                x.state = .fromProfile
                x.note = "From your profile (\(what))."
            }
            return x
        }

        // Contact fields
        if l.contains("first name") { return fromProfile(c.name.split(separator: " ").first.map(String.init) ?? "", "name") }
        if l.contains("last name") || l.contains("surname") || l.contains("family name") {
            return fromProfile(c.name.split(separator: " ").dropFirst().joined(separator: " "), "name")
        }
        if l.contains("full name") || l == "name" || l == "name:" || l.hasPrefix("name ") { return fromProfile(c.name, "name") }
        if l.contains("email") { return fromProfile(c.email, "email address") }
        if l.contains("phone") || l.contains("mobile") { return fromProfile(c.phone, "phone number") }
        if l.contains("linkedin") { return fromProfile(c.links.first { $0.lowercased().contains("linkedin") } ?? "", "LinkedIn link") }
        if l.contains("website") || l.contains("portfolio") || l.contains("github") {
            return fromProfile(c.links.first { !$0.lowercased().contains("linkedin") } ?? "", "website or portfolio link")
        }

        // Questions only the person can answer.
        if personalCues.contains(where: { l.contains($0) }) {
            a.state = .personal
            a.note = "Only you can answer this. Job Bot leaves it blank on purpose."
            if l.contains("salary") || l.contains("compensation") || l.contains("pay") {
                if let target = preferences?.targetCompensation {
                    a.note += " Your saved target is \(Int(target)) per year; use it only if you want to."
                }
            }
            return a
        }
        if (l.contains("city") || l.contains("location") || l.contains("where are you located") || l.contains("address")) && !l.contains("experience") {
            return fromProfile(c.location, "location")
        }

        // Total years of experience.
        if l.contains("how many years") && (l.contains("total") || l.contains("professional experience") || l.hasSuffix("experience do you have?")) {
            if let y = report.profileYears, y >= 1 {
                a.answer = "\(Int(y))"
                a.state = .needsConfirmation
                a.note = "Calculated from the dates in your experience section. Confirm before using."
            } else {
                a.state = .unknown
                a.note = "Add dates to your experience to calculate this, or answer it yourself."
            }
            return a
        }

        // Motivation
        if l.contains("why are you interested") || l.contains("why do you want") || l.contains("what interests you")
            || l.contains("why this role") || l.contains("why " + job.employer.lowercased()) && !job.employer.isEmpty {
            let areas = Array(report.matchedKeywords.prefix(3))
            guard !areas.isEmpty else {
                a.state = .unknown
                a.note = "Job Bot couldn't connect this role to your profile clearly enough to draft an answer."
                return a
            }
            let role = job.title.isEmpty ? "this role" : "the \(job.title) role"
            var text = "I'm interested in \(role)\(job.employer.isEmpty ? "" : " at \(job.employer)") because it centers on \(CoverLetterDrafter.joinList(areas.map { $0.uppercased() == $0 ? $0 : $0.lowercased() })), which is the work I have focused on."
            if let ev = bestEvidence(for: q + " " + job.parsed.responsibilities.joined(separator: " "), profile: profile) {
                text += " For example, I \(CoverLetterDrafter.ensurePeriod(CoverLetterDrafter.lowerFirst(ev.text)))"
                a.evidence = [ev.ref]
            }
            a.answer = WritingRules.clean(text)
            a.state = .needsConfirmation
            a.note = "A starting point built from your profile. Make it yours: only you know why you want this job."
            return a
        }

        // Experience questions
        let experienceCue = ["experience", "describe", "tell us", "have you", "do you have", "familiar", "worked with",
                             "example", "proficien", "knowledge of", "skills"].contains { l.contains($0) }
        if experienceCue, let ev = bestEvidence(for: q, profile: profile) {
            let isYesNo = l.hasPrefix("do you") || l.hasPrefix("have you") || l.hasPrefix("are you") || l.hasPrefix("can you")
            var text = ""
            if isYesNo { text = "Yes. " }
            if CoverLetterDrafter.startsWithVerb(ev.text) {
                if let entryID = ev.ref.entryID, let entry = profile.entry(entryID)?.1, !entry.title.trimmed.isEmpty {
                    let at = entry.organization.trimmed.isEmpty ? "" : " at \(entry.organization.trimmed)"
                    text += "As \(entry.title.trimmed)\(at), I \(CoverLetterDrafter.ensurePeriod(CoverLetterDrafter.lowerFirst(ev.text)))"
                } else {
                    text += "I \(CoverLetterDrafter.ensurePeriod(CoverLetterDrafter.lowerFirst(ev.text)))"
                }
            } else {
                text += "My profile notes: \(CoverLetterDrafter.ensurePeriod(ev.text))"
            }
            a.answer = WritingRules.clean(text)
            a.state = .needsConfirmation
            a.evidence = [ev.ref]
            a.note = "Drafted from “\(ev.location)”. Confirm it answers the question."
            return a
        }

        a.state = .unknown
        a.note = experienceCue ? "Nothing in your profile clearly answers this. Left blank." : "Job Bot doesn't have the information to answer this. Left blank."
        return a
    }

    static func bestEvidence(for text: String, profile: Profile) -> ProfileUnit? {
        let q = TextTools.terms(text)
        guard !q.isEmpty else { return nil }
        var best: (ProfileUnit, Double)?
        for u in profile.units(includeHidden: false) where u.ref.field == .bullet || u.ref.field == .note || u.ref.field == .summary {
            let shared = q.intersection(TextTools.terms(u.text))
            let score = shared.reduce(0.0) { $0 + ($1.contains(" ") ? 2 : 1) }
            if score >= 2, score > (best?.1 ?? 0) { best = (u, score) }
        }
        return best?.0
    }
}
