import SwiftUI

/// Menu bar commands and keyboard shortcuts.
///
/// Playback: ⌘P play/pause (Space also works when the video has focus) · ⌘→ / ⌘← next/previous channel ·
/// ⌘↑ / ⌘↓ volume · ⌥⌘M mute · ⌘R reconnect · ⌘D favorite ·
/// ⌃⌘F full screen (system) · ⌘1…⌘7 switch screens.
struct WorldTVCommands: Commands {
    @ObservedObject var model: AppModel

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            ForEach(SidebarItem.allCases) { item in
                Button(item.title) { model.selection = item }
                    .keyboardShortcut(item.shortcut, modifiers: .command)
            }
        }

        CommandMenu("Playback") {
            Button("Play / Pause") { model.live.player.togglePlayPause() }
                .keyboardShortcut("p", modifiers: .command)
            Button("Next Channel") { model.live.next() }
                .keyboardShortcut(.rightArrow, modifiers: .command)
            Button("Previous Channel") { model.live.previous() }
                .keyboardShortcut(.leftArrow, modifiers: .command)
            Divider()
            Button("Volume Up") { model.live.player.volume = min(1, model.live.player.volume + 0.1) }
                .keyboardShortcut(.upArrow, modifiers: .command)
            Button("Volume Down") { model.live.player.volume = max(0, model.live.player.volume - 0.1) }
                .keyboardShortcut(.downArrow, modifiers: .command)
            Button("Mute") { model.live.player.isMuted.toggle() }
                .keyboardShortcut("m", modifiers: [.command, .option])
            Divider()
            Button("Reconnect Stream") { model.live.player.retry() }
                .keyboardShortcut("r", modifiers: .command)
            Button("Stop") { model.live.stop() }
                .keyboardShortcut(".", modifiers: .command)
            Divider()
            Button("Toggle Favorite") {
                if let channel = model.live.current { model.library.toggleFavorite(channel) }
            }.keyboardShortcut("d", modifiers: .command)
        }

        CommandGroup(after: .newItem) {
            Button("Refresh Channel Directory") {
                Task { await model.catalog.refreshDirectory() }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
        }
    }
}
