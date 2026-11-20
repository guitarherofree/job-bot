import SwiftUI
import JobBotCore

/// All applications by status.
struct TrackerView: View {
    @EnvironmentObject var app: AppModel
    @State private var showClosed = false

    private let columns: [ApplicationStatus] = [.saved, .preparing, .applied, .interviewing, .offer]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                SectionTitle(title: "Applications", subtitle: "\(app.data.jobs.filter { $0.status.isActive }.count) active, \(app.data.jobs.filter { $0.status == .applied || $0.status == .interviewing }.count) in progress")
                Spacer()
                Toggle("Show closed", isOn: $showClosed).toggleStyle(.checkbox)
            }
            .padding(20)
            if app.data.jobs.isEmpty {
                EmptyState(symbol: "list.bullet.rectangle", title: "Nothing to track yet",
                           message: "Saved jobs appear here by status: saved, preparing, applied, interviewing and offers.",
                           actionTitle: "Go to Jobs") { app.selection = .jobs }
            } else {
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(columns + (showClosed ? [.rejected, .withdrawn, .archived] : [])) { status in
                            column(status)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
        }
        .navigationTitle("Applications")
    }

    private func column(_ status: ApplicationStatus) -> some View {
        let jobs = app.data.jobs.filter { $0.status == status }.sorted { $0.updated > $1.updated }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(status.title, systemImage: status.symbol).font(.headline).foregroundStyle(status.color)
                Spacer()
                Text("\(jobs.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(jobs) { job in
                        Button {
                            app.selectedJobID = job.id
                            app.selection = .jobs
                        } label: {
                            TrackerCard(job: job)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            ForEach(ApplicationStatus.allCases) { s in
                                Button("Move to \(s.title)") { app.updateJob(job.id) { $0.setStatus(s) } }
                            }
                        }
                    }
                    if jobs.isEmpty {
                        Text("None").font(.callout).foregroundStyle(.tertiary).frame(maxWidth: .infinity).padding(.vertical, 20)
                    }
                }
            }
        }
        .padding(10)
        .frame(width: 240)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 10).fill(Palette.subtle))
    }
}

struct TrackerCard: View {
    @EnvironmentObject var app: AppModel
    var job: Job

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(job.displayTitle).font(.callout.weight(.semibold)).lineLimit(2).multilineTextAlignment(.leading)
            Text(job.displayEmployer).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                if app.tailoredResume(for: job) != nil { Image(systemName: "person.text.rectangle").help("Tailored resume") }
                if app.coverLetter(for: job) != nil { Image(systemName: "envelope").help("Cover letter") }
                if job.expired { Image(systemName: "clock.badge.xmark").foregroundStyle(Palette.gap).help("May be closed") }
                Spacer()
                Text(job.appliedDate.map { "Applied \($0.shortDate)" } ?? job.updated.shortDate)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Palette.card))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.08)))
        .contentShape(Rectangle())
    }
}
