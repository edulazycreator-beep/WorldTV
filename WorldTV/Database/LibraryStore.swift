import Foundation

/// Owns the user's favorites, history, groups and settings, and persists every
/// change to disk (debounced) through `JSONFileStore`.
@MainActor
final class LibraryStore: ObservableObject {
    static let libraryFile = "library.json"
    static let settingsFile = "settings.json"

    @Published private(set) var library = UserLibrary()
    @Published var settings = AppSettings() {
        didSet { scheduleSave() }
    }
    @Published private(set) var lastError: String?

    private let store: JSONFileStore
    private var saveTask: Task<Void, Never>?
    private var isLoading = false

    init(store: JSONFileStore) {
        self.store = store
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            if let saved = try await store.load(UserLibrary.self, from: Self.libraryFile) { library = saved }
        } catch {
            lastError = "Your library could not be read and was reset: \(error.localizedDescription)"
        }
        do {
            if let saved = try await store.load(AppSettings.self, from: Self.settingsFile) { settings = saved }
        } catch {
            lastError = "Settings could not be read and were reset: \(error.localizedDescription)"
        }
    }

    // MARK: Mutations

    func isFavorite(_ channel: Channel) -> Bool { library.isFavorite(channel.id) }

    func toggleFavorite(_ channel: Channel) {
        library.toggleFavorite(channel.id)
        scheduleSave()
    }

    @discardableResult
    func recordPlay(_ channel: Channel) -> UUID {
        let id = library.recordPlay(channelID: channel.id, channelName: channel.name)
        scheduleSave()
        return id
    }

    func finishSession(_ id: UUID) {
        library.finishSession(id)
        scheduleSave()
    }

    func clearHistory() {
        library.clearHistory()
        scheduleSave()
    }

    @discardableResult
    func createGroup(named name: String) -> ChannelGroup {
        let group = library.createGroup(named: name)
        scheduleSave()
        return group
    }

    func renameGroup(_ id: UUID, to name: String) {
        library.renameGroup(id, to: name)
        scheduleSave()
    }

    func deleteGroup(_ id: UUID) {
        library.deleteGroup(id)
        scheduleSave()
    }

    func toggle(_ channel: Channel, inGroup id: UUID) {
        library.toggle(channelID: channel.id, inGroup: id)
        scheduleSave()
    }

    // MARK: Persistence

    private func scheduleSave() {
        guard !isLoading else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            await self?.flush()
        }
    }

    /// Writes immediately. Called on quit and from tests.
    func flush() async {
        let library = self.library
        let settings = self.settings
        do {
            try await store.save(library, to: Self.libraryFile)
            try await store.save(settings, to: Self.settingsFile)
            lastError = nil
        } catch {
            lastError = "Could not save your library: \(error.localizedDescription)"
        }
    }
}
