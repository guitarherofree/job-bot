import SwiftUI
import JobBotCore

/// Compares the job with the master resume: evidence for each requirement, gaps, and questions,
/// before anything on the resume changes.
struct MatchView: View {
    @EnvironmentObject var app: AppModel
    let jobID: UUID
    var openResume: () -> Void
    @State private var filter: Filter = .all

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", gaps = "Gaps", supported = "Supported"
        var id: String { rawValue }
    }

    var body: some View {
        if let job = app.data.job(jobID) {
            let report = app.report(for: job)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if app.data.master.isEmpty {
                        Card {
                            Label("Your master resume is empty", systemImage: "exclamationmark.triangle").font(.headline)
                            Text("Import or write your resume first; the comparison uses it as evidence.").font(.callout)
                            Button("Go to Master Resume") { app.selection = .profile }
                        }
                    }
                    SummaryCard(report: report, openResume: openResume)
                    KeywordsCard(report: report)
                    if !report.followUps.isEmpty || !(app.aiQuestions[jobID] ?? []).isEmpty {
                        FollowUpCard(jobID: jobID, questions: report.followUps + (app.aiQuestions[jobID] ?? []))
                    }
                    HStack {
                        Text("Requirement by requirement").font(.headline)
                        Spacer()
                        Picker("", selection: $filter) {
                            ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 260)
                    }
                    ForEach(rows(report)) { r in RequirementCard(match: r) }
                    if report.requirements.isEmpty {
                        Text("No responsibilities or qualifications were found in this posting. Open Overview to check the description.")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(20)
            }
        }
    }

    private func rows(_ report: MatchReport) -> [RequirementMatch] {
        switch filter {
        case .all: return report.requirements
        case .gaps: return report.requirements.filter { $0.strength == .gap }
        case .supported: return report.requirements.filter { $0.strength != .gap }
        }
    }
}

struct SummaryCard: View {
    var report: MatchReport
    var openResume: () -> Void

    var body: some View {
        let required = report.requirements.filter { $0.kind == .required }
        let supported = required.filter { $0.strength != .gap }.count
        let strong = required.filter { $0.strength == .strong }.count
        Card {
            HStack(alignment: .top, spacing: 18) {
                ZStack {
                    Circle().stroke(Color.primary.opacity(0.08), lineWidth: 8)
                    Circle().trim(from: 0, to: report.requiredCoverage)
                        .stroke(Palette.strong, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(supported)/\(required.count)").font(.headline.monospacedDigit())
                }
                .frame(width: 70, height: 70)
                VStack(alignment: .leading, spacing: 4) {
                    Text(required.isEmpty ? "No required qualifications were listed" : "\(supported) of \(required.count) required qualifications have evidence in your profile")
                        .font(.headline)
                    Text("\(strong) clearly supported, \(supported - strong) partly, \(required.count - supported) with no evidence found. This shows what your profile speaks to; it doesn't predict how an employer will decide.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if let years = report.profileYears {
                        Text("Your experience dates add up to about \(String(format: "%.1f", years)) years.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("Tailor Resume", action: openResume).buttonStyle(.borderedProminent)
            }
        }
    }
}

struct KeywordsCard: View {
    var report: MatchReport

    var body: some View {
        Card {
            Text("Keywords from the posting").font(.headline)
            if report.matchedKeywords.isEmpty && report.missingKeywords.isEmpty {
                Text("No keywords were found.").foregroundStyle(.secondary)
            }
            if !report.matchedKeywords.isEmpty {
                Text("In your profile").font(.subheadline).foregroundStyle(.secondary)
                FlowLayout {
                    ForEach(report.matchedKeywords, id: \.self) { Pill(text: $0, color: Palette.strong, symbol: "checkmark") }
                }
            }
            if !report.missingKeywords.isEmpty {
                Text("Not found in your profile").font(.subheadline).foregroundStyle(.secondary)
                FlowLayout {
                    ForEach(report.missingKeywords, id: \.self) { Pill(text: $0, color: .secondary) }
                }
                Text("Only add these to a resume if they're true for you. Answer the questions below to record experience that isn't written down yet.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct RequirementCard: View {
    var match: RequirementMatch
    @State private var expanded = false

    var body: some View {
        Card(padding: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: match.strength.symbol).foregroundStyle(match.strength.color).font(.title3)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Pill(text: match.kind.title, color: match.kind == .required ? Palette.accent : .secondary)
                        Pill(text: match.strength.title, color: match.strength.color)
                    }
                    Text(match.text).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    ForEach(match.notes, id: \.self) { n in
                        Label(n, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
                    }
                    if !match.evidence.isEmpty {
                        DisclosureGroup(isExpanded: $expanded) {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(Array(match.evidence.enumerated()), id: \.offset) { _, e in
                                    EvidenceRow(unit: e.unit, terms: e.sharedTerms)
                                }
                            }
                            .padding(.top, 4)
                        } label: {
                            Text("Evidence from your profile (\(match.evidence.count))").font(.callout)
                        }
                    } else if !match.missingTerms.isEmpty {
                        Text("Not found in your profile: " + match.missingTerms.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onAppear { expanded = match.strength == .strong && match.evidence.count <= 2 }
    }
}

struct FollowUpCard: View {
    @EnvironmentObject var app: AppModel
    let jobID: UUID
    var questions: [FollowUpQuestion]

    var body: some View {
        Card {
            Label("Questions before changing your resume", systemImage: "questionmark.bubble").font(.headline)
            Text("Job Bot won't fill gaps with guesses. If you have experience it doesn't know about, describe it here; you can save it to your profile notes so it counts as evidence.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ForEach(questions) { q in
                FollowUpRow(jobID: jobID, question: q, saved: app.data.job(jobID)?.followUps[q.id] ?? "")
                if q.id != questions.last?.id { Divider() }
            }
        }
    }
}

struct FollowUpRow: View {
    @EnvironmentObject var app: AppModel
    let jobID: UUID
    var question: FollowUpQuestion
    var saved: String
    @State private var answer = ""
    @State private var addToProfile = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(question.question).fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top) {
                TextField("Your answer (leave blank if it doesn't apply)", text: $answer, axis: .vertical)
                    .lineLimit(1...4)
                    .fieldBox()
                VStack(alignment: .leading) {
                    Button(saved.isEmpty ? "Save" : "Update") {
                        app.answerFollowUp(job: jobID, question: question, answer: answer, addToProfile: addToProfile)
                    }
                    .disabled(answer.trimmed.isEmpty || answer.trimmed == saved)
                    Toggle("Add to profile notes", isOn: $addToProfile).toggleStyle(.checkbox).font(.caption)
                }
            }
            if !saved.isEmpty {
                Label("Saved", systemImage: "checkmark").font(.caption).foregroundStyle(Palette.strong)
            }
        }
        .onAppear { answer = saved }
    }
}
