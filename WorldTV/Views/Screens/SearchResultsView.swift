import SwiftUI

/// Global search results with filters for country, continent, language,
/// category and sort order.
struct SearchResultsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var catalog: CatalogViewModel
    @EnvironmentObject private var search: SearchViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            filters
                .padding(.horizontal, 28)
                .padding(.vertical, 14)
            Divider()
            if search.results.isEmpty {
                if search.isSearching {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    EmptyStateView(symbol: "magnifyingglass", title: "No results",
                                   message: "Try a channel name, a country (“Japan”), a language (“Malay”) or a category (“news”).")
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("\(search.results.count) channels").font(.headline).foregroundStyle(.secondary)
                        ChannelGrid(channels: Array(search.results.prefix(400))) { channel in
                            model.play(channel, in: Array(search.results.prefix(400)), title: "Search")
                        }
                        if search.results.count > 400 {
                            Text("Showing the first 400 results. Refine your search or add a filter.")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    .padding(28)
                }
            }
        }
        .navigationTitle("Search")
        .accessibilityIdentifier("search-results")
    }

    private var filters: some View {
        HStack(spacing: 10) {
            Picker("Country", selection: $search.query.countryCode) {
                Text("Any country").tag(String?.none)
                ForEach(catalog.countries) { Text("\($0.flag) \($0.name)").tag(Optional($0.code)) }
            }
            .labelsHidden()
            .frame(maxWidth: 200)
            Picker("Continent", selection: $search.query.continent) {
                Text("Any continent").tag(Continent?.none)
                ForEach(Continent.allCases) { Text($0.displayName).tag(Optional($0)) }
            }
            .labelsHidden()
            .frame(maxWidth: 190)
            Picker("Language", selection: $search.query.languageCode) {
                Text("Any language").tag(String?.none)
                ForEach(catalog.languages) { Text($0.name).tag(Optional($0.code)) }
            }
            .labelsHidden()
            .frame(maxWidth: 190)
            Picker("Category", selection: $search.query.categoryID) {
                Text("Any category").tag(String?.none)
                ForEach(catalog.categories) { Text($0.name).tag(Optional($0.id)) }
            }
            .labelsHidden()
            .frame(maxWidth: 190)
            Spacer()
            Toggle("Favorites only", isOn: $search.query.onlyFavorites)
            Picker("Sort", selection: $search.query.sort) {
                ForEach(SearchSort.allCases) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .frame(maxWidth: 170)
            if search.query.hasFilters {
                Button("Clear") {
                    let text = search.query.text
                    search.query = SearchQuery()
                    search.query.text = text
                }
            }
        }
        .controlSize(.regular)
    }
}
