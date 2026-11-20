import SwiftUI
import JobBotCore

/// Application questions with drafted answers. Submitting stays with you: Job Bot never fills in
/// or sends application forms.
struct ApplicationView: View {
    @EnvironmentObject var app: AppModel
    let jobID: UUID
    @State private var questionsText = ""

    var body: some View {
        if let job = app.data.job(jobID) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ChecklistCard(job: job)
                    Card {
                        Text("Application questions").font(.headline)
                        Text("Paste the questions from the application form, one per line. Job Bot drafts answers from your profile, marks the ones you need to confirm, and leaves the rest blank. Personal questions (work authorization, pay, start date, demographics) are always left to you.")
                            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        TextEditor(text: $questionsText)
                            .frame(minHeight: 90)
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.15)))
                        HStack {
                            Button("Draft Answers") {
                                app.draftAnswers(job: jobID, questionsText: questionsText)
                                questionsText = ""
                            }
                            .disabled(questionsText.trimmed.isEmpty)
                            if app.data.preferences.aiEnabled && job.answers.contains(where: { $0.state == .unknown }) {
                                Button("Draft Blank Answers with AI…") { Task { await app.aiAnswers(job: jobID) } }
                            }
                        }
                    }
                    ForEach(job.answers) { answer in
                        AnswerCard(jobID: jobID, answer: answer)
                    }
                    if !job.answers.isEmpty {
                        HStack {
                            Spacer()
                            Button("Copy All Answers") {
                                let text = (app.data.job(jobID)?.answers ?? []).map { "\($0.question)\n\($0.answer)" }.joined(separator: "\n\n")
                                app.copyPlainText(text)
                            }
                        }
                    }
                }
                .padding(20)
            }
        }
    }
}

struct ChecklistCard: View {
    @EnvironmentObject var app: AppModel
    var job: Job

    var body: some View {
        let resume = app.tailoredResume(for: job)
        let letter = app.coverLetter(for: job)
        let unconfirmed = job.answers.filter { $0.state == .needsConfirmation }.count
        Card {
            Text("Getting ready").font(.headline)
            item(resume != nil, "Tailored resume created", detail: resume.map { r in "\(r.suggestions.filter { $0.status == .accepted }.count) suggestions accepted" })
            item(letter != nil, "Cover letter drafted", detail: letter.map { "Last edited \($0.updated.shortDate)" })
            item(unconfirmed == 0 && !job.answers.isEmpty, "Application answers confirmed",
                 detail: job.answers.isEmpty ? "No questions added" : (unconfirmed == 0 ? "All reviewed" : (unconfirmed == 1 ? "1 still needs your confirmation" : "\(unconfirmed) still need your confirmation")))
            item(job.status == .applied || job.status == .interviewing || job.status == .offer, "Submitted by you",
                 detail: job.appliedDate.map { "Applied \($0.shortDate)" } ?? "Set the status to Applied after you submit")
        }
    }

    private func item(_ done: Bool, _ title: String, detail: String?) -> some View {
        HStack(alignment: .top) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle").foregroundStyle(done ? Palette.strong : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
}

struct AnswerCard: View {
    @EnvironmentObject var app: AppModel
    let jobID: UUID
    var answer: ApplicationAnswer

    var body: some View {
        Card(padding: 12) {
            HStack(alignment: .top) {
                Text(answer.question).font(.headline).fixedSize(horizontal: false, vertical: true)
                Spacer()
                Pill(text: stateTitle, color: stateColor)
                Button(role: .destructive) {
                    app.updateJob(jobID) { $0.answers.removeAll { $0.id == answer.id } }
                } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
            }
            TextField(answer.state == .personal ? "Only you can answer this" : "Answer", text: binding, axis: .vertical)
                .lineLimit(1...8)
                .fieldBox()
            if !answer.note.isEmpty {
                Text(answer.note).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if answer.state == .needsConfirmation || answer.state == .fromProfile {
                HStack {
                    Spacer()
                    Button("Confirm") { app.updateJob(jobID) { j in
                        if let i = j.answers.firstIndex(where: { $0.id == answer.id }) { j.answers[i].state = .confirmed }
                    } }
                }
            }
        }
    }

    private var binding: Binding<String> {
        Binding(get: { app.data.job(jobID)?.answers.first { $0.id == answer.id }?.answer ?? "" },
                set: { v in app.updateJob(jobID) { j in
                    if let i = j.answers.firstIndex(where: { $0.id == answer.id }) {
                        j.answers[i].answer = v
                        if j.answers[i].state == .unknown || j.answers[i].state == .personal { j.answers[i].state = .confirmed }
                    }
                } })
    }

    private var stateTitle: String {
        switch answer.state {
        case .fromProfile: return "From profile"
        case .needsConfirmation: return "Needs your confirmation"
        case .confirmed: return "Confirmed"
        case .unknown: return "Left blank"
        case .personal: return "Yours to answer"
        }
    }

    private var stateColor: Color {
        switch answer.state {
        case .fromProfile: return Palette.accent
        case .needsConfirmation: return Palette.partial
        case .confirmed: return Palette.strong
        case .unknown, .personal: return .secondary
        }
    }
}
