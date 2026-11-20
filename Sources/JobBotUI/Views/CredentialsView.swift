import SwiftUI
import JobBotCore

/// Certifications, workshops and degree programs to consider, with the reason each may help,
/// time and cost as the source states them, and a link.
struct CredentialsView: View {
    @EnvironmentObject var app: AppModel
    @State private var showAll = false

    var body: some View {
        let roles = relevantRoles
        let shown = showAll ? Credentials.catalog : Credentials.relevant(to: roles)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SectionTitle(title: "Credentials to consider",
                             subtitle: "Certifications, workshops and degree programs related to your pivot roles: why each may help, time and cost from the source, and a link to check before deciding.")
                HStack {
                    Picker("", selection: $showAll) {
                        Text("For my pivot roles").tag(false)
                        Text("All (\(Credentials.catalog.count))").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 320)
                    Spacer()
                    Button("Edit Pivot Roles") { app.selection = .pivots }
                }
                if !showAll && !roles.isEmpty {
                    Text("Based on: " + roles.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                }
                Label("Time and cost are shown as each source stated them on the date listed. Items marked “Estimate” or “Unknown” weren't confirmed on the provider's own page.",
                      systemImage: "info.circle")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                ForEach(shown) { c in CredentialCard(credential: c) }
            }
            .padding(20)
        }
        .navigationTitle("Credentials")
    }

    /// Your tracked pivot titles, plus the three roles your profile supports best (no repeats).
    private var relevantRoles: [String] {
        let top = Pivots.assess(app.data.master).prefix(3).map { $0.role.title }
        var out: [String] = []
        for r in app.data.pivots.titles + top where !out.contains(r) {
            out.append(r)
        }
        return out
    }
}

struct CredentialCard: View {
    var credential: Credential

    var body: some View {
        Card {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(credential.name).font(.headline)
                    Text("\(credential.issuer) · \(credential.kind)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let url = URL(string: credential.url) {
                    Link(destination: url) { Label("Source", systemImage: "arrow.up.right.square") }.font(.callout)
                }
            }
            Text(credential.why).font(.callout).fixedSize(horizontal: false, vertical: true)
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                GridRow {
                    Text("Time").foregroundStyle(.secondary)
                    Text(credential.time)
                }
                GridRow {
                    Text("Cost").foregroundStyle(.secondary)
                    Text(credential.cost)
                }
                GridRow {
                    Text("Based on").foregroundStyle(.secondary)
                    Text("\(credential.basis) (checked \(credential.checked))")
                }
            }
            .font(.callout)
            FlowLayout {
                ForEach(credential.relevantTo, id: \.self) { Pill(text: $0, symbol: "arrow.triangle.branch") }
            }
        }
    }
}
