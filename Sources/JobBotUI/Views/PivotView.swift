import SwiftUI
import JobBotCore

/// Adjacent roles, what supports them, what may be missing, credentials and pay.
struct PivotView: View {
    @EnvironmentObject var app: AppModel

    var body: some View {
        let assessments = Pivots.assess(app.data.master)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SectionTitle(title: "Pivot paths",
                             subtitle: "Roles next to the work you already do, the experience in your profile that supports each, and skills that may be missing.")
                HStack(alignment: .top, spacing: 16) {
                    Card {
                        Text("Pivot job titles").font(.headline)
                        Text("Included in Find Jobs searches.").font(.caption).foregroundStyle(.secondary)
                        ChipEditor(items: $app.data.pivots.titles, placeholder: "Add a title, e.g. Learning Designer")
                    }
                    Card {
                        Text("Pivot keywords").font(.headline)
                        Text("Skills or areas you want to grow into.").font(.caption).foregroundStyle(.secondary)
                        ChipEditor(items: $app.data.pivots.keywords, placeholder: "Add a keyword, e.g. storyboarding")
                    }
                }
                let suggestions = Pivots.suggestedSearchTerms(assessments, existing: app.data.pivots.titles + app.data.discovery.searchTerms)
                if !suggestions.isEmpty && !app.data.master.isEmpty {
                    Card {
                        Text("Suggested search terms").font(.headline)
                        Text("Based on roles your profile already supports well.").font(.caption).foregroundStyle(.secondary)
                        FlowLayout {
                            ForEach(suggestions, id: \.self) { term in
                                Button {
                                    app.data.pivots.titles.append(term)
                                } label: {
                                    Label(term, systemImage: "plus")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                }
                Text("Adjacent roles").font(.title3.weight(.semibold))
                if app.data.master.isEmpty {
                    Text("Add your master resume to see which roles your experience supports.").foregroundStyle(.secondary)
                }
                ForEach(assessments) { a in RoleCard(assessment: a) }
                CredentialsSection(roles: Array(assessments.prefix(3).map { $0.role.title }) + app.data.pivots.titles)
                PaySection()
            }
            .padding(20)
        }
        .navigationTitle("Pivot Paths")
    }
}

struct RoleCard: View {
    @EnvironmentObject var app: AppModel
    var assessment: PivotAssessment
    @State private var expanded = false

    var body: some View {
        Card {
            HStack(alignment: .firstTextBaseline) {
                Text(assessment.role.title).font(.headline)
                Spacer()
                Text("\(assessment.supported.count) of \(assessment.role.typicalSkills.count) typical skills shown in your profile")
                    .font(.caption).foregroundStyle(.secondary)
                if !app.data.pivots.titles.contains(assessment.role.title) {
                    Button("Track Title") { app.data.pivots.titles.append(assessment.role.title) }.controlSize(.small)
                }
            }
            ProgressView(value: assessment.share).tint(Palette.accent)
            Text(assessment.role.why).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            DisclosureGroup(isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 10) {
                    if !assessment.supported.isEmpty {
                        Text("Supported by your experience").font(.subheadline.weight(.semibold))
                        ForEach(Array(assessment.supported.enumerated()), id: \.offset) { _, item in
                            VStack(alignment: .leading, spacing: 2) {
                                Pill(text: item.skill, color: Palette.strong, symbol: "checkmark")
                                EvidenceRow(unit: item.evidence)
                            }
                        }
                    }
                    if !assessment.missing.isEmpty {
                        Text("Possibly missing").font(.subheadline.weight(.semibold))
                        FlowLayout {
                            ForEach(assessment.missing, id: \.self) { Pill(text: $0, color: .secondary) }
                        }
                        Text("“Missing” means Job Bot didn't find it in your profile. If you have it, add it to your master resume or notes.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text("Search terms: " + assessment.role.searchTerms.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                }
                .padding(.top, 6)
            } label: {
                Text("Evidence and gaps").font(.callout)
            }
        }
    }
}

struct CredentialsSection: View {
    var roles: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Credentials to consider").font(.title3.weight(.semibold))
            Text("Time and cost come from each source as of the date shown. Items marked “Estimate” or “Unknown” weren't confirmed on the provider's own page; check the link before deciding.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ForEach(Credentials.relevant(to: roles)) { c in
                Card {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.name).font(.headline)
                            Text("\(c.issuer) · \(c.kind)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let url = URL(string: c.url) {
                            Link(destination: url) { Label("Source", systemImage: "arrow.up.right.square") }.font(.callout)
                        }
                    }
                    Text(c.why).font(.callout).fixedSize(horizontal: false, vertical: true)
                    Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                        GridRow {
                            Text("Time").foregroundStyle(.secondary)
                            Text(c.time)
                        }
                        GridRow {
                            Text("Cost").foregroundStyle(.secondary)
                            Text(c.cost)
                        }
                        GridRow {
                            Text("Based on").foregroundStyle(.secondary)
                            Text("\(c.basis) (checked \(c.checked))")
                        }
                    }
                    .font(.callout)
                    FlowLayout {
                        ForEach(c.relevantTo, id: \.self) { Pill(text: $0, symbol: "arrow.triangle.branch") }
                    }
                }
            }
        }
    }
}

struct PaySection: View {
    @EnvironmentObject var app: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Pay").font(.title3.weight(.semibold))
            Card {
                Text("Optional. Used only on this Mac, to compare postings that list pay.").font(.callout).foregroundStyle(.secondary)
                HStack(spacing: 20) {
                    LabeledContent("Current yearly pay") {
                        TextField("e.g. 70000", value: $app.data.preferences.currentCompensation, format: .number)
                            .textFieldStyle(.roundedBorder).frame(width: 140)
                    }
                    LabeledContent("Target yearly pay") {
                        TextField("e.g. 85000", value: $app.data.preferences.targetCompensation, format: .number)
                            .textFieldStyle(.roundedBorder).frame(width: 140)
                    }
                }
            }
            let withPay = app.data.jobs.filter { $0.parsed.salary != nil }
            if withPay.isEmpty {
                Text("None of your saved jobs list pay yet.").font(.callout).foregroundStyle(.secondary)
            } else {
                Card {
                    Text("Saved jobs that list pay").font(.headline)
                    ForEach(withPay) { job in
                        if let s = job.parsed.salary {
                            let cmp = PayComparison.compare(s, current: app.data.preferences.currentCompensation, target: app.data.preferences.targetCompensation)
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("\(job.displayTitle), \(job.displayEmployer)").font(.callout.weight(.medium))
                                    Text("\(s.display) · \(s.source), read \(s.date.shortDate)").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if let c = cmp?.versusCurrent { percent(c, "vs. current") }
                                if let t = cmp?.versusTarget { percent(t, "vs. target") }
                            }
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func percent(_ v: Double, _ label: String) -> some View {
        let p = Int((v * 100).rounded())
        return Text("\(p >= 0 ? "+" : "")\(p)% \(label)").font(.caption.weight(.semibold)).foregroundStyle(p >= 0 ? Palette.strong : Palette.gap)
    }
}
