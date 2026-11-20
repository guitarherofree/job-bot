import SwiftUI
import JobBotCore

struct JobsView: View {
    @EnvironmentObject var app: AppModel
    @State private var search = ""
    @State private var filterByLocation = false
    @State private var showInactive = true

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Search saved jobs", text: $search).textFieldStyle(.roundedBorder)
                    HStack {
                        Toggle("Filter by location", isOn: $filterByLocation).toggleStyle(.checkbox)
                        Spacer()
                        Toggle("Closed", isOn: $showInactive).toggleStyle(.checkbox).help("Show jobs marked not selected, withdrawn or archived")
                    }
                    .font(.callout)
                    if filterByLocation {
                        ActiveLocationChips()
                    }
                }
                .padding(10)
                Divider()
                if app.data.jobs.isEmpty {
                    EmptyState(symbol: "briefcase", title: "No saved jobs",
                               message: "Add a job by pasting its link or its description.",
                               actionTitle: "Add Job…") { app.showAddJob = true }
                } else {
                    List(selection: $app.selectedJobID) {
                        ForEach(filtered) { job in
                            JobRow(job: job, duplicate: app.duplicate(of: job) != nil).tag(job.id)
                        }
                    }
                    .listStyle(.inset)
                    if filtered.isEmpty {
                        Text("No jobs match the current filters.").font(.callout).foregroundStyle(.secondary).padding()
                    }
                }
            }
            .frame(minWidth: 280, idealWidth: 320, maxWidth: 420)

            Group {
                if let id = app.selectedJobID, app.data.job(id) != nil {
                    JobDetailView(jobID: id).id(id)
                } else {
                    EmptyState(symbol: "sidebar.left", title: "Select a job", message: "Pick a saved job to compare it with your experience and prepare your materials.")
                }
            }
            .frame(minWidth: 560, maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Jobs")
        .toolbar {
            ToolbarItem {
                Button { app.showAddJob = true } label: { Label("Add Job", systemImage: "plus") }
                    .help("Add a job by link or by pasting its description")
            }
        }
        .sheet(isPresented: $app.showAddJob) { AddJobSheet().environmentObject(app) }
    }

    private var filtered: [Job] {
        app.data.jobs.filter { job in
            if !showInactive && !job.status.isActive { return false }
            if filterByLocation && !app.data.preferences.locations.accepts(job) { return false }
            let q = search.trimmed.lowercased()
            if q.isEmpty { return true }
            return "\(job.title) \(job.employer) \(job.location) \(job.notes)".lowercased().contains(q)
        }
    }
}

struct ActiveLocationChips: View {
    @EnvironmentObject var app: AppModel

    var body: some View {
        FlowLayout {
            ForEach(app.data.preferences.locations.active) { loc in
                Pill(text: loc.name, color: Palette.accent, symbol: loc.isRemote ? "house" : "mappin")
            }
            if app.data.preferences.locations.includeUnlisted {
                Pill(text: "Location not listed", symbol: "questionmark")
            }
            if app.data.preferences.locations.active.isEmpty {
                Pill(text: "No locations selected", color: Palette.gap)
            }
        }
    }
}

struct JobRow: View {
    var job: Job
    var duplicate: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(job.displayTitle).font(.headline).lineLimit(2)
            Text(job.displayEmployer).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            HStack(spacing: 6) {
                Pill(text: job.status.title, color: job.status.color, symbol: job.status.symbol)
                if !job.location.isEmpty { Text(job.location).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
            HStack(spacing: 6) {
                if job.expired { Pill(text: "May be closed", color: Palette.gap, symbol: "clock.badge.xmark") }
                if duplicate { Pill(text: "Possible duplicate", color: Palette.partial, symbol: "square.on.square") }
            }
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Adding jobs

struct AddJobSheet: View {
    @EnvironmentObject var app: AppModel
    @Environment(\.dismiss) private var dismiss
    enum Mode: String, CaseIterable, Identifiable {
        case link = "From a link", paste = "Paste description"
        var id: String { rawValue }
    }
    @State private var mode: Mode = .link
    @State private var url = ""
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add a job").font(.title2.weight(.semibold))
            Picker("", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            switch mode {
            case .link:
                Text("Paste the link to the posting. Job Bot reads the page the way a browser would, without signing in. Sites that require sign-in or block automated access (LinkedIn, Indeed, Handshake and similar) need the description pasted instead.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                TextField("https://…", text: $url).textFieldStyle(.roundedBorder)
                Label("Only the page address is sent to that site. Nothing about you is.", systemImage: "lock")
                    .font(.caption).foregroundStyle(.secondary)
            case .paste:
                Text("Paste the whole job description, including headings like Responsibilities and Qualifications if it has them.")
                    .font(.callout).foregroundStyle(.secondary)
                TextEditor(text: $text)
                    .frame(minHeight: 280)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.15)))
                TextField("Link to the original posting (optional)", text: $url).textFieldStyle(.roundedBorder)
            }
            HStack {
                if let busy = app.busy {
                    ProgressView().controlSize(.small)
                    Text(busy).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(mode == .link ? "Read Page" : "Continue") {
                    if mode == .link {
                        Task {
                            await app.fetchJob(urlString: url)
                            if app.jobDraft != nil { dismiss() }
                        }
                    } else {
                        app.prepareJob(text: text, url: url)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(mode == .link ? url.trimmed.isEmpty || app.busy != nil : text.trimmed.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 640)
    }
}

/// Check what Job Bot read before saving.
struct JobReviewSheet: View {
    @EnvironmentObject var app: AppModel
    @State var draft: JobDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Review the job").font(.title2.weight(.semibold))
            if let dup = draft.duplicateOf {
                Label("This looks like “\(dup.displayTitle)” at \(dup.displayEmployer), saved \(dup.dateFound.shortDate).", systemImage: "square.on.square")
                    .foregroundStyle(Palette.partial)
            }
            ForEach(draft.warnings, id: \.self) { w in
                Label(w, systemImage: "exclamationmark.triangle").foregroundStyle(Palette.partial).font(.callout)
            }
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    Text("Title").foregroundStyle(.secondary)
                    TextField("Job title", text: $draft.job.title).textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Employer").foregroundStyle(.secondary)
                    TextField("Employer", text: $draft.job.employer).textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Location").foregroundStyle(.secondary)
                    TextField("Location (or Remote)", text: $draft.job.location).textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Link").foregroundStyle(.secondary)
                    TextField("Original link", text: $draft.job.url).textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Source").foregroundStyle(.secondary)
                    Text(draft.job.source)
                }
                if let posted = draft.job.postedDate {
                    GridRow {
                        Text("Posted").foregroundStyle(.secondary)
                        Text(posted.shortDate)
                    }
                }
                if let salary = draft.job.parsed.salary {
                    GridRow {
                        Text("Pay").foregroundStyle(.secondary)
                        Text("\(salary.display) (\(salary.source), read \(salary.date.shortDate))")
                    }
                }
            }
            ScrollView {
                ParsedJobView(parsed: draft.job.parsed)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 260)
            HStack {
                Spacer()
                Button("Cancel") { app.jobDraft = nil }.keyboardShortcut(.cancelAction)
                Button(draft.duplicateOf == nil ? "Save Job" : "Save Anyway") { app.saveDraft(draft) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 720, height: 680)
    }
}

/// Responsibilities, qualifications and keywords as parsed.
struct ParsedJobView: View {
    var parsed: ParsedJob

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            group("Responsibilities", parsed.responsibilities, symbol: "checklist")
            group("Required qualifications", parsed.requiredQualifications, symbol: "star.fill")
            group("Preferred qualifications", parsed.preferredQualifications, symbol: "star")
            if !parsed.keywords.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Keywords", systemImage: "tag").font(.headline)
                    FlowLayout {
                        ForEach(parsed.keywords, id: \.self) { Pill(text: $0, color: Palette.accent) }
                    }
                }
            }
            HStack(spacing: 8) {
                if parsed.remote { Pill(text: "Remote", color: Palette.accent, symbol: "house") }
                if let l = parsed.location, !l.isEmpty { Pill(text: l, symbol: "mappin") }
                if let t = parsed.employmentType { Pill(text: t, symbol: "clock") }
            }
        }
    }

    @ViewBuilder
    private func group(_ title: String, _ items: [String], symbol: String) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Label("\(title) (\(items.count))", systemImage: symbol).font(.headline)
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    Text("• " + item).font(.callout).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                }
            }
        }
    }
}
