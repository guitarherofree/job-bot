import SwiftUI
import JobBotCore

struct JobDetailView: View {
    @EnvironmentObject var app: AppModel
    let jobID: UUID
    enum Tab: String, CaseIterable, Identifiable {
        case overview = "Overview", match = "Compare", resume = "Resume", letter = "Cover Letter", application = "Application"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .overview: return "doc.text"
            case .match: return "arrow.left.arrow.right"
            case .resume: return "person.text.rectangle"
            case .letter: return "envelope"
            case .application: return "checklist"
            }
        }
    }
    @State private var tab: Tab = .overview

    var body: some View {
        if let job = app.data.job(jobID) {
            VStack(spacing: 0) {
                JobHeader(job: job)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 10)
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases) { t in Label(t.rawValue, systemImage: t.symbol).tag(t) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
                Divider()
                switch tab {
                case .overview: JobOverview(jobID: jobID)
                case .match: MatchView(jobID: jobID, openResume: { tab = .resume })
                case .resume: TailorView(jobID: jobID)
                case .letter: CoverLetterView(jobID: jobID)
                case .application: ApplicationView(jobID: jobID)
                }
            }
        }
    }
}

struct JobHeader: View {
    @EnvironmentObject var app: AppModel
    var job: Job

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(job.displayTitle).font(.title2.weight(.semibold)).textSelection(.enabled)
                HStack(spacing: 6) {
                    Text(job.displayEmployer)
                    if !job.location.isEmpty { Text("· \(job.location)") }
                }
                .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Pill(text: job.source.isEmpty ? "Added by you" : job.source, symbol: "tray.and.arrow.down")
                    if let posted = job.postedDate { Pill(text: "Posted \(posted.shortDate)", symbol: "calendar") }
                    Pill(text: "Found \(job.dateFound.shortDate)", symbol: "calendar.badge.plus")
                    if job.expired { Pill(text: "May be closed", color: Palette.gap, symbol: "clock.badge.xmark") }
                    if let dup = app.duplicate(of: job) { Pill(text: "Possible duplicate of \(dup.displayTitle)", color: Palette.partial, symbol: "square.on.square") }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Picker("Status", selection: Binding(get: { job.status }, set: { s in app.updateJob(job.id) { $0.setStatus(s) } })) {
                    ForEach(ApplicationStatus.allCases) { s in Label(s.title, systemImage: s.symbol).tag(s) }
                }
                .frame(width: 200)
                if let url = URL(string: job.url), !job.url.isEmpty {
                    Link(destination: url) { Label("Open Original Posting", systemImage: "safari") }.font(.callout)
                }
            }
        }
    }
}

struct JobOverview: View {
    @EnvironmentObject var app: AppModel
    let jobID: UUID
    @State private var showDescription = false
    @State private var confirmDelete = false

    var body: some View {
        if let job = app.data.job(jobID) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if job.expired {
                        Card {
                            Label("This posting may be closed", systemImage: "clock.badge.xmark").font(.headline).foregroundStyle(Palette.gap)
                            Text(job.expiredReason).font(.callout)
                            HStack {
                                Button("Check Again") { Task { await app.recheck(jobID) } }
                                Button("It's Still Open") { app.updateJob(jobID) { $0.expired = false; $0.expiredReason = "" } }
                            }
                        }
                    }
                    PayCard(job: job)
                    Card {
                        HStack {
                            Text("What the posting asks for").font(.headline)
                            Spacer()
                            Button("Read Again") { app.reparse(jobID) }
                                .help("Re-read the description (after you edit it below)")
                        }
                        if job.parsed.isEmpty {
                            Text("Job Bot couldn't separate the description into responsibilities and qualifications. You can still compare it: the whole text is used. Editing the description to add headings (Responsibilities, Qualifications) helps.")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        ParsedJobView(parsed: job.parsed)
                    }
                    Card {
                        Text("Your notes").font(.headline)
                        TextField("Contacts, deadlines, anything to remember", text: Binding(get: { app.data.job(jobID)?.notes ?? "" },
                                                                                            set: { v in app.updateJob(jobID) { $0.notes = v } }),
                                  axis: .vertical)
                            .lineLimit(2...8)
                            .fieldBox()
                    }
                    StatusHistory(job: job)
                    DisclosureGroup("Original description", isExpanded: $showDescription) {
                        TextField("Description", text: Binding(get: { app.data.job(jobID)?.descriptionText ?? "" },
                                                               set: { v in app.updateJob(jobID) { $0.descriptionText = v } }),
                                  axis: .vertical)
                            .lineLimit(8...40)
                            .fieldBox()
                            .font(.callout)
                    }
                    HStack {
                        if !job.url.isEmpty {
                            Button("Check If Still Open") { Task { await app.recheck(jobID) } }
                        }
                        Spacer()
                        Button("Delete Job…", role: .destructive) { confirmDelete = true }
                    }
                }
                .padding(20)
            }
            .confirmationDialog("Delete this job?", isPresented: $confirmDelete) {
                Button("Delete Job and Its Documents", role: .destructive) { app.deleteJob(jobID) }
            } message: {
                Text("The tailored resume and cover letter for this job are deleted too. Your master resume isn't affected.")
            }
        }
    }
}

struct PayCard: View {
    @EnvironmentObject var app: AppModel
    var job: Job

    var body: some View {
        if let salary = job.parsed.salary {
            Card {
                HStack {
                    Label("Pay", systemImage: "dollarsign.circle").font(.headline)
                    Spacer()
                    Text("Source: \(salary.source), read \(salary.date.shortDate)").font(.caption).foregroundStyle(.secondary)
                }
                Text(salary.display).font(.title3)
                if let cmp = PayComparison.compare(salary, current: app.data.preferences.currentCompensation, target: app.data.preferences.targetCompensation) {
                    HStack(spacing: 14) {
                        Text("Midpoint ≈ \(currency(cmp.yearlyMidpoint))/year").font(.callout)
                        if let c = cmp.versusCurrent { change("vs. current", c) }
                        if let t = cmp.versusTarget { change("vs. target", t) }
                    }
                    if salary.period == .hour {
                        Text("Hourly pay was converted to a yearly estimate at 2,080 hours (full time).").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if app.data.preferences.currentCompensation == nil && app.data.preferences.targetCompensation == nil {
                    Text("Add your current or target pay in Pivot Paths to compare.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func change(_ label: String, _ v: Double) -> some View {
        let pct = Int((v * 100).rounded())
        return Text("\(pct >= 0 ? "+" : "")\(pct)% \(label)")
            .font(.callout.weight(.medium))
            .foregroundStyle(pct >= 0 ? Palette.strong : Palette.gap)
    }
}

func currency(_ v: Double) -> String {
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.currencyCode = "USD"
    f.maximumFractionDigits = 0
    return f.string(from: NSNumber(value: v)) ?? "$\(Int(v))"
}

struct StatusHistory: View {
    var job: Job

    var body: some View {
        Card {
            Text("Status history").font(.headline)
            ForEach(Array(job.statusHistory.enumerated().reversed()), id: \.offset) { _, change in
                HStack {
                    Image(systemName: change.status.symbol).foregroundStyle(change.status.color)
                    Text(change.status.title)
                    Spacer()
                    Text(change.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
