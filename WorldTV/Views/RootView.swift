import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var catalog: CatalogViewModel
    @EnvironmentObject private var search: SearchViewModel
    @EnvironmentObject private var live: LiveTVViewModel

    var body: some View {
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            ZStack {
                Theme.background.ignoresSafeArea()
                if search.isActive {
                    SearchResultsView()
                        .transition(.opacity)
                } else {
                    detail(for: model.selection ?? .home)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.18), value: search.isActive)
        }
        .searchable(text: $model.searchText, placement: .sidebar, prompt: "Channels, countries, languages")
        .overlay(alignment: .bottom) { NoticeBanner() }
    }

    @ViewBuilder
    private func detail(for item: SidebarItem) -> some View {
        switch item {
        case .home: HomeView()
        case .explore: ExploreView()
        case .live: LiveTVView()
        case .guide: TVGuideView()
        case .favorites: FavoritesView()
        case .playlists: PlaylistsView()
        case .settings: SettingsView().padding(.top, 8)
        }
    }
}

private struct Sidebar: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var catalog: CatalogViewModel
    @EnvironmentObject private var live: LiveTVViewModel

    var body: some View {
        List(selection: $model.selection) {
            Section {
                ForEach([SidebarItem.home, .explore, .live, .guide]) { item in
                    row(item)
                }
            }
            Section("Library") {
                ForEach([SidebarItem.favorites, .playlists]) { item in
                    row(item)
                }
            }
            Section {
                row(.settings)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top) { Brand().padding(.horizontal, 14).padding(.top, 6).padding(.bottom, 4) }
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                if let current = live.current {
                    NowPlayingChip(channel: current) { model.selection = .live }
                }
                DirectoryStatus()
            }
            .padding(12)
        }
    }

    private func row(_ item: SidebarItem) -> some View {
        Label(item.title, systemImage: item.symbol)
            .tag(item)
            .accessibilityIdentifier("sidebar-\(item.rawValue)")
    }
}

private struct Brand: View {
    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.brandGradient)
                Image(systemName: "globe.asia.australia.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 26, height: 26)
            Text("World TV").font(.system(size: 17, weight: .bold, design: .rounded))
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("World TV")
    }
}

private struct NowPlayingChip: View {
    let channel: Channel
    var action: () -> Void
    @EnvironmentObject private var player: PlayerController

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                ChannelLogoView(channel: channel, size: 28, cornerRadius: 6)
                VStack(alignment: .leading, spacing: 1) {
                    Text(channel.name).font(.caption.weight(.semibold)).lineLimit(1)
                    Text(player.state.label).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.surfaceRaised))
        }
        .buttonStyle(.plain)
    }
}

private struct DirectoryStatus: View {
    @EnvironmentObject private var catalog: CatalogViewModel

    var body: some View {
        HStack(spacing: 6) {
            switch catalog.directoryState {
            case .loading:
                ProgressView().controlSize(.small)
                Text("Updating directory…")
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text("Directory offline")
            default:
                Image(systemName: "dot.radiowaves.left.and.right").foregroundStyle(Theme.accent)
                Text("\(catalog.channels.count.formatted()) channels")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

/// Transient, dismissible message for import/validation/refresh results.
struct NoticeBanner: View {
    @EnvironmentObject private var catalog: CatalogViewModel

    var body: some View {
        if let notice = catalog.notice {
            HStack(spacing: 10) {
                Image(systemName: "info.circle.fill").foregroundStyle(Theme.accent)
                Text(notice).font(.callout).lineLimit(3)
                Button {
                    catalog.notice = nil
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .shadow(radius: 10)
            .padding(.bottom, 18)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task(id: notice) {
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                if catalog.notice == notice { catalog.notice = nil }
            }
        }
    }
}
