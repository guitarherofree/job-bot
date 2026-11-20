import SwiftUI
import UniformTypeIdentifiers
import JobBotCore
import JobBotRender

struct ProfileView: View {
    @EnvironmentObject var app: AppModel
    @State private var showPaste = false
    @State private var showHistory = false
    @State private var showPreview = true
    @State private var previewTemplate: TemplateID = .atsSimple
    @State private var startFresh = false

    var body: some View {
        Group {
            if app.data.master.isEmpty && !startFresh {
                EmptyState(symbol: "doc.badge.plus", title: "Start with your resume",
                           message: "Import a PDF, Word or text file, or paste your resume's text. Job Bot turns it into an editable master resume that stays unchanged when you tailor versions for jobs.",
                           actionTitle: "Import Resume…", action: importFile)
                    .overlay(alignment: .bottom) {
                        HStack(spacing: 16) {
                            Button("Paste Resume Text…") { showPaste = true }
                            Button("Start from Scratch") { startFresh = true }
                        }
                        .buttonStyle(.link)
                        .padding(.bottom, 80)
                    }
            } else {
                HSplitView {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            SectionTitle(title: "Master resume",
                                         subtitle: "Your complete, unchanged record. Tailored versions for each job are copies; editing them never changes this.")
                            ResumeEditor(profile: $app.data.master, showNotes: true)
                        }
                        .padding(20)
                        .frame(maxWidth: 820, alignment: .leading)
                    }
                    .frame(minWidth: 460)
                    if showPreview {
                        ResumePreviewPane(profile: app.data.master, template: $previewTemplate)
                            .frame(minWidth: 360, idealWidth: 460)
                    }
                }
            }
        }
        .navigationTitle("Master Resume")
        .toolbar {
            ToolbarItemGroup {
                Button { importFile() } label: { Label("Import", systemImage: "square.and.arrow.down") }
                    .help("Import a resume file (PDF, Word, or text)")
                Button { showPaste = true } label: { Label("Paste Text", systemImage: "doc.on.clipboard") }
                    .help("Paste resume text")
                Button { showHistory = true } label: { Label("History", systemImage: "clock.arrow.circlepath") }
                    .help("Saved versions: compare or restore")
                Button { app.snapshot(.master, label: "Saved \(Date().formatted(date: .abbreviated, time: .shortened))"); app.show("Version saved.", .success) } label: {
                    Label("Save Version", systemImage: "bookmark")
                }
                .help("Save a version you can return to")
                ExportMenu(profile: app.data.master, template: previewTemplate, name: "Master")
                Toggle(isOn: $showPreview) { Label("Preview", systemImage: "sidebar.right") }
                    .help("Show or hide the preview")
            }
        }
        .sheet(isPresented: $showPaste) {
            PasteTextSheet(title: "Paste your resume", prompt: "Paste the full text of your resume. Job Bot will sort it into sections for you to review.") { text in
                app.importResume(text: text)
            }
        }
        .sheet(isPresented: $showHistory) {
            HistorySheet(owner: .master, title: "Master resume history").environmentObject(app)
        }
        .onAppear { previewTemplate = app.data.preferences.defaultTemplate }
        .onChange(of: app.requestImport) { _, requested in
            if requested {
                app.requestImport = false
                importFile()
            }
        }
    }

    private func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ResumeImporter.supportedExtensions.compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = false
        panel.message = "Choose your resume (PDF, Word .docx, or plain text)."
        if panel.runModal() == .OK, let url = panel.url {
            app.importResume(from: url)
        }
    }
}

/// Live PDF preview with a template picker.
struct ResumePreviewPane: View {
    var profile: Profile
    @Binding var template: TemplateID
    @State private var pdf = Data()
    @State private var pages = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Template", selection: $template) {
                    ForEach(TemplateID.allCases) { t in Text(t.title).tag(t) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Spacer()
                Text(pages == 1 ? "1 page" : "\(pages) pages").font(.caption).foregroundStyle(.secondary)
            }
            .padding(10)
            Text(template.blurb).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 10).padding(.bottom, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
            Divider()
            if pdf.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                PDFPreview(data: pdf)
            }
        }
        .task(id: PreviewKey(profile: profile, template: template)) {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            let data = PDFRenderer.resume(profile, template: template)
            pdf = data
            pages = PDFText.pageCount(of: data)
        }
    }
}

struct PreviewKey: Hashable {
    var profile: Profile
    var template: TemplateID
}

struct ExportMenu: View {
    @EnvironmentObject var app: AppModel
    var profile: Profile
    var template: TemplateID
    var name: String

    var body: some View {
        Menu {
            ForEach(ExportFormat.allCases) { f in
                Button("Export as \(f.title)…") { app.export(resume: profile, template: template, name: name, format: f) }
            }
            Divider()
            Button("Copy as Plain Text") { app.copyPlainText(PlainTextRenderer.resume(profile)) }
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
        }
        .help("Export as PDF, Word or plain text")
    }
}

struct PasteTextSheet: View {
    var title: String
    var prompt: String
    var onDone: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title2.weight(.semibold))
            Text(prompt).foregroundStyle(.secondary)
            TextEditor(text: $text)
                .font(.body)
                .frame(minWidth: 560, minHeight: 360)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.15)))
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Continue") {
                    onDone(text)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(text.trimmed.isEmpty)
            }
        }
        .padding(20)
    }
}

/// Review an imported resume before it becomes the master.
struct ImportReviewSheet: View {
    @EnvironmentObject var app: AppModel
    var preview: ImportPreview

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Review the import").font(.title2.weight(.semibold))
            Text("From \(preview.source). Job Bot only sorted your text into sections; nothing was added. You can fix anything after importing.")
                .foregroundStyle(.secondary)
            if !preview.warnings.isEmpty {
                Card {
                    Label("Check these", systemImage: "exclamationmark.triangle").font(.headline).foregroundStyle(Palette.partial)
                    ForEach(preview.warnings, id: \.self) { w in
                        Text("• " + w).font(.callout).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            HStack(spacing: 10) {
                Pill(text: preview.profile.contact.name.isEmpty ? "No name found" : preview.profile.contact.name, color: Palette.accent, symbol: "person")
                ForEach(preview.profile.sections.filter { !$0.isEmpty }) { s in
                    Pill(text: "\(s.title): \(s.kind.usesList ? s.items.count : s.entries.count)", symbol: "list.bullet")
                }
            }
            ScrollView {
                Text(PlainTextRenderer.resume(preview.profile))
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(minWidth: 620, minHeight: 340)
            .background(RoundedRectangle(cornerRadius: 8).fill(Palette.subtle))
            if !app.data.master.isEmpty {
                Text("Your current master resume will be replaced. It's saved in History first, so you can restore it.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel") { app.importPreview = nil }.keyboardShortcut(.cancelAction)
                Button("Use as Master Resume") { app.acceptImport(preview) }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 720)
    }
}
