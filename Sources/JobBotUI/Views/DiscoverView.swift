import SwiftUI
import JobBotCore

/// Finding roles: search terms, locations, job sites (opened in your browser), and company
/// job boards with public feeds.
struct DiscoverView: View {
    @EnvironmentObject var app: AppModel
    @State private var companySearch = ""
    @State private var newCompany = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SectionTitle(title: "Find jobs",
                             subtitle: "Job Bot searches only through permitted sources: public company job-board feeds, and searches you open in your own browser. It never signs in for you or works around site protections.")
                HStack(alignment: .top, spacing: 16) {
                    Card {
                        Text("Search terms").font(.headline)
                        ChipEditor(items: $app.data.discovery.searchTerms, placeholder: "Add a job title or keyword")
                        if !app.data.pivots.titles.isEmpty {
                            Text("Pivot titles are searched too: " + app.data.pivots.titles.joined(separator: ", "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Card {
                        Text("Locations").font(.headline)
                        LocationFilterEditor(filter: $app.data.preferences.locations)
                    }
                }
                SitesCard()
                ResultsCard()
                CompaniesCard(search: $companySearch, newCompany: $newCompany)
            }
            .padding(20)
        }
        .navigationTitle("Find Jobs")
    }
}

struct LocationFilterEditor: View {
    @Binding var filter: LocationFilter
    @State private var newLocation = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("All", isOn: Binding(get: { filter.allSelected }, set: { filter.setAll($0) }))
                .toggleStyle(.checkbox)
                .fontWeight(.medium)
            ForEach(filter.options) { option in
                HStack {
                    Toggle(option.name, isOn: elementBinding($filter.options, option).selected).toggleStyle(.checkbox)
                    Spacer()
                    if !option.builtIn {
                        Button { filter.remove(option.id) } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                            .help("Remove \(option.name)")
                    }
                }
            }
            Toggle("Include postings with no location listed", isOn: $filter.includeUnlisted).toggleStyle(.checkbox).font(.callout)
            HStack {
                TextField("Add a location (e.g. Chicago)", text: $newLocation)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                Button("Add", action: add).disabled(newLocation.trimmed.isEmpty)
            }
            Text("Active: \(filter.summary)").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func add() {
        filter.add(newLocation)
        newLocation = ""
    }
}

struct SitesCard: View {
    @EnvironmentObject var app: AppModel
    @State private var editing = false

    var body: some View {
        Card {
            HStack {
                Text("Job sites").font(.headline)
                Spacer()
                Button(editing ? "Done" : "Edit Sites") { editing.toggle() }.buttonStyle(.borderless)
            }
            Text("These open in your browser with your search terms, so you browse them as yourself. When you find a role, copy its description into Jobs › Add Job.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if editing {
                ForEach(app.data.discovery.sites) { site in
                    let b = elementBinding($app.data.discovery.sites, site)
                    HStack {
                        Toggle("", isOn: b.enabled).labelsHidden()
                        TextField("Name", text: b.name).textFieldStyle(.roundedBorder).frame(width: 140)
                        TextField("Search URL with {keywords} and {location}", text: b.template).textFieldStyle(.roundedBorder)
                        Button { app.data.discovery.sites.removeAll { $0.id == site.id } } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                    }
                }
                Button { app.data.discovery.sites.append(SearchSite(name: "New site", template: "https://")) } label: {
                    Label("Add Site", systemImage: "plus")
                }
                .buttonStyle(.borderless)
            } else {
                let terms = app.data.discovery.searchTerms + app.data.pivots.titles
                ForEach(app.data.discovery.sites.filter { $0.enabled }) { site in
                    HStack(alignment: .firstTextBaseline) {
                        Text(site.name).font(.callout.weight(.semibold)).frame(width: 90, alignment: .leading)
                        FlowLayout {
                            ForEach(terms, id: \.self) { term in
                                Button(term) { app.openSearch(site, term: term) }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .help("Open a \(site.name) search for “\(term)” in your browser")
                            }
                        }
                    }
                }
            }
        }
    }
}

struct ResultsCard: View {
    @EnvironmentObject var app: AppModel

    var body: some View {
        Card {
            HStack {
                Text("Company job boards").font(.headline)
                Spacer()
                Button {
                    Task { await app.runDiscovery() }
                } label: {
                    Label("Search Connected Boards", systemImage: "arrow.clockwise")
                }
                .disabled(app.busy != nil)
            }
            Text("Searches public job-board feeds (Greenhouse, Lever, Ashby) for companies below that have one connected, filtered by your search terms and locations. Only a request for the job list is sent; nothing about you.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let busy = app.busy {
                HStack { ProgressView().controlSize(.small); Text(busy).font(.callout) }
            }
            if !app.discoveryLog.isEmpty {
                DisclosureGroup("Search details") {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(app.discoveryLog, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.callout)
            }
            if !app.discovered.isEmpty {
                HStack(spacing: 6) {
                    Text("Filters:").font(.caption).foregroundStyle(.secondary)
                    ForEach(app.data.preferences.locations.active) { loc in Pill(text: loc.name, color: Palette.accent) }
                }
                ForEach(app.discovered) { d in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(d.title).font(.callout.weight(.semibold))
                            Text([d.employer, d.location.isEmpty ? nil : d.location, d.posted.map { "updated \($0.shortDate)" }]
                                .compactMap { $0 }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                            Text("Source: \(d.source)").font(.caption2).foregroundStyle(.tertiary)
                        }
                        Spacer()
                        if let url = URL(string: d.url), !d.url.isEmpty {
                            Link(destination: url) { Image(systemName: "safari") }.help("Open the original posting")
                        }
                        Button("Save") { app.save(discovered: d) }
                    }
                    Divider()
                }
            }
        }
    }
}

struct CompaniesCard: View {
    @EnvironmentObject var app: AppModel
    @Binding var search: String
    @Binding var newCompany: String

    var body: some View {
        Card {
            HStack {
                Text("Companies (\(app.data.discovery.companies.count))").font(.headline)
                Spacer()
                TextField("Filter companies", text: $search).textFieldStyle(.roundedBorder).frame(width: 200)
            }
            Text("Add a careers page link to open it in your browser. “Find board” looks for a public job feed for that company and connects it if one exists.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ForEach(app.data.discovery.companies) { company in
                if search.trimmed.isEmpty || company.name.localizedCaseInsensitiveContains(search) {
                    CompanyRow(company: elementBinding($app.data.discovery.companies, company))
                    Divider()
                }
            }
            HStack {
                TextField("Add a company", text: $newCompany).textFieldStyle(.roundedBorder).onSubmit(add)
                Button("Add", action: add).disabled(newCompany.trimmed.isEmpty)
            }
        }
    }

    private func add() {
        let n = newCompany.trimmed
        guard !n.isEmpty else { return }
        app.data.discovery.companies.append(CompanySource(name: n))
        newCompany = ""
    }
}

struct CompanyRow: View {
    @EnvironmentObject var app: AppModel
    @Binding var company: CompanySource

    var body: some View {
        HStack(spacing: 8) {
            Toggle("", isOn: $company.enabled).labelsHidden().help("Include in searches")
            Text(company.name).frame(width: 190, alignment: .leading).lineLimit(1)
            TextField("Careers page link", text: $company.careersURL).textFieldStyle(.roundedBorder)
            if company.board != .none {
                Pill(text: "\(company.board.title): \(company.boardToken)", color: Palette.strong, symbol: "dot.radiowaves.left.and.right")
                Button { company.board = .none; company.boardToken = "" } label: { Image(systemName: "xmark.circle") }
                    .buttonStyle(.borderless)
                    .help("Disconnect this job board")
            } else {
                Button("Find Board") { Task { await app.findBoard(for: company.id) } }
                    .controlSize(.small)
                    .disabled(app.busy != nil)
            }
            Button { app.openCareers(company) } label: { Image(systemName: "safari") }
                .buttonStyle(.borderless)
                .help(company.careersURL.isEmpty ? "Search the web for \(company.name)'s careers page" : "Open the careers page")
            Button { app.data.discovery.companies.removeAll { $0.id == company.id } } label: { Image(systemName: "minus.circle") }
                .buttonStyle(.borderless)
                .help("Remove \(company.name)")
        }
    }
}
