import SwiftUI

struct LiveTVView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var live: LiveTVViewModel
    @EnvironmentObject private var catalog: CatalogViewModel
    @State private var listFilter = ""
    @State private var showList = true

    var body: some View {
        HStack(spacing: 0) {
            if showList {
                channelList
                    .frame(width: 290)
                    .transition(.move(edge: .leading))
                Divider()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    PlayerSurface()
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                    PlayerControlsBar()
                    if let channel = live.current {
                        ChannelInfoPanel(channel: channel)
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle(live.current?.name ?? "Live TV")
        .toolbar {
            ToolbarItem {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showList.toggle() }
                } label: {
                    Image(systemName: "sidebar.squares.left")
                }
                .help(showList ? "Hide channel list" : "Show channel list")
            }
        }
        .onAppear {
            if live.queue.isEmpty, !catalog.channels.isEmpty {
                live.setQueue(catalog.popular(limit: 200), title: "Popular")
            }
        }
    }

    private var channelList: some View {
        let channels = filteredQueue
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(live.queueTitle).font(.headline)
                Spacer()
                Menu {
                    Button("Popular") { live.setQueue(catalog.popular(limit: 300), title: "Popular") }
                    Button("Favorites") {
                        live.setQueue(catalog.channels(ids: model.library.library.favoriteIDs), title: "Favorites")
                    }
                    Button("Recently Watched") {
                        live.setQueue(catalog.channels(ids: model.library.library.recentChannelIDs(limit: 50)),
                                      title: "Recently Watched")
                    }
                    if let code = live.current?.countryCode {
                        Button("Same Country") {
                            var query = SearchQuery()
                            query.countryCode = code
                            query.sort = .popularity
                            live.setQueue(SearchService.search(catalog.channels, query: query,
                                                               context: catalog.searchContext()),
                                          title: catalog.countryName(code))
                        }
                    }
                    if !model.library.library.groups.isEmpty {
                        Divider()
                        ForEach(model.library.library.groups) { group in
                            Button(group.name) {
                                live.setQueue(catalog.channels(ids: group.channelIDs), title: group.name)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Choose channel list")
            }
            TextField("Filter channels", text: $listFilter)
                .textFieldStyle(.roundedBorder)
            if channels.isEmpty {
                Text(live.queue.isEmpty ? "No channels in this list." : "No matches.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, 20)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    List(channels) { channel in
                        Button {
                            live.play(channel)
                        } label: {
                            ChannelRow(channel: channel, isPlaying: channel.id == live.current?.id)
                        }
                        .buttonStyle(.plain)
                        .id(channel.id)
                        .listRowBackground(channel.id == live.current?.id
                                           ? RoundedRectangle(cornerRadius: 8).fill(Theme.accent.opacity(0.15))
                                           : RoundedRectangle(cornerRadius: 8).fill(Color.clear))
                        .contextMenu { ChannelContextMenu(channel: channel) { live.play(channel) } }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .onChange(of: live.current?.id) { id in
                        if let id { withAnimation { proxy.scrollTo(id, anchor: .center) } }
                    }
                }
            }
        }
        .padding(14)
        .background(Theme.surface.opacity(0.5))
    }

    private var filteredQueue: [Channel] {
        guard !listFilter.isEmpty else { return live.queue }
        let needle = listFilter.searchFolded
        return live.queue.filter { $0.name.searchFolded.contains(needle) }
    }
}

/// Channel details: now/next programme, streams and source attribution.
struct ChannelInfoPanel: View {
    let channel: Channel
    @EnvironmentObject private var catalog: CatalogViewModel
    @EnvironmentObject private var player: PlayerController

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Now & Next").font(.headline)
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    if let programme = catalog.currentProgramme(for: channel, at: context.date) {
                        ProgrammeSummary(programme: programme, now: context.date, isCurrent: true)
                        ForEach(catalog.upcoming(for: channel, limit: 3)) { next in
                            ProgrammeSummary(programme: next, now: context.date, isCurrent: false)
                        }
                    } else {
                        Text("No programme information. Add an XMLTV guide in Playlists to see what's on.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .card()

            VStack(alignment: .leading, spacing: 10) {
                Text("Channel").font(.headline)
                infoRow("Country", catalog.countryName(channel.countryCode))
                if !channel.languages.isEmpty {
                    infoRow("Language", channel.languages.map { catalog.languageName($0) }.joined(separator: ", "))
                }
                if !channel.categories.isEmpty {
                    infoRow("Category", channel.categories.map { catalog.categoryName($0) }.joined(separator: ", "))
                }
                if let quality = player.qualityLabel ?? channel.bestQualityLabel {
                    infoRow("Quality", quality)
                }
                infoRow("Streams", "\(channel.streams.count)")
                if let active = player.activeStream, !active.labels.isEmpty {
                    infoRow("Notes", active.labels.joined(separator: ", "))
                }
                infoRow("Source", channel.attribution)
                if let notes = channel.usageNotes {
                    Text(notes).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                if let website = channel.website {
                    Link(destination: website) { Label("Broadcaster website", systemImage: "safari") }
                        .font(.callout)
                }
            }
            .frame(width: 300, alignment: .leading)
            .padding(16)
            .card()
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary).frame(width: 72, alignment: .leading)
            Text(value).lineLimit(2)
        }
        .font(.callout)
    }
}

struct ProgrammeSummary: View {
    let programme: Programme
    let now: Date
    let isCurrent: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(Formatters.time.string(from: programme.start)) – \(Formatters.time.string(from: programme.stop))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(isCurrent ? Theme.accent : .secondary)
                if isCurrent { Pill(text: "Now", color: Theme.live, foreground: .white) }
            }
            Text(programme.title).font(isCurrent ? .title3.weight(.semibold) : .body)
            if isCurrent {
                ProgressView(value: programme.progress(at: now))
                    .tint(Theme.accent)
                if let description = programme.description {
                    Text(description).font(.callout).foregroundStyle(.secondary).lineLimit(3)
                }
            }
        }
    }
}
