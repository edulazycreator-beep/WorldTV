import Foundation

/// Atomic JSON persistence in the app's Application Support container.
///
/// The app targets macOS 13, where SwiftData isn't available; Codable files are
/// simple, inspectable and easy to migrate. All I/O happens off the main actor.
actor JSONFileStore {
    let directory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(directory: URL) {
        self.directory = directory
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    /// `~/Library/Containers/<bundle id>/Data/Library/Application Support/WorldTV`
    /// when sandboxed.
    static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("WorldTV", isDirectory: true)
    }

    func url(for name: String) -> URL {
        directory.appendingPathComponent(name)
    }

    func load<T: Decodable>(_ type: T.Type, from name: String) throws -> T? {
        let fileURL = url(for: name)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(T.self, from: data)
    }

    func save<T: Encodable>(_ value: T, to name: String) throws {
        let data = try encoder.encode(value)
        try writeData(data, to: name)
    }

    func loadData(_ name: String) -> Data? {
        try? Data(contentsOf: url(for: name))
    }

    func writeData(_ data: Data, to name: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: url(for: name), options: [.atomic])
    }

    func modificationDate(of name: String) -> Date? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url(for: name).path)
        return attributes?[.modificationDate] as? Date
    }

    func remove(_ name: String) {
        try? FileManager.default.removeItem(at: url(for: name))
    }
}
