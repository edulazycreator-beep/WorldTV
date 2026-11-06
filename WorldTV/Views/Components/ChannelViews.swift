import AppKit
import SwiftUI

/// Grid card: logo on a tinted backdrop, name, country and quality.
struct ChannelCard: View {
    let channel: Channel
    var onPlay: () -> Void

    @EnvironmentObject private var catalog: CatalogViewModel
    @EnvironmentObject private var library: LibraryStore
    @State private var hovered = false

    var body: some View {
        Button(action: onPlay) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    LinearGradient(colors: [Theme.tint(for: channel.id).opacity(0.85), Theme.surface],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    ChannelLogoView(channel: channel, size: 64, cornerRadius: 14)
                        .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
                    VStack {
                        HStack(spacing: 4) {
                            if library.library.isFavorite(channel.id) {
                                Image(systemName: "star.fill").font(.caption).foregroundStyle(.yellow)
                            }
                            Spacer()
                            if let quality = channel.bestQualityLabel { Pill(text: quality) }
                        }
                        Spacer()
                        if hovered {
                            HStack {
                                Spacer()
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 26))
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, Theme.accent)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                    }
                    .padding(8)
                }
                .frame(height: 112)
                .clipped()

                VStack(alignment: .leading, spacing: 3) {
                    Text(channel.name)
                        .font(.headline)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        if let country = catalog.country(channel.countryCode) { Text(country.flag) }
                        Text(subtitle)
                            .lineLimit(1)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .card(hovered: hovered)
            .scaleEffect(hovered ? 1.025 : 1)
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) { hovered = isHovering }
        }
        .contextMenu { ChannelContextMenu(channel: channel, onPlay: onPlay) }
        .help(channel.name)
        .accessibilityLabel("\(channel.name), \(subtitle)")
        .accessibilityIdentifier("channel-card-\(channel.id)")
    }

    private var subtitle: String {
        let country = channel.countryCode.map { catalog.countryName($0) } ?? "International"
        if let category = channel.primaryCategory {
            return "\(country) · \(catalog.categoryName(category))"
        }
        return country
    }
}

/// Compact list row used in channel lists and search results.
struct ChannelRow: View {
    let channel: Channel
    var isPlaying = false
    var showProgramme = true

    @EnvironmentObject private var catalog: CatalogViewModel
    @EnvironmentObject private var library: LibraryStore

    var body: some View {
        HStack(spacing: 10) {
            ChannelLogoView(channel: channel, size: 36, cornerRadius: 8)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(channel.name).font(.body.weight(isPlaying ? .semibold : .regular)).lineLimit(1)
                    if library.library.isFavorite(channel.id) {
                        Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow)
                    }
                }
                if showProgramme, let programme = catalog.currentProgramme(for: channel) {
                    Text(programme.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                } else {
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if isPlaying {
                Image(systemName: "waveform")
                    .foregroundStyle(Theme.accent)
                    .accessibilityLabel("Now playing")
            } else if let quality = channel.bestQualityLabel {
                Pill(text: quality)
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }

    private var detail: String {
        var parts: [String] = []
        if let country = catalog.country(channel.countryCode) { parts.append("\(country.flag) \(country.name)") }
        if let category = channel.primaryCategory { parts.append(catalog.categoryName(category)) }
        return parts.isEmpty ? channel.attribution : parts.joined(separator: " · ")
    }
}

struct ChannelContextMenu: View {
    let channel: Channel
    var onPlay: () -> Void

    @EnvironmentObject private var library: LibraryStore

    var body: some View {
        Button("Play", action: onPlay)
        Button(library.library.isFavorite(channel.id) ? "Remove from Favorites" : "Add to Favorites") {
            library.toggleFavorite(channel)
        }
        if !library.library.groups.isEmpty {
            Menu("Groups") {
                ForEach(library.library.groups) { group in
                    Button {
                        library.toggle(channel, inGroup: group.id)
                    } label: {
                        if group.channelIDs.contains(channel.id) {
                            Label(group.name, systemImage: "checkmark")
                        } else {
                            Text(group.name)
                        }
                    }
                }
            }
        }
        Divider()
        if let website = channel.website {
            Link("Open Broadcaster Website", destination: website)
        }
        if let stream = channel.primaryStream {
            Button("Copy Stream Address") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(stream.url.absoluteString, forType: .string)
            }
        }
    }
}

/// Adaptive grid of channel cards.
struct ChannelGrid: View {
    let channels: [Channel]
    var onPlay: (Channel) -> Void

    private let columns = [GridItem(.adaptive(minimum: 180, maximum: 240), spacing: Theme.gridSpacing)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: Theme.gridSpacing) {
            ForEach(channels) { channel in
                ChannelCard(channel: channel) { onPlay(channel) }
            }
        }
    }
}

/// Horizontally scrolling row of cards ("shelf"), Apple TV style.
struct ChannelShelf: View {
    let title: String
    var subtitle: String?
    let channels: [Channel]
    var onPlay: (Channel) -> Void
    var onSeeAll: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: title, subtitle: subtitle,
                          actionTitle: onSeeAll == nil ? nil : "See All", action: onSeeAll)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: Theme.gridSpacing) {
                    ForEach(channels) { channel in
                        ChannelCard(channel: channel) { onPlay(channel) }
                            .frame(width: 200)
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 2)
            }
        }
    }
}
