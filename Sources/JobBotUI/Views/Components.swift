import SwiftUI
import PDFKit
import JobBotCore

enum Palette {
    static let accent = Color(red: 0.12, green: 0.37, blue: 0.48)
    static let strong = Color(red: 0.16, green: 0.55, blue: 0.33)
    static let partial = Color(red: 0.85, green: 0.55, blue: 0.10)
    static let gap = Color(red: 0.70, green: 0.25, blue: 0.22)
    static let card = Color(nsColor: .controlBackgroundColor)
    static let subtle = Color.primary.opacity(0.05)
}

extension MatchStrength {
    var color: Color {
        switch self {
        case .strong: return Palette.strong
        case .partial: return Palette.partial
        case .gap: return Palette.gap
        }
    }

    var symbol: String {
        switch self {
        case .strong: return "checkmark.circle.fill"
        case .partial: return "circle.lefthalf.filled"
        case .gap: return "questionmark.circle"
        }
    }
}

extension ApplicationStatus {
    var color: Color {
        switch self {
        case .saved: return .secondary
        case .preparing: return Palette.accent
        case .applied: return .blue
        case .interviewing: return .purple
        case .offer: return Palette.strong
        case .rejected, .withdrawn: return .gray
        case .archived: return .gray.opacity(0.6)
        }
    }

    var symbol: String {
        switch self {
        case .saved: return "bookmark"
        case .preparing: return "pencil.and.list.clipboard"
        case .applied: return "paperplane"
        case .interviewing: return "person.2"
        case .offer: return "star"
        case .rejected: return "xmark.circle"
        case .withdrawn: return "arrow.uturn.backward.circle"
        case .archived: return "archivebox"
        }
    }
}

/// A rounded panel.
struct Card<Content: View>: View {
    var padding: CGFloat = 14
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Palette.card))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08)))
    }
}

struct Pill: View {
    var text: String
    var color: Color = .secondary
    var symbol: String?

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).imageScale(.small) }
            Text(text).lineLimit(1)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .foregroundStyle(color)
        .background(Capsule().fill(color.opacity(0.12)))
    }
}

struct SectionTitle: View {
    var title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.title3.weight(.semibold))
            if let subtitle { Text(subtitle).font(.callout).foregroundStyle(.secondary) }
        }
    }
}

struct EmptyState: View {
    var symbol: String
    var title: String
    var message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 40)).foregroundStyle(.secondary)
            Text(title).font(.title3.weight(.semibold))
            Text(message).multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 420)
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(.borderedProminent).padding(.top, 4)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One profile detail shown as evidence, with where it came from.
struct EvidenceRow: View {
    var unit: ProfileUnit
    var terms: [String] = []

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "text.quote").foregroundStyle(Palette.accent).imageScale(.small).padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(unit.text).font(.callout).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                HStack(spacing: 6) {
                    Text(unit.location).font(.caption).foregroundStyle(.secondary)
                    if !terms.isEmpty {
                        Text("· shares: " + terms.prefix(4).joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

/// Wraps chips onto multiple lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 600
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += s.width + spacing
            maxX = max(maxX, x)
            rowHeight = max(rowHeight, s.height)
        }
        return CGSize(width: min(width, maxX), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX && x + s.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
    }
}

/// Editable list of short strings shown as chips.
struct ChipEditor: View {
    @Binding var items: [String]
    var placeholder: String
    var color: Color = Palette.accent
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FlowLayout {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(spacing: 4) {
                        Text(item)
                        Button {
                            if items.indices.contains(index) { items.remove(at: index) }
                        } label: {
                            Image(systemName: "xmark").imageScale(.small)
                        }
                        .buttonStyle(.plain)
                        .help("Remove “\(item)”")
                    }
                    .font(.callout)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(color.opacity(0.12)))
                    .foregroundStyle(color)
                }
            }
            HStack {
                TextField(placeholder, text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                Button("Add", action: add).disabled(draft.trimmed.isEmpty)
            }
        }
    }

    private func add() {
        let t = draft.trimmed
        guard !t.isEmpty, !items.contains(where: { $0.caseInsensitiveCompare(t) == .orderedSame }) else { draft = ""; return }
        items.append(t)
        draft = ""
    }
}

/// Shows a PDF made by Job Bot.
struct PDFPreview: NSViewRepresentable {
    var data: Data

    final class Coordinator {
        var shown = Data()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displaysPageBreaks = true
        view.backgroundColor = NSColor.windowBackgroundColor
        view.document = PDFDocument(data: data)
        context.coordinator.shown = data
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        guard context.coordinator.shown != data else { return }
        context.coordinator.shown = data
        // Keep the reader's place when the document is refreshed.
        let pageIndex = view.currentPage.flatMap { view.document?.index(for: $0) } ?? 0
        view.document = PDFDocument(data: data)
        if let page = view.document?.page(at: min(pageIndex, max(0, (view.document?.pageCount ?? 1) - 1))) {
            view.go(to: page)
        }
    }
}

/// Banner shown at the bottom of the window.
struct BannerView: View {
    var banner: Banner

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(banner.text).font(.callout).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(color.opacity(0.35)))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
        .frame(maxWidth: 560)
    }

    private var symbol: String {
        switch banner.kind {
        case .info: return "info.circle"
        case .success: return "checkmark.circle"
        case .warning: return "exclamationmark.triangle"
        }
    }

    private var color: Color {
        switch banner.kind {
        case .info: return Palette.accent
        case .success: return Palette.strong
        case .warning: return Palette.partial
        }
    }
}

extension Date {
    var shortDate: String { formatted(date: .abbreviated, time: .omitted) }
}

/// A binding to one element of an array, looked up by id each time. Safe when the element is
/// removed while its row is still on screen (unlike bindings by index).
func elementBinding<T: Identifiable>(_ array: Binding<[T]>, _ element: T) -> Binding<T> {
    let id = element.id
    return Binding(
        get: { array.wrappedValue.first { $0.id == id } ?? element },
        set: { value in
            if let i = array.wrappedValue.firstIndex(where: { $0.id == id }) { array.wrappedValue[i] = value }
        })
}

/// A box for multi-line text fields. (On macOS the rounded-border style keeps fields one line
/// tall; plain fields grow with their text.)
struct FieldBox: ViewModifier {
    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.15)))
    }
}

extension View {
    func fieldBox() -> some View { modifier(FieldBox()) }
}
