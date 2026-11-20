import SwiftUI
import JobBotCore

/// Edits a profile: contact details, summary and sections (add, edit, reorder, remove).
struct ResumeEditor: View {
    @Binding var profile: Profile
    /// Notes (follow-up answers) are shown for the master resume only.
    var showNotes: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ContactEditor(profile: $profile)
            Card {
                Text("Summary").font(.headline)
                TextField("A few sentences about your experience, in your own words", text: $profile.summary, axis: .vertical)
                    .lineLimit(3...10)
                    .fieldBox()
            }
            ForEach(profile.sections) { section in
                SectionEditor(section: elementBinding($profile.sections, section),
                              isFirst: profile.sections.first?.id == section.id,
                              isLast: profile.sections.last?.id == section.id,
                              move: { delta in moveSection(section.id, by: delta) },
                              delete: { deleteSection(section.id) })
            }
            Menu {
                ForEach(SectionKind.allCases) { kind in
                    Button(kind.defaultTitle) { profile.sections.append(ResumeSection(kind: kind)) }
                }
            } label: {
                Label("Add Section", systemImage: "plus")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            if showNotes {
                NotesEditor(notes: $profile.notes)
            }
        }
    }

    private func moveSection(_ id: UUID, by delta: Int) {
        guard let i = profile.sections.firstIndex(where: { $0.id == id }) else { return }
        let j = i + delta
        guard profile.sections.indices.contains(j) else { return }
        profile.sections.swapAt(i, j)
    }

    private func deleteSection(_ id: UUID) {
        profile.sections.removeAll { $0.id == id }
    }
}

struct ContactEditor: View {
    @Binding var profile: Profile

    var body: some View {
        Card {
            Text("Contact").font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    TextField("Full name", text: $profile.contact.name).textFieldStyle(.roundedBorder)
                    TextField("Headline (optional), e.g. Assessment Content Specialist", text: $profile.headline).textFieldStyle(.roundedBorder)
                }
                GridRow {
                    TextField("Email", text: $profile.contact.email).textFieldStyle(.roundedBorder)
                    TextField("Phone", text: $profile.contact.phone).textFieldStyle(.roundedBorder)
                }
                GridRow {
                    TextField("City, State", text: $profile.contact.location).textFieldStyle(.roundedBorder)
                    Color.clear.frame(height: 1)
                }
            }
            Text("Links").font(.subheadline).foregroundStyle(.secondary)
            ChipEditor(items: $profile.contact.links, placeholder: "linkedin.com/in/… or a portfolio link")
        }
    }
}

struct SectionEditor: View {
    @Binding var section: ResumeSection
    var isFirst: Bool
    var isLast: Bool
    var move: (Int) -> Void
    var delete: () -> Void
    @State private var confirmDelete = false

    var body: some View {
        Card {
            HStack(spacing: 8) {
                TextField("Section title", text: $section.title)
                    .font(.headline)
                    .textFieldStyle(.plain)
                Spacer()
                Toggle("Show", isOn: Binding(get: { !section.hidden }, set: { section.hidden = !$0 }))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .help("Hidden sections stay in your profile but are left off this document.")
                MoveButtons(isFirst: isFirst, isLast: isLast, move: move)
                Button(role: .destructive) { confirmDelete = true } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                    .help("Remove this section")
            }
            if section.kind.usesList {
                ListItemsEditor(items: $section.items, placeholder: "Add a skill")
            } else {
                ForEach(section.entries) { entry in
                    EntryEditor(entry: elementBinding($section.entries, entry), kind: section.kind,
                                isFirst: section.entries.first?.id == entry.id,
                                isLast: section.entries.last?.id == entry.id,
                                move: { delta in moveEntry(entry.id, by: delta) },
                                delete: { section.entries.removeAll { $0.id == entry.id } })
                    if section.entries.last?.id != entry.id { Divider() }
                }
                Button {
                    section.entries.append(ResumeEntry())
                } label: {
                    Label(addLabel, systemImage: "plus.circle")
                }
                .buttonStyle(.borderless)
            }
        }
        .opacity(section.hidden ? 0.6 : 1)
        .confirmationDialog("Remove the “\(section.title)” section?", isPresented: $confirmDelete) {
            Button("Remove Section", role: .destructive, action: delete)
        } message: {
            Text("Everything in it will be removed from this document. You can restore an earlier version from History.")
        }
    }

    private var addLabel: String {
        switch section.kind {
        case .experience, .volunteer: return "Add Role"
        case .education: return "Add Education"
        case .certifications: return "Add Credential"
        default: return "Add Entry"
        }
    }

    private func moveEntry(_ id: UUID, by delta: Int) {
        guard let i = section.entries.firstIndex(where: { $0.id == id }) else { return }
        let j = i + delta
        guard section.entries.indices.contains(j) else { return }
        section.entries.swapAt(i, j)
    }
}

struct MoveButtons: View {
    var isFirst: Bool
    var isLast: Bool
    var move: (Int) -> Void

    var body: some View {
        HStack(spacing: 2) {
            Button { move(-1) } label: { Image(systemName: "chevron.up") }
                .disabled(isFirst)
                .help("Move up")
            Button { move(1) } label: { Image(systemName: "chevron.down") }
                .disabled(isLast)
                .help("Move down")
        }
        .buttonStyle(.borderless)
    }
}

struct EntryEditor: View {
    @Binding var entry: ResumeEntry
    var kind: SectionKind
    var isFirst: Bool
    var isLast: Bool
    var move: (Int) -> Void
    var delete: () -> Void
    @State private var showDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                    GridRow {
                        TextField(kind.titleLabel, text: $entry.title).textFieldStyle(.roundedBorder)
                        TextField(kind.organizationLabel, text: $entry.organization).textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        TextField("Location", text: $entry.location).textFieldStyle(.roundedBorder)
                        HStack {
                            TextField("Start (e.g. Jan 2019)", text: $entry.startDate).textFieldStyle(.roundedBorder)
                            TextField("End (or Present)", text: $entry.endDate).textFieldStyle(.roundedBorder)
                        }
                    }
                }
                VStack(spacing: 6) {
                    MoveButtons(isFirst: isFirst, isLast: isLast, move: move)
                    Button { entry.hidden.toggle() } label: {
                        Image(systemName: entry.hidden ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                    .help(entry.hidden ? "Hidden from this document. Click to show." : "Shown. Click to leave it off this document.")
                    Button(role: .destructive, action: delete) { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                        .help("Remove")
                }
            }
            if showDetails || !entry.details.isEmpty {
                TextField("Description (optional)", text: $entry.details, axis: .vertical)
                    .lineLimit(1...5)
                    .fieldBox()
            }
            BulletsEditor(bullets: $entry.bullets)
            HStack {
                Button {
                    entry.bullets.append(Bullet(text: ""))
                } label: { Label("Add Bullet", systemImage: "plus") }
                if entry.details.isEmpty && !showDetails {
                    Button("Add Description") { showDetails = true }
                }
            }
            .buttonStyle(.borderless)
            .font(.callout)
        }
        .opacity(entry.hidden ? 0.55 : 1)
    }
}

struct BulletsEditor: View {
    @Binding var bullets: [Bullet]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(bullets) { bullet in
                HStack(alignment: .top, spacing: 6) {
                    Text("•").foregroundStyle(.secondary).padding(.top, 4)
                    TextField("What you did and what came of it", text: elementBinding($bullets, bullet).text, axis: .vertical)
                        .lineLimit(1...6)
                        .fieldBox()
                    MoveButtons(isFirst: bullets.first?.id == bullet.id, isLast: bullets.last?.id == bullet.id) { delta in
                        move(bullet.id, by: delta)
                    }
                    .padding(.top, 3)
                    Button(role: .destructive) {
                        bullets.removeAll { $0.id == bullet.id }
                    } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                        .padding(.top, 3)
                        .help("Remove bullet")
                }
            }
        }
    }

    private func move(_ id: UUID, by delta: Int) {
        guard let i = bullets.firstIndex(where: { $0.id == id }) else { return }
        let j = i + delta
        guard bullets.indices.contains(j) else { return }
        bullets.swapAt(i, j)
    }
}

/// Skills and other short lists: one row per item, reorderable.
struct ListItemsEditor: View {
    @Binding var items: [String]
    var placeholder: String
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FlowLayout(spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(spacing: 3) {
                        Button { shift(index, -1) } label: { Image(systemName: "chevron.left") }
                            .disabled(index == 0)
                            .help("Move earlier")
                        Text(item)
                        Button { shift(index, 1) } label: { Image(systemName: "chevron.right") }
                            .disabled(index == items.count - 1)
                            .help("Move later")
                        Button { if items.indices.contains(index) { items.remove(at: index) } } label: { Image(systemName: "xmark") }
                            .help("Remove")
                    }
                    .buttonStyle(.plain)
                    .font(.callout)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Palette.accent.opacity(0.1)))
                }
            }
            HStack {
                TextField(placeholder, text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                Button("Add", action: add).disabled(draft.trimmed.isEmpty)
            }
            Text("Tip: paste several items separated by commas.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func shift(_ index: Int, _ delta: Int) {
        let j = index + delta
        guard items.indices.contains(index), items.indices.contains(j) else { return }
        items.swapAt(index, j)
    }

    private func add() {
        let parts = draft.components(separatedBy: CharacterSet(charactersIn: ",;")).map { $0.trimmed }.filter { !$0.isEmpty }
        for p in parts where !items.contains(where: { $0.caseInsensitiveCompare(p) == .orderedSame }) {
            items.append(p)
        }
        draft = ""
    }
}

struct NotesEditor: View {
    @Binding var notes: [ProfileNote]

    var body: some View {
        Card {
            HStack {
                Text("Notes for matching").font(.headline)
                Spacer()
                Button { notes.append(ProfileNote(topic: "", text: "")) } label: { Label("Add Note", systemImage: "plus") }
                    .buttonStyle(.borderless)
            }
            Text("Facts about your experience that aren't on the resume (for example, answers to follow-up questions). They count as evidence when comparing jobs but are never printed.")
                .font(.callout).foregroundStyle(.secondary)
            ForEach(notes) { note in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Topic", text: elementBinding($notes, note).topic).textFieldStyle(.roundedBorder)
                        TextField("What you did", text: elementBinding($notes, note).text, axis: .vertical).lineLimit(1...5).fieldBox()
                    }
                    Button(role: .destructive) { notes.removeAll { $0.id == note.id } } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                }
            }
        }
    }
}
