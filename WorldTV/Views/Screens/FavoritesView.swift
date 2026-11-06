import SwiftUI

struct FavoritesView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case favorites = "Favorites", groups = "Groups", history = "History"
        var id: String { rawValue }
    }

    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var catalog: CatalogViewModel
    @EnvironmentObject private var library: LibraryStore
    @State private var tab: Tab = .favorites
    @State private var newGroupName = ""
    @State private var selectedGroup: UUID?
    @State private var confirmClear = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker("Section", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 360)
            .padding([.horizontal, .top], 28)
            .padding(.bottom, 12)

            switch tab {
            case .favorites: favorites
            case .groups: groups
            case .history: history
            }
        }
        .background(Theme.backdrop.ignoresSafeArea())
        .navigationTitle("Favorites")
    }

    // MARK: Favorites

    @ViewBuilder
    private var favorites: some View {
        let channels = catalog.channels(ids: library.library.favoriteIDs)
        let missing = library.library.favoriteIDs.count - channels.count
        if library.library.favoriteIDs.isEmpty {
            EmptyStateView(symbol: "star", title: "No favorites yet",
                           message: "Right-click any channel and choose “Add to Favorites”, or press ⌘D while watching.")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if missing > 0 {
                        Label("\(missing) favorite(s) are not in the current catalog (removed playlist or directory change).",
                              systemImage: "info.circle")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    ChannelGrid(channels: channels) { model.play($0, in: channels, title: "Favorites") }
                }
                .padding(28)
            }
        }
    }

    // MARK: Groups

    private var groups: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    TextField("New group name", text: $newGroupName)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(createGroup)
                    Button("Add", action: createGroup)
                        .disabled(newGroupName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                List(selection: $selectedGroup) {
                    ForEach(library.library.groups) { group in
                        HStack {
                            Image(systemName: "folder.fill").foregroundStyle(Theme.accent)
                            Text(group.name)
                            Spacer()
                            Text("\(group.channelIDs.count)").foregroundStyle(.secondary)
                        }
                        .tag(group.id)
                        .contextMenu {
                            Button("Delete Group", role: .destructive) {
                                if selectedGroup == group.id { selectedGroup = nil }
                                library.deleteGroup(group.id)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
            .frame(width: 260)
            .padding(.leading, 28)

            Divider().padding(.horizontal, 16)

            Group {
                if let id = selectedGroup, let group = library.library.groups.first(where: { $0.id == id }) {
                    let channels = catalog.channels(ids: group.channelIDs)
                    if channels.isEmpty {
                        EmptyStateView(symbol: "folder", title: "“\(group.name)” is empty",
                                       message: "Right-click a channel anywhere and choose Groups → \(group.name).")
                    } else {
                        ScrollView {
                            ChannelGrid(channels: channels) { model.play($0, in: channels, title: group.name) }
                                .padding(.trailing, 28)
                        }
                    }
                } else {
                    EmptyStateView(symbol: "folder.badge.plus", title: "Custom groups",
                                   message: "Create groups like “Morning News” or “Football” and add channels from their right-click menu.")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func createGroup() {
        let name = newGroupName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        selectedGroup = library.createGroup(named: name).id
        newGroupName = ""
    }

    // MARK: History

    @ViewBuilder
    private var history: some View {
        if library.library.history.isEmpty {
            EmptyStateView(symbol: "clock", title: "No watch history",
                           message: "Channels you watch will appear here.")
        } else {
            VStack(alignment: .trailing) {
                Button("Clear History…") { confirmClear = true }
                    .padding(.horizontal, 28)
                List(library.library.history) { entry in
                    HStack {
                        if let channel = catalog.channel(id: entry.channelID) {
                            Button { model.play(channel) } label: {
                                ChannelRow(channel: channel, showProgramme: false)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Text(entry.channelName).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text(Formatters.dayTime.string(from: entry.startedAt)).font(.caption)
                            if entry.duration > 0 {
                                Text(Formatters.duration(entry.duration)).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .listStyle(.inset)
                .padding(.horizontal, 20)
            }
            .confirmationDialog("Clear all watch history?", isPresented: $confirmClear) {
                Button("Clear History", role: .destructive) { library.clearHistory() }
            }
        }
    }
}
