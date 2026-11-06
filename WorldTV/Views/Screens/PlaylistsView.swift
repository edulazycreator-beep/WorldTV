import SwiftUI
import UniformTypeIdentifiers

struct PlaylistsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var catalog: CatalogViewModel
    @State private var selection: UUID?
    @State private var importingPlaylist = false
    @State private var importingGuide = false
    @State private var showAddURL = false
    @State private var showAddGuideURL = false
    @State private var confirmRemove: Playlist?

    static let playlistTypes: [UTType] = [
        UTType(filenameExtension: "m3u"), UTType(filenameExtension: "m3u8"),
        UTType("public.m3u-playlist"), UTType("com.apple.mpegurl"), .plainText,
    ].compactMap { $0 }

    static let guideTypes: [UTType] = [
        .xml, UTType(filenameExtension: "xmltv"), UTType(filenameExtension: "gz"), .gzip,
    ].compactMap { $0 }

    var body: some View {
        HSplitView {
            sidebar
                .frame(minWidth: 280, idealWidth: 320, maxWidth: 400)
            detail
                .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Playlists")
        .toolbar {
            ToolbarItemGroup {
                Menu {
                    Button("Import Playlist File…") { importingPlaylist = true }
                    Button("Add Playlist URL…") { showAddURL = true }
                    Divider()
                    Button("Import XMLTV Guide File…") { importingGuide = true }
                    Button("Add XMLTV Guide URL…") { showAddGuideURL = true }
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .accessibilityIdentifier("playlists-add")
            }
        }
        .fileImporter(isPresented: $importingPlaylist, allowedContentTypes: Self.playlistTypes) { result in
            if case .success(let url) = result { Task { await catalog.importPlaylist(fileURL: url) } }
        }
        .background(EmptyView().fileImporter(isPresented: $importingGuide, allowedContentTypes: Self.guideTypes) { result in
            if case .success(let url) = result { Task { await catalog.importGuide(fileURL: url) } }
        })
        .sheet(isPresented: $showAddURL) {
            URLEntrySheet(title: "Add Playlist URL",
                          message: "Enter the address of an M3U/M3U8 playlist you own or are authorized to use.",
                          showsName: true) { url, name in
                Task { await catalog.addPlaylist(urlString: url, name: name) }
            }
        }
        .sheet(isPresented: $showAddGuideURL) {
            URLEntrySheet(title: "Add XMLTV Guide URL",
                          message: "Enter the address of an XMLTV guide (.xml or .xml.gz).",
                          showsName: false) { url, _ in
                Task { await catalog.addGuide(urlString: url) }
            }
        }
        .confirmationDialog("Remove “\(confirmRemove?.name ?? "")”?", isPresented: Binding(
            get: { confirmRemove != nil }, set: { if !$0 { confirmRemove = nil } })) {
            Button("Remove Playlist", role: .destructive) {
                if let playlist = confirmRemove {
                    if selection == playlist.id { selection = nil }
                    Task { await catalog.removePlaylist(playlist.id) }
                }
                confirmRemove = nil
            }
        } message: {
            Text("Its channels will disappear from World TV. Favorites pointing to them are kept in case you re-import it.")
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List(selection: $selection) {
            Section("Playlists") {
                if catalog.imported.playlists.isEmpty {
                    Text("No playlists imported").foregroundStyle(.secondary)
                }
                ForEach(catalog.imported.playlists) { playlist in
                    PlaylistRow(playlist: playlist,
                                busy: catalog.busyPlaylists.contains(playlist.id),
                                progress: catalog.validationProgress[playlist.id])
                        .tag(playlist.id)
                        .contextMenu {
                            Button("Update") { Task { await catalog.updatePlaylist(playlist.id) } }
                            Button("Check Streams") { Task { await catalog.validatePlaylist(playlist.id) } }
                            Divider()
                            Button("Remove…", role: .destructive) { confirmRemove = playlist }
                        }
                }
            }
            Section("Programme Guides") {
                if catalog.imported.guides.isEmpty && !catalog.imported.playlists.contains(where: { $0.epgURL != nil }) {
                    Text("No guides").foregroundStyle(.secondary)
                }
                ForEach(catalog.imported.playlists.filter { $0.epgURL != nil }) { playlist in
                    Label {
                        VStack(alignment: .leading) {
                            Text(playlist.epgURL?.host ?? "Guide").lineLimit(1)
                            Text("From “\(playlist.name)”").font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: { Image(systemName: "list.bullet.rectangle") }
                }
                ForEach(catalog.imported.guides) { guide in
                    Label {
                        VStack(alignment: .leading) {
                            Text(guide.name).lineLimit(1)
                            Text(guide.source.displayValue).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    } icon: { Image(systemName: "list.bullet.rectangle") }
                    .contextMenu {
                        Button("Remove Guide", role: .destructive) { Task { await catalog.removeGuide(guide.id) } }
                    }
                }
                HStack {
                    guideStatus
                    Spacer()
                    Button("Reload") { Task { await catalog.refreshGuides() } }
                        .buttonStyle(.link)
                }
                .font(.caption)
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private var guideStatus: some View {
        switch catalog.guideState {
        case .loading: Text("Loading guides…").foregroundStyle(.secondary)
        case .failed(let message): Text(message).foregroundStyle(.orange)
        case .loaded: Text("\(catalog.channelsWithGuide.count) channels with guide data").foregroundStyle(.secondary)
        case .idle: EmptyView()
        }
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        if let id = selection, let playlist = catalog.imported.playlists.first(where: { $0.id == id }) {
            PlaylistDetail(playlist: playlist, onRemove: { confirmRemove = playlist })
        } else {
            VStack(spacing: 0) {
                EmptyStateView(
                    symbol: "music.note.list",
                    title: "Bring your own playlists",
                    message: "Import M3U/M3U8 playlists you own or are authorized to use, and XMLTV guides for programme information. Everything stays on this Mac.",
                    actionTitle: "Import Playlist File…") { importingPlaylist = true }
                HStack {
                    Button("Add Playlist URL…") { showAddURL = true }
                    Button("Add XMLTV Guide…") { showAddGuideURL = true }
                }
                .padding(.bottom, 40)
            }
        }
    }
}

private struct PlaylistRow: View {
    let playlist: Playlist
    let busy: Bool
    let progress: Double?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: playlistIcon).foregroundStyle(Theme.accent).frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.name).lineLimit(1)
                Text("\(playlist.channels.count) channels" + (playlist.invalidStreamCount > 0 ? " · \(playlist.invalidStreamCount) unreachable" : ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let progress {
                    ProgressView(value: progress).controlSize(.small)
                }
            }
            Spacer()
            if busy && progress == nil { ProgressView().controlSize(.small) }
        }
    }

    private var playlistIcon: String {
        if case .remote = playlist.source { return "link" }
        return "doc.text"
    }
}

private struct PlaylistDetail: View {
    let playlist: Playlist
    var onRemove: () -> Void

    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var catalog: CatalogViewModel
    @State private var name = ""
    @State private var guideURL = ""
    @State private var filter = ""
    @State private var onlyInvalid = false

    var body: some View {
        let busy = catalog.busyPlaylists.contains(playlist.id)
        let channels = filteredChannels
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Name", text: $name)
                        .textFieldStyle(.plain)
                        .font(.title.weight(.bold))
                        .onSubmit { Task { await catalog.renamePlaylist(playlist.id, to: name) } }
                    Text(playlist.source.displayValue).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Text("Updated \(Formatters.dayTime.string(from: playlist.updatedAt)) · \(playlist.channels.count) channels")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { Task { await catalog.updatePlaylist(playlist.id) } } label: {
                    Label("Update", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(busy)
                Button { Task { await catalog.validatePlaylist(playlist.id) } } label: {
                    Label("Check Streams", systemImage: "checkmark.shield")
                }
                .disabled(busy)
                .help("Contacts each stream briefly (manifest only) to see whether it responds")
                Button(role: .destructive, action: onRemove) { Label("Remove", systemImage: "trash") }
            }

            HStack {
                Text("XMLTV guide").foregroundStyle(.secondary)
                TextField("https://example.com/guide.xml.gz", text: $guideURL)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await catalog.setGuideURL(guideURL, for: playlist.id) } }
                Button("Save") { Task { await catalog.setGuideURL(guideURL, for: playlist.id) } }
            }

            HStack {
                TextField("Filter channels", text: $filter).textFieldStyle(.roundedBorder).frame(maxWidth: 260)
                Toggle("Only unreachable", isOn: $onlyInvalid)
                    .disabled(playlist.validation.isEmpty)
                Spacer()
                Button {
                    if let first = channels.first { model.play(first, in: channels, title: playlist.name) }
                } label: { Label("Play All", systemImage: "play.fill") }
                    .disabled(channels.isEmpty)
            }

            List(channels) { channel in
                HStack {
                    Button { model.play(channel, in: channels, title: playlist.name) } label: {
                        ChannelRow(channel: channel, showProgramme: true)
                    }
                    .buttonStyle(.plain)
                    healthBadge(for: channel)
                }
                .contextMenu { ChannelContextMenu(channel: channel) { model.play(channel, in: channels, title: playlist.name) } }
            }
            .listStyle(.inset)
        }
        .padding(24)
        .onAppear(perform: syncFields)
        .onChange(of: playlist.id) { _ in syncFields() }
    }

    private func syncFields() {
        name = playlist.name
        guideURL = playlist.epgURL?.absoluteString ?? ""
    }

    private var filteredChannels: [Channel] {
        let current = catalog.channels.filter {
            if case .playlist(let id) = $0.origin { return id == playlist.id }
            return false
        }
        return current.filter { channel in
            if !filter.isEmpty && !channel.name.localizedCaseInsensitiveContains(filter) { return false }
            if onlyInvalid {
                return channel.streams.allSatisfy { playlist.validation[$0.url.absoluteString]?.isUnreachable == true }
            }
            return true
        }
    }

    @ViewBuilder
    private func healthBadge(for channel: Channel) -> some View {
        let states = channel.streams.map { playlist.validation[$0.url.absoluteString] ?? .unknown }
        if states.contains(where: { if case .ok = $0 { return true }; return false }) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).help("Responded at last check")
        } else if let reason = states.compactMap({ state -> String? in
            if case .unreachable(let reason, _) = state { return reason }
            return nil
        }).first {
            Image(systemName: "xmark.octagon.fill").foregroundStyle(.red).help(reason)
        } else {
            Image(systemName: "questionmark.circle").foregroundStyle(.secondary).help("Not checked yet")
        }
    }
}

/// Small modal for entering a URL (and optional name).
struct URLEntrySheet: View {
    let title: String
    let message: String
    let showsName: Bool
    var onSubmit: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var name = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.title2.weight(.bold))
            Text(message).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            TextField("https://", text: $url).textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("url-entry-field")
            if showsName {
                TextField("Name (optional)", text: $name).textFieldStyle(.roundedBorder)
            }
            if let error { Text(error).font(.callout).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Add") {
                    switch StreamValidator.validate(url) {
                    case .success:
                        onSubmit(url, name)
                        dismiss()
                    case .failure(let issue):
                        error = issue.localizedDescription
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(22)
        .frame(width: 460)
    }
}
