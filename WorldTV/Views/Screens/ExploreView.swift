import SwiftUI

struct ExploreView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case countries = "Countries", continents = "Continents", categories = "Categories", languages = "Languages"
        var id: String { rawValue }
    }

    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var catalog: CatalogViewModel
    @State private var mode: Mode = .countries
    @State private var filter = ""

    var body: some View {
        NavigationStack(path: $model.explorePath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack {
                        Picker("Browse", selection: $mode) {
                            ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(maxWidth: 460)
                        Spacer()
                        if mode == .countries || mode == .languages {
                            TextField("Filter", text: $filter)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 200)
                        }
                    }
                    switch mode {
                    case .countries: countries
                    case .continents: continents
                    case .categories: categories
                    case .languages: languages
                    }
                }
                .padding(28)
            }
            .background(Theme.backdrop.ignoresSafeArea())
            .navigationTitle("Explore")
            .navigationDestination(for: ExploreDestination.self) { destination in
                ChannelBrowserView(destination: destination)
            }
        }
    }

    private let tileColumns = [GridItem(.adaptive(minimum: 190), spacing: 14)]

    @ViewBuilder
    private var countries: some View {
        let featuredCodes = Country.featuredCodes
        let featured = featuredCodes.compactMap { code in catalog.countries.first { $0.code == code } }
        let others = catalog.countries
            .filter { !featuredCodes.contains($0.code) }
            .filter { filter.isEmpty || $0.name.localizedCaseInsensitiveContains(filter) }

        if filter.isEmpty && !featured.isEmpty {
            SectionHeader(title: "Featured Countries")
            LazyVGrid(columns: tileColumns, spacing: 14) {
                ForEach(featured) { country in countryTile(country) }
            }
        }
        SectionHeader(title: filter.isEmpty ? "All Countries" : "Matching Countries",
                      subtitle: "\(catalog.countries.count) countries with available channels")
        if catalog.countries.isEmpty {
            EmptyStateView(symbol: "globe", title: "No countries yet",
                           message: "The channel directory hasn't loaded. Check your connection or import a playlist.")
        }
        LazyVGrid(columns: tileColumns, spacing: 14) {
            ForEach(filter.isEmpty ? others : catalog.countries.filter { $0.name.localizedCaseInsensitiveContains(filter) }) {
                countryTile($0)
            }
        }
    }

    private func countryTile(_ country: Country) -> some View {
        Button { model.explorePath.append(.country(country.code)) } label: {
            BrowseTile(leading: Text(country.flag).font(.system(size: 28)),
                       title: country.name,
                       subtitle: "\(catalog.channelCount(country: country.code)) channels")
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("country-\(country.code)")
    }

    private var continents: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 14)], spacing: 14) {
            ForEach(Continent.allCases) { continent in
                let count = catalog.channelCount(continent: continent)
                if count > 0 {
                    Button { model.explorePath.append(.continent(continent)) } label: {
                        BrowseTile(leading: Image(systemName: continent.symbol)
                                    .font(.system(size: 26)).foregroundStyle(Theme.brandGradient),
                                   title: continent.displayName,
                                   subtitle: "\(count) channels")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var categories: some View {
        let featured = ChannelCategory.featuredIDs
        let sorted = catalog.categories.sorted { lhs, rhs in
            let l = featured.firstIndex(of: lhs.id) ?? Int.max
            let r = featured.firstIndex(of: rhs.id) ?? Int.max
            return l == r ? lhs.name < rhs.name : l < r
        }
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 14)], spacing: 14) {
            ForEach(sorted) { category in
                Button { model.explorePath.append(.category(category.id)) } label: {
                    CategoryTile(category: category, count: catalog.channelCount(category: category.id))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var languages: some View {
        let list = catalog.languages.filter { filter.isEmpty || $0.name.localizedCaseInsensitiveContains(filter) }
        return LazyVGrid(columns: tileColumns, spacing: 14) {
            ForEach(list) { language in
                Button { model.explorePath.append(.language(language.code)) } label: {
                    BrowseTile(leading: Image(systemName: "character.bubble.fill")
                                .font(.system(size: 22)).foregroundStyle(Theme.brandGradient),
                               title: language.name, subtitle: language.code)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct BrowseTile<Leading: View>: View {
    let leading: Leading
    let title: String
    let subtitle: String
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 12) {
            leading.frame(width: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(14)
        .card(hovered: hovered)
        .contentShape(Rectangle())
        .onHover { isHovering in withAnimation(.easeOut(duration: 0.15)) { hovered = isHovering } }
    }
}

/// Channel list for one country / continent / category / language, with
/// secondary filters, sorting and grid/list layouts.
struct ChannelBrowserView: View {
    let destination: ExploreDestination

    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var catalog: CatalogViewModel
    @State private var sort: SearchSort = .popularity
    @State private var categoryFilter: String?
    @State private var languageFilter: String?
    @State private var textFilter = ""
    @State private var asList = false

    var body: some View {
        let channels = results
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header(count: channels.count)
                if channels.isEmpty {
                    EmptyStateView(symbol: "tv.slash", title: "No channels",
                                   message: "Nothing matches these filters.")
                } else if asList {
                    LazyVStack(spacing: 0) {
                        ForEach(channels) { channel in
                            Button { model.play(channel, in: channels, title: title) } label: {
                                ChannelRow(channel: channel).padding(.horizontal, 8)
                            }
                            .buttonStyle(.plain)
                            .contextMenu { ChannelContextMenu(channel: channel) { model.play(channel, in: channels, title: title) } }
                            Divider()
                        }
                    }
                    .card()
                } else {
                    ChannelGrid(channels: channels) { model.play($0, in: channels, title: title) }
                }
            }
            .padding(28)
        }
        .background(Theme.backdrop.ignoresSafeArea())
        .navigationTitle(title)
        .toolbar {
            ToolbarItemGroup {
                Picker("Sort", selection: $sort) {
                    ForEach(SearchSort.allCases.filter { $0 != .relevance }) { Text($0.title).tag($0) }
                }
                .help("Sort channels")
                Picker("Layout", selection: $asList) {
                    Image(systemName: "square.grid.2x2").tag(false)
                    Image(systemName: "list.bullet").tag(true)
                }
                .pickerStyle(.segmented)
                .help("Grid or list")
            }
        }
    }

    private func header(count: Int) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.largeTitle.weight(.bold))
                Text("\(count) channels").foregroundStyle(.secondary)
            }
            Spacer()
            TextField("Filter", text: $textFilter).textFieldStyle(.roundedBorder).frame(width: 180)
            if !isCategory {
                Picker("Category", selection: $categoryFilter) {
                    Text("All Categories").tag(String?.none)
                    ForEach(catalog.categories) { Text($0.name).tag(Optional($0.id)) }
                }
                .frame(width: 180)
            }
            if !isLanguage {
                Picker("Language", selection: $languageFilter) {
                    Text("All Languages").tag(String?.none)
                    ForEach(catalog.languages) { Text($0.name).tag(Optional($0.code)) }
                }
                .frame(width: 180)
            }
        }
    }

    private var isCategory: Bool { if case .category = destination { return true }; return false }
    private var isLanguage: Bool { if case .language = destination { return true }; return false }

    private var title: String {
        switch destination {
        case .country(let code):
            let country = catalog.country(code)
            return [country?.flag, country?.name ?? Locale.countryName(for: code)].compactMap { $0 }.joined(separator: " ")
        case .continent(let continent): return continent.displayName
        case .category(let id): return catalog.categoryName(id)
        case .language(let code): return catalog.languageName(code)
        }
    }

    private var results: [Channel] {
        var query = SearchQuery()
        query.text = textFilter
        query.sort = textFilter.isEmpty ? sort : .relevance
        query.categoryID = categoryFilter
        query.languageCode = languageFilter
        switch destination {
        case .country(let code): query.countryCode = code
        case .continent(let continent): query.continent = continent
        case .category(let id): query.categoryID = id
        case .language(let code): query.languageCode = code
        }
        return SearchService.search(catalog.channels, query: query, context: catalog.searchContext())
    }
}
