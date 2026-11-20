import SwiftUI
import JobBotCore

struct SettingsView: View {
    @EnvironmentObject var app: AppModel
    @State private var apiKey = ""
    @State private var hasKey = Keychain.has(.anthropicKey)
    @State private var token = ""
    @State private var hasToken = Keychain.has(.githubToken)
    @State private var confirmDelete = false
    @State private var deleteKeys = true

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Your resume, jobs and documents are stored only on this Mac.", systemImage: "internaldrive")
                    Label("Job Bot never uses your information to train models, and never sends it anywhere unless you turn a service on below.", systemImage: "hand.raised")
                    Label("API keys and tokens are kept in your macOS Keychain, not in files.", systemImage: "key")
                }
                .font(.callout)
                LabeledContent("Library folder") {
                    HStack {
                        Text(app.store.folder.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([app.store.folder]) }
                    }
                }
            } header: { Text("Privacy") }

            Section {
                Toggle("Use AI drafting (optional)", isOn: $app.data.preferences.aiEnabled)
                Text("When on, Job Bot can send your profile (without your name or contact details) and a job description to \(AIClient.serviceName) to draft wording, cover letters and answers. Built-in suggestions work without it. Every AI draft is checked against your profile, and anything not supported by it is flagged.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Toggle("Ask me before every AI request", isOn: $app.data.preferences.confirmEachAIRequest)
                    .disabled(!app.data.preferences.aiEnabled)
                LabeledContent("Anthropic API key") {
                    HStack {
                        SecureField(hasKey ? "Saved in Keychain" : "sk-ant-…", text: $apiKey).frame(width: 260)
                        Button("Save") {
                            do {
                                try Keychain.set(apiKey, for: .anthropicKey)
                                apiKey = ""
                                hasKey = Keychain.has(.anthropicKey)
                                app.show("API key saved in your Keychain.", .success)
                            } catch { app.fail("Couldn't save the key", error) }
                        }
                        .disabled(apiKey.trimmed.isEmpty)
                        if hasKey {
                            Button("Remove") { Keychain.delete(.anthropicKey); hasKey = false }
                        }
                    }
                }
                LabeledContent("Model") {
                    HStack {
                        TextField("Model name", text: $app.data.preferences.aiModel).frame(width: 200)
                        Menu("Choose") {
                            ForEach(["claude-sonnet-5-5", "claude-opus-5-5", "claude-haiku-5-5"], id: \.self) { m in
                                Button(m) { app.data.preferences.aiModel = m }
                            }
                        }
                        .fixedSize()
                    }
                }
                Text("Anthropic says it doesn't use inputs or outputs from its API to train models by default.")
                    .font(.caption).foregroundStyle(.secondary)
                if let url = URL(string: "https://privacy.claude.com/en/articles/7996868") {
                    Link("Anthropic: is my data used for model training?", destination: url).font(.caption)
                }
            } header: { Text("AI") }

            Section {
                Toggle("Download job pages I add by link", isOn: $app.data.preferences.fetchJobPages)
                Text("Only the page address goes to that site. Sites that don't allow automated access (LinkedIn, Indeed, Handshake and similar) are never downloaded; paste their descriptions instead.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Toggle("Search public company job boards", isOn: $app.data.preferences.publicJobBoards)
                Text("Greenhouse, Lever, Ashby, SmartRecruiters and Workable job lists, and Workday careers sites: the listings companies publish for anyone to read. Only requests for job lists (and, for Workday sites, your search terms) are sent. Results appear in Jobs › Found.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("Job sources") }

            Section {
                Picker("Default template", selection: $app.data.preferences.defaultTemplate) {
                    ForEach(TemplateID.allCases) { Text($0.title).tag($0) }
                }
                Text("All templates are single column with real text, so they stay readable by applicant tracking systems and when copied as plain text. ATS Simple is the safest for online applications.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } header: { Text("Documents") }

            Section {
                UpdatesPanel()
                LabeledContent("Release repository") {
                    TextField("owner/name", text: $app.data.preferences.updateRepository).frame(width: 260)
                }
                LabeledContent("GitHub token (for a private repository)") {
                    HStack {
                        SecureField(hasToken ? "Saved in Keychain" : "github_pat_…", text: $token).frame(width: 260)
                        Button("Save") {
                            do {
                                try Keychain.set(token, for: .githubToken)
                                token = ""
                                hasToken = Keychain.has(.githubToken)
                                app.show("Token saved in your Keychain.", .success)
                            } catch { app.fail("Couldn't save the token", error) }
                        }
                        .disabled(token.trimmed.isEmpty)
                        if hasToken { Button("Remove") { Keychain.delete(.githubToken); hasToken = false } }
                    }
                }
                Text("Use a fine-grained token with read-only “Contents” access to the release repository only.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Check for updates automatically and download them in the background", isOn: $app.data.preferences.checkForUpdates)
            } header: { Text("Updates") }

            Section {
                if app.data.activity.isEmpty {
                    Text("Nothing has been sent from this Mac yet.").foregroundStyle(.secondary)
                } else {
                    ForEach(app.data.activity.prefix(40)) { r in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(r.service).font(.callout.weight(.medium))
                                Spacer()
                                Text(r.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                            }
                            Text(activityLine(r)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Button("Clear Activity Log") { app.data.activity.removeAll() }
                }
            } header: { Text("What left this Mac") }

            Section {
                HStack {
                    Button("Export All Data…") { app.exportAllData() }
                    Text("A folder with your library (JSON) and plain-text copies of every document.").font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Button("Delete All Data…", role: .destructive) { confirmDelete = true }
                    Text("Removes your profile, jobs, documents and history from this Mac.").font(.caption).foregroundStyle(.secondary)
                }
            } header: { Text("Your data") }
        }
        .formStyle(.grouped)
        .navigationTitle("Privacy & Settings")
        .confirmationDialog("Delete all Job Bot data on this Mac?", isPresented: $confirmDelete) {
            Button("Delete Everything", role: .destructive) { app.deleteAllData(includingKeys: deleteKeys) }
        } message: {
            Text("Your master resume, saved jobs, tailored resumes, cover letters, answers and version history will be permanently deleted. API keys and tokens are removed from the Keychain too. Export first if you want a copy. This can't be undone.")
        }
    }
}

func activityLine(_ r: ActivityRecord) -> String {
    var line = "\(r.purpose). Sent: \(r.dataSent)"
    if r.bytes > 0 { line += " (" + ByteCountFormatter.string(fromByteCount: Int64(r.bytes), countStyle: .file) + ")" }
    return line + "."
}

struct UpdatesPanel: View {
    @EnvironmentObject var app: AppModel

    var body: some View {
        UpdatesContent(updates: app.updates)
    }
}

struct UpdatesContent: View {
    @EnvironmentObject var app: AppModel
    @ObservedObject var updates: UpdateManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Job Bot \(UpdateManager.appVersion)").font(.headline)
                Spacer()
                Button("Check for Updates") {
                    Task { await updates.check(repository: app.data.preferences.updateRepository, automaticDownload: false) }
                }
                .disabled(updates.phase == .checking)
            }
            switch updates.phase {
            case .idle:
                Text(updates.lastChecked.map { "Last checked \($0.formatted(date: .abbreviated, time: .shortened))." } ?? "Not checked yet.")
                    .font(.caption).foregroundStyle(.secondary)
            case .checking:
                HStack { ProgressView().controlSize(.small); Text("Checking GitHub…").font(.callout) }
            case .upToDate(let v):
                Label("You're up to date (version \(v)).", systemImage: "checkmark.circle").foregroundStyle(Palette.strong)
            case .available(let r):
                ReleaseNotes(release: r)
                HStack {
                    Button("Download and Install") { updates.download(r) }.buttonStyle(.borderedProminent)
                    if let url = URL(string: r.htmlURL), !r.htmlURL.isEmpty { Link("View on GitHub", destination: url) }
                }
            case .downloading(let r, let fraction):
                Text("Downloading version \(r.version)…").font(.callout)
                ProgressView(value: fraction)
                Button("Cancel") { updates.cancelDownload() }
            case .ready(let r, _):
                ReleaseNotes(release: r)
                Label("Version \(r.version) is downloaded and ready.", systemImage: "checkmark.seal").foregroundStyle(Palette.strong)
                HStack {
                    Button("Restart to Install") { app.persistNow(); updates.restartToInstall() }.buttonStyle(.borderedProminent)
                    Text("Or it installs next time you quit Job Bot.").font(.caption).foregroundStyle(.secondary)
                }
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(Palette.gap).fixedSize(horizontal: false, vertical: true)
            }
            if !updates.canInstall {
                Text("This copy is running from a build folder, so updates can be checked but not installed.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct ReleaseNotes: View {
    var release: Releases.Release

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Version \(release.version) is available\(release.published.map { ", released \($0.shortDate)" } ?? "")")
                .font(.callout.weight(.semibold))
            ScrollView {
                Text(markdown(release.notes.isEmpty ? "No release notes." : release.notes))
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 160)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 6).fill(Palette.subtle))
        }
    }

    private func markdown(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(s)
    }
}
