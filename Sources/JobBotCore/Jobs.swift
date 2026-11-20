import Foundation

public enum ApplicationStatus: String, Codable, CaseIterable, Identifiable {
    case saved
    case preparing
    case applied
    case interviewing
    case offer
    case rejected
    case withdrawn
    case archived

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .saved: return "Saved"
        case .preparing: return "Preparing"
        case .applied: return "Applied"
        case .interviewing: return "Interviewing"
        case .offer: return "Offer"
        case .rejected: return "Not selected"
        case .withdrawn: return "Withdrawn"
        case .archived: return "Archived"
        }
    }

    public var isActive: Bool {
        switch self {
        case .saved, .preparing, .applied, .interviewing, .offer: return true
        case .rejected, .withdrawn, .archived: return false
        }
    }
}

public struct StatusChange: Codable, Equatable, Hashable {
    public var status: ApplicationStatus
    public var date: Date
    public init(status: ApplicationStatus, date: Date = Date()) {
        self.status = status
        self.date = date
    }
}

public enum PayPeriod: String, Codable, CaseIterable {
    case year, month, week, day, hour

    public var title: String {
        switch self {
        case .year: return "per year"
        case .month: return "per month"
        case .week: return "per week"
        case .day: return "per day"
        case .hour: return "per hour"
        }
    }

    /// Rough multiplier to a yearly figure (full time).
    public var yearlyFactor: Double {
        switch self {
        case .year: return 1
        case .month: return 12
        case .week: return 52
        case .day: return 260
        case .hour: return 2080
        }
    }
}

public struct SalaryInfo: Codable, Equatable, Hashable {
    public var minimum: Double?
    public var maximum: Double?
    public var currency: String
    public var period: PayPeriod
    /// The text it came from ("$65,000 - $80,000 per year").
    public var text: String
    /// Where it came from ("Job posting", "Greenhouse"), and when it was read.
    public var source: String
    public var date: Date

    public init(minimum: Double?, maximum: Double?, currency: String = "USD", period: PayPeriod = .year,
                text: String, source: String, date: Date = Date()) {
        self.minimum = minimum
        self.maximum = maximum
        self.currency = currency
        self.period = period
        self.text = text
        self.source = source
        self.date = date
    }

    public var yearlyMidpoint: Double? {
        let values = [minimum, maximum].compactMap { $0 }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count) * period.yearlyFactor
    }

    public var display: String {
        func money(_ v: Double) -> String {
            let f = NumberFormatter()
            f.numberStyle = .currency
            f.currencyCode = currency
            f.maximumFractionDigits = v < 1000 ? 2 : 0
            return f.string(from: NSNumber(value: v)) ?? "\(Int(v))"
        }
        if let lo = minimum, let hi = maximum, lo != hi { return "\(money(lo)) to \(money(hi)) \(period.title)" }
        if let lo = minimum { return "\(money(lo)) \(period.title)" }
        if let hi = maximum { return "Up to \(money(hi)) \(period.title)" }
        return text
    }
}

/// What Job Bot read out of a job description.
public struct ParsedJob: Codable, Equatable, Hashable {
    public var responsibilities: [String]
    public var requiredQualifications: [String]
    public var preferredQualifications: [String]
    public var keywords: [String]
    public var location: String?
    public var remote: Bool
    public var salary: SalaryInfo?
    public var employmentType: String?
    /// Lines that didn't fit a category (kept so nothing is lost).
    public var other: [String]

    public init(responsibilities: [String] = [], requiredQualifications: [String] = [], preferredQualifications: [String] = [],
                keywords: [String] = [], location: String? = nil, remote: Bool = false, salary: SalaryInfo? = nil,
                employmentType: String? = nil, other: [String] = []) {
        self.responsibilities = responsibilities
        self.requiredQualifications = requiredQualifications
        self.preferredQualifications = preferredQualifications
        self.keywords = keywords
        self.location = location
        self.remote = remote
        self.salary = salary
        self.employmentType = employmentType
        self.other = other
    }

    public var isEmpty: Bool {
        responsibilities.isEmpty && requiredQualifications.isEmpty && preferredQualifications.isEmpty
    }
}

public struct ApplicationAnswer: Codable, Equatable, Hashable, Identifiable {
    public enum State: String, Codable {
        /// Filled from a profile field (name, email...).
        case fromProfile
        /// Drafted from the profile; needs the person's confirmation.
        case needsConfirmation
        /// The person reviewed and confirmed it.
        case confirmed
        /// Job Bot doesn't know; left blank on purpose.
        case unknown
        /// Only the person can answer (work authorization, salary, demographics...).
        case personal
    }

    public var id: UUID
    public var question: String
    public var answer: String
    public var state: State
    /// Why it was filled this way, or what's missing.
    public var note: String
    public var evidence: [EvidenceRef]

    public init(id: UUID = UUID(), question: String, answer: String = "", state: State = .unknown, note: String = "",
                evidence: [EvidenceRef] = []) {
        self.id = id
        self.question = question
        self.answer = answer
        self.state = state
        self.note = note
        self.evidence = evidence
    }
}

public struct Job: Codable, Equatable, Hashable, Identifiable {
    public var id: UUID
    public var title: String
    public var employer: String
    public var location: String
    /// "Pasted description", "Job page", "Greenhouse", "Lever"...
    public var source: String
    public var url: String
    /// When the employer posted it, if the page said.
    public var postedDate: Date?
    public var dateFound: Date
    /// When the posting closes (from the page), if known.
    public var validThrough: Date?
    public var expired: Bool
    public var expiredReason: String
    public var descriptionText: String
    public var parsed: ParsedJob
    public var status: ApplicationStatus
    public var statusHistory: [StatusChange]
    public var notes: String
    public var appliedDate: Date?
    public var tailoredResumeID: UUID?
    public var coverLetterID: UUID?
    public var answers: [ApplicationAnswer]
    /// Answers to follow-up questions, by question ID.
    public var followUps: [String: String]
    public var updated: Date

    public init(id: UUID = UUID(), title: String = "", employer: String = "", location: String = "", source: String = "",
                url: String = "", postedDate: Date? = nil, dateFound: Date = Date(), validThrough: Date? = nil,
                expired: Bool = false, expiredReason: String = "", descriptionText: String = "",
                parsed: ParsedJob = ParsedJob(), status: ApplicationStatus = .saved, notes: String = "") {
        self.id = id
        self.title = title
        self.employer = employer
        self.location = location
        self.source = source
        self.url = url
        self.postedDate = postedDate
        self.dateFound = dateFound
        self.validThrough = validThrough
        self.expired = expired
        self.expiredReason = expiredReason
        self.descriptionText = descriptionText
        self.parsed = parsed
        self.status = status
        self.statusHistory = [StatusChange(status: status, date: dateFound)]
        self.notes = notes
        self.appliedDate = nil
        self.tailoredResumeID = nil
        self.coverLetterID = nil
        self.answers = []
        self.followUps = [:]
        self.updated = dateFound
    }

    public var displayTitle: String { title.trimmed.isEmpty ? "Untitled role" : title }
    public var displayEmployer: String { employer.trimmed.isEmpty ? "Unknown employer" : employer }

    public mutating func setStatus(_ new: ApplicationStatus, on date: Date = Date()) {
        guard new != status else { return }
        status = new
        statusHistory.append(StatusChange(status: new, date: date))
        if new == .applied && appliedDate == nil { appliedDate = date }
        updated = date
    }

    /// Location text used for filtering: what the posting said, plus "Remote" when it's remote.
    public var locationForFiltering: String {
        var parts = [location]
        if let l = parsed.location { parts.append(l) }
        if parsed.remote { parts.append("Remote") }
        return parts.joined(separator: " ")
    }
}
