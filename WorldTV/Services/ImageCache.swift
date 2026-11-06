import AppKit
import SwiftUI

/// Two-level logo cache: decoded images in memory (NSCache, auto-evicting)
/// and raw bytes on disk via the shared URLCache. Concurrent requests for the
/// same URL share one download.
actor ImageCache {
    static let shared = ImageCache()

    private let memory: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>()
        cache.countLimit = 600
        cache.totalCostLimit = 64 * 1024 * 1024
        return cache
    }()
    private var inFlight: [URL: Task<NSImage?, Never>] = [:]
    private var failures: Set<URL> = []
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        configuration.urlCache = URLCache(memoryCapacity: 8 * 1024 * 1024, diskCapacity: 128 * 1024 * 1024)
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: configuration)
    }()

    func cachedImage(for url: URL) -> NSImage? {
        memory.object(forKey: url as NSURL)
    }

    func image(for url: URL) async -> NSImage? {
        if let cached = memory.object(forKey: url as NSURL) { return cached }
        if failures.contains(url) { return nil }
        if let task = inFlight[url] { return await task.value }

        let session = self.session
        let task = Task<NSImage?, Never> {
            guard let (data, response) = try? await session.data(from: url),
                  (response as? HTTPURLResponse).map({ (200...299).contains($0.statusCode) }) ?? true,
                  let image = NSImage(data: data) else { return nil }
            return image
        }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil
        if let image {
            memory.setObject(image, forKey: url as NSURL, cost: Self.cost(of: image))
        } else {
            failures.insert(url)
        }
        return image
    }

    private static func cost(of image: NSImage) -> Int {
        Int(image.size.width * image.size.height * 4)
    }
}

/// A channel logo with a monogram placeholder while loading or on failure.
struct ChannelLogoView: View {
    let channel: Channel
    var size: CGFloat = 44
    var cornerRadius: CGFloat = 10

    @State private var image: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Theme.logoBackground)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .padding(size * 0.12)
            } else {
                Text(monogram)
                    .font(.system(size: size * 0.34, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: channel.logoURL) {
            guard let url = channel.logoURL else { image = nil; return }
            if let cached = await ImageCache.shared.cachedImage(for: url) {
                image = cached
                return
            }
            image = await ImageCache.shared.image(for: url)
        }
        .accessibilityHidden(true)
    }

    private var monogram: String {
        let words = channel.name.split(separator: " ").prefix(2)
        let letters = words.compactMap { $0.first }.map(String.init).joined()
        return letters.isEmpty ? "TV" : letters.uppercased()
    }
}
