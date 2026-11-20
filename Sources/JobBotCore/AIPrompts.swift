import Foundation

/// Requests to an optional AI writing service, and strict checks on what comes back.
/// Contact details (name, email, phone, links, location) are never included in requests.
public enum AIPrompts {
    public enum Task: String {
        case tailor, coverLetter, answers

        public var purpose: String {
            switch self {
            case .tailor: return "Suggest resume wording for a saved job"
            case .coverLetter: return "Draft a cover letter for a saved job"
            case .answers: return "Draft application answers for a saved job"
            }
        }
    }

    public struct Request: Equatable {
        public var task: Task
        public var system: String
        public var user: String
        /// Plain description of what's included, shown before sending.
        public var dataSummary: String
    }

    public static let rules = """
    You help one person prepare job applications. Follow these rules without exception:
    1. Use only facts that appear in the PROFILE. Never add or change employers, job titles, dates, numbers, metrics, credentials, degrees, tools, or accomplishments.
    2. Keep the meaning and every fact of the original wording. You may reorder, tighten, and use the job posting's terms for things the profile already says.
    3. If a stronger claim would need information the profile doesn't contain, do not write it. Add a question instead.
    4. Write plainly and naturally, in the person's own voice. No buzzwords, no exaggeration, no clichés.
    5. Never use em dashes. Use commas, periods, or parentheses instead.
    6. Cite the PROFILE labels (like B3 or S1) that support everything you write.
    7. Reply with JSON only, matching the requested format exactly.
    """

    /// The profile as labeled lines ("B3 [Experience › Assessment Specialist, Pearson]: Wrote ...").
    public static func profileText(_ profile: Profile) -> String {
        profile.units(includeHidden: false).map { "\($0.label) [\($0.location)]: \($0.text)" }.joined(separator: "\n")
    }

    public static func jobText(_ job: Job) -> String {
        var parts: [String] = []
        parts.append("Title: \(job.title)")
        if !job.employer.isEmpty { parts.append("Employer: \(job.employer)") }
        if !job.parsed.responsibilities.isEmpty { parts.append("Responsibilities:\n- " + job.parsed.responsibilities.joined(separator: "\n- ")) }
        if !job.parsed.requiredQualifications.isEmpty { parts.append("Required qualifications:\n- " + job.parsed.requiredQualifications.joined(separator: "\n- ")) }
        if !job.parsed.preferredQualifications.isEmpty { parts.append("Preferred qualifications:\n- " + job.parsed.preferredQualifications.joined(separator: "\n- ")) }
        if !job.parsed.keywords.isEmpty { parts.append("Keywords: " + job.parsed.keywords.joined(separator: ", ")) }
        if job.parsed.isEmpty { parts.append("Description:\n" + String(job.descriptionText.prefix(12000))) }
        return parts.joined(separator: "\n\n")
    }

    public static func tailor(profile: Profile, job: Job) -> Request {
        let user = """
        PROFILE (labeled lines):
        \(profileText(profile))

        JOB POSTING:
        \(jobText(job))

        Suggest up to 8 rewrites of bullets (labels starting with B) or the summary (S1) that would make this resume a better fit for the posting while following every rule. Only suggest a rewrite when it clearly helps. Also list questions for requirements the profile can't support.

        JSON format:
        {"suggestions":[{"target":"B3","text":"rewritten text","evidence":["B3"],"job_terms":["term from posting"],"why":"one sentence"}],"questions":[{"requirement":"text from posting","question":"what to ask the person"}]}
        """
        return Request(task: .tailor, system: rules, user: user,
                       dataSummary: "Your profile's summary, experience, education, skills and notes (without your name or contact details), and this job's description.")
    }

    public static func coverLetter(profile: Profile, job: Job) -> Request {
        let user = """
        PROFILE (labeled lines):
        \(profileText(profile))

        JOB POSTING:
        \(jobText(job))

        Write a cover letter body of 3 or 4 short paragraphs for this job. Use only profile facts. Do not include a greeting, closing, signature, date, or address. Do not mention requirements the profile doesn't support. List anything the person should add or check.

        JSON format:
        {"paragraphs":["..."],"evidence":["B3","S1"],"notes":["..."]}
        """
        return Request(task: .coverLetter, system: rules, user: user,
                       dataSummary: "Your profile's summary, experience, education, skills and notes (without your name or contact details), and this job's description.")
    }

    public static func answers(questions: [String], profile: Profile, job: Job) -> Request {
        let list = questions.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        let user = """
        PROFILE (labeled lines):
        \(profileText(profile))

        JOB POSTING:
        \(jobText(job))

        APPLICATION QUESTIONS:
        \(list)

        Draft an answer for each question using only profile facts. If the profile can't answer it, or it asks about personal matters (work authorization, salary, start date, demographics, references, background checks), return an empty answer with status "unknown".

        JSON format:
        {"answers":[{"number":1,"answer":"...","evidence":["B3"],"status":"draft"}]}
        """
        return Request(task: .answers, system: rules, user: user,
                       dataSummary: "Your profile's summary, experience, education, skills and notes (without your name or contact details), this job's description, and the application questions.")
    }

    // MARK: Reading replies

    /// The first JSON object in a reply (models sometimes wrap it in a code fence).
    public static func jsonObject(in reply: String) -> [String: Any]? {
        guard let start = reply.firstIndex(of: "{"), let end = reply.lastIndex(of: "}"), start < end else { return nil }
        let slice = String(reply[start...end])
        guard let data = slice.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    public struct TailorResult {
        public var suggestions: [Suggestion]
        public var questions: [FollowUpQuestion]
        /// Items that were dropped and why.
        public var rejected: [String]
    }

    public static func readTailor(_ reply: String, profile: Profile, job: Job, service: String) -> TailorResult {
        var result = TailorResult(suggestions: [], questions: [], rejected: [])
        guard let obj = jsonObject(in: reply) else {
            result.rejected.append("The reply wasn't in the expected format, so nothing was used.")
            return result
        }
        let units = profile.units(includeHidden: false)
        let byLabel = Dictionary(units.map { ($0.label, $0) }, uniquingKeysWith: { a, _ in a })
        for item in (obj["suggestions"] as? [[String: Any]]) ?? [] {
            let label = (item["target"] as? String ?? "").trimmed
            guard let target = byLabel[label], target.ref.field == .bullet || target.ref.field == .summary else {
                result.rejected.append("A suggestion pointed at “\(label)”, which isn't a bullet or the summary.")
                continue
            }
            let text = WritingRules.clean((item["text"] as? String) ?? "")
            guard !text.isEmpty, text != target.text else { continue }
            let cited = ((item["evidence"] as? [String]) ?? []).compactMap { byLabel[$0.trimmed] }
            if cited.isEmpty {
                result.rejected.append("A rewrite of \(label) cited no evidence from your profile, so it was dropped.")
                continue
            }
            let findings = FactGuard.check(text, profile: profile, job: job)
            let jobTerms = (item["job_terms"] as? [String]) ?? []
            let why = WritingRules.clean((item["why"] as? String) ?? "Uses wording closer to the posting.")
            let kind: SuggestionKind = target.ref.field == .summary ? .rewriteSummary : .rewriteBullet
            result.suggestions.append(Suggestion(kind: kind,
                                                 title: kind == .rewriteSummary ? "Reword the summary" : "Reword a bullet in \(target.location)",
                                                 explanation: why, before: target.text, after: text, target: target.ref,
                                                 jobEvidence: jobTerms.isEmpty ? [] : ["Posting terms: " + jobTerms.joined(separator: ", ")],
                                                 profileEvidence: cited, warnings: findings.map { $0.message }, origin: service))
        }
        for (i, q) in ((obj["questions"] as? [[String: Any]]) ?? []).enumerated() {
            let question = WritingRules.clean((q["question"] as? String) ?? "")
            guard !question.isEmpty else { continue }
            result.questions.append(FollowUpQuestion(id: "ai-\(i)-\(TextTools.key(question).prefix(20))", question: question,
                                                     requirement: (q["requirement"] as? String) ?? ""))
        }
        return result
    }

    public static func readCoverLetter(_ reply: String, into letter: CoverLetter, profile: Profile, job: Job, service: String) -> CoverLetter? {
        guard let obj = jsonObject(in: reply), let paragraphs = obj["paragraphs"] as? [String], !paragraphs.isEmpty else { return nil }
        var out = letter
        out.body = paragraphs.map { WritingRules.clean($0) }.filter { !$0.isEmpty }.joined(separator: "\n\n")
        var notes = ((obj["notes"] as? [String]) ?? []).map { WritingRules.clean($0) }.filter { !$0.isEmpty }
        notes.insert("Drafted with \(service). Review every sentence before using it.", at: 0)
        for f in FactGuard.check(out.body, profile: profile, job: job) { notes.append(f.message) }
        out.reviewNotes = notes
        out.updated = Date()
        return out
    }

    public static func readAnswers(_ reply: String, questions: [String], profile: Profile, job: Job, service: String) -> [ApplicationAnswer]? {
        guard let obj = jsonObject(in: reply), let items = obj["answers"] as? [[String: Any]] else { return nil }
        let byLabel = Dictionary(profile.units(includeHidden: false).map { ($0.label, $0) }, uniquingKeysWith: { a, _ in a })
        var out = questions.map { ApplicationAnswer(question: $0, state: .unknown, note: "No answer was drafted.") }
        for item in items {
            guard let n = (item["number"] as? Int) ?? Int((item["number"] as? String) ?? ""), n >= 1, n <= out.count else { continue }
            let text = WritingRules.clean((item["answer"] as? String) ?? "")
            let status = (item["status"] as? String) ?? ""
            let cited = ((item["evidence"] as? [String]) ?? []).compactMap { byLabel[$0.trimmed] }
            if text.isEmpty || status == "unknown" || cited.isEmpty {
                out[n - 1].state = .unknown
                out[n - 1].note = text.isEmpty || status == "unknown" ? "Left blank: your profile doesn't answer this." : "Left blank: the draft cited nothing from your profile."
                continue
            }
            out[n - 1].answer = text
            out[n - 1].state = .needsConfirmation
            out[n - 1].evidence = cited.map { $0.ref }
            var note = "Drafted with \(service) from \(cited.map { $0.location }.joined(separator: "; ")). Confirm before using."
            for f in FactGuard.check(text, profile: profile, job: job) { note += " " + f.message }
            out[n - 1].note = note
        }
        return out
    }
}
