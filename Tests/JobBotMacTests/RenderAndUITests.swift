import XCTest
import AppKit
import SwiftUI
import PDFKit
@testable import JobBotCore
@testable import JobBotRender
@testable import JobBotUI

/// Where previews are written (CI uploads this folder so the output can be looked at).
let previewFolder: URL = {
    let path = ProcessInfo.processInfo.environment["JOBBOT_PREVIEWS"]
        ?? FileManager.default.temporaryDirectory.appendingPathComponent("jobbot-previews").path
    let url = URL(fileURLWithPath: path, isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}()

func writePreview(_ data: Data, _ name: String) {
    try? data.write(to: previewFolder.appendingPathComponent(name))
}

func pngOfFirstPage(_ pdf: Data, pageIndex: Int = 0) -> Data? {
    guard let doc = PDFDocument(data: pdf), let page = doc.page(at: pageIndex) else { return nil }
    let bounds = page.bounds(for: .mediaBox)
    let scale: CGFloat = 1.5
    let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    ctx.cgContext.setFillColor(NSColor.white.cgColor)
    ctx.cgContext.fill(CGRect(origin: .zero, size: size))
    ctx.cgContext.scaleBy(x: scale, y: scale)
    page.draw(with: .mediaBox, to: ctx.cgContext)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

final class RenderTests: XCTestCase {
    func testResumePDFsForEveryTemplate() throws {
        let profile = SampleData.profile
        for t in TemplateID.allCases {
            let pdf = PDFRenderer.resume(profile, template: t)
            writePreview(pdf, "resume-\(t.rawValue).pdf")
            if let png = pngOfFirstPage(pdf) { writePreview(png, "resume-\(t.rawValue).png") }
            XCTAssertEqual(PDFText.pageCount(of: pdf), 1, "\(t) should fit the sample on one page")
            let text = PDFText.text(of: pdf)
            writePreview(Data(text.utf8), "resume-\(t.rawValue)-pdftext.txt")
            XCTAssertTrue(text.contains("Jordan Rivera"), t.rawValue)
            XCTAssertTrue(text.contains("Write and review ELA items"), t.rawValue)
            XCTAssertTrue(text.lowercased().contains("experience"), t.rawValue)
            XCTAssertFalse(text.contains("—"), t.rawValue)
            // The PDF's text reads back into the same structure.
            let reparsed = ResumeParser.parse(text).profile
            XCTAssertEqual(reparsed.sections.first { $0.kind == .experience }?.entries.count, 3, "re-reading \(t) PDF")
        }
    }

    func testLongResumePaginates() {
        var p = SampleData.profile
        if let i = p.sections.firstIndex(where: { $0.kind == .experience }) {
            for n in 0..<6 {
                var e = p.sections[i].entries[0]
                e.id = UUID()
                e.title = "Content Role \(n + 1)"
                e.bullets = (0..<6).map { Bullet(text: "Reviewed and revised assessment items number \($0 + 1) for alignment, clarity and fairness across grades 3–8") }
                p.sections[i].entries.append(e)
            }
        }
        let pdf = PDFRenderer.resume(p, template: .modern)
        writePreview(pdf, "resume-long-modern.pdf")
        if let png = pngOfFirstPage(pdf, pageIndex: 1) { writePreview(png, "resume-long-modern-page2.png") }
        XCTAssertGreaterThanOrEqual(PDFText.pageCount(of: pdf), 2)
        let text = PDFText.text(of: pdf)
        XCTAssertTrue(text.contains("Content Role 6"))
        XCTAssertTrue(text.contains("Georgia State University"))
    }

    func testCoverLetterPDFs() {
        let now = HTMLText.parseDate("2026-11-20")!
        var letter = CoverLetterDrafter.draft(profile: SampleData.profile, job: SampleData.job(now: now), now: now)
        for t in TemplateID.allCases {
            letter.template = t
            let pdf = PDFRenderer.coverLetter(letter, profile: SampleData.profile, date: now)
            writePreview(pdf, "letter-\(t.rawValue).pdf")
            if let png = pngOfFirstPage(pdf) { writePreview(png, "letter-\(t.rawValue).png") }
            XCTAssertEqual(PDFText.pageCount(of: pdf), 1)
            let text = PDFText.text(of: pdf)
            XCTAssertTrue(text.contains("Dear Brightpath Learning Hiring Team"))
            XCTAssertTrue(text.contains("Sincerely"))
            XCTAssertFalse(text.contains("—"))
        }
        let txt = PlainTextRenderer.coverLetter(letter, profile: SampleData.profile, date: now)
        writePreview(Data(txt.utf8), "letter.txt")
    }

    func testDocxOpensInAppKit() throws {
        let profile = SampleData.profile
        for t in TemplateID.allCases {
            let data = DocxWriter.document(Composer.resume(profile), style: .style(for: t), title: "Resume", author: profile.contact.name)
            writePreview(data, "resume-\(t.rawValue).docx")
            let attributed = try NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.officeOpenXML],
                                                    documentAttributes: nil)
            XCTAssertTrue(attributed.string.contains("Jordan Rivera"), t.rawValue)
            XCTAssertTrue(attributed.string.contains("Write and review ELA items"), t.rawValue)
        }
        let letter = CoverLetterDrafter.draft(profile: profile, job: SampleData.job())
        let docx = DocxWriter.document(Composer.coverLetter(letter, profile: profile), style: .style(for: .classic), title: "Letter", author: "")
        writePreview(docx, "letter-classic.docx")
        let a = try NSAttributedString(data: docx, options: [.documentType: NSAttributedString.DocumentType.officeOpenXML], documentAttributes: nil)
        XCTAssertTrue(a.string.contains("Sincerely"))
        writePreview(Data(PlainTextRenderer.resume(profile).utf8), "resume.txt")
    }

    func testImportRoundTrips() throws {
        let profile = SampleData.profile
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("jobbot-import-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let pdfURL = dir.appendingPathComponent("resume.pdf")
        try PDFRenderer.resume(profile, template: .atsSimple).write(to: pdfURL)
        let docxURL = dir.appendingPathComponent("resume.docx")
        try DocxWriter.document(Composer.resume(profile), style: .style(for: .atsSimple), title: "", author: "").write(to: docxURL)
        let txtURL = dir.appendingPathComponent("resume.txt")
        try SampleData.resumeText.write(to: txtURL, atomically: true, encoding: .utf8)
        for url in [pdfURL, docxURL, txtURL] {
            let text = try ResumeImporter.text(from: url)
            let p = ResumeParser.parse(text).profile
            XCTAssertEqual(p.contact.name, "Jordan Rivera", url.lastPathComponent)
            XCTAssertEqual(p.contact.email, "jordan.rivera@example.com", url.lastPathComponent)
            XCTAssertEqual(p.sections.first { $0.kind == .experience }?.entries.count, 3, url.lastPathComponent)
        }
        let bad = dir.appendingPathComponent("resume.pages")
        try Data().write(to: bad)
        XCTAssertThrowsError(try ResumeImporter.text(from: bad))
    }
}

// MARK: - UI snapshots

@MainActor
final class UISnapshotTests: XCTestCase {
    var model: AppModel!
    var jobID: UUID!

    override func setUp() async throws {
        try await super.setUp()
        _ = NSApplication.shared
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("jobbot-ui-\(UUID().uuidString)")
        let m = AppModel(folder: folder)
        m.data.master = SampleData.profile
        var job = SampleData.job()
        job.postedDate = HTMLText.parseDate("2026-11-10")
        m.data.jobs = [job,
                       Job(title: "Item Writer, Grades 6–8", employer: "Northbeam Testing", location: "Atlanta, GA", source: "Greenhouse (Northbeam)"),
                       Job(title: "Curriculum Designer", employer: "Lumen Schools", location: "New York, NY", source: "Pasted description", status: .applied)]
        m.data.preferences.targetCompensation = 80000
        m.selectedJobID = job.id
        jobID = job.id
        _ = m.createTailoredResume(for: job.id)
        m.createCoverLetter(for: job.id)
        m.draftAnswers(job: job.id, questionsText: "Email address\nAre you authorized to work in the United States?\nDescribe your experience with bias and sensitivity reviews.\nDo you have experience with Articulate Storyline?")
        m.data.examplePatterns = [ExampleAnalyzer.analyze(SampleData.resumeText, label: "Career center sample")]
        m.data.activity = [ActivityRecord(service: "Job page at careers.example.com", purpose: "Read a job posting you added", dataSent: "The page address only", bytes: 0)]
        model = m
    }

    private func snapshot<V: View>(_ view: V, name: String, size: CGSize = CGSize(width: 1280, height: 820)) {
        let root = view
            .environmentObject(model)
            .frame(width: size.width, height: size.height)
        let host = NSHostingView(rootView: root)
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.contentView = host
        window.appearance = NSAppearance(named: .aqua)
        window.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(1.2))
        host.layoutSubtreeIfNeeded()
        host.display()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return XCTFail("no bitmap for \(name)") }
        host.cacheDisplay(in: host.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) {
            writePreview(png, "ui-\(name).png")
        }
        window.orderOut(nil)
    }

    func testRootScreens() {
        model.selection = .profile
        snapshot(RootView(), name: "01-master-resume")
        model.selection = .jobs
        snapshot(RootView(), name: "02-jobs-overview")
        model.selection = .tracker
        snapshot(RootView(), name: "03-applications")
        model.selection = .discover
        snapshot(RootView(), name: "04-find-jobs")
        model.selection = .pivots
        snapshot(RootView(), name: "05-pivots")
        model.selection = .settings
        snapshot(RootView(), name: "06-settings")
        model.selection = .examples
        snapshot(RootView(), name: "07-examples")
        model.selection = .credentials
        snapshot(RootView(), name: "08-credentials")
    }

    func testJobTabs() {
        snapshot(MatchView(jobID: jobID, openResume: {}), name: "10-compare", size: CGSize(width: 1000, height: 1100))
        snapshot(TailorView(jobID: jobID), name: "11-tailor", size: CGSize(width: 1100, height: 1000))
        snapshot(CoverLetterView(jobID: jobID), name: "12-cover-letter", size: CGSize(width: 1100, height: 900))
        snapshot(ApplicationView(jobID: jobID), name: "13-application", size: CGSize(width: 900, height: 1000))
    }

    func testSheets() {
        let preview = ImportPreview(profile: SampleData.profile, warnings: ResumeParser.parse(SampleData.resumeText).warnings, source: "resume.pdf")
        snapshot(ImportReviewSheet(preview: preview), name: "20-import-review", size: CGSize(width: 760, height: 760))
        let draft = JobDraft(job: SampleData.job(), duplicateOf: nil, warnings: [])
        snapshot(JobReviewSheet(draft: draft), name: "21-job-review", size: CGSize(width: 760, height: 700))
        let pending = PendingAI(request: AIPrompts.tailor(profile: SampleData.profile, job: SampleData.job()), model: "claude-sonnet-5-5") { _ in }
        snapshot(AIConsentSheet(pending: pending), name: "22-ai-consent", size: CGSize(width: 640, height: 420))
        model.snapshot(.master, label: "Imported from resume.pdf")
        model.data.master.summary += " Updated."
        snapshot(HistorySheet(owner: .master, title: "Master resume history"), name: "23-history", size: CGSize(width: 900, height: 600))
    }

    func testModelFlows() throws {
        // Accepting a suggestion changes only the tailored copy.
        let job = try XCTUnwrap(model.data.job(jobID))
        let resume = try XCTUnwrap(model.tailoredResume(for: job))
        let before = model.data.master
        let s = try XCTUnwrap(resume.suggestions.first { $0.kind == .alignTerm && $0.target.field == .bullet })
        model.accept(s, in: resume.id)
        XCTAssertEqual(model.data.master, before)
        let updated = try XCTUnwrap(model.data.resume(resume.id))
        XCTAssertTrue(PlainTextRenderer.resume(updated.content).contains("English Language Arts (ELA)"))
        XCTAssertEqual(updated.suggestions.first { $0.id == s.id }?.status, .accepted)
        // A version was saved before the change and can be restored.
        let versions = model.versions(for: .resume(resume.id))
        XCTAssertGreaterThanOrEqual(versions.count, 1)
        model.restore(versions.last!)
        XCTAssertEqual(model.data.resume(resume.id)?.content, before)
        // Answers: personal questions stay blank.
        let answers = model.data.job(jobID)?.answers ?? []
        XCTAssertEqual(answers.count, 4)
        XCTAssertTrue(answers[1].answer.isEmpty)
        // Status tracking
        model.updateJob(jobID) { $0.setStatus(.applied) }
        XCTAssertNotNil(model.data.job(jobID)?.appliedDate)
        // Saved to disk and reloaded.
        model.persistNow()
        let reloaded = DataStore(folder: model.store.folder).load()
        guard case .loaded(let d) = reloaded else { return XCTFail("not saved") }
        XCTAssertEqual(d.jobs.count, 3)
        XCTAssertEqual(d.job(jobID)?.status, .applied)
        XCTAssertNotNil(d.letter(d.job(jobID)?.coverLetterID))
    }
}
