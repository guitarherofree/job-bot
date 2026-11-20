import SwiftUI
import JobBotCore

/// Saved versions of a document: compare any version with the current one, or restore it.
struct HistorySheet: View {
    @EnvironmentObject var app: AppModel
    @Environment(\.dismiss) private var dismiss
    var owner: VersionSnapshot.Owner
    var title: String
    @State private var selected: UUID?
    @State private var confirmRestore = false

    var body: some View {
        let versions = app.versions(for: owner)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title).font(.title2.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            if versions.isEmpty {
                EmptyState(symbol: "clock", title: "No saved versions yet",
                           message: "Versions are saved when you import, before suggestions are applied, before restoring, and whenever you click Save Version.")
                    .frame(height: 300)
            } else {
                HStack(alignment: .top, spacing: 12) {
                    List(versions, selection: $selected) { v in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(v.label).lineLimit(2)
                            Text(v.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                        }
                        .tag(v.id)
                    }
                    .frame(width: 250)
                    VStack(alignment: .leading, spacing: 8) {
                        if let v = versions.first(where: { $0.id == selected }) {
                            let changes = LineDiff.compare(v.plainText, currentText)
                            HStack {
                                Text("Changes from this version to now").font(.headline)
                                Spacer()
                                Text(LineDiff.summary(changes)).font(.caption).foregroundStyle(.secondary)
                                Button("Restore This Version") { confirmRestore = true }
                            }
                            DiffView(changes: changes)
                        } else {
                            Text("Select a version to compare it with the current document.")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 900, height: 600)
        .confirmationDialog("Restore this version?", isPresented: $confirmRestore) {
            Button("Restore") {
                if let v = app.versions(for: owner).first(where: { $0.id == selected }) {
                    app.restore(v)
                    dismiss()
                }
            }
        } message: {
            Text("The current document is saved in History first, so you can undo this.")
        }
        .onAppear { selected = versions.first?.id }
    }

    private var currentText: String {
        switch owner {
        case .master: return PlainTextRenderer.resume(app.data.master)
        case .resume(let id): return app.data.resume(id).map { PlainTextRenderer.resume($0.content) } ?? ""
        case .coverLetter(let id): return app.data.letter(id)?.plainText ?? ""
        }
    }
}

struct DiffView: View {
    var changes: [LineDiff.Change]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(Array(changes.enumerated()), id: \.offset) { _, change in
                    row(change)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(Palette.subtle))
    }

    @ViewBuilder
    private func row(_ change: LineDiff.Change) -> some View {
        switch change {
        case .same(let s):
            Text(s.isEmpty ? " " : s)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
        case .added(let s):
            Text("+ " + s)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(Palette.strong)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.strong.opacity(0.08))
        case .removed(let s):
            Text("− " + s).strikethrough()
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(Palette.gap)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.gap.opacity(0.08))
        }
    }
}
