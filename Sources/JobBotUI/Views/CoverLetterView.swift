import SwiftUI
import JobBotCore
import JobBotRender

struct CoverLetterView: View {
    @EnvironmentObject var app: AppModel
    let jobID: UUID
    @State private var showHistory = false
    @State private var confirmRedraft = false

    var body: some View {
        if let job = app.data.job(jobID) {
            if let letter = app.coverLetter(for: job) {
                HSplitView {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            if !letter.reviewNotes.isEmpty {
                                Card {
                                    Label("Review before using", systemImage: "eye").font(.headline)
                                    ForEach(letter.reviewNotes, id: \.self) { n in
                                        Text("• " + n).font(.callout).fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                            Card {
                                Text("Recipient (optional)").font(.caption).foregroundStyle(.secondary)
                                TextField("Company, address", text: field(\.recipient), axis: .vertical)
                                    .lineLimit(1...4)
                                    .fieldBox()
                                Text("Greeting").font(.caption).foregroundStyle(.secondary)
                                TextField("Dear Hiring Team,", text: field(\.greeting)).textFieldStyle(.roundedBorder)
                                Text("Letter (separate paragraphs with a blank line)").font(.caption).foregroundStyle(.secondary)
                                TextEditor(text: field(\.body))
                                    .font(.body)
                                    .frame(minHeight: 320)
                                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.15)))
                                if WritingRules.containsEmDash(letter.body) {
                                    HStack {
                                        Label("The letter contains em dashes.", systemImage: "exclamationmark.triangle")
                                            .font(.caption).foregroundStyle(Palette.partial)
                                        Button("Replace Them") {
                                            app.updateLetter(letter.id) { $0.body = WritingRules.clean($0.body) }
                                        }
                                        .controlSize(.small)
                                    }
                                }
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text("Closing").font(.caption).foregroundStyle(.secondary)
                                        TextField("Sincerely,", text: field(\.closing)).textFieldStyle(.roundedBorder)
                                    }
                                    VStack(alignment: .leading) {
                                        Text("Signature").font(.caption).foregroundStyle(.secondary)
                                        TextField("Your name", text: field(\.signature)).textFieldStyle(.roundedBorder)
                                    }
                                }
                            }
                        }
                        .padding(16)
                    }
                    .frame(minWidth: 440)
                    LetterPreviewPane(letter: letter, profile: app.data.master,
                                      template: Binding(get: { app.data.letter(letter.id)?.template ?? .atsSimple },
                                                        set: { t in app.updateLetter(letter.id) { $0.template = t } }))
                        .frame(minWidth: 340, idealWidth: 420)
                }
                .toolbar {
                    ToolbarItemGroup {
                        Menu {
                            Button("Redraft from Profile…") { confirmRedraft = true }
                            Button("Draft with AI…") { Task { await app.aiLetter(letter.id) } }
                                .disabled(!app.data.preferences.aiEnabled)
                            Divider()
                            Button("Version History…") { showHistory = true }
                            Button("Save Version") { app.snapshot(.coverLetter(letter.id), label: "Saved \(Date().formatted(date: .abbreviated, time: .shortened))"); app.show("Version saved.", .success) }
                        } label: {
                            Label("Letter", systemImage: "envelope.badge")
                        }
                        Menu {
                            ForEach(ExportFormat.allCases) { f in
                                Button("Export as \(f.title)…") { app.export(letter: app.data.letter(letter.id) ?? letter, format: f) }
                            }
                            Divider()
                            Button("Copy as Plain Text") { app.copyPlainText((app.data.letter(letter.id) ?? letter).plainText) }
                        } label: {
                            Label("Export Letter", systemImage: "square.and.arrow.up")
                        }
                    }
                }
                .sheet(isPresented: $showHistory) { HistorySheet(owner: .coverLetter(letter.id), title: "History: \(letter.name)").environmentObject(app) }
                .confirmationDialog("Redraft the letter from your profile?", isPresented: $confirmRedraft) {
                    Button("Redraft") { app.redraftLetter(letter.id) }
                } message: {
                    Text("The current letter is saved in History first.")
                }
            } else {
                EmptyState(symbol: "envelope", title: "Draft a cover letter",
                           message: "Job Bot drafts a letter from your profile and this posting, using only your own experience. Anything it can't support is left out and listed for you to review.",
                           actionTitle: app.data.master.isEmpty ? nil : "Draft Cover Letter") {
                    app.createCoverLetter(for: jobID)
                }
            }
        }
    }

    private func field(_ key: WritableKeyPath<CoverLetter, String>) -> Binding<String> {
        Binding(get: {
            guard let job = app.data.job(jobID), let l = app.coverLetter(for: job) else { return "" }
            return l[keyPath: key]
        }, set: { v in
            guard let job = app.data.job(jobID), let id = job.coverLetterID else { return }
            app.updateLetter(id) { $0[keyPath: key] = v }
        })
    }
}

struct LetterPreviewPane: View {
    var letter: CoverLetter
    var profile: Profile
    @Binding var template: TemplateID
    @State private var pdf = Data()

    var body: some View {
        VStack(spacing: 0) {
            Picker("Template", selection: $template) {
                ForEach(TemplateID.allCases) { t in Text(t.title).tag(t) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(10)
            Divider()
            if pdf.isEmpty { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) } else { PDFPreview(data: pdf) }
        }
        .task(id: LetterKey(letter: letter, profile: profile)) {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            pdf = PDFRenderer.coverLetter(letter, profile: profile)
        }
    }
}

struct LetterKey: Hashable {
    var letter: CoverLetter
    var profile: Profile
}
