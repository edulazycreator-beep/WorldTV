import Combine
import Foundation

/// Global search with filters. Queries are debounced and evaluated off the
/// main actor so typing stays smooth with large catalogs.
@MainActor
final class SearchViewModel: ObservableObject {
    @Published var query = SearchQuery()
    @Published private(set) var results: [Channel] = []
    @Published private(set) var isSearching = false

    private let catalog: CatalogViewModel
    private var task: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    init(catalog: CatalogViewModel) {
        self.catalog = catalog
        $query
            .removeDuplicates()
            .debounce(for: .milliseconds(180), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.run() }
            .store(in: &cancellables)
        catalog.$channels
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.run() }
            }
            .store(in: &cancellables)
    }

    /// Search mode is driven by the search field; filters refine it.
    var isActive: Bool { !query.text.trimmingCharacters(in: .whitespaces).isEmpty }

    func reset() {
        query = SearchQuery()
        results = []
    }

    func run() {
        task?.cancel()
        guard isActive else {
            results = []
            isSearching = false
            return
        }
        let channels = catalog.channels
        let query = self.query
        let context = catalog.searchContext()
        isSearching = true
        task = Task { [weak self] in
            let found = await Task.detached(priority: .userInitiated) {
                SearchService.search(channels, query: query, context: context)
            }.value
            guard !Task.isCancelled else { return }
            self?.results = found
            self?.isSearching = false
        }
    }
}
