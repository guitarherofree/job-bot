import SwiftUI
import JobBotCore

/// Learn general patterns from examples you're allowed to use, without keeping their wording.
struct ExamplesView: View {
    @EnvironmentObject var app: AppModel
    @State private var text = ""
    @State private var label = ""
    @State private var permitted = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SectionTitle(title: "Professional examples",
                             subtitle: "Paste a resume or profile you have permission to use (for example, one a colleague shared with you, or a career-center sample). Job Bot keeps only general patterns: role titles, credentials, skills, and how achievements are described.")
                Card {
                    Label("What Job Bot does and doesn't do", systemImage: "hand.raised").font(.headline)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("• It doesn't scrape LinkedIn or any other site for profiles.")
                        Text("• It doesn't copy anyone's wording into your documents.")
                        Text("• The pasted text is analyzed on this Mac and then discarded; names and contact details are never stored.")
                    }
                    .font(.callout)
                }
                Card {
                    TextField("Label (e.g. “Curriculum designer sample from career center”)", text: $label).textFieldStyle(.roundedBorder)
                    TextEditor(text: $text)
                        .frame(minHeight: 180)
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.15)))
                    Toggle("I'm allowed to use this example", isOn: $permitted).toggleStyle(.checkbox)
                    HStack {
                        Spacer()
                        Button("Find Patterns") {
                            let result = ExampleAnalyzer.analyze(text, label: label)
                            app.data.examplePatterns.insert(result, at: 0)
                            text = ""
                            label = ""
                            permitted = false
                            app.show("Patterns saved. The example text was discarded.", .success)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!permitted || text.trimmed.count < 80)
                    }
                }
                if !app.data.examplePatterns.isEmpty {
                    CombinedPatterns(patterns: app.data.examplePatterns)
                }
                ForEach(app.data.examplePatterns) { p in PatternCard(patterns: p) }
            }
            .padding(20)
        }
        .navigationTitle("Examples")
    }
}

struct CombinedPatterns: View {
    var patterns: [ExamplePatterns]

    var body: some View {
        let titles = counted(patterns.flatMap { $0.roleTitles })
        let creds = counted(patterns.flatMap { $0.credentials })
        let skills = counted(patterns.flatMap { $0.skills })
        Card {
            Text("Across \(patterns.count) example\(patterns.count == 1 ? "" : "s")").font(.headline)
            if !titles.isEmpty { row("Role titles", titles) }
            if !creds.isEmpty { row("Credentials", creds) }
            if !skills.isEmpty { row("Skills", Array(skills.prefix(20))) }
        }
    }

    private func row(_ title: String, _ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            FlowLayout { ForEach(items, id: \.self) { Pill(text: $0, color: Palette.accent) } }
        }
    }

    private func counted(_ items: [String]) -> [String] {
        var counts: [String: Int] = [:]
        for i in items { counts[i, default: 0] += 1 }
        return counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.map { $0.value > 1 ? "\($0.key) ×\($0.value)" : $0.key }
    }
}

struct PatternCard: View {
    @EnvironmentObject var app: AppModel
    var patterns: ExamplePatterns

    var body: some View {
        Card {
            HStack {
                Text(patterns.label).font(.headline)
                Spacer()
                Text("Analyzed \(patterns.analyzed.shortDate)").font(.caption).foregroundStyle(.secondary)
                Button(role: .destructive) { app.data.examplePatterns.removeAll { $0.id == patterns.id } } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
            }
            if !patterns.sectionOrder.isEmpty {
                Text("Section order: " + patterns.sectionOrder.joined(separator: " → ")).font(.callout)
            }
            if !patterns.roleTitles.isEmpty { Text("Role titles: " + patterns.roleTitles.joined(separator: ", ")).font(.callout) }
            if !patterns.credentials.isEmpty { Text("Credentials: " + patterns.credentials.joined(separator: ", ")).font(.callout) }
            if !patterns.skills.isEmpty { Text("Skills: " + patterns.skills.joined(separator: ", ")).font(.callout).foregroundStyle(.secondary) }
            if !patterns.achievementPatterns.isEmpty {
                Text("How achievements are described").font(.subheadline.weight(.semibold))
                ForEach(patterns.achievementPatterns, id: \.self) { Text("• " + $0).font(.callout) }
            }
            if !patterns.commonVerbs.isEmpty {
                Text("Common opening verbs: " + patterns.commonVerbs.joined(separator: ", ")).font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}
