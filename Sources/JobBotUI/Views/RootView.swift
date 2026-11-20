import SwiftUI
import JobBotCore

public struct RootView: View {
    @EnvironmentObject var app: AppModel

    public init() {}

    public var body: some View {
        NavigationSplitView {
            List(selection: $app.selection) {
                Section {
                    row(.profile)
                    row(.jobs)
                    row(.tracker)
                }
                Section("Explore") {
                    row(.discover)
                    row(.pivots)
                    row(.credentials)
                    row(.examples)
                }
                Section {
                    row(.settings)
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        } detail: {
            detail
        }
        .overlay(alignment: .bottom) {
            if let banner = app.banner {
                BannerView(banner: banner)
                    .padding(.bottom, 18)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onTapGesture { app.banner = nil }
            }
        }
        .overlay(alignment: .topTrailing) {
            if let busy = app.busy {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(busy).font(.callout)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: Capsule())
                .padding(12)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: app.banner)
        .sheet(item: $app.importPreview) { preview in
            ImportReviewSheet(preview: preview).environmentObject(app)
        }
        .sheet(item: $app.jobDraft) { draft in
            JobReviewSheet(draft: draft).environmentObject(app)
        }
        .sheet(item: $app.pendingAI) { pending in
            AIConsentSheet(pending: pending)
        }
        .alert(app.alert?.title ?? "", isPresented: Binding(get: { app.alert != nil }, set: { if !$0 { app.alert = nil } }),
               presenting: app.alert) { _ in
            Button("OK") { app.alert = nil }
        } message: { a in
            Text(a.message)
        }
    }

    private func row(_ item: SidebarItem) -> some View {
        Label(item.title, systemImage: item.symbol)
            .badge(badge(item))
            .tag(item)
    }

    private func badge(_ item: SidebarItem) -> Int {
        switch item {
        case .jobs: return app.data.jobs.filter { $0.status.isActive }.count
        case .discover: return app.discovered.count
        default: return 0
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch app.selection ?? .profile {
        case .profile: ProfileView()
        case .jobs: JobsView()
        case .tracker: TrackerView()
        case .discover: DiscoverView()
        case .pivots: PivotView()
        case .credentials: CredentialsView()
        case .examples: ExamplesView()
        case .settings: SettingsView()
        }
    }
}

/// Shown before anything is sent to the AI service.
struct AIConsentSheet: View {
    let pending: PendingAI
    @State private var showText = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Send to \(AIClient.serviceName)?", systemImage: "paperplane").font(.title2.weight(.semibold))
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    Text("Purpose").foregroundStyle(.secondary)
                    Text(pending.request.task.purpose)
                }
                GridRow {
                    Text("Goes to").foregroundStyle(.secondary)
                    Text("\(AIClient.host), model \(pending.model)")
                }
                GridRow {
                    Text("Includes").foregroundStyle(.secondary)
                    Text(pending.request.dataSummary).fixedSize(horizontal: false, vertical: true)
                }
                GridRow {
                    Text("Size").foregroundStyle(.secondary)
                    Text(ByteCountFormatter.string(fromByteCount: Int64(pending.request.user.utf8.count + pending.request.system.utf8.count), countStyle: .file))
                }
            }
            .font(.callout)
            Text("Not included: your name, email, phone, links or location. Job Bot doesn't use your information to train models; the reply is checked against your profile before you see it.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            DisclosureGroup("Show exactly what will be sent", isExpanded: $showText) {
                ScrollView {
                    Text(pending.request.system + "\n\n" + pending.request.user)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(height: 260)
                .background(RoundedRectangle(cornerRadius: 6).fill(Palette.subtle))
            }
            HStack {
                Text("You can turn off this confirmation in Privacy & Settings.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { pending.finish(false) }.keyboardShortcut(.cancelAction)
                Button("Send") { pending.finish(true) }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 620)
        .onDisappear { pending.finish(false) }
    }
}

/// Menu commands.
public struct JobBotCommands: Commands {
    let app: AppModel

    public init(app: AppModel) {
        self.app = app
    }

    public var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") {
                app.selection = .settings
                Task { await app.updates.check(repository: app.data.preferences.updateRepository, automaticDownload: false) }
            }
        }
        CommandGroup(replacing: .newItem) {
            Button("Add Job…") {
                app.selection = .jobs
                app.showAddJob = true
            }
            .keyboardShortcut("n")
            Button("Import Resume…") {
                app.selection = .profile
                app.requestImport = true
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])
        }
        CommandMenu("Go") {
            ForEach(SidebarItem.allCases) { item in
                Button(item.title) { app.selection = item }
            }
        }
    }
}
