import Foundation
import AppKit
import Combine
import UniformTypeIdentifiers
import JobBotCore
import JobBotRender

enum JobsMode: String, CaseIterable, Identifiable {
    case found, saved
    var id: String { rawValue }
}

enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case profile, jobs, tracker, discover, pivots, credentials, examples, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .profile: return "Master Resume"
        case .jobs: return "Jobs"
        case .tracker: return "Applications"
        case .discover: return "Find Jobs"
        case .pivots: return "Pivot Paths"
        case .credentials: return "Credentials"
        case .examples: return "Examples"
        case .settings: return "Privacy & Settings"
        }
    }

    var symbol: String {
        switch self {
        case .profile: return "person.text.rectangle"
        case .jobs: return "briefcase"
        case .tracker: return "list.bullet.rectangle"
        case .discover: return "magnifyingglass"
        case .pivots: return "arrow.triangle.branch"
        case .credentials: return "rosette"
        case .examples: return "doc.text.magnifyingglass"
        case .settings: return "lock.shield"
        }
    }
}

struct Banner: Equatable, Identifiable {
    enum Kind { case info, success, warning }
    let id = UUID()
    var text: String
    var kind: Kind
}

struct AlertInfo: Identifiable {
    let id = UUID()
    var title: String
    var message: String
}

/// A request waiting for the person's OK before data leaves the Mac.
final class PendingAI: Identifiable {
    let id = UUID()
    let request: AIPrompts.Request
    let model: String
    private var resumeHandler: ((Bool) -> Void)?

    init(request: AIPrompts.Request, model: String, resume: @escaping (Bool) -> Void) {
        self.request = request
        self.model = model
        self.resumeHandler = resume
    }

    func finish(_ approved: Bool) {
        resumeHandler?(approved)
        resumeHandler = nil
    }
}

struct ImportPreview: Identifiable {
    let id = UUID()
    var profile: Profile
    var warnings: [String]
    var source: String
}

struct JobDraft: Identifiable {
    let id = UUID()
    var job: Job
    var duplicateOf: Job?
    var warnings: [String]
}

enum ExportFormat: String, CaseIterable, Identifiable {
    case pdf, docx, txt
    var id: String { rawValue }
    var title: String {
        switch self {
        case .pdf: return "PDF"
        case .docx: return "Word (.docx)"
        case .txt: return "Plain text"
        }
    }
    var type: UTType {
        switch self {
        case .pdf: return .pdf
        case .docx: return UTType(filenameExtension: "docx") ?? .data
        case .txt: return .plainText
        }
    }
}

@MainActor
public final class AppModel: ObservableObject {
    @Published public var data: AppData
    @Published var selection: SidebarItem? = .profile
    @Published var selectedJobID: UUID?
    @Published var banner: Banner?
    @Published var alert: AlertInfo?
    @Published var pendingAI: PendingAI?
    @Published var busy: String?
    @Published var importPreview: ImportPreview?
    @Published var jobDraft: JobDraft?
    /// Jobs › Found or Jobs › Saved.
    @Published var jobsMode: JobsMode = .found
    @Published var selectedListingID: String?
    /// Progress of a job-board search ("Checking Amplify (3 of 13)…").
    @Published var listingStatus: String?
    @Published var aiQuestions: [UUID: [FollowUpQuestion]] = [:]
    @Published var showAddJob = false
    @Published var requestImport = false

    /// Off in tests, so screenshots never reach the network.
    var allowAutomaticBoardSearch = true
    private var fitCache: (profile: Profile, fits: [String: Fit]) = (Profile(), [:])

    let store: DataStore
    let updates = UpdateManager()
    private var cancellables: Set<AnyCancellable> = []
    private var canSave = true

    public init(folder: URL? = nil) {
        let dataStore = DataStore(folder: folder ?? DataStore.defaultFolder)
        var loaded = AppData()
        var saveAllowed = true
        var startupMessage: String?
        switch dataStore.load() {
        case .fresh(let d):
            loaded = d
        case .loaded(let d):
            loaded = d
        case .recovered(let d, let message):
            loaded = d
            startupMessage = message
        case .failed(let message):
            // Keep the unreadable file aside so nothing is overwritten.
            let aside = dataStore.folder.appendingPathComponent("library.unreadable-\(Int(Date().timeIntervalSince1970)).json")
            if (try? FileManager.default.moveItem(at: dataStore.file, to: aside)) == nil { saveAllowed = false }
            startupMessage = message + (saveAllowed ? " It was set aside as \(aside.lastPathComponent), and Job Bot started fresh." : " Job Bot won't save changes until this is resolved.")
        }
        let linksAdded = loaded.discovery.addDefaultCareerLinks()
        let boardsConnected = loaded.discovery.connectDetectedBoards()
        store = dataStore
        data = loaded
        canSave = saveAllowed
        if let startupMessage { alert = AlertInfo(title: "Library problem", message: startupMessage) }
        updates.record = { [weak self] r in self?.log(r) }
        $data
            .dropFirst()
            .debounce(for: .seconds(0.8), scheduler: RunLoop.main)
            .sink { [weak self] d in self?.persist(d) }
            .store(in: &cancellables)
        if linksAdded > 0 || boardsConnected > 0 { persist(data) }
        jobsMode = data.found.items.isEmpty && !data.jobs.isEmpty ? .saved : .found
    }

    /// Call once when the window appears.
    public func start() {
        if let report = updates.launchReport() { show(report, .success) }
        if data.preferences.checkForUpdates && updates.canInstall {
            Task { await updates.check(repository: data.preferences.updateRepository, automaticDownload: true) }
        }
        Task { await searchBoardsIfDue() }
    }

    public func shutdown() {
        persist(data)
        updates.installOnQuitIfReady()
    }

    func persistNow() { persist(data) }

    private func persist(_ d: AppData) {
        guard canSave else { return }
        do {
            try store.save(d)
        } catch {
            alert = AlertInfo(title: "Couldn't save", message: "Your changes couldn't be saved: \(error.localizedDescription)")
        }
    }

    func show(_ text: String, _ kind: Banner.Kind = .info) {
        let b = Banner(text: text, kind: kind)
        banner = b
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            if self?.banner?.id == b.id { self?.banner = nil }
        }
    }

    func fail(_ title: String, _ error: Error) {
        alert = AlertInfo(title: title, message: error.localizedDescription)
    }

    func log(_ record: ActivityRecord) {
        data.activity.insert(record, at: 0)
        if data.activity.count > 500 { data.activity.removeLast(data.activity.count - 500) }
    }

    // MARK: - Versions

    func snapshot(_ owner: VersionSnapshot.Owner, label: String) {
        var snap = VersionSnapshot(owner: owner, label: label)
        switch owner {
        case .master: snap.profile = data.master
        case .resume(let id): snap.profile = data.resume(id)?.content
        case .coverLetter(let id): snap.letter = data.letter(id)
        }
        // Skip if nothing changed since the last snapshot of this document.
        if let last = data.versions.first(where: { $0.owner == owner }), last.profile == snap.profile, last.letter == snap.letter {
            return
        }
        data.versions.insert(snap, at: 0)
        let mine = data.versions.enumerated().filter { $0.element.owner == owner }
        if mine.count > 60 {
            let drop = Set(mine.dropFirst(60).map { $0.element.id })
            data.versions.removeAll { drop.contains($0.id) }
        }
    }

    func versions(for owner: VersionSnapshot.Owner) -> [VersionSnapshot] {
        data.versions.filter { $0.owner == owner }
    }

    func restore(_ snap: VersionSnapshot) {
        snapshot(snap.owner, label: "Before restoring \(snap.label)")
        switch snap.owner {
        case .master:
            if let p = snap.profile { data.master = p }
        case .resume(let id):
            if let p = snap.profile, let i = data.resumes.firstIndex(where: { $0.id == id }) {
                data.resumes[i].content = p
                data.resumes[i].updated = Date()
            }
        case .coverLetter(let id):
            if let l = snap.letter, let i = data.letters.firstIndex(where: { $0.id == id }) {
                var restored = l
                restored.updated = Date()
                data.letters[i] = restored
            }
        }
        show("Restored “\(snap.label)”.", .success)
    }

    // MARK: - Master resume

    func importResume(from url: URL) {
        do {
            let text = try ResumeImporter.text(from: url)
            let result = ResumeParser.parse(text)
            importPreview = ImportPreview(profile: result.profile, warnings: result.warnings, source: url.lastPathComponent)
        } catch {
            fail("Couldn't import the resume", error)
        }
    }

    func importResume(text: String) {
        guard !text.trimmed.isEmpty else { return }
        let result = ResumeParser.parse(text)
        importPreview = ImportPreview(profile: result.profile, warnings: result.warnings, source: "pasted text")
    }

    func acceptImport(_ preview: ImportPreview) {
        if !data.master.isEmpty { snapshot(.master, label: "Before importing \(preview.source)") }
        var p = preview.profile
        p.notes = data.master.notes
        data.master = p
        snapshot(.master, label: "Imported from \(preview.source)")
        importPreview = nil
        show("Imported your resume. Review each section; nothing was added that wasn't in the file.", .success)
    }

    // MARK: - Jobs

    var selectedJob: Job? { data.job(selectedJobID) }

    func binding(forJob id: UUID) -> Job? { data.job(id) }

    func updateJob(_ id: UUID, _ change: (inout Job) -> Void) {
        guard let i = data.jobs.firstIndex(where: { $0.id == id }) else { return }
        change(&data.jobs[i])
        data.jobs[i].updated = Date()
    }

    func prepareJob(text: String, url: String) {
        let job = JobParser.job(fromText: text, url: url.trimmed)
        presentDraft(job, warnings: job.parsed.isEmpty ? ["Job Bot couldn't find separate responsibilities and qualifications. Check the description, or paste it with its headings."] : [])
    }

    func fetchJob(urlString: String) async {
        let s = urlString.trimmed
        guard let url = URL(string: s.hasPrefix("http") ? s : "https://" + s), url.host != nil else {
            alert = AlertInfo(title: "Not a web address", message: "Enter the full address of the job posting, starting with https://.")
            return
        }
        if !data.preferences.fetchJobPages {
            alert = AlertInfo(title: "Page downloads are off", message: "Downloading job pages is turned off in Privacy & Settings. Paste the description instead, or turn it back on.")
            return
        }
        busy = "Reading \(url.host ?? "the page")…"
        defer { busy = nil }
        do {
            let html = try await WebFetcher.jobPage(url)
            log(ActivityRecord(service: "Job page at \(url.host ?? "web")", purpose: "Read a job posting you added", dataSent: "The page address only", bytes: 0))
            let job = JobParser.job(fromHTML: html, url: url.absoluteString)
            let text = HTMLText.text(fromHTML: html)
            if HTMLText.jobPostings(fromHTML: html).isEmpty, let issue = HTMLText.issue(html: html, text: text) {
                switch issue {
                case .signInRequired, .botCheck:
                    throw WebFetcher.FetchError.blocked(url.host ?? "The site")
                case .tooLittleText:
                    throw WebFetcher.FetchError.unreadable
                }
            }
            var warnings: [String] = []
            if job.parsed.isEmpty { warnings.append("Job Bot couldn't separate responsibilities from qualifications on this page. Check the description below.") }
            if job.title.isEmpty { warnings.append("The job title wasn't found. Add it before saving.") }
            presentDraft(job, warnings: warnings)
        } catch {
            alert = AlertInfo(title: "Couldn't read the page", message: error.localizedDescription)
        }
    }

    private func presentDraft(_ job: Job, warnings: [String]) {
        var w = warnings
        if job.expired { w.append("This posting may be closed: \(job.expiredReason)") }
        jobDraft = JobDraft(job: job, duplicateOf: Duplicates.match(for: job, in: data.jobs), warnings: w)
    }

    func saveDraft(_ draft: JobDraft) {
        var job = draft.job
        if job.parsed.isEmpty || job.parsed.keywords.isEmpty {
            let reparsed = JobParser.parse(job.descriptionText, source: job.source, date: job.dateFound)
            if job.parsed.isEmpty { job.parsed = reparsed }
            if job.parsed.keywords.isEmpty { job.parsed.keywords = reparsed.keywords }
        }
        data.jobs.insert(job, at: 0)
        jobDraft = nil
        selection = .jobs
        selectedJobID = job.id
        show("Saved “\(job.displayTitle)”.", .success)
    }

    func reparse(_ id: UUID) {
        updateJob(id) { job in
            let salary = job.parsed.salary
            job.parsed = JobParser.parse(job.descriptionText, source: job.source, date: job.dateFound)
            if job.parsed.salary == nil { job.parsed.salary = salary }
        }
    }

    func deleteJob(_ id: UUID) {
        guard let job = data.job(id) else { return }
        data.jobs.removeAll { $0.id == id }
        data.resumes.removeAll { $0.jobID == id }
        data.letters.removeAll { $0.jobID == id }
        if selectedJobID == id { selectedJobID = nil }
        show("Deleted “\(job.displayTitle)” and its documents.")
    }

    /// Looks at the posting again to see whether it has closed.
    func recheck(_ id: UUID) async {
        guard let job = data.job(id), let url = URL(string: job.url), !job.url.isEmpty else {
            show("This job has no link to check.", .warning)
            return
        }
        busy = "Checking the posting…"
        defer { busy = nil }
        do {
            let html = try await WebFetcher.jobPage(url)
            log(ActivityRecord(service: "Job page at \(url.host ?? "web")", purpose: "Check whether a saved posting is still open", dataSent: "The page address only", bytes: 0))
            let fresh = JobParser.job(fromHTML: html, url: job.url)
            if fresh.expired || HTMLText.closedCue(in: HTMLText.text(fromHTML: html)) != nil {
                updateJob(id) { $0.expired = true; $0.expiredReason = fresh.expiredReason.isEmpty ? "The page says the posting is closed." : fresh.expiredReason }
                show("The posting appears to be closed.", .warning)
            } else {
                updateJob(id) { $0.expired = false; $0.expiredReason = "" }
                show("The posting still appears to be open.", .success)
            }
        } catch WebFetcher.FetchError.notFound {
            updateJob(id) { $0.expired = true; $0.expiredReason = "The page is no longer available (checked \(Date().formatted(date: .abbreviated, time: .omitted)))." }
            show("The posting's page is gone, so it's marked as expired.", .warning)
        } catch {
            alert = AlertInfo(title: "Couldn't check the posting", message: error.localizedDescription)
        }
    }

    func duplicate(of job: Job) -> Job? { Duplicates.match(for: job, in: data.jobs) }

    // MARK: - Matching

    func report(for job: Job) -> MatchReport { Matcher.compare(profile: data.master, job: job) }

    func answerFollowUp(job id: UUID, question: FollowUpQuestion, answer: String, addToProfile: Bool) {
        let text = answer.trimmed
        updateJob(id) { $0.followUps[question.id] = text }
        if addToProfile && !text.isEmpty {
            data.master.notes.append(ProfileNote(topic: question.requirement, text: text))
            show("Added to your profile notes. It now counts as evidence (it isn't printed on your resume).", .success)
        }
    }

    // MARK: - Tailored resumes

    func tailoredResume(for job: Job) -> TailoredResume? { data.resume(job.tailoredResumeID) }

    @discardableResult
    func createTailoredResume(for jobID: UUID) -> UUID? {
        guard let job = data.job(jobID) else { return nil }
        var resume = TailoredResume(jobID: jobID, name: "Resume for \(job.displayTitle), \(job.displayEmployer)",
                                    content: data.master, template: data.preferences.defaultTemplate)
        resume.suggestions = Tailor.suggestions(for: resume.content, job: job, report: report(for: job))
        data.resumes.append(resume)
        updateJob(jobID) { j in
            j.tailoredResumeID = resume.id
            if j.status == .saved { j.setStatus(.preparing) }
        }
        snapshot(.resume(resume.id), label: "Copied from master resume")
        return resume.id
    }

    func updateResume(_ id: UUID, _ change: (inout TailoredResume) -> Void) {
        guard let i = data.resumes.firstIndex(where: { $0.id == id }) else { return }
        change(&data.resumes[i])
        data.resumes[i].updated = Date()
    }

    func refreshSuggestions(_ resumeID: UUID) {
        guard let r = data.resume(resumeID), let job = data.job(r.jobID) else { return }
        let fresh = Tailor.suggestions(for: r.content, job: job, report: report(for: job))
        updateResume(resumeID) { res in
            let decided = res.suggestions.filter { $0.status != .pending }
            let ai = res.suggestions.filter { $0.status == .pending && $0.origin != "Job Bot" }
            res.suggestions = decided + ai + fresh
        }
        show(fresh.isEmpty ? "No new suggestions: this version already follows the built-in rules." : "Suggestions refreshed.")
    }

    func accept(_ suggestion: Suggestion, in resumeID: UUID, editedText: String? = nil) {
        guard let r = data.resume(resumeID) else { return }
        var s = suggestion
        if let editedText { s.after = editedText }
        var content = r.content
        do {
            try Tailor.apply(s, to: &content)
        } catch {
            fail("Couldn't apply the suggestion", error)
            return
        }
        snapshot(.resume(resumeID), label: "Before: \(s.title)")
        updateResume(resumeID) { res in
            res.content = content
            if let i = res.suggestions.firstIndex(where: { $0.id == s.id }) {
                res.suggestions[i] = s
                res.suggestions[i].status = .accepted
            }
        }
    }

    func reject(_ suggestion: Suggestion, in resumeID: UUID) {
        updateResume(resumeID) { res in
            if let i = res.suggestions.firstIndex(where: { $0.id == suggestion.id }) { res.suggestions[i].status = .rejected }
        }
    }

    func resetFromMaster(_ resumeID: UUID) {
        snapshot(.resume(resumeID), label: "Before resetting from master")
        let master = data.master
        updateResume(resumeID) { res in
            res.content = master
            res.suggestions = []
        }
        refreshSuggestions(resumeID)
    }

    func aiSuggestions(_ resumeID: UUID) async {
        guard let r = data.resume(resumeID), let job = data.job(r.jobID) else { return }
        let request = AIPrompts.tailor(profile: r.content, job: job)
        guard let reply = await runAI(request) else { return }
        let result = AIPrompts.readTailor(reply, profile: r.content, job: job, service: AIClient.serviceName)
        updateResume(resumeID) { $0.suggestions.append(contentsOf: result.suggestions) }
        if !result.questions.isEmpty { aiQuestions[job.id] = result.questions }
        var message = "\(result.suggestions.count) AI suggestion\(result.suggestions.count == 1 ? "" : "s") added for review."
        if !result.rejected.isEmpty { message += " \(result.rejected.count) didn't pass Job Bot's checks and were dropped." }
        show(message, result.suggestions.isEmpty ? .warning : .success)
    }

    // MARK: - Cover letters

    func coverLetter(for job: Job) -> CoverLetter? { data.letter(job.coverLetterID) }

    func createCoverLetter(for jobID: UUID) {
        guard let job = data.job(jobID) else { return }
        var letter = CoverLetterDrafter.draft(profile: data.master, job: job, report: report(for: job))
        letter.template = tailoredResume(for: job)?.template ?? data.preferences.defaultTemplate
        data.letters.append(letter)
        updateJob(jobID) { $0.coverLetterID = letter.id }
        snapshot(.coverLetter(letter.id), label: "First draft")
    }

    func updateLetter(_ id: UUID, _ change: (inout CoverLetter) -> Void) {
        guard let i = data.letters.firstIndex(where: { $0.id == id }) else { return }
        change(&data.letters[i])
        data.letters[i].updated = Date()
    }

    func redraftLetter(_ id: UUID) {
        guard let letter = data.letter(id), let job = data.job(letter.jobID) else { return }
        snapshot(.coverLetter(id), label: "Before redrafting")
        let fresh = CoverLetterDrafter.draft(profile: data.master, job: job, report: report(for: job))
        updateLetter(id) { l in
            l.body = fresh.body
            l.greeting = fresh.greeting
            l.reviewNotes = fresh.reviewNotes
        }
    }

    func aiLetter(_ id: UUID) async {
        guard let letter = data.letter(id), let job = data.job(letter.jobID) else { return }
        guard let reply = await runAI(AIPrompts.coverLetter(profile: data.master, job: job)) else { return }
        guard let updated = AIPrompts.readCoverLetter(reply, into: letter, profile: data.master, job: job, service: AIClient.serviceName) else {
            alert = AlertInfo(title: "Nothing changed", message: "The AI reply wasn't in the expected format.")
            return
        }
        snapshot(.coverLetter(id), label: "Before AI draft")
        updateLetter(id) { $0 = updated }
        show("AI draft ready. Review every sentence; flagged items are listed beside the letter.", .success)
    }

    // MARK: - Application answers

    func draftAnswers(job id: UUID, questionsText: String) {
        guard let job = data.job(id) else { return }
        let questions = AnswerDrafter.questions(from: questionsText)
        guard !questions.isEmpty else { return }
        let answers = AnswerDrafter.draft(questions: questions, profile: data.master, job: job, report: report(for: job), preferences: data.preferences)
        updateJob(id) { $0.answers.append(contentsOf: answers) }
    }

    func aiAnswers(job id: UUID) async {
        guard let job = data.job(id) else { return }
        let open = job.answers.filter { $0.state == .unknown }
        guard !open.isEmpty else {
            show("There are no blank answers for AI to draft. Personal questions always stay blank.")
            return
        }
        let questions = open.map { $0.question }
        guard let reply = await runAI(AIPrompts.answers(questions: questions, profile: data.master, job: job)) else { return }
        guard let drafted = AIPrompts.readAnswers(reply, questions: questions, profile: data.master, job: job, service: AIClient.serviceName) else {
            alert = AlertInfo(title: "Nothing changed", message: "The AI reply wasn't in the expected format.")
            return
        }
        updateJob(id) { j in
            for (q, a) in zip(open, drafted) where a.state == .needsConfirmation {
                if let i = j.answers.firstIndex(where: { $0.id == q.id }) {
                    j.answers[i].answer = a.answer
                    j.answers[i].state = .needsConfirmation
                    j.answers[i].note = a.note
                    j.answers[i].evidence = a.evidence
                }
            }
        }
    }

    // MARK: - AI

    /// Sends a request to the AI service after the person approves (when that's turned on).
    func runAI(_ request: AIPrompts.Request) async -> String? {
        guard data.preferences.aiEnabled else {
            alert = AlertInfo(title: "AI drafting is off", message: "Job Bot's built-in suggestions work without AI. To use AI drafting, turn it on in Privacy & Settings › AI and add an API key.")
            return nil
        }
        guard let key = Keychain.get(.anthropicKey) else {
            alert = AlertInfo(title: "No API key", message: AIClient.AIError.noKey.localizedDescription)
            return nil
        }
        let model = data.preferences.aiModel
        if data.preferences.confirmEachAIRequest {
            let approved = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                pendingAI = PendingAI(request: request, model: model) { cont.resume(returning: $0) }
            }
            pendingAI = nil
            guard approved else { return nil }
        }
        busy = "Waiting for \(AIClient.serviceName)…"
        defer { busy = nil }
        log(ActivityRecord(service: AIClient.serviceName, purpose: request.task.purpose, dataSent: request.dataSummary,
                           bytes: request.system.utf8.count + request.user.utf8.count))
        do {
            return try await AIClient(apiKey: key, model: model).send(system: request.system, user: request.user)
        } catch {
            fail("AI request failed", error)
            return nil
        }
    }

    // MARK: - Export

    func pdfData(resume profile: Profile, template: TemplateID) -> Data { PDFRenderer.resume(profile, template: template) }

    func export(resume profile: Profile, template: TemplateID, name: String, format: ExportFormat) {
        let blocks = Composer.resume(profile)
        let data: Data
        switch format {
        case .pdf: data = PDFRenderer.resume(profile, template: template)
        case .docx: data = DocxWriter.document(blocks, style: .style(for: template), title: "\(profile.contact.name) Resume", author: profile.contact.name)
        case .txt: data = Data(PlainTextRenderer.render(blocks).utf8)
        }
        save(data, suggestedName: fileName(name, profile: profile, kind: "Resume"), format: format)
    }

    func export(letter: CoverLetter, format: ExportFormat) {
        let profile = data.master
        let blocks = Composer.coverLetter(letter, profile: profile)
        let out: Data
        switch format {
        case .pdf: out = PDFRenderer.coverLetter(letter, profile: profile)
        case .docx: out = DocxWriter.document(blocks, style: .style(for: letter.template), title: "\(profile.contact.name) Cover Letter", author: profile.contact.name)
        case .txt: out = Data(PlainTextRenderer.render(blocks).utf8)
        }
        let employer = data.job(letter.jobID)?.employer ?? ""
        save(out, suggestedName: fileName(employer, profile: profile, kind: "Cover Letter"), format: format)
    }

    func fileName(_ context: String, profile: Profile, kind: String) -> String {
        let name = profile.contact.name.trimmed.isEmpty ? "" : profile.contact.name.trimmed + " "
        let extra = context.trimmed.isEmpty ? "" : " - " + context.trimmed
        let raw = "\(name)\(kind)\(extra)"
        return raw.components(separatedBy: CharacterSet(charactersIn: "/:\\?%*|\"<>")).joined(separator: "-")
    }

    private func save(_ data: Data, suggestedName: String, format: ExportFormat) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.type]
        panel.nameFieldStringValue = suggestedName + "." + format.rawValue
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url, options: .atomic)
            show("Saved \(url.lastPathComponent).", .success)
        } catch {
            fail("Couldn't save the file", error)
        }
    }

    func copyPlainText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        show("Copied as plain text.", .success)
    }

    // MARK: - Discovery

    /// Searches every connected company job board and puts matching postings, fully read, in
    /// Jobs › Found. Only requests for public job lists (and, for Workday sites, the search terms)
    /// are sent; nothing about the person.
    func runDiscovery(automatic: Bool = false) async {
        guard listingStatus == nil else { return }
        guard data.preferences.publicJobBoards else {
            if !automatic {
                alert = AlertInfo(title: "Job board searches are off", message: "Turn on public job board feeds in Privacy & Settings to search company boards from Job Bot.")
            }
            return
        }
        let companies = data.discovery.companies.filter { $0.enabled && $0.board != .none && !$0.boardToken.trimmed.isEmpty }
        guard !companies.isEmpty else {
            data.found.notes = ["No company has a job board connected yet. Use “Find Board” next to a company in Find Jobs, or paste a board link as its careers page."]
            return
        }
        listingStatus = "Checking \(companies.count) job board\(companies.count == 1 ? "" : "s")…"
        defer { listingStatus = nil }
        let terms = data.discovery.searchTerms + data.pivots.titles
        let outcome = await BoardSearch.run(companies: companies, terms: terms, locations: data.preferences.locations,
                                            progress: { text in await MainActor.run { self.listingStatus = text } },
                                            fetch: { request in try await WebFetcher.board(request) })
        for c in companies where outcome.searched.contains(c.name) {
            let sent = c.board == .workday ? "Your search terms only" : "A request for the public job list only"
            log(ActivityRecord(service: "\(c.board.title) (\(c.name))", purpose: "List open jobs", dataSent: sent, bytes: 0))
        }
        var found = data.found
        let added = found.merge(outcome.jobs, searched: outcome.searched, notes: outcome.notes)
        data.found = found
        let failed = companies.count - outcome.searched.count
        let problem = failed > 0 ? " \(failed) board\(failed == 1 ? "" : "s") couldn't be read; see Find Jobs for details." : ""
        if added > 0 {
            show("Found \(added) new listing\(added == 1 ? "" : "s") in Jobs.\(problem)", .success)
        } else if !automatic {
            show("No new listings since the last search.\(problem)", failed > 0 ? .warning : .info)
        }
    }

    /// Searches the boards when the last search is more than six hours old.
    func searchBoardsIfDue() async {
        guard allowAutomaticBoardSearch, data.preferences.publicJobBoards, listingStatus == nil else { return }
        if let last = data.found.lastSearch, Date().timeIntervalSince(last) < 6 * 3600 { return }
        await runDiscovery(automatic: true)
    }

    /// How much of a listing the master resume covers (cached until the resume or listing changes).
    func fit(for listing: FoundListing) -> Fit {
        if fitCache.profile != data.master { fitCache = (data.master, [:]) }
        let key = "\(listing.id)|\(listing.lastSeen.timeIntervalSince1970)"
        if let f = fitCache.fits[key] { return f }
        let f = Matcher.compare(profile: data.master, job: listing.job).fit
        fitCache.fits[key] = f
        return f
    }

    /// Found listings in the chosen locations that aren't saved yet, best covered first.
    func visibleListings(search: String = "") -> [FoundListing] {
        let q = search.trimmed.lowercased()
        let locations = data.preferences.locations
        let listings = data.found.items.filter { l in
            let place = l.job.parsed.remote ? l.job.location + " Remote" : l.job.location
            guard locations.accepts(locationText: place) else { return false }
            guard Duplicates.match(for: l.job, in: data.jobs) == nil else { return false }
            if q.isEmpty { return true }
            return "\(l.job.title) \(l.job.employer) \(l.job.location)".lowercased().contains(q)
        }
        let scored = listings.map { ($0, fit(for: $0).score) }
        return scored.sorted { a, b in
            if abs(a.1 - b.1) > 0.001 { return a.1 > b.1 }
            return (a.0.job.postedDate ?? a.0.firstSeen) > (b.0.job.postedDate ?? b.0.firstSeen)
        }.map { $0.0 }
    }

    func listing(_ id: String?) -> FoundListing? {
        guard let id else { return nil }
        return data.found.items.first { $0.id == id }
    }

    /// Moves a found listing into the person's saved jobs and opens it.
    func saveListing(_ id: String) {
        guard let listing = listing(id) else { return }
        if let dup = Duplicates.match(for: listing.job, in: data.jobs) {
            _ = data.found.take(id)
            jobsMode = .saved
            selectedJobID = dup.id
            show("Already saved as “\(dup.displayTitle)”.", .info)
            return
        }
        _ = data.found.take(id)
        var job = listing.job
        job.status = .saved
        job.updated = Date()
        data.jobs.insert(job, at: 0)
        selectedListingID = nil
        jobsMode = .saved
        selectedJobID = job.id
        show("Saved “\(job.displayTitle)”. Compare it with your experience, tailor your resume and write a cover letter from here.", .success)
    }

    /// Hides a listing for good, and selects the next one.
    func dismissListing(_ id: String) {
        let visible = visibleListings()
        let next: String? = visible.firstIndex { $0.id == id }.flatMap { i in
            i + 1 < visible.count ? visible[i + 1].id : (i > 0 ? visible[i - 1].id : nil)
        }
        data.found.dismiss(id)
        if selectedListingID == id { selectedListingID = next }
    }

    func markViewed(_ id: String) {
        guard let i = data.found.items.firstIndex(where: { $0.id == id }), !data.found.items[i].viewed else { return }
        data.found.items[i].viewed = true
    }

    func findBoard(for companyID: UUID) async {
        guard let c = data.discovery.companies.first(where: { $0.id == companyID }) else { return }
        guard data.preferences.publicJobBoards else {
            alert = AlertInfo(title: "Job board searches are off", message: "Turn on public job board feeds in Privacy & Settings first.")
            return
        }
        if let detected = Boards.detect(fromURL: c.careersURL) {
            setBoard(companyID, detected.0, detected.1)
            show("Connected \(c.name)'s \(detected.0.title).", .success)
            return
        }
        busy = "Looking for \(c.name)'s job board…"
        defer { busy = nil }
        for kind in [BoardKind.greenhouse, .lever, .ashby] {
            for token in c.tokenGuesses {
                guard let raw = try? await WebFetcher.board(kind, token: token),
                      let jobs = try? Boards.parse(raw, kind: kind, company: c.name) else { continue }
                log(ActivityRecord(service: kind.title, purpose: "Look for \(c.name)'s public job board", dataSent: "A request for a public job list only", bytes: 0))
                // A board with a name that matches and at least one job (or a valid empty board).
                if !jobs.isEmpty || kind == .greenhouse {
                    setBoard(companyID, kind, token)
                    show("Found \(c.name)'s \(kind.title) (“\(token)”). Check it lists the right company.", .success)
                    return
                }
            }
        }
        show("No public job board was found for \(c.name). Add its careers page, and open it in your browser to look for roles.", .warning)
    }

    private func setBoard(_ id: UUID, _ kind: BoardKind, _ token: String) {
        if let i = data.discovery.companies.firstIndex(where: { $0.id == id }) {
            data.discovery.companies[i].board = kind
            data.discovery.companies[i].boardToken = token
        }
    }

    func openSearch(_ site: SearchSite, term: String) {
        let location = data.preferences.locations.active.first { !$0.isRemote }?.name ?? (data.preferences.locations.active.first?.name ?? "")
        guard let url = site.url(keywords: term, location: location) else { return }
        NSWorkspace.shared.open(url)
    }

    func openCareers(_ c: CompanySource) {
        if let url = URL(string: c.careersURL.trimmed), url.scheme != nil {
            NSWorkspace.shared.open(url)
        } else {
            let q = "\(c.name) careers jobs".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? c.name
            if let url = URL(string: "https://duckduckgo.com/?q=\(q)") { NSWorkspace.shared.open(url) }
        }
    }

    // MARK: - Data controls

    func exportAllData() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Export Here"
        panel.message = "Choose a folder for your Job Bot export."
        guard panel.runModal() == .OK, let base = panel.url else { return }
        let stamp = Date().formatted(.iso8601.year().month().day())
        let folder = base.appendingPathComponent("Job Bot Export \(stamp)", isDirectory: true)
        do {
            let fm = FileManager.default
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            try DataStore.encoder.encode(data).write(to: folder.appendingPathComponent("job-bot-library.json"))
            try PlainTextRenderer.resume(data.master).write(to: folder.appendingPathComponent("Master Resume.txt"), atomically: true, encoding: .utf8)
            let docs = folder.appendingPathComponent("Documents", isDirectory: true)
            try fm.createDirectory(at: docs, withIntermediateDirectories: true)
            for r in data.resumes {
                let name = fileName(r.name, profile: Profile(), kind: "").trimmingCharacters(in: CharacterSet(charactersIn: " -"))
                try PlainTextRenderer.resume(r.content).write(to: docs.appendingPathComponent("\(name).txt"), atomically: true, encoding: .utf8)
            }
            for l in data.letters {
                let name = fileName(l.name, profile: Profile(), kind: "").trimmingCharacters(in: CharacterSet(charactersIn: " -"))
                try PlainTextRenderer.coverLetter(l, profile: data.master).write(to: docs.appendingPathComponent("\(name).txt"), atomically: true, encoding: .utf8)
            }
            NSWorkspace.shared.activateFileViewerSelecting([folder])
            show("Exported everything to “\(folder.lastPathComponent)”.", .success)
        } catch {
            fail("Export failed", error)
        }
    }

    func deleteAllData(includingKeys: Bool) {
        do {
            try store.deleteAll()
        } catch {
            fail("Couldn't delete everything", error)
            return
        }
        if includingKeys {
            Keychain.delete(.anthropicKey)
            Keychain.delete(.githubToken)
        }
        canSave = false
        data = AppData()
        canSave = true
        persistAfterReset()
        selectedJobID = nil
        selection = .profile
        selectedListingID = nil
        show("All Job Bot data on this Mac was deleted.", .success)
    }

    private func persistAfterReset() {
        // Don't write the empty library back immediately; the next real change creates it.
        cancellables.removeAll()
        $data
            .dropFirst()
            .debounce(for: .seconds(0.8), scheduler: RunLoop.main)
            .sink { [weak self] d in self?.persist(d) }
            .store(in: &cancellables)
    }
}
