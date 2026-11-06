import Foundation
import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case home, explore, live, guide, favorites, playlists, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .explore: return "Explore"
        case .live: return "Live TV"
        case .guide: return "TV Guide"
        case .favorites: return "Favorites"
        case .playlists: return "Playlists"
        case .settings: return "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .home: return "house.fill"
        case .explore: return "globe"
        case .live: return "play.tv.fill"
        case .guide: return "list.bullet.rectangle.portrait.fill"
        case .favorites: return "star.fill"
        case .playlists: return "music.note.list"
        case .settings: return "gearshape.fill"
        }
    }

    /// ⌘1…⌘7
    var shortcut: KeyEquivalent { KeyEquivalent(Character("\((SidebarItem.allCases.firstIndex(of: self) ?? 0) + 1)")) }
}

/// Drill-down destinations inside Explore.
enum ExploreDestination: Hashable {
    case country(String)
    case continent(Continent)
    case category(String)
    case language(String)
}

/// Composition root: builds the services and view models once and wires
/// their dependencies (constructor injection throughout).
@MainActor
final class AppModel: ObservableObject {
    @Published var selection: SidebarItem? = .home
    @Published var explorePath: [ExploreDestination] = []
    @Published var searchText = "" {
        didSet { search.query.text = searchText }
    }

    let library: LibraryStore
    let catalog: CatalogViewModel
    let live: LiveTVViewModel
    let search: SearchViewModel
    let isUITesting: Bool

    init(library: LibraryStore, catalog: CatalogViewModel, live: LiveTVViewModel,
         search: SearchViewModel, isUITesting: Bool) {
        self.library = library
        self.catalog = catalog
        self.live = live
        self.search = search
        self.isUITesting = isUITesting
    }

    static func make(arguments: [String] = ProcessInfo.processInfo.arguments) -> AppModel {
        let isUITesting = arguments.contains("-ui-testing")
        let directory = isUITesting
            ? FileManager.default.temporaryDirectory.appendingPathComponent("WorldTV-UITests-\(UUID().uuidString)")
            : JSONFileStore.defaultDirectory()
        let store = JSONFileStore(directory: directory)
        let client = URLSessionHTTPClient()
        let library = LibraryStore(store: store)
        let repository = CatalogRepository(api: DirectoryAPI(client: client), store: store)
        let catalog = CatalogViewModel(
            repository: repository,
            store: store,
            playlistService: PlaylistService(client: client),
            validator: StreamValidator(client: client),
            library: library,
            networkEnabled: !isUITesting
        )
        let live = LiveTVViewModel(player: PlayerController(), library: library)
        let search = SearchViewModel(catalog: catalog)
        return AppModel(library: library, catalog: catalog, live: live, search: search, isUITesting: isUITesting)
    }

    func start() async {
        await library.load()
        await catalog.start()
    }

    func play(_ channel: Channel, in list: [Channel]? = nil, title: String? = nil) {
        live.play(channel, in: list, title: title)
        selection = .live
    }

    func explore(_ destination: ExploreDestination) {
        explorePath = [destination]
        selection = .explore
    }

    func clearSearch() {
        searchText = ""
        search.reset()
    }
}
