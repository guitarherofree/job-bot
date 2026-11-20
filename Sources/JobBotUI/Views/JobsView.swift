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
                    Picker("", selection: $app.jobsMode) {
                        Text("Found (\(app.visibleListings().count))").tag(JobsMode.found)
                        Text("Saved (\(app.data.jobs.count))").tag(JobsMode.saved)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    TextField(app.jobsMode == .found ? "Search found listings" : "Search saved jobs", text: $search)
                        .textFieldStyle(.roundedBorder)
                    if app.jobsMode == .found {
                        FoundStatusLine()
                    } else {
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
                }
                .padding(10)
                Divider()
                if app.jobsMode == .found {
                    FoundList(search: search)
                } else if app.data.jobs.isEmpty {
                    EmptyState(symbol: "briefcase", title: "No saved jobs",
                               message: "Save a listing from Found, or add a job by pasting its link or its description.",
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
            .frame(minWidth: 300, idealWidth: 340, maxWidth: 440)

            Group {
                switch app.jobsMode {
                case .found:
                    if let id = app.selectedListingID, app.listing(id) != nil {
                        ListingDetailView(listingID: id).id(id)
                    } else {
                        EmptyState(symbol: "doc.text.magnifyingglass", title: "Select a listing",
                                   message: "Each listing is read into responsibilities, qualifications and pay, and compared with your master resume. Save the ones you want to work on.")
                    }
                case .saved:
                    if let id = app.selectedJobID, app.data.job(id) != nil {
                        JobDetailView(jobID: id).id(id)
                    } else {
                        EmptyState(symbol: "sidebar.left", title: "Select a job", message: "Pick a saved job to compare it with your experience and prepare your materials.")
                    }
                }
            }
            .frame(minWidth: 560, maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Jobs")
        .toolbar {
            ToolbarItem {
                Button { Task { await app.runDiscovery() } } label: { Label("Check for New Listings", systemImage: "arrow.clockwise") }
                    .disabled(app.listingStatus != nil)
                    .help("Search your connected company job boards now")
            }
            ToolbarItem {
                Button { app.showAddJob = true } label: { Label("Add Job", systemImage: "plus") }
                    .help("Add a job by link or by pasting its description")
            }
        }
        .sheet(isPresented: $app.showAddJob) { AddJobSheet().environmentObject(app) }
        .task { await app.searchBoardsIfDue() }
        .onChange(of: app.selectedListingID) { _, id in
            if let id { app.markViewed(id) }
        }
        .onChange(of: app.jobsMode) { _, _ in search = "" }
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

// MARK: - Found listings

/// When the boards were last checked, and what's being searched for.
struct FoundStatusLine: View {
    @EnvironmentObject var app: AppModel

    var body: some View {
        let boards = app.data.discovery.companies.filter { $0.enabled && $0.board != .none }.count
        let terms = app.data.discovery.searchTerms + app.data.pivots.titles
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                if let status = app.listingStatus {
                    ProgressView().controlSize(.mini)
                    Text(status).lineLimit(1)
                } else if let last = app.data.found.lastSearch {
                    Image(systemName: "clock")
                    Text("\(boards) company boards checked \(last.formatted(.relative(presentation: .named)))").lineLimit(1)
                } else {
                    Image(systemName: "clock")
                    Text("\(boards) company boards connected, not checked yet").lineLimit(1)
                }
                Spacer(minLength: 4)
                Button("Edit Search") { app.selection = .discover }
                    .buttonStyle(.link)
                    .help("Change search terms, locations and companies in Find Jobs")
            }
            Text("Titles matching: " + (terms.isEmpty ? "any" : terms.joined(separator: ", ")) + " · " + app.data.preferences.locations.summary)
                .lineLimit(2)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

struct FoundList: View {
    @EnvironmentObject var app: AppModel
    var search: String

    var body: some View {
        let listings = app.visibleListings(search: search)
        if !listings.isEmpty {
            List(selection: $app.selectedListingID) {
                ForEach(listings) { listing in
                    FoundRow(listing: listing, fit: app.fit(for: listing)).tag(listing.id)
                }
            }
            .listStyle(.inset)
        } else if !search.trimmed.isEmpty {
            Text("No listings match “\(search.trimmed)”.").font(.callout).foregroundStyle(.secondary).padding()
            Spacer()
        } else {
            emptyState
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        let boards = app.data.discovery.companies.filter { $0.enabled && $0.board != .none }.count
        if !app.data.preferences.publicJobBoards {
            EmptyState(symbol: "lock.shield", title: "Job board searches are off",
                       message: "Turn on public job board feeds in Privacy & Settings to see listings here.",
                       actionTitle: "Open Privacy & Settings") { app.selection = .settings }
        } else if boards == 0 {
            EmptyState(symbol: "antenna.radiowaves.left.and.right", title: "No company job boards connected",
                       message: "Connect boards in Find Jobs (“Find Board” next to a company) and their listings will appear here.",
                       actionTitle: "Open Find Jobs") { app.selection = .discover }
        } else if app.listingStatus != nil {
            EmptyState(symbol: "hourglass", title: "Checking company job boards", message: "Listings appear here as soon as the search finishes.")
        } else if app.data.found.lastSearch == nil {
            EmptyState(symbol: "magnifyingglass", title: "Not checked yet",
                       message: "Job Bot reads public job lists from \(boards) company boards. Nothing about you is sent.",
                       actionTitle: "Check Now") { Task { await app.runDiscovery() } }
        } else {
            EmptyState(symbol: "tray", title: "No open roles match right now",
                       message: "Job Bot checked \(boards) company boards for titles matching your search terms in your chosen locations. Add search terms or locations to widen the search, or check back later.",
                       actionTitle: "Edit Search") { app.selection = .discover }
        }
    }
}

struct FoundRow: View {
    var listing: FoundListing
    var fit: Fit

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if !listing.viewed {
                    Circle().fill(Palette.accent).frame(width: 7, height: 7).help("New")
                }
                Text(listing.job.displayTitle).font(.headline).lineLimit(2)
            }
            Text(listing.job.displayEmployer).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            HStack(spacing: 6) {
                FitPill(fit: fit)
                if !listing.job.location.isEmpty {
                    Text(listing.job.location).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            if let posted = listing.job.postedDate {
                Text("Posted \(posted.shortDate)").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 3)
    }
}

struct FitPill: View {
    var fit: Fit

    var body: some View {
        switch fit.level {
        case .strong: Pill(text: fit.summary, color: Palette.strong, symbol: "checkmark.circle")
        case .partial: Pill(text: fit.summary, color: Palette.partial, symbol: "circle.lefthalf.filled")
        case .low: Pill(text: fit.summary, color: Palette.gap, symbol: "circle")
        case .unknown: Pill(text: fit.summary, symbol: "questionmark.circle")
        }
    }
}

/// A found listing, read and compared, before it's saved.
struct ListingDetailView: View {
    @EnvironmentObject var app: AppModel
    let listingID: String
    @State private var showDescription = false

    var body: some View {
        if let listing = app.listing(listingID) {
            let job = listing.job
            let report = app.report(for: job)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(job.displayTitle).font(.title2.weight(.semibold)).textSelection(.enabled)
                            Text([job.displayEmployer, job.location].filter { !$0.isEmpty }.joined(separator: " · "))
                                .foregroundStyle(.secondary)
                            HStack(spacing: 6) {
                                Pill(text: job.source, symbol: "antenna.radiowaves.left.and.right")
                                if let posted = job.postedDate { Pill(text: "Posted \(posted.shortDate)", symbol: "calendar") }
                                Pill(text: "Found \(listing.firstSeen.shortDate)", symbol: "calendar.badge.plus")
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 8) {
                            Button { app.saveListing(listingID) } label: {
                                Label("Save to My Jobs", systemImage: "tray.and.arrow.down")
                            }
                            .buttonStyle(.borderedProminent)
                            .help("Move it to Saved, where you can compare it in detail, tailor your resume and write a cover letter")
                            HStack(spacing: 12) {
                                if let url = URL(string: job.url), !job.url.isEmpty {
                                    Link(destination: url) { Label("Open Posting", systemImage: "safari") }
                                }
                                Button("Not Interested") { app.dismissListing(listingID) }
                                    .help("Hide this listing; it won't come back in later searches")
                            }
                            .font(.callout)
                        }
                    }
                    FitCard(report: report)
                    PayCard(job: job)
                    Card {
                        Text("What the posting asks for").font(.headline)
                        if job.parsed.isEmpty {
                            Text("Job Bot couldn't separate this posting into responsibilities and qualifications. The full description is below, and the comparison uses all of it.")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        ParsedJobView(parsed: job.parsed)
                    }
                    DisclosureGroup("Full description", isExpanded: $showDescription) {
                        Text(job.descriptionText.isEmpty ? "The board didn't include a description. Open the posting to read it." : job.descriptionText)
                            .font(.callout)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4)
                    }
                    Text("Found on \(listing.company)'s public job board. Only a request for the job list was sent; nothing about you.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(20)
            }
        }
    }
}

/// A short version of the comparison: how much of the required list the master resume speaks to.
struct FitCard: View {
    var report: MatchReport

    var body: some View {
        let fit = report.fit
        let gaps = report.gaps.filter { $0.kind == .required }
        Card {
            HStack(alignment: .firstTextBaseline) {
                Text("Compared with your master resume").font(.headline)
                Spacer()
                FitPill(fit: fit)
            }
            if fit.requiredTotal > 0 {
                Text("\(fit.requiredCovered) of \(fit.requiredTotal) required qualifications have evidence in your master resume. This shows what your resume speaks to; it doesn't predict how an employer will decide.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                Text("The posting doesn't list required qualifications separately, so this compares its keywords.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if !gaps.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("No evidence found yet for").font(.subheadline.weight(.medium))
                    ForEach(gaps.prefix(4)) { g in
                        Text("• " + g.text).font(.callout).fixedSize(horizontal: false, vertical: true)
                    }
                    if gaps.count > 4 { Text("and \(gaps.count - 4) more").font(.caption).foregroundStyle(.secondary) }
                }
            }
            if !report.matchedKeywords.isEmpty {
                FlowLayout {
                    ForEach(report.matchedKeywords.prefix(10), id: \.self) { Pill(text: $0, color: Palette.strong, symbol: "checkmark") }
                    ForEach(report.missingKeywords.prefix(6), id: \.self) { Pill(text: $0, color: Palette.gap) }
                }
            }
            Text("Save it to see every requirement with its evidence, answer follow-up questions, and tailor your resume.")
                .font(.caption).foregroundStyle(.secondary)
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
