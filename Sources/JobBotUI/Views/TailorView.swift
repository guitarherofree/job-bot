import SwiftUI
import JobBotCore

/// The tailored resume for one job: evidence-based suggestions, full editing, preview, export.
struct TailorView: View {
    @EnvironmentObject var app: AppModel
    let jobID: UUID
    enum Pane: String, CaseIterable, Identifiable {
        case suggestions = "Suggestions", edit = "Edit"
        var id: String { rawValue }
    }
    @State private var pane: Pane = .suggestions
    @State private var showHistory = false
    @State private var showDecided = false
    @State private var confirmReset = false

    var body: some View {
        if let job = app.data.job(jobID) {
            if let resume = app.tailoredResume(for: job) {
                HSplitView {
                    VStack(spacing: 0) {
                        HStack {
                            Picker("", selection: $pane) {
                                ForEach(Pane.allCases) { Text($0.rawValue).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(width: 220)
                            Spacer()
                            Menu {
                                Button("Refresh Suggestions") { app.refreshSuggestions(resume.id) }
                                Button("Suggest Wording with AI…") { Task { await app.aiSuggestions(resume.id) } }
                                    .disabled(!app.data.preferences.aiEnabled)
                                Divider()
                                Button("Version History…") { showHistory = true }
                                Button("Save Version") { app.snapshot(.resume(resume.id), label: "Saved \(Date().formatted(date: .abbreviated, time: .shortened))"); app.show("Version saved.", .success) }
                                Divider()
                                Button("Start Over from Master Resume…") { confirmReset = true }
                            } label: {
                                Label("More", systemImage: "ellipsis.circle")
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                            ExportMenu(profile: resume.content, template: resume.template, name: job.employer)
                                .fixedSize()
                        }
                        .padding(10)
                        Divider()
                        ScrollView {
                            VStack(alignment: .leading, spacing: 12) {
                                switch pane {
                                case .suggestions:
                                    SuggestionsList(resume: resume, showDecided: $showDecided)
                                case .edit:
                                    Text("Changes here affect only this job's resume. Your master resume stays as it is.")
                                        .font(.callout).foregroundStyle(.secondary)
                                    ResumeEditor(profile: Binding(get: { app.data.resume(resume.id)?.content ?? resume.content },
                                                                  set: { p in app.updateResume(resume.id) { $0.content = p } }))
                                }
                            }
                            .padding(16)
                        }
                    }
                    .frame(minWidth: 440)
                    ResumePreviewPane(profile: resume.content,
                                      template: Binding(get: { app.data.resume(resume.id)?.template ?? .atsSimple },
                                                        set: { t in app.updateResume(resume.id) { $0.template = t } }))
                        .frame(minWidth: 340, idealWidth: 420)
                }
                .sheet(isPresented: $showHistory) { HistorySheet(owner: .resume(resume.id), title: "History: \(resume.name)").environmentObject(app) }
                .confirmationDialog("Start over from your master resume?", isPresented: $confirmReset) {
                    Button("Start Over", role: .destructive) { app.resetFromMaster(resume.id) }
                } message: {
                    Text("This version is replaced by a fresh copy of your master resume. The current version is saved in History.")
                }
            } else {
                VStack(spacing: 14) {
                    EmptyState(symbol: "person.text.rectangle", title: "Tailor a resume for this job",
                               message: "Job Bot copies your master resume for this job and suggests changes, each with the evidence behind it. You review every change. Your master resume never changes.",
                               actionTitle: app.data.master.isEmpty ? nil : "Create Tailored Resume") {
                        _ = app.createTailoredResume(for: jobID)
                    }
                    if app.data.master.isEmpty {
                        Button("Set Up Master Resume First") { app.selection = .profile }
                    }
                }
            }
        }
    }
}

struct SuggestionsList: View {
    @EnvironmentObject var app: AppModel
    var resume: TailoredResume
    @Binding var showDecided: Bool

    var body: some View {
        let pending = resume.suggestions.filter { $0.status == .pending }
        let decided = resume.suggestions.filter { $0.status != .pending }
        VStack(alignment: .leading, spacing: 12) {
            Text("Each suggestion shows why it may help and which parts of your profile support it. Nothing changes until you accept it, and you can edit the wording first.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if pending.isEmpty {
                Card {
                    Label("No open suggestions", systemImage: "checkmark.seal").font(.headline)
                    Text("Check the Compare tab for gaps and questions. If you answer them or edit your master resume, refresh the suggestions.")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("Refresh Suggestions") { app.refreshSuggestions(resume.id) }
                }
            }
            ForEach(pending) { s in SuggestionCard(suggestion: s, resumeID: resume.id) }
            if !decided.isEmpty {
                DisclosureGroup("Reviewed (\(decided.count))", isExpanded: $showDecided) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(decided) { s in
                            HStack {
                                Image(systemName: s.status == .accepted ? "checkmark.circle.fill" : "xmark.circle")
                                    .foregroundStyle(s.status == .accepted ? Palette.strong : .secondary)
                                Text(s.title).font(.callout)
                                Spacer()
                                Text(s.status == .accepted ? "Accepted" : "Declined").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.top, 6)
                }
            }
        }
    }
}

struct SuggestionCard: View {
    @EnvironmentObject var app: AppModel
    var suggestion: Suggestion
    let resumeID: UUID
    @State private var edited = ""
    @State private var showEvidence = true

    private var editable: Bool {
        [.alignTerm, .rewriteBullet, .rewriteSummary, .addSkill].contains(suggestion.kind)
    }

    var body: some View {
        Card {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: icon).foregroundStyle(Palette.accent)
                Text(suggestion.title).font(.headline).fixedSize(horizontal: false, vertical: true)
                Spacer()
                if suggestion.origin != "Job Bot" { Pill(text: "AI draft", color: .purple, symbol: "sparkles") }
            }
            Text(suggestion.explanation).font(.callout).fixedSize(horizontal: false, vertical: true)
            if !suggestion.before.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Now").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(suggestion.before).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6).fill(Palette.subtle))
            }
            if suggestion.kind != .hideBullet {
                VStack(alignment: .leading, spacing: 4) {
                    Text(editable ? "Suggested (you can edit)" : "Suggested").font(.caption.weight(.semibold)).foregroundStyle(Palette.accent)
                    if editable {
                        TextField("", text: $edited, axis: .vertical)
                            .lineLimit(1...8)
                            .fieldBox()
                    } else {
                        Text(suggestion.after).font(.callout).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6).fill(Palette.accent.opacity(0.06)))
            }
            ForEach(suggestion.warnings, id: \.self) { w in
                Label(w, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(Palette.partial)
            }
            if WritingRules.containsEmDash(edited) {
                Label("Em dashes will be replaced with commas.", systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
            }
            DisclosureGroup(isExpanded: $showEvidence) {
                VStack(alignment: .leading, spacing: 8) {
                    if !suggestion.jobEvidence.isEmpty {
                        Text("From the posting").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(suggestion.jobEvidence, id: \.self) { line in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "briefcase").imageScale(.small).foregroundStyle(.secondary).padding(.top, 2)
                                Text(line).font(.callout).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    if !suggestion.profileEvidence.isEmpty {
                        Text("Supported by your profile").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(Array(suggestion.profileEvidence.enumerated()), id: \.offset) { _, u in EvidenceRow(unit: u) }
                    }
                }
                .padding(.top, 4)
            } label: {
                Text("Why and evidence").font(.callout)
            }
            HStack {
                Spacer()
                Button("Decline") { app.reject(suggestion, in: resumeID) }
                Button("Accept") {
                    app.accept(suggestion, in: resumeID, editedText: editable ? edited : nil)
                }
                .buttonStyle(.borderedProminent)
                .disabled(editable && edited.trimmed.isEmpty)
            }
        }
        .onAppear { edited = suggestion.after }
    }

    private var icon: String {
        switch suggestion.kind {
        case .reorderBullets, .reorderSkills: return "arrow.up.arrow.down"
        case .addSkill: return "plus.circle"
        case .alignTerm: return "textformat.alt"
        case .rewriteSummary, .rewriteBullet: return "pencil"
        case .hideBullet: return "eye.slash"
        }
    }
}
