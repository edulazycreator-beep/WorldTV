import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var catalog: CatalogViewModel
    @EnvironmentObject private var library: LibraryStore

    var body: some View {
        Group {
            if catalog.channels.isEmpty {
                emptyState
            } else {
                content
            }
        }
        .navigationTitle("Home")
    }

    @ViewBuilder
    private var emptyState: some View {
        switch catalog.directoryState {
        case .loading, .idle:
            VStack(spacing: 14) {
                ProgressView()
                Text("Loading the world's channels…").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            EmptyStateView(symbol: "wifi.exclamationmark", title: "Couldn't load the channel directory",
                           message: message + " You can retry, or import your own playlist.",
                           actionTitle: "Try Again") {
                Task { await catalog.refreshDirectory() }
            }
        case .loaded:
            EmptyStateView(symbol: "tv", title: "No channels yet",
                           message: "Enable the public directory in Settings or import an M3U playlist.",
                           actionTitle: "Open Playlists") { model.selection = .playlists }
        }
    }

    private var content: some View {
        let featured = catalog.featured()
        let recent = catalog.channels(ids: library.library.recentChannelIDs(limit: 16))
        let popular = catalog.popular()
        let added = catalog.recentlyAdded()

        return ScrollView {
            VStack(alignment: .leading, spacing: 34) {
                if let hero = featured.first {
                    HeroBanner(channel: hero) { model.play(hero, in: featured, title: "Featured") }
                }
                if featured.count > 1 {
                    ChannelShelf(title: "Featured", subtitle: "A daily pick from around the world",
                                 channels: Array(featured.dropFirst())) {
                        model.play($0, in: featured, title: "Featured")
                    }
                }
                if !recent.isEmpty {
                    ChannelShelf(title: "Recently Watched", channels: recent) {
                        model.play($0, in: recent, title: "Recently Watched")
                    }
                }
                ChannelShelf(title: "Popular", subtitle: "Well-sourced channels and the ones you watch most",
                             channels: popular) {
                    model.play($0, in: popular, title: "Popular")
                }
                if !added.isEmpty {
                    ChannelShelf(title: "Recently Added", channels: added) {
                        model.play($0, in: added, title: "Recently Added")
                    }
                }
                CategoryStrip()
            }
            .padding(28)
        }
        .background(Theme.backdrop.ignoresSafeArea())
    }
}

private struct HeroBanner: View {
    let channel: Channel
    var onPlay: () -> Void
    @EnvironmentObject private var catalog: CatalogViewModel
    @State private var hovered = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [Theme.tint(for: channel.id), Theme.accentSecondary.opacity(0.35), Theme.surface],
                           startPoint: .topTrailing, endPoint: .bottomLeading)
            HStack {
                Spacer()
                ChannelLogoView(channel: channel, size: 150, cornerRadius: 30)
                    .shadow(color: .black.opacity(0.4), radius: 24, y: 12)
                    .padding(.trailing, 48)
                    .scaleEffect(hovered ? 1.04 : 1)
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Pill(text: "Live", color: Theme.live, foreground: .white)
                    if let country = catalog.country(channel.countryCode) {
                        Text("\(country.flag) \(country.name)").font(.subheadline.weight(.medium))
                    }
                }
                Text(channel.name)
                    .font(.system(size: 38, weight: .heavy, design: .rounded))
                    .lineLimit(2)
                if let programme = catalog.currentProgramme(for: channel) {
                    Text("Now: \(programme.title)").font(.title3).foregroundStyle(.secondary)
                } else if let category = channel.primaryCategory {
                    Text(catalog.categoryName(category)).font(.title3).foregroundStyle(.secondary)
                }
                Button(action: onPlay) {
                    Label("Watch Now", systemImage: "play.fill")
                        .font(.headline)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 6)
            }
            .padding(32)
        }
        .frame(height: 300)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.stroke))
        .onHover { isHovering in withAnimation(.easeOut(duration: 0.3)) { hovered = isHovering } }
    }
}

/// Featured categories as tappable tiles; opens Explore filtered by category.
struct CategoryStrip: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var catalog: CatalogViewModel

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 14)]

    var body: some View {
        let available = ChannelCategory.featuredIDs.filter { id in catalog.categories.contains { $0.id == id } }
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Browse by Category")
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(available, id: \.self) { id in
                    let category = catalog.categories.first { $0.id == id }
                        ?? ChannelCategory(id: id, name: ChannelCategory.fallbackName(for: id))
                    Button {
                        model.explore(.category(id))
                    } label: {
                        CategoryTile(category: category, count: catalog.channelCount(category: id))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct CategoryTile: View {
    let category: ChannelCategory
    let count: Int
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: category.symbol)
                .font(.title2)
                .foregroundStyle(Theme.brandGradient)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(category.name).font(.headline)
                Text("\(count) channels").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .card(hovered: hovered)
        .onHover { isHovering in withAnimation(.easeOut(duration: 0.15)) { hovered = isHovering } }
    }
}
