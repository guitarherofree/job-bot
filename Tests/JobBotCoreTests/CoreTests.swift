import XCTest
@testable import JobBotCore

final class ResumeParserTests: XCTestCase {
    func testParsesSampleResume() {
        let result = ResumeParser.parse(SampleData.resumeText)
        let p = result.profile
        XCTAssertEqual(p.contact.name, "Jordan Rivera")
        XCTAssertEqual(p.contact.email, "jordan.rivera@example.com")
        XCTAssertEqual(p.contact.phone, "(404) 555-0142")
        XCTAssertEqual(p.contact.location, "Atlanta, GA")
        XCTAssertTrue(p.contact.links.contains { $0.contains("linkedin.com/in/jordan-rivera-example") })
        XCTAssertEqual(p.headline, "Assessment Content Specialist")
        XCTAssertTrue(p.summary.hasPrefix("Assessment content specialist with 9 years"))

        let exp = p.sections.first { $0.kind == .experience }
        XCTAssertEqual(exp?.entries.count, 3)
        let first = exp?.entries.first
        XCTAssertEqual(first?.title, "Senior Content Developer")
        XCTAssertEqual(first?.organization, "Northwind Assessment Services")
        XCTAssertEqual(first?.startDate, "Mar 2021")
        XCTAssertEqual(first?.endDate, "Present")
        XCTAssertEqual(first?.bullets.count, 4)
        let second = exp?.entries[1]
        XCTAssertEqual(second?.title, "Assessment Specialist")
        XCTAssertEqual(second?.organization, "Lakeside Learning Center")
        XCTAssertEqual(second?.location, "Decatur, GA")
        XCTAssertEqual(second?.dateRange, "Aug 2016 – Feb 2021")

        let edu = p.sections.first { $0.kind == .education }?.entries.first
        XCTAssertEqual(edu?.organization, "Georgia State University")
        XCTAssertEqual(edu?.title, "B.A., English")
        XCTAssertEqual(edu?.endDate, "2013")

        let skills = p.sections.first { $0.kind == .skills }?.items ?? []
        XCTAssertEqual(skills.first, "Item writing")
        XCTAssertTrue(skills.contains("QTI"))

        let cert = p.sections.first { $0.kind == .certifications }?.entries.first
        XCTAssertEqual(cert?.title, "Georgia Educator Certificate, English 6–12")
    }

    func testNothingIsInvented() {
        // Every word in the parsed profile appears in the source text.
        let p = ResumeParser.parse(SampleData.resumeText).profile
        let source = Set(TextTools.words(SampleData.resumeText))
        for w in TextTools.words(p.corpus) {
            XCTAssertTrue(source.contains(w), "“\(w)” isn't in the source")
        }
    }

    func testWrappedLinesAreJoined() {
        let text = """
        EXPERIENCE
        Item Writer | Acme Testing | 2019 - 2021
        • Wrote passages and items for grade 4 reading assessments, working closely
        with editors and psychometricians
        """
        let p = ResumeParser.parse(text).profile
        let b = p.sections.first { $0.kind == .experience }?.entries.first?.bullets
        XCTAssertEqual(b?.count, 1)
        XCTAssertEqual(b?.first?.text, "Wrote passages and items for grade 4 reading assessments, working closely with editors and psychometricians")
    }

    func testEmptyTextWarns() {
        let r = ResumeParser.parse("   ")
        XCTAssertFalse(r.warnings.isEmpty)
    }
}

final class JobParserTests: XCTestCase {
    func testBulletIsNotAHeading() {
        XCTAssertNil(JobParser.bucket(forHeader: "• Classroom teaching experience"))
        XCTAssertNil(JobParser.bucket(forHeader: "Classroom teaching experience"))
        XCTAssertNotNil(JobParser.bucket(forHeader: "Preferred Qualifications"))
        XCTAssertNotNil(JobParser.bucket(forHeader: "Experience:"))
    }

    func testParsesSampleJob() {
        let job = SampleData.job()
        XCTAssertEqual(job.title, "ELA Assessment Content Developer")
        XCTAssertEqual(job.employer, "Brightpath Learning")
        XCTAssertTrue(job.parsed.remote)
        XCTAssertEqual(job.parsed.responsibilities.count, 5)
        XCTAssertEqual(job.parsed.requiredQualifications.count, 5)
        XCTAssertEqual(job.parsed.preferredQualifications.count, 2)
        XCTAssertEqual(job.parsed.salary?.minimum, 68000)
        XCTAssertEqual(job.parsed.salary?.maximum, 82000)
        XCTAssertEqual(job.parsed.salary?.period, .year)
        XCTAssertFalse(job.parsed.keywords.isEmpty)
        XCTAssertTrue(job.parsed.keywords.contains { $0.lowercased().contains("qti") })
    }

    func testSalaryFormats() {
        XCTAssertEqual(JobParser.salary(in: "Pay: $25 - $30 per hour")?.period, .hour)
        let k = JobParser.salary(in: "Salary range $65K–$80K annually")
        XCTAssertEqual(k?.minimum, 65000)
        XCTAssertEqual(k?.maximum, 80000)
        let short = JobParser.salary(in: "$65-80K")
        XCTAssertEqual(short?.minimum, 65000)
        XCTAssertNil(JobParser.salary(in: "We offer a $500 learning stipend."))
    }

    func testJSONLDPosting() {
        let html = """
        <html><head><title>Item Writer - Acme</title>
        <script type="application/ld+json">{"@context":"https://schema.org","@type":"JobPosting","title":"Item Writer","datePosted":"2026-10-01",
        "validThrough":"2026-01-01T00:00:00Z","hiringOrganization":{"@type":"Organization","name":"Acme Assessment"},
        "jobLocationType":"TELECOMMUTE","description":"<p>Responsibilities</p><ul><li>Write ELA items</li></ul><p>Qualifications</p><ul><li>3+ years of item writing</li></ul>",
        "baseSalary":{"@type":"MonetaryAmount","currency":"USD","value":{"@type":"QuantitativeValue","minValue":60000,"maxValue":70000,"unitText":"YEAR"}}}</script>
        </head><body>Hello</body></html>
        """
        let now = HTMLText.parseDate("2026-11-20")!
        let job = JobParser.job(fromHTML: html, url: "https://jobs.example.com/1", date: now)
        XCTAssertEqual(job.title, "Item Writer")
        XCTAssertEqual(job.employer, "Acme Assessment")
        XCTAssertTrue(job.parsed.remote)
        XCTAssertEqual(job.parsed.responsibilities, ["Write ELA items"])
        XCTAssertEqual(job.parsed.requiredQualifications, ["3+ years of item writing"])
        XCTAssertEqual(job.parsed.salary?.maximum, 70000)
        XCTAssertTrue(job.expired, "validThrough is in the past")
        XCTAssertNotNil(job.postedDate)
    }

    func testHTMLToText() {
        let t = HTMLText.text(fromHTML: "<div><h2>Duties</h2><ul><li>Edit &amp; review</li><li>Write&nbsp;items</li></ul><script>x()</script></div>")
        XCTAssertEqual(t, "Duties\n• Edit & review\n• Write items")
    }

    func testPageIssues() {
        XCTAssertEqual(HTMLText.issue(html: "", text: "Please verify you are human"), .botCheck)
        XCTAssertEqual(HTMLText.issue(html: "", text: "Sign in to view this job"), .signInRequired)
        XCTAssertNotNil(HTMLText.closedCue(in: "Sorry, this position has been filled."))
    }

    func testNoFetchSites() {
        XCTAssertNotNil(FetchPolicy.blockedReason(for: URL(string: "https://www.linkedin.com/jobs/view/123")!))
        XCTAssertNotNil(FetchPolicy.blockedReason(for: URL(string: "https://www.indeed.com/viewjob?jk=1")!))
        XCTAssertNil(FetchPolicy.blockedReason(for: URL(string: "https://boards.greenhouse.io/acme/jobs/1")!))
    }
}

final class MatcherTests: XCTestCase {
    func testEvidenceAndGaps() {
        let now = HTMLText.parseDate("2026-11-20")!
        let report = Matcher.compare(profile: SampleData.profile, job: SampleData.job(now: now), now: now)
        func req(_ contains: String) -> RequirementMatch? { report.requirements.first { $0.text.contains(contains) } }

        XCTAssertEqual(req("Bachelor's degree")?.strength, .strong)
        XCTAssertEqual(req("standards alignment and item writing")?.strength, .strong)
        XCTAssertFalse(req("standards alignment and item writing")?.evidence.isEmpty ?? true)
        XCTAssertEqual(req("universal design")?.strength, .gap)
        XCTAssertEqual(req("Articulate Storyline")?.strength, .gap)
        XCTAssertNotEqual(req("5+ years")?.strength, .gap)
        XCTAssertTrue(req("5+ years")?.notes.first?.contains("years") ?? false)
        XCTAssertTrue(report.followUps.contains { $0.requirement.contains("universal design") })
        XCTAssertGreaterThan(report.requiredCoverage, 0.5)
        XCTAssertLessThan(report.requiredCoverage, 1.0)
        // Evidence always points at real profile text.
        let corpus = SampleData.profile.corpus
        for r in report.requirements {
            for e in r.evidence { XCTAssertTrue(corpus.contains(e.unit.text) || e.unit.text.contains(",")) }
        }
    }

    func testExperienceYears() {
        var p = Profile()
        p.sections = [ResumeSection(kind: .experience, entries: [
            ResumeEntry(title: "A", startDate: "Jan 2020", endDate: "Dec 2021"),
            ResumeEntry(title: "B", startDate: "Jun 2021", endDate: "Dec 2022"),
        ])]
        let y = Matcher.experienceYears(p) ?? 0
        XCTAssertEqual(y, 3.0, accuracy: 0.01)
    }

    func testRequiredYears() {
        XCTAssertEqual(Matcher.requiredYears(in: "5+ years of experience"), 5)
        XCTAssertEqual(Matcher.requiredYears(in: "three years of teaching"), 3)
        XCTAssertNil(Matcher.requiredYears(in: "grades 3-8"))
    }
}

final class TailorTests: XCTestCase {
    func testSuggestionsAreEvidenceBasedAndApply() {
        let profile = SampleData.profile
        let original = profile
        let job = SampleData.job()
        let suggestions = Tailor.suggestions(for: profile, job: job)
        XCTAssertFalse(suggestions.isEmpty)
        for s in suggestions {
            XCTAssertFalse(s.explanation.isEmpty)
            XCTAssertFalse(WritingRules.containsEmDash(s.after), s.after)
            if s.kind == .addSkill || s.kind == .alignTerm {
                XCTAssertFalse(s.profileEvidence.isEmpty, "\(s.title) has no evidence")
            }
        }
        // The ELA wording suggestion expands the abbreviation instead of dropping it.
        let align = suggestions.first { $0.kind == .alignTerm && $0.before.contains("ELA items") }
        XCTAssertNotNil(align)
        XCTAssertTrue(align?.after.contains("English Language Arts (ELA)") ?? false)

        // Skills are never added without evidence.
        for s in suggestions where s.kind == .addSkill {
            let evidenceText = s.profileEvidence.map { $0.text.lowercased() }.joined(separator: " ")
            XCTAssertFalse(evidenceText.isEmpty)
        }
        XCTAssertFalse(suggestions.contains { $0.kind == .addSkill && $0.after.lowercased().contains("storyline") })

        // Applying every suggestion keeps the profile consistent and the master unchanged.
        var copy = profile
        var applied = 0
        for s in suggestions where (try? Tailor.apply(s, to: &copy)) != nil { applied += 1 }
        XCTAssertGreaterThan(applied, 0)
        XCTAssertNotEqual(copy, profile)
        XCTAssertEqual(original, profile)
    }

    func testStaleSuggestionIsRefused() {
        var profile = SampleData.profile
        let job = SampleData.job()
        guard let s = Tailor.suggestions(for: profile, job: job).first(where: { $0.kind == .alignTerm && $0.target.field == .bullet }) else {
            return XCTFail("expected a wording suggestion")
        }
        // Edit the bullet first.
        for si in profile.sections.indices {
            for ei in profile.sections[si].entries.indices {
                for bi in profile.sections[si].entries[ei].bullets.indices where profile.sections[si].entries[ei].bullets[bi].id == s.target.bulletID {
                    profile.sections[si].entries[ei].bullets[bi].text += " (edited)"
                }
            }
        }
        XCTAssertThrowsError(try Tailor.apply(s, to: &profile))
    }
}

final class WritingTests: XCTestCase {
    func testEmDashesRemoved() {
        XCTAssertEqual(WritingRules.clean("I led reviews — and wrote rubrics."), "I led reviews, and wrote rubrics.")
        XCTAssertEqual(WritingRules.clean("Items—passages—rubrics"), "Items, passages, rubrics")
        XCTAssertEqual(WritingRules.clean("Grades 3–8 from 2019–2021"), "Grades 3–8 from 2019–2021")
        XCTAssertFalse(WritingRules.containsEmDash(WritingRules.clean("A — B")))
    }

    func testFactGuardFlagsNewNumbersAndNames() {
        let p = SampleData.profile
        let findings = FactGuard.check("I increased scores by 40% at Pearson.", profile: p)
        XCTAssertTrue(findings.contains { $0.text == "40%" })
        XCTAssertTrue(findings.contains { $0.text == "Pearson" })
        XCTAssertTrue(FactGuard.check("I developed 1,200+ reading items.", profile: p).isEmpty)
    }

    func testCoverLetterUsesOnlyProfile() {
        let now = HTMLText.parseDate("2026-11-20")!
        let letter = CoverLetterDrafter.draft(profile: SampleData.profile, job: SampleData.job(now: now), now: now)
        XCTAssertFalse(WritingRules.containsEmDash(letter.plainText))
        XCTAssertTrue(letter.body.contains("Brightpath Learning"))
        XCTAssertTrue(letter.body.contains("I am an assessment content specialist"))
        XCTAssertGreaterThanOrEqual(letter.paragraphs.count, 3)
        // No unsupported facts were flagged.
        XCTAssertFalse(letter.reviewNotes.contains { $0.contains("doesn't appear") }, letter.reviewNotes.joined(separator: "\n"))
        // Gaps are listed for review, not written into the letter.
        XCTAssertTrue(letter.reviewNotes.contains { $0.contains("universal design") })
        XCTAssertFalse(letter.body.lowercased().contains("universal design"))
    }

    func testAnswers() {
        let job = SampleData.job()
        let answers = AnswerDrafter.draft(questions: [
            "Email address",
            "Are you authorized to work in the United States?",
            "What are your salary expectations?",
            "Describe your experience with bias and sensitivity reviews.",
            "Do you have experience with Articulate Storyline?",
        ], profile: SampleData.profile, job: job)
        XCTAssertEqual(answers[0].answer, "jordan.rivera@example.com")
        XCTAssertEqual(answers[0].state, .fromProfile)
        XCTAssertEqual(answers[1].state, .personal)
        XCTAssertTrue(answers[1].answer.isEmpty)
        XCTAssertEqual(answers[2].state, .personal)
        XCTAssertEqual(answers[3].state, .needsConfirmation)
        XCTAssertTrue(answers[3].answer.contains("bias and sensitivity"))
        XCTAssertEqual(answers[4].state, .unknown)
        XCTAssertTrue(answers[4].answer.isEmpty)
    }

    func testQuestionSplitting() {
        let qs = AnswerDrafter.questions(from: "Why do you want this job?\n\nDescribe a project you led.\n• Email *")
        XCTAssertEqual(qs, ["Why do you want this job?", "Describe a project you led.", "Email"])
    }
}

final class DocumentTests: XCTestCase {
    func testDocxRoundTrip() throws {
        let profile = SampleData.profile
        let data = DocxWriter.document(Composer.resume(profile), style: .style(for: .modern), title: "Resume", author: "Jordan Rivera")
        XCTAssertEqual(Array(data.prefix(2)), [0x50, 0x4B])
        let xml = try XCTUnwrap(try Zip.read("word/document.xml", from: data))
        let text = DocxReader.text(fromDocumentXML: xml)
        XCTAssertTrue(text.contains("Jordan Rivera"))
        XCTAssertTrue(text.contains("• Write and review ELA items"))
        XCTAssertNotNil(try Zip.read("word/styles.xml", from: data))
        XCTAssertNotNil(try Zip.read("[Content_Types].xml", from: data))
        // Re-parsing the export gives back the same structure.
        let reparsed = ResumeParser.parse(text).profile
        XCTAssertEqual(reparsed.sections.first { $0.kind == .experience }?.entries.count, 3)
    }

    func testXMLEscaping() {
        XCTAssertEqual(DocxWriter.escape("R&D <tag> \"q\" 'a'"), "R&amp;D &lt;tag&gt; &quot;q&quot; &apos;a&apos;")
    }

    func testCRC() {
        XCTAssertEqual(Zip.crc32(Data("123456789".utf8)), 0xCBF43926)
    }

    func testPlainText() {
        let text = PlainTextRenderer.resume(SampleData.profile)
        XCTAssertTrue(text.hasPrefix("Jordan Rivera\nAssessment Content Specialist"))
        XCTAssertTrue(text.contains("EXPERIENCE"))
        XCTAssertTrue(text.contains("- Developed 1,200+ reading and writing items"))
    }

    func testHiddenEntriesAreLeftOut() {
        var p = SampleData.profile
        if let i = p.sections.firstIndex(where: { $0.kind == .experience }) { p.sections[i].entries[2].hidden = true }
        XCTAssertFalse(PlainTextRenderer.resume(p).contains("Oak Hill Middle School"))
    }

    func testDiff() {
        let changes = LineDiff.compare("a\nb\nc", "a\nc\nd")
        XCTAssertEqual(changes, [.same("a"), .removed("b"), .same("c"), .added("d")])
    }
}

final class SettingsLogicTests: XCTestCase {
    func testDefaultLocations() {
        let f = LocationFilter()
        XCTAssertEqual(f.active.map { $0.name }, ["Remote", "Atlanta", "New York"])
        XCTAssertTrue(f.allSelected)
        var g = f
        g.add("Chicago")
        g.options[3].selected = false
        XCTAssertFalse(g.allSelected)
        g.setAll(true)
        XCTAssertTrue(g.allSelected)
        XCTAssertTrue(f.accepts(locationText: "New York, NY"))
        XCTAssertTrue(f.accepts(locationText: "Remote - US"))
        XCTAssertTrue(f.accepts(locationText: "Atlanta, GA (Hybrid)"))
        XCTAssertFalse(f.accepts(locationText: "Chicago, IL"))
        XCTAssertTrue(f.accepts(locationText: ""))
    }

    func testDefaults() {
        let d = DiscoverySettings()
        XCTAssertEqual(d.searchTerms, ["Assessment Specialist", "ELA Content Developer", "Item Writer"])
        XCTAssertEqual(d.companies.count, 42)
        XCTAssertEqual(Set(d.sites.map { $0.name }), ["LinkedIn", "Indeed", "Handshake"])
    }

    func testCareerLinks() {
        let d = DiscoverySettings()
        XCTAssertEqual(d.careerLinksVersion, DiscoverySettings.currentCareerLinksVersion)
        // Every built-in company has a link, and every link belongs to a built-in company.
        XCTAssertEqual(Set(DiscoverySettings.defaultCompanies), Set(DiscoverySettings.defaultCareerLinks.keys))
        for c in d.companies {
            XCTAssertTrue(c.careersURL.hasPrefix("https://"), c.name)
            XCTAssertNotNil(URL(string: c.careersURL), c.name)
        }
        func company(_ name: String) -> CompanySource? { d.companies.first { $0.name == name } }
        XCTAssertEqual(company("Prodigy")?.board, .ashby)
        XCTAssertEqual(company("Prodigy")?.boardToken, "prodigy-education")
        XCTAssertEqual(company("Edmentum")?.board, .greenhouse)
        XCTAssertEqual(company("Edmentum")?.boardToken, "edmentum")
        XCTAssertEqual(company("Seesaw")?.board, .greenhouse)
        XCTAssertEqual(company("Seesaw")?.boardToken, "seesaw")
        XCTAssertEqual(company("CommonLit")?.board, .lever)
        XCTAssertEqual(company("CommonLit")?.boardToken, "commonlit")
        XCTAssertEqual(company("Pearson")?.board, BoardKind.none)
        XCTAssertEqual(company("Renaissance")?.board, .smartrecruiters)
        XCTAssertEqual(company("Renaissance")?.boardToken, "Renaissance")
        XCTAssertEqual(company("Riverside Insights")?.board, .workable)
        XCTAssertEqual(company("Riverside Insights")?.boardToken, "riverside-insights")
        XCTAssertEqual(company("College Board")?.board, .workday)
        XCTAssertEqual(company("College Board")?.boardToken, "collegeboard.wd1.myworkdayjobs.com/Careers")
        XCTAssertEqual(company("Kaplan")?.boardToken, "ghc.wd1.myworkdayjobs.com/Kaplan_Careers")
        XCTAssertEqual(d.companies.filter { $0.board != .none }.count, 13)

        // Older libraries get the links once; links someone entered are kept.
        var old = DiscoverySettings()
        old.careerLinksVersion = nil
        for i in old.companies.indices {
            old.companies[i].careersURL = ""
            old.companies[i].board = .none
            old.companies[i].boardToken = ""
        }
        old.companies[0].careersURL = "https://example.com/my-own-link"
        old.companies[1].name = "prodigy"
        XCTAssertEqual(old.addDefaultCareerLinks(), 41)
        XCTAssertEqual(old.companies[0].careersURL, "https://example.com/my-own-link")
        XCTAssertEqual(old.companies[1].board, .ashby)
        XCTAssertEqual(old.addDefaultCareerLinks(), 0)
        old.companies[2].careersURL = ""
        XCTAssertEqual(old.addDefaultCareerLinks(), 0, "a cleared link isn't refilled")
    }

    func testDuplicates() {
        let a = Job(title: "Item Writer", employer: "Acme", url: "https://jobs.acme.com/1?utm_source=x")
        let b = Job(title: "Item Writer", employer: "Acme", url: "https://jobs.acme.com/1")
        XCTAssertNotNil(Duplicates.match(for: b, in: [a]))
        let c = Job(title: "Editor", employer: "Acme", url: "https://jobs.acme.com/2")
        XCTAssertNil(Duplicates.match(for: c, in: [a]))
    }

    func testBoardDetection() {
        XCTAssertEqual(Boards.detect(fromURL: "https://boards.greenhouse.io/acme/jobs/123")?.1, "acme")
        XCTAssertEqual(Boards.detect(fromURL: "https://jobs.lever.co/acme/abc")?.0, .lever)
        XCTAssertEqual(Boards.detect(fromURL: "https://jobs.ashbyhq.com/acme")?.1, "acme")
        XCTAssertNil(Boards.detect(fromURL: "https://acme.com/careers"))
    }

    func testBoardParsing() throws {
        let gh = """
        {"jobs":[{"id":1,"title":"Assessment Specialist","absolute_url":"https://boards.greenhouse.io/acme/jobs/1","location":{"name":"Remote"},"updated_at":"2026-11-01T10:00:00-04:00","content":"&lt;p&gt;Write items&lt;/p&gt;"},
        {"id":2,"title":"Software Engineer","absolute_url":"https://boards.greenhouse.io/acme/jobs/2","location":{"name":"Chicago, IL"},"content":""}]}
        """
        let jobs = try Boards.parse(Data(gh.utf8), kind: .greenhouse, company: "Acme")
        XCTAssertEqual(jobs.count, 2)
        let filtered = Boards.filter(jobs, terms: ["Assessment Specialist", "Item Writer"], locations: LocationFilter())
        XCTAssertEqual(filtered.map { $0.title }, ["Assessment Specialist"])
        let job = filtered[0].toJob()
        XCTAssertTrue(job.descriptionText.contains("Write items"))
    }

    func testVersions() {
        XCTAssertTrue(Releases.isNewer("1.10.0", than: "1.9.3"))
        XCTAssertFalse(Releases.isNewer("1.0.0", than: "1.0"))
        XCTAssertEqual(Releases.version(fromTag: "v2.1.0"), "2.1.0")
        let json = """
        {"tag_name":"v1.2.0","name":"Job Bot 1.2.0","body":"- Faster","html_url":"https://github.com/o/r/releases/tag/v1.2.0",
         "zipball_url":"https://api.github.com/repos/o/r/zipball/v1.2.0","published_at":"2026-11-20T12:00:00Z",
         "assets":[{"name":"Job-Bot-1.2.0.zip","url":"https://api.github.com/repos/o/r/releases/assets/9","browser_download_url":"https://github.com/o/r/releases/download/v1.2.0/Job-Bot-1.2.0.zip","size":100}]}
        """
        let r = try? Releases.parse(Data(json.utf8))
        XCTAssertEqual(r?.version, "1.2.0")
        XCTAssertEqual(r?.appAsset?.name, "Job-Bot-1.2.0.zip")
        XCTAssertEqual(r?.notes, "- Faster")
    }

    func testStoreRoundTripAndBackup() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("jobbot-test-\(UUID().uuidString)")
        let store = DataStore(folder: dir)
        var data = AppData()
        data.master = SampleData.profile
        data.jobs = [SampleData.job()]
        try store.save(data)
        try store.save(data)
        guard case .loaded(let loaded) = store.load() else { return XCTFail("didn't load") }
        XCTAssertEqual(loaded.master, data.master)
        XCTAssertEqual(loaded.jobs.first?.title, data.jobs.first?.title)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.backup.path))
        // A damaged file falls back to the backup and is kept.
        try Data("{not json".utf8).write(to: store.file)
        guard case .recovered(let recovered, _) = store.load() else { return XCTFail("didn't recover") }
        XCTAssertEqual(recovered.master, data.master)
        try store.deleteAll()
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path))
    }

    func testPivotsAndCredentials() {
        let a = Pivots.assess(SampleData.profile)
        XCTAssertEqual(a.count, Pivots.catalog.count)
        XCTAssertTrue(a.first!.share >= a.last!.share)
        for x in a { for s in x.supported { XCTAssertFalse(s.evidence.text.isEmpty) } }
        for c in Credentials.catalog {
            XCTAssertTrue(c.url.hasPrefix("https://"))
            XCTAssertFalse(c.cost.isEmpty)
            XCTAssertFalse(c.time.isEmpty)
        }
    }

    func testExamplesKeepPatternsOnly() {
        let p = ExampleAnalyzer.analyze(SampleData.resumeText, label: "Sample")
        XCTAssertTrue(p.roleTitles.contains("Senior Content Developer"))
        let stored = (p.roleTitles + p.credentials + p.skills + p.achievementPatterns + p.commonVerbs).joined(separator: " ")
        XCTAssertFalse(stored.contains("Jordan"))
        XCTAssertFalse(stored.contains("example.com"))
        XCTAssertFalse(stored.contains("Northwind"))
        XCTAssertFalse(p.achievementPatterns.isEmpty)
    }

    func testAIReplyValidation() {
        let profile = SampleData.profile
        let job = SampleData.job()
        let units = profile.units()
        let bullet = units.first { $0.ref.field == .bullet }!
        let reply = """
        Here you go:
        ```json
        {"suggestions":[
          {"target":"\(bullet.label)","text":"Wrote and reviewed ELA items — boosting scores 30%","evidence":["\(bullet.label)"],"job_terms":["item writing"],"why":"Uses the posting's terms."},
          {"target":"\(bullet.label)","text":"Something else","evidence":[],"why":"x"},
          {"target":"Z9","text":"Nope","evidence":["Z9"]}
        ],"questions":[{"requirement":"UDL","question":"Have you applied UDL?"}]}
        ```
        """
        let r = AIPrompts.readTailor(reply, profile: profile, job: job, service: "Test")
        XCTAssertEqual(r.suggestions.count, 1)
        XCTAssertFalse(WritingRules.containsEmDash(r.suggestions[0].after))
        XCTAssertTrue(r.suggestions[0].warnings.contains { $0.contains("30%") })
        XCTAssertEqual(r.rejected.count, 2)
        XCTAssertEqual(r.questions.count, 1)
        // Requests never include contact details.
        let req = AIPrompts.tailor(profile: profile, job: job)
        XCTAssertFalse(req.user.contains("jordan.rivera@example.com"))
        XCTAssertFalse(req.user.contains("555-0142"))
        XCTAssertFalse(req.user.contains("Jordan Rivera"))
    }
}


final class ListingTests: XCTestCase {
    func testNewBoardDetection() {
        XCTAssertEqual(Boards.detect(fromURL: "https://careers.smartrecruiters.com/Renaissance")?.0, .smartrecruiters)
        XCTAssertEqual(Boards.detect(fromURL: "https://jobs.smartrecruiters.com/Acme/123-editor")?.1, "Acme")
        XCTAssertEqual(Boards.detect(fromURL: "https://apply.workable.com/riverside-insights/")?.1, "riverside-insights")
        XCTAssertNil(Boards.detect(fromURL: "https://apply.workable.com/j/ABC123"))
        XCTAssertEqual(Boards.detect(fromURL: "https://amplify.wd1.myworkdayjobs.com/Amplify_Careers")?.1, "amplify.wd1.myworkdayjobs.com/Amplify_Careers")
        XCTAssertEqual(Boards.detect(fromURL: "https://collegeboard.wd1.myworkdayjobs.com/en-US/Careers/job/Remote/Editor_R1")?.1, "collegeboard.wd1.myworkdayjobs.com/Careers")
        let site = WorkdaySite(token: "ghc.wd1.myworkdayjobs.com/Kaplan_Careers")
        XCTAssertEqual(site?.tenant, "ghc")
        XCTAssertEqual(site?.searchURL?.absoluteString, "https://ghc.wd1.myworkdayjobs.com/wday/cxs/ghc/Kaplan_Careers/jobs")
        XCTAssertEqual(site?.publicURL(externalPath: "/job/Remote/Item-Writer_R9"), "https://ghc.wd1.myworkdayjobs.com/Kaplan_Careers/job/Remote/Item-Writer_R9")
        var c = CompanySource(name: "Kaplan", board: .workday, boardToken: "ghc.wd1.myworkdayjobs.com/Kaplan_Careers")
        XCTAssertEqual(c.boardLabel, "ghc")
        c.board = .lever
        c.boardToken = "acme"
        XCTAssertEqual(c.boardLabel, "acme")
    }

    func testWorkdayRequestsSearchEachTerm() throws {
        let reqs = BoardKind.workday.listingRequests(token: "amplify.wd1.myworkdayjobs.com/Amplify_Careers",
                                                     terms: ["Item Writer", "item writer", "ELA Content Developer"])
        XCTAssertEqual(reqs.count, 2)
        XCTAssertEqual(reqs[0].method, "POST")
        let body = try XCTUnwrap(reqs[0].body)
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(obj["searchText"] as? String, "Item Writer")
        XCTAssertEqual(obj["limit"] as? Int, 20)
        XCTAssertEqual(BoardKind.greenhouse.listingRequests(token: "acme", terms: ["x"]).count, 1)
    }

    func testSmartRecruitersParsing() throws {
        let list = """
        {"offset":0,"limit":100,"totalFound":230,"content":[
          {"id":"744000099","name":"Assessment Specialist, ELA","releasedDate":"2026-11-12T15:00:00.000Z","company":{"identifier":"Renaissance","name":"Renaissance Learning"},
           "location":{"city":"Wisconsin Rapids","region":"WI","country":"us","remote":true},"ref":"https://api.smartrecruiters.com/v1/companies/Renaissance/postings/744000099"},
          {"id":"744000100","name":"Senior Software Engineer","company":{"name":"Renaissance Learning"},"location":{"city":"Minneapolis","region":"MN","country":"us","remote":false}}]}
        """
        let jobs = try Boards.parse(Data(list.utf8), kind: .smartrecruiters, company: "Renaissance", token: "Renaissance")
        XCTAssertEqual(jobs.count, 2)
        XCTAssertEqual(jobs[0].id, "sr-744000099")
        XCTAssertEqual(jobs[0].employer, "Renaissance Learning")
        XCTAssertEqual(jobs[0].origin, "Renaissance")
        XCTAssertTrue(jobs[0].remote)
        XCTAssertTrue(jobs[0].location.hasPrefix("Remote"))
        XCTAssertEqual(jobs[0].detailURL, "https://api.smartrecruiters.com/v1/companies/Renaissance/postings/744000099")
        XCTAssertEqual(jobs[1].detailURL, "https://api.smartrecruiters.com/v1/companies/Renaissance/postings/744000100")

        let first = BoardRequest(url: URL(string: "https://api.smartrecruiters.com/v1/companies/Renaissance/postings?limit=100&offset=0")!)
        let next = Boards.nextPage(after: Data(list.utf8), request: first, kind: .smartrecruiters)
        XCTAssertEqual(next?.url.absoluteString, "https://api.smartrecruiters.com/v1/companies/Renaissance/postings?limit=100&offset=100")
        let last = BoardRequest(url: URL(string: "https://api.smartrecruiters.com/v1/companies/Renaissance/postings?limit=100&offset=200")!)
        XCTAssertNil(Boards.nextPage(after: Data(list.utf8), request: last, kind: .smartrecruiters))

        let detail = """
        {"id":"744000099","postingUrl":"https://jobs.smartrecruiters.com/Renaissance/744000099-assessment-specialist-ela",
         "jobAd":{"sections":{"companyDescription":{"title":"Company Description","text":"<p>We make software.</p>"},
          "jobDescription":{"title":"Job Description","text":"<ul><li>Write and review ELA items aligned to standards</li><li>Lead bias and sensitivity reviews</li></ul>"},
          "qualifications":{"title":"Qualifications","text":"<ul><li>3+ years of K-12 assessment development</li><li>Bachelor's degree</li></ul>"}}}}
        """
        var job = jobs[0]
        try Boards.applyDetail(Data(detail.utf8), to: &job)
        XCTAssertEqual(job.url, "https://jobs.smartrecruiters.com/Renaissance/744000099-assessment-specialist-ela")
        XCTAssertFalse(job.descriptionHTML.contains("We make software"), "the company blurb is left out")
        let parsed = job.toJob().parsed
        XCTAssertFalse(parsed.requiredQualifications.isEmpty || parsed.responsibilities.isEmpty, "\(parsed)")
    }

    func testWorkableParsing() throws {
        let feed = """
        {"name":"Riverside Insights","jobs":[
          {"title":"Content Developer, ELA","shortcode":"AB12CD","url":"https://apply.workable.com/j/AB12CD","published_on":"2026-11-03","telecommuting":true,
           "city":"Itasca","state":"Illinois","country":"United States","description":"<p>Develop reading items.</p>","requirements":"<ul><li>ELA teaching experience</li></ul>"},
          {"title":"Item Writer","shortcode":"ZZ99","city":"","state":"","country":"","locations":[{"city":"Atlanta","region":"Georgia","country":"United States"}]}]}
        """
        let jobs = try Boards.parse(Data(feed.utf8), kind: .workable, company: "Riverside Insights", token: "riverside-insights")
        XCTAssertEqual(jobs.map(\.id), ["wk-AB12CD", "wk-ZZ99"])
        XCTAssertTrue(jobs[0].remote)
        XCTAssertTrue(jobs[0].descriptionHTML.contains("Requirements"))
        XCTAssertNil(jobs[0].detailURL)
        XCTAssertEqual(jobs[1].location, "Atlanta, Georgia, United States")
        XCTAssertEqual(jobs[1].detailURL, "https://apply.workable.com/api/v2/accounts/riverside-insights/jobs/ZZ99")
        XCTAssertNotNil(jobs[0].posted)
        var second = jobs[1]
        try Boards.applyDetail(Data(#"{"description":"<p>Write items.</p>","requirements":"<p>Teaching</p>"}"#.utf8), to: &second)
        XCTAssertTrue(second.descriptionHTML.contains("Write items"))
    }

    func testWorkdayParsing() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let search = """
        {"total":2,"jobPostings":[
          {"title":"Assessment Specialist - Reading","externalPath":"/job/Remote-USA/Assessment-Specialist---Reading_R1001","locationsText":"Remote - USA","postedOn":"Posted 3 Days Ago","bulletFields":["R1001"]},
          {"title":"Item Writer (Contract)","externalPath":"/job/New-York/Item-Writer_R1002","locationsText":"2 Locations","postedOn":"Posted Today"}]}
        """
        let token = "amplify.wd1.myworkdayjobs.com/Amplify_Careers"
        let jobs = try Boards.parse(Data(search.utf8), kind: .workday, company: "Amplify", token: token, now: now)
        XCTAssertEqual(jobs.count, 2)
        XCTAssertEqual(jobs[0].url, "https://amplify.wd1.myworkdayjobs.com/Amplify_Careers/job/Remote-USA/Assessment-Specialist---Reading_R1001")
        XCTAssertEqual(jobs[0].detailURL, "https://amplify.wd1.myworkdayjobs.com/wday/cxs/amplify/Amplify_Careers/job/Remote-USA/Assessment-Specialist---Reading_R1001")
        XCTAssertTrue(jobs[0].remote)
        XCTAssertEqual(jobs[0].posted, now.addingTimeInterval(-3 * 86_400))
        XCTAssertEqual(jobs[1].location, "", "“2 Locations” waits for the posting")
        XCTAssertEqual(jobs[1].posted, now)
        XCTAssertEqual(jobs[1].board, .workday)

        let detail = """
        {"jobPostingInfo":{"title":"Item Writer (Contract)","jobDescription":"<p><b>What you'll do</b></p><ul><li>Write items</li></ul>",
          "location":"New York, NY","additionalLocations":["Remote - USA"],"startDate":"2026-11-02","timeType":"Part time",
          "externalUrl":"https://amplify.wd1.myworkdayjobs.com/en-US/Amplify_Careers/job/New-York/Item-Writer_R1002"},
         "hiringOrganization":{"name":"Amplify Education"}}
        """
        var job = jobs[1]
        try Boards.applyDetail(Data(detail.utf8), to: &job)
        XCTAssertEqual(job.location, "New York, NY, Remote - USA")
        XCTAssertTrue(job.remote)
        XCTAssertTrue(job.descriptionHTML.contains("Write items"))
        XCTAssertEqual(job.url, "https://amplify.wd1.myworkdayjobs.com/en-US/Amplify_Careers/job/New-York/Item-Writer_R1002")
        XCTAssertEqual(job.posted, HTMLText.parseDate("2026-11-02"))
    }

    func testSearchRunsEveryBoardAndReadsPostings() async throws {
        let gh = CompanySource(name: "Acme", board: .greenhouse, boardToken: "acme")
        let wd = CompanySource(name: "Beta", board: .workday, boardToken: "beta.wd5.myworkdayjobs.com/External")
        let broken = CompanySource(name: "Gamma", board: .lever, boardToken: "gamma")
        let off = CompanySource(name: "Delta", board: .ashby, boardToken: "delta", enabled: false)
        let ghList = """
        {"jobs":[{"id":1,"title":"Assessment Specialist","absolute_url":"https://boards.greenhouse.io/acme/jobs/1","location":{"name":"Remote"},"content":"<p>Write items</p>"},
                 {"id":2,"title":"Assessment Specialist","absolute_url":"https://boards.greenhouse.io/acme/jobs/2","location":{"name":"Chicago, IL"},"content":"<p>x</p>"},
                 {"id":3,"title":"Accountant","absolute_url":"https://boards.greenhouse.io/acme/jobs/3","location":{"name":"Remote"},"content":""}]}
        """
        let wdList = """
        {"total":1,"jobPostings":[{"title":"Item Writer","externalPath":"/job/x/Item-Writer_R5","locationsText":"3 Locations","postedOn":"Posted Yesterday"}]}
        """
        let wdDetail = """
        {"jobPostingInfo":{"jobDescription":"<p>Write ELA items.</p>","location":"Atlanta, GA"}}
        """
        var requested: [String] = []
        let outcome = await BoardSearch.run(companies: [gh, wd, broken, off], terms: ["Assessment Specialist", "Item Writer"],
                                            locations: LocationFilter()) { request in
            requested.append("\(request.method) \(request.url.absoluteString)")
            switch request.url.host ?? "" {
            case "boards-api.greenhouse.io": return Data(ghList.utf8)
            case "beta.wd5.myworkdayjobs.com": return Data((request.method == "POST" ? wdList : wdDetail).utf8)
            default: throw URLError(.notConnectedToInternet)
            }
        }
        XCTAssertEqual(outcome.searched, ["Acme", "Beta"])
        XCTAssertEqual(Set(outcome.jobs.map(\.id)), ["gh-1", "wd-beta-/job/x/Item-Writer_R5"])
        let item = try XCTUnwrap(outcome.jobs.first { $0.board == .workday })
        XCTAssertEqual(item.location, "Atlanta, GA")
        XCTAssertTrue(item.descriptionHTML.contains("Write ELA items"))
        XCTAssertEqual(requested.filter { $0.hasPrefix("POST") }.count, 2, "one Workday search per term")
        XCTAssertFalse(requested.contains { $0.contains("delta") }, "turned-off companies aren't searched")
        XCTAssertTrue(outcome.notes.contains { $0.hasPrefix("Gamma:") })
        XCTAssertTrue(outcome.notes.contains("Acme: 1 match of 3 open roles."), "\(outcome.notes)")
    }

    func testFoundListingsMerge() {
        func d(_ id: String, _ company: String, _ title: String = "Item Writer") -> DiscoveredJob {
            DiscoveredJob(id: id, title: title, employer: company, location: "Remote", url: "https://example.com/\(id)", source: "Test",
                          posted: nil, descriptionHTML: "<p>Write items.</p>", origin: company)
        }
        var found = FoundListings()
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(found.merge([d("a", "Acme"), d("b", "Acme"), d("c", "Beta")], searched: ["Acme", "Beta"], now: t0), 3)
        XCTAssertEqual(found.unviewedCount, 3)
        let idOfA = found.items.first { $0.id == "a" }!.job.id
        found.items[0].viewed = true
        found.dismiss("b")
        // Next search: "a" again, "b" again (dismissed), "c" missing but Beta couldn't be read, "d" new.
        let t1 = t0.addingTimeInterval(3600)
        XCTAssertEqual(found.merge([d("a", "Acme", "Item Writer II"), d("b", "Acme"), d("d", "Acme")], searched: ["Acme"], now: t1), 1)
        XCTAssertEqual(Set(found.items.map(\.id)), ["a", "c", "d"])
        let a = found.items.first { $0.id == "a" }!
        XCTAssertEqual(a.job.id, idOfA, "a listing keeps its identity")
        XCTAssertEqual(a.job.title, "Item Writer II")
        XCTAssertTrue(a.viewed)
        XCTAssertEqual(a.firstSeen, t0)
        XCTAssertEqual(a.lastSeen, t1)
        // Beta read again without "c": it's gone.
        found.merge([d("a", "Acme"), d("d", "Acme")], searched: ["Acme", "Beta"], now: t1)
        XCTAssertEqual(Set(found.items.map(\.id)), ["a", "d"])
        XCTAssertEqual(found.take("d")?.id, "d")
        XCTAssertNil(found.take("d"))
        XCTAssertEqual(found.lastSearch, t1)
    }

    func testConnectingBoardsInOlderLibraries() {
        var old = DiscoverySettings()
        old.boardLinksVersion = nil
        for i in old.companies.indices where ![BoardKind.greenhouse, .lever, .ashby].contains(old.companies[i].board) {
            old.companies[i].board = .none
            old.companies[i].boardToken = ""
        }
        old.companies[0].careersURL = "https://jobs.lever.co/my-own-board"
        old.companies[0].board = .lever
        old.companies[0].boardToken = "my-own-board"
        XCTAssertEqual(old.connectDetectedBoards(), 9)
        XCTAssertEqual(old.companies.filter { $0.board != .none }.count, 14)
        XCTAssertEqual(old.companies[0].boardToken, "my-own-board")
        XCTAssertEqual(old.connectDetectedBoards(), 0, "runs once")
    }

    func testOlderLibraryWithoutListingsStillOpens() throws {
        var data = AppData()
        data.found.items = []
        let encoded = try DataStore.encoder.encode(data)
        var obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        obj.removeValue(forKey: "foundListings")
        var discovery = try XCTUnwrap(obj["discovery"] as? [String: Any])
        discovery.removeValue(forKey: "boardLinksVersion")
        obj["discovery"] = discovery
        let old = try JSONSerialization.data(withJSONObject: obj)
        let decoded = try DataStore.decoder.decode(AppData.self, from: old)
        XCTAssertNil(decoded.foundListings)
        XCTAssertTrue(decoded.found.items.isEmpty)
        XCTAssertNil(decoded.discovery.boardLinksVersion)
    }

    func testFit() {
        let job = SampleData.job()
        let report = Matcher.compare(profile: SampleData.profile, job: job)
        let fit = report.fit
        XCTAssertGreaterThan(fit.requiredTotal, 0)
        XCTAssertLessThanOrEqual(fit.requiredCovered, fit.requiredTotal)
        XCTAssertTrue(fit.summary.hasPrefix("Covers \(fit.requiredCovered) of \(fit.requiredTotal)"))
        XCTAssertNotEqual(fit.level, .unknown)
        XCTAssertEqual(Fit(requiredCovered: 0, requiredTotal: 0, keywordsMatched: 0, keywordsTotal: 0).level, .unknown)
        XCTAssertEqual(Fit(requiredCovered: 4, requiredTotal: 4, keywordsMatched: 8, keywordsTotal: 10).level, .strong)
        XCTAssertEqual(Fit(requiredCovered: 1, requiredTotal: 4, keywordsMatched: 1, keywordsTotal: 10).level, .low)
        XCTAssertFalse(WritingRules.containsEmDash(fit.summary))
    }

    /// Reads the real boards. Runs only with JOBBOT_LIVE=1 (the build check does this in a
    /// separate step, so a board being down never fails the build).
    func testLiveBoards() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["JOBBOT_LIVE"] == "1", "live check off")
        let settings = DiscoverySettings()
        var all = LocationFilter()
        all.setAll(true)
        let terms = settings.searchTerms + ["Editor", "Content", "Assessment", "Curriculum", "Writer", "Specialist"]
        let session = URLSession(configuration: .ephemeral)
        let outcome = await BoardSearch.run(companies: settings.companies, terms: terms, locations: all, detailLimit: 40) { request in
            var r = URLRequest(url: request.url)
            r.httpMethod = request.method
            r.httpBody = request.body
            r.setValue("application/json", forHTTPHeaderField: "Accept")
            r.setValue("JobBot/1.0 (Macintosh; personal job search app)", forHTTPHeaderField: "User-Agent")
            if request.body != nil { r.setValue("application/json", forHTTPHeaderField: "Content-Type") }
            let (data, response) = try await session.data(for: r)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(code) else {
                throw NSError(domain: "live", code: code, userInfo: [NSLocalizedDescriptionKey: "HTTP \(code) from \(request.url.host ?? "")"])
            }
            return data
        }
        print("LIVE requests: \(outcome.requests)")
        for note in outcome.notes { print("LIVE note: \(note)") }
        for job in outcome.jobs.prefix(60) {
            let parsed = job.toJob().parsed
            print("LIVE job: [\(job.board.shortName)] \(job.title) | \(job.employer) | \(job.location) | remote=\(job.remote) | posted=\(job.posted.map { "\($0)" } ?? "-") | desc=\(job.descriptionHTML.count) | resp=\(parsed.responsibilities.count) req=\(parsed.requiredQualifications.count) pref=\(parsed.preferredQualifications.count) | \(job.url)")
        }
        // Raw answers from boards that returned nothing, to tell "no openings" from a changed feed.
        let quiet = settings.companies.filter { c in
            c.board != .none && !outcome.jobs.contains { $0.origin == c.name }
        }
        for c in quiet {
            guard let request = c.board.listingRequests(token: c.boardToken, terms: settings.searchTerms).first else { continue }
            var r = URLRequest(url: request.url)
            r.httpMethod = request.method
            r.httpBody = request.body
            r.setValue("application/json", forHTTPHeaderField: "Accept")
            r.setValue("JobBot/1.0 (Macintosh; personal job search app)", forHTTPHeaderField: "User-Agent")
            if request.body != nil { r.setValue("application/json", forHTTPHeaderField: "Content-Type") }
            do {
                let (data, response) = try await session.data(for: r)
                let http = response as? HTTPURLResponse
                let text = String(decoding: data.prefix(500), as: UTF8.self).replacingOccurrences(of: "\n", with: " ")
                print("LIVE raw \(c.name) [\(c.board.shortName)] \(request.url.absoluteString) -> \(http?.statusCode ?? 0) server=\(http?.value(forHTTPHeaderField: "Server") ?? "-"): \(text)")
            } catch {
                print("LIVE raw \(c.name): \(error.localizedDescription)")
            }
        }
        XCTAssertFalse(outcome.searched.isEmpty)
    }
}
