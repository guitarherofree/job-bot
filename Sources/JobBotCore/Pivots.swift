import Foundation

/// Adjacent roles to explore, with the experience that supports each and the skills that may be
/// missing.
public struct PivotRole: Codable, Equatable, Hashable, Identifiable {
    public var id: String { title }
    public var title: String
    public var searchTerms: [String]
    /// Skills the role usually calls for.
    public var typicalSkills: [String]
    public var why: String

    public init(title: String, searchTerms: [String], typicalSkills: [String], why: String) {
        self.title = title
        self.searchTerms = searchTerms
        self.typicalSkills = typicalSkills
        self.why = why
    }
}

public struct PivotSettings: Codable, Equatable {
    /// Titles and keywords the person wants to explore (editable).
    public var titles: [String]
    public var keywords: [String]

    public init() {
        titles = ["Instructional Designer", "Curriculum Designer", "Curriculum Developer"]
        keywords = ["instructional design", "curriculum design"]
    }
}

public struct PivotAssessment: Equatable, Identifiable {
    public var id: String { role.title }
    public var role: PivotRole
    /// Typical skills the profile shows, each with a piece of evidence.
    public var supported: [(skill: String, evidence: ProfileUnit)]
    public var missing: [String]
    public var share: Double

    public static func == (a: PivotAssessment, b: PivotAssessment) -> Bool {
        a.role == b.role && a.missing == b.missing && a.share == b.share
            && a.supported.map { $0.skill } == b.supported.map { $0.skill }
    }
}

public enum Pivots {
    public static let catalog: [PivotRole] = [
        PivotRole(title: "Instructional Designer",
                  searchTerms: ["Instructional Designer", "Instructional Design Specialist", "Learning Designer"],
                  typicalSkills: ["instructional design", "learning objectives", "storyboarding", "e-learning", "assessment design",
                                  "articulate storyline", "lms", "adult learning", "needs analysis", "addie", "project management",
                                  "subject matter expert"],
                  why: "Writing aligned assessments, rubrics and learning content uses the same backward-design thinking instructional design is built on."),
        PivotRole(title: "Curriculum Designer",
                  searchTerms: ["Curriculum Designer", "Curriculum Developer", "Curriculum Writer", "Curriculum Specialist"],
                  typicalSkills: ["curriculum development", "standards alignment", "lesson planning", "scope and sequence",
                                  "unit planning", "differentiation", "k-12", "english language arts", "formative assessment",
                                  "rubrics", "teacher materials"],
                  why: "Curriculum teams need people who know standards closely and can build materials and checks for understanding."),
        PivotRole(title: "Learning Experience Designer",
                  searchTerms: ["Learning Experience Designer", "LX Designer", "Learning Experience Design"],
                  typicalSkills: ["learning experience design", "user research", "prototyping", "figma", "usability testing",
                                  "instructional design", "storyboarding", "accessibility", "e-learning"],
                  why: "Combines learning design with product and user-research methods; content and assessment experience is a common way in."),
        PivotRole(title: "Assessment Designer / Test Developer",
                  searchTerms: ["Test Developer", "Assessment Designer", "Assessment Developer", "Psychometric Content Specialist"],
                  typicalSkills: ["item writing", "test blueprint", "standards alignment", "item analysis", "bias and sensitivity",
                                  "psychometrics", "rubrics", "content review", "style guide"],
                  why: "A close neighbor of assessment content work, often at testing organizations and credentialing bodies."),
        PivotRole(title: "Content Quality Assurance Specialist",
                  searchTerms: ["Content Quality Assurance", "Content QA Specialist", "Editorial Quality Specialist"],
                  typicalSkills: ["quality assurance", "editing", "proofreading", "style guide", "fact checking", "accessibility",
                                  "attention to detail", "content review"],
                  why: "Quality review of educational content transfers directly to QA roles across publishing and edtech."),
        PivotRole(title: "Educational Content Editor",
                  searchTerms: ["Content Editor Education", "Educational Editor", "Developmental Editor K-12"],
                  typicalSkills: ["editing", "copyediting", "style guide", "content development", "project management",
                                  "proofreading", "english language arts"],
                  why: "Publishers hire editors who understand standards and student-facing text."),
        PivotRole(title: "Learning Content Developer (EdTech)",
                  searchTerms: ["Learning Content Developer", "Content Developer EdTech", "Digital Content Developer"],
                  typicalSkills: ["content development", "authoring tools", "qti", "xml", "html", "standards alignment",
                                  "project management", "generative ai"],
                  why: "EdTech companies build digital lessons and items in authoring platforms; content experience plus tool fluency fits."),
        PivotRole(title: "Accessibility Specialist (Content)",
                  searchTerms: ["Accessibility Specialist", "Digital Accessibility Content", "Accessibility Content Specialist"],
                  typicalSkills: ["accessibility", "wcag", "alt text", "screen readers", "universal design for learning", "accommodations"],
                  why: "Accessible assessment and content work is in demand; it builds on review and accommodations experience."),
        PivotRole(title: "Professional Learning Specialist",
                  searchTerms: ["Professional Learning Specialist", "Professional Development Specialist", "Implementation Specialist"],
                  typicalSkills: ["professional development", "facilitation", "coaching", "presentations", "adult learning",
                                  "teacher training", "curriculum development"],
                  why: "Helps educators use curriculum and assessment well; suits people who can explain content and standards."),
    ]

    public static func assess(_ profile: Profile, roles: [PivotRole] = catalog) -> [PivotAssessment] {
        let units = profile.units(includeHidden: false)
        let unitTerms = units.map { TextTools.terms($0.text) }
        let unitWords = units.map { " " + TextTools.words($0.text).joined(separator: " ") + " " }
        return roles.map { role in
            var supported: [(skill: String, evidence: ProfileUnit)] = []
            var missing: [String] = []
            for skill in role.typicalSkills {
                let words = " " + TextTools.words(skill).joined(separator: " ") + " "
                let terms = TextTools.terms(skill)
                let hit = units.indices.first { i in
                    unitWords[i].contains(words) || (!terms.isEmpty && terms.isSubset(of: unitTerms[i]))
                }
                if let i = hit { supported.append((skill, units[i])) } else { missing.append(skill) }
            }
            let share = role.typicalSkills.isEmpty ? 0 : Double(supported.count) / Double(role.typicalSkills.count)
            return PivotAssessment(role: role, supported: supported, missing: missing, share: share)
        }
        .sorted { $0.share > $1.share }
    }

    /// Search terms for roles the profile supports best, minus ones already in use.
    public static func suggestedSearchTerms(_ assessments: [PivotAssessment], existing: [String], limit: Int = 8) -> [String] {
        let have = Set(existing.map { $0.lowercased() })
        var out: [String] = []
        for a in assessments where a.share >= 0.3 {
            for t in a.role.searchTerms where !have.contains(t.lowercased()) && !out.contains(t) {
                out.append(t)
                if out.count >= limit { return out }
            }
        }
        return out
    }
}

// MARK: - Credentials

public struct Credential: Codable, Equatable, Hashable, Identifiable {
    public var id: String { name }
    public var name: String
    public var issuer: String
    public var kind: String
    /// Roles it's most relevant to.
    public var relevantTo: [String]
    public var why: String
    /// Time and cost as the source stated them, or "Unknown".
    public var time: String
    public var cost: String
    /// How sure the numbers are: what they're based on.
    public var basis: String
    public var url: String
    /// When Job Bot's details were last checked against the source.
    public var checked: String
}

public enum Credentials {
    public static let catalog: [Credential] = [
        Credential(name: "Associate Professional in Talent Development (APTD)", issuer: "ATD Certification Institute",
                   kind: "Certification exam", relevantTo: ["Instructional Designer", "Learning Experience Designer", "Professional Learning Specialist"],
                   why: "A recognized credential in training and instructional design; useful evidence for a move from K–12 content into learning design.",
                   time: "2-hour exam (preparation time varies)", cost: "Exam fee $525 for ATD members, $800 for non-members",
                   basis: "From ATD's APTD exam page", url: "https://www.td.org/certification/aptd/exam", checked: "November 2026"),
        Credential(name: "Certified Professional in Talent Development (CPTD)", issuer: "ATD Certification Institute",
                   kind: "Certification exam", relevantTo: ["Instructional Designer", "Professional Learning Specialist"],
                   why: "ATD's senior credential. It has experience requirements, so check eligibility first.",
                   time: "3-hour exam (eligibility requires prior experience)", cost: "Exam fee $1,099 for ATD members, $1,500 for non-members",
                   basis: "From ATD's CPTD exam page", url: "https://www.td.org/certification/cptd/exam", checked: "November 2026"),
        Credential(name: "Applying the QM Rubric (APPQMR)", issuer: "Quality Matters",
                   kind: "Workshop with certificate", relevantTo: ["Instructional Designer", "Learning Experience Designer", "Content Quality Assurance Specialist"],
                   why: "Widely used standard for online course quality review; a short, inexpensive signal of online course design knowledge.",
                   time: "Two weeks online, or one full day (or two half days) virtual", cost: "$330 per person; $220 through a member institution",
                   basis: "From the Quality Matters workshop page", url: "https://www.qualitymatters.org/professional-development/workshops/higher-ed-appqmr",
                   checked: "November 2026"),
        Credential(name: "ISTE+ASCD Edtech Leader Certification (formerly ISTE Certification)", issuer: "ISTE+ASCD",
                   kind: "Portfolio certification", relevantTo: ["Learning Content Developer (EdTech)", "Professional Learning Specialist", "Instructional Designer"],
                   why: "Shows pedagogy-first use of technology, which edtech and professional learning teams value.",
                   time: "About 80 hours over roughly 9 months", cost: "$825 per cohort seat (listed on recent cohort pages)",
                   basis: "From ISTE cohort pages; check the current cohort", url: "https://iste-ascd.org/edtech-leader-certification",
                   checked: "November 2026"),
        Credential(name: "Certified Professional in Accessibility Core Competencies (CPACC)", issuer: "International Association of Accessibility Professionals (IAAP)",
                   kind: "Certification exam", relevantTo: ["Accessibility Specialist (Content)", "Assessment Designer / Test Developer", "Content Quality Assurance Specialist"],
                   why: "The foundational accessibility credential; relevant to accessible assessment and content review.",
                   time: "Unknown: check IAAP", cost: "Estimate: about $385 for members and $485 for non-members (reported in 2023 by a third party)",
                   basis: "Estimate from a 2023 third-party article; IAAP's own page wasn't checked", url: "https://www.accessibilityassociation.org/",
                   checked: "November 2026"),
        Credential(name: "Certified Associate in Project Management (CAPM)", issuer: "Project Management Institute (PMI)",
                   kind: "Certification exam", relevantTo: ["Learning Content Developer (EdTech)", "Curriculum Designer", "Instructional Designer"],
                   why: "Content development roles often include managing timelines, writers and reviewers; CAPM documents that skill.",
                   time: "Requires 23 hours of project management education before the exam", cost: "Estimate: $225 for PMI members, $300 for non-members",
                   basis: "Fee reported by several third-party guides; confirm on PMI's page", url: "https://www.pmi.org/certifications/certified-associate-capm",
                   checked: "November 2026"),
        Credential(name: "M.Ed. in Learning, Design & Technology (Instructional Design & Development)", issuer: "University of Georgia (online)",
                   kind: "Degree program", relevantTo: ["Instructional Designer", "Learning Experience Designer", "Curriculum Designer"],
                   why: "A full graduate degree in instructional design, offered fully online by a Georgia university.",
                   time: "At least 36 semester hours; about two years following the standard sequence", cost: "Unknown: check the program page for tuition",
                   basis: "From UGA Online's program page", url: "https://online.uga.edu/online-offerings-graduate/degrees-in-education/master-of-education-in-learning-design-technology-ldt",
                   checked: "November 2026"),
    ]

    public static func relevant(to roles: [String]) -> [Credential] {
        let set = Set(roles)
        let hits = catalog.filter { !set.isDisjoint(with: $0.relevantTo) }
        return hits.isEmpty ? catalog : hits
    }
}

// MARK: - Pay comparison

public enum PayComparison {
    public struct Result: Equatable {
        public var yearlyMidpoint: Double
        public var versusCurrent: Double?
        public var versusTarget: Double?
    }

    /// Compares a posting's pay (as a yearly midpoint) with the person's current and target pay.
    /// Returns nil when the posting has no pay information.
    public static func compare(_ salary: SalaryInfo?, current: Double?, target: Double?) -> Result? {
        guard let mid = salary?.yearlyMidpoint, mid > 0 else { return nil }
        func change(_ base: Double?) -> Double? {
            guard let b = base, b > 0 else { return nil }
            return (mid - b) / b
        }
        return Result(yearlyMidpoint: mid, versusCurrent: change(current), versusTarget: change(target))
    }
}
