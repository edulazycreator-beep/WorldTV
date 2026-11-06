import Foundation

/// One `#EXTINF` entry (or bare URL line) from an M3U / M3U8 playlist.
struct M3UEntry: Hashable, Sendable {
    var name: String
    var url: URL
    var duration: Int
    var attributes: [String: String]
    var groupTitle: String?
    var referrer: String?
    var userAgent: String?

    var tvgID: String? { attributes["tvg-id"].nonEmpty }
    var tvgName: String? { attributes["tvg-name"].nonEmpty }
    var logo: URL? { attributes["tvg-logo"].nonEmpty.flatMap(URL.init(string:)) }
    var country: String? { attributes["tvg-country"].nonEmpty }
    var language: String? { attributes["tvg-language"].nonEmpty }
}

struct M3UPlaylist: Hashable, Sendable {
    var epgURLs: [URL]
    var entries: [M3UEntry]
    /// Lines that looked like stream entries but could not be parsed.
    var skippedLines: Int
}

enum M3UParserError: LocalizedError, Equatable {
    case empty
    case notAPlaylist
    case unreadableEncoding

    var errorDescription: String? {
        switch self {
        case .empty: return "The playlist is empty."
        case .notAPlaylist: return "This file doesn't look like an M3U playlist."
        case .unreadableEncoding: return "The playlist uses an unsupported text encoding."
        }
    }
}

/// Parser for extended M3U playlists as used by IPTV providers.
///
/// Supports `#EXTM3U` header attributes (`url-tvg`, `x-tvg-url`), `#EXTINF`
/// attributes (`tvg-id`, `tvg-name`, `tvg-logo`, `tvg-country`,
/// `tvg-language`, `group-title`), `#EXTGRP`, `#EXTVLCOPT` HTTP options and
/// Kodi-style `url|User-Agent=…&Referer=…` suffixes.
enum M3UParser {
    static func parse(data: Data) throws -> M3UPlaylist {
        guard !data.isEmpty else { throw M3UParserError.empty }
        let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
        guard let text else { throw M3UParserError.unreadableEncoding }
        return try parse(text: text)
    }

    static func parse(text rawText: String) throws -> M3UPlaylist {
        var text = rawText
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { throw M3UParserError.empty }

        let hasHeader = lines[0].uppercased().hasPrefix("#EXTM3U")
        let hasEntries = lines.contains { $0.uppercased().hasPrefix("#EXTINF") }
        let hasURLs = lines.contains { isStreamLine($0) }
        guard hasHeader || hasEntries || hasURLs else { throw M3UParserError.notAPlaylist }

        var epgURLs: [URL] = []
        var entries: [M3UEntry] = []
        var skipped = 0

        var pendingName: String?
        var pendingDuration = -1
        var pendingAttributes: [String: String] = [:]
        var pendingGroup: String?
        var pendingReferrer: String?
        var pendingUserAgent: String?

        func resetPending() {
            pendingName = nil
            pendingDuration = -1
            pendingAttributes = [:]
            pendingGroup = nil
            pendingReferrer = nil
            pendingUserAgent = nil
        }

        for line in lines {
            let upper = line.uppercased()
            if upper.hasPrefix("#EXTM3U") {
                let attributes = parseAttributes(String(line.dropFirst("#EXTM3U".count)))
                for key in ["url-tvg", "x-tvg-url", "tvg-url"] {
                    guard let value = attributes[key] else { continue }
                    for part in value.split(separator: ",") {
                        let trimmed = part.trimmingCharacters(in: .whitespaces)
                        if let url = URL(string: trimmed), url.scheme != nil, !epgURLs.contains(url) {
                            epgURLs.append(url)
                        }
                    }
                }
            } else if upper.hasPrefix("#EXTINF:") {
                if pendingName != nil { skipped += 1 } // previous EXTINF had no URL
                resetPending()
                let body = String(line.dropFirst("#EXTINF:".count))
                let (meta, title) = splitTitle(body)
                let durationText = meta.prefix { $0 == "-" || $0.isNumber }
                pendingDuration = Int(durationText) ?? -1
                pendingAttributes = parseAttributes(String(meta.dropFirst(durationText.count)))
                pendingName = title
                pendingGroup = pendingAttributes["group-title"].nonEmpty
            } else if upper.hasPrefix("#EXTGRP:") {
                pendingGroup = String(line.dropFirst("#EXTGRP:".count)).trimmingCharacters(in: .whitespaces).nonEmpty
            } else if upper.hasPrefix("#EXTVLCOPT:") {
                let option = String(line.dropFirst("#EXTVLCOPT:".count))
                if let value = optionValue(option, key: "http-referrer") { pendingReferrer = value }
                if let value = optionValue(option, key: "http-user-agent") { pendingUserAgent = value }
            } else if line.hasPrefix("#") {
                continue
            } else {
                // A URL line, possibly with Kodi-style header suffix.
                let (urlString, headers) = splitKodiHeaders(line)
                guard let url = URL(string: urlString), let scheme = url.scheme?.lowercased(),
                      ["http", "https", "rtmp", "rtsp", "file"].contains(scheme) else {
                    skipped += 1
                    resetPending()
                    continue
                }
                let fallbackName = url.deletingPathExtension().lastPathComponent
                let name = pendingName.nonEmpty
                    ?? pendingAttributes["tvg-name"].nonEmpty
                    ?? (fallbackName.isEmpty ? url.host ?? urlString : fallbackName)
                entries.append(M3UEntry(
                    name: name,
                    url: url,
                    duration: pendingDuration,
                    attributes: pendingAttributes,
                    groupTitle: pendingGroup,
                    referrer: pendingReferrer ?? headers["referer"] ?? headers["referrer"],
                    userAgent: pendingUserAgent ?? headers["user-agent"]
                ))
                resetPending()
            }
        }
        if pendingName != nil { skipped += 1 }

        return M3UPlaylist(epgURLs: epgURLs, entries: entries, skippedLines: skipped)
    }

    // MARK: Helpers

    private static func isStreamLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        return lower.hasPrefix("http://") || lower.hasPrefix("https://")
            || lower.hasPrefix("rtmp://") || lower.hasPrefix("rtsp://")
    }

    /// Splits `-1 tvg-id="x",Channel Name` into attributes part and title,
    /// ignoring commas that appear inside quoted attribute values.
    static func splitTitle(_ body: String) -> (meta: String, title: String) {
        var inQuotes = false
        for index in body.indices {
            let char = body[index]
            if char == "\"" { inQuotes.toggle() }
            if char == "," && !inQuotes {
                let meta = String(body[..<index])
                let title = String(body[body.index(after: index)...]).trimmingCharacters(in: .whitespaces)
                return (meta, title)
            }
        }
        return (body, "")
    }

    /// Parses `key="value" key2=value2` pairs. Keys are lower-cased.
    static func parseAttributes(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            while i < chars.count, chars[i].isWhitespace { i += 1 }
            let keyStart = i
            while i < chars.count, chars[i] != "=", !chars[i].isWhitespace { i += 1 }
            let key = String(chars[keyStart..<i]).lowercased()
            guard i < chars.count, chars[i] == "=" else {
                i += 1
                continue
            }
            i += 1 // skip '='
            var value = ""
            if i < chars.count, chars[i] == "\"" || chars[i] == "'" {
                let quote = chars[i]
                i += 1
                let valueStart = i
                while i < chars.count, chars[i] != quote { i += 1 }
                value = String(chars[valueStart..<min(i, chars.count)])
                i += 1
            } else {
                let valueStart = i
                while i < chars.count, !chars[i].isWhitespace { i += 1 }
                value = String(chars[valueStart..<i])
            }
            if !key.isEmpty { result[key] = value.trimmingCharacters(in: .whitespaces) }
        }
        return result
    }

    private static func optionValue(_ option: String, key: String) -> String? {
        let parts = option.split(separator: "=", maxSplits: 1).map(String.init)
        guard parts.count == 2, parts[0].lowercased() == key else { return nil }
        return parts[1].trimmingCharacters(in: .whitespaces).nonEmpty
    }

    private static func splitKodiHeaders(_ line: String) -> (String, [String: String]) {
        guard let pipe = line.firstIndex(of: "|") else { return (line, [:]) }
        let urlPart = String(line[..<pipe])
        var headers: [String: String] = [:]
        for pair in line[line.index(after: pipe)...].split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard kv.count == 2 else { continue }
            let value = kv[1].removingPercentEncoding ?? kv[1]
            headers[kv[0].lowercased()] = value
        }
        return (urlPart, headers)
    }
}

// MARK: - Conversion to catalog channels

extension M3UPlaylist {
    /// Converts entries into catalog channels for a playlist. Entries that share
    /// a `tvg-id` (or name, when there is no ID) become one channel with
    /// several stream sources. IDs are stable across playlist updates so
    /// favorites survive a refresh.
    func channels(playlistID: UUID, playlistName: String, knownCategoryIDs: Set<String>) -> [Channel] {
        var order: [String] = []
        var byKey: [String: Channel] = [:]

        for entry in entries {
            let rawKey = (entry.tvgID ?? entry.name).lowercased()
            let key = "pl:\(playlistID.uuidString):\(rawKey)"
            let stream = StreamSource(url: entry.url, title: entry.name,
                                      quality: Self.qualityHint(in: entry.name),
                                      referrer: entry.referrer, userAgent: entry.userAgent)
            if var existing = byKey[key] {
                if !existing.streams.contains(where: { $0.url == stream.url }) {
                    existing.streams.append(stream)
                }
                byKey[key] = existing
                continue
            }
            let groups = (entry.groupTitle ?? "")
                .split(whereSeparator: { $0 == ";" || $0 == "|" })
                .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                .filter { !$0.isEmpty }
            let categories = groups.map { group -> String in
                if knownCategoryIDs.contains(group) { return group }
                if let match = knownCategoryIDs.first(where: { group.contains($0) }) { return match }
                return group
            }
            let country = entry.country?
                .split(whereSeparator: { $0 == ";" || $0 == "," })
                .first.map { $0.trimmingCharacters(in: .whitespaces).uppercased() }
                .flatMap { $0.count == 2 ? $0 : nil }
            let languages = (entry.language ?? "")
                .split(whereSeparator: { $0 == ";" || $0 == "," })
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            let channel = Channel(
                id: key,
                name: entry.tvgName ?? entry.name,
                altNames: entry.tvgName != nil && entry.tvgName != entry.name ? [entry.name] : [],
                countryCode: country,
                languages: languages,
                categories: categories.uniqued(),
                logoURL: entry.logo,
                streams: [stream],
                origin: .playlist(playlistID),
                attribution: "Imported playlist “\(playlistName)”",
                usageNotes: "Provided by the user. Make sure you are authorized to use this playlist.",
                epgID: entry.tvgID,
                popularity: 0,
                firstSeen: Date()
            )
            order.append(key)
            byKey[key] = channel
        }
        return order.compactMap { byKey[$0] }
    }

    static func qualityHint(in name: String) -> String? {
        let lower = name.lowercased()
        for (needle, label) in [("2160", "2160p"), ("4k", "2160p"), ("1080", "1080p"),
                                ("720", "720p"), ("576", "576p"), ("480", "480p"), ("360", "360p")]
        where lower.contains(needle) {
            return label
        }
        return nil
    }
}

extension Optional where Wrapped == String {
    /// Nil for nil, empty or whitespace-only strings.
    var nonEmpty: String? {
        guard let value = self?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}

extension String {
    var nonEmpty: String? { (self as String?).nonEmpty }
}
