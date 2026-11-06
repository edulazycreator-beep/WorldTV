import AppKit
import SwiftUI

@main
struct WorldTVApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.make()

    var body: some Scene {
        WindowGroup("World TV", id: "main") {
            RootView()
                .modifier(AppThemeModifier())
                .environmentObject(model)
                .environmentObject(model.catalog)
                .environmentObject(model.library)
                .environmentObject(model.live)
                .environmentObject(model.live.player)
                .environmentObject(model.search)
                .frame(minWidth: 960, minHeight: 620)
                .task {
                    appDelegate.model = model
                    await model.start()
                }
                .onOpenURL { url in
                    guard url.isFileURL else { return }
                    Task {
                        await model.catalog.importPlaylist(fileURL: url)
                        model.selection = .playlists
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .commands { WorldTVCommands(model: model) }

        Settings {
            SettingsView()
                .modifier(AppThemeModifier())
                .environmentObject(model)
                .environmentObject(model.catalog)
                .environmentObject(model.library)
                .frame(width: 560, height: 520)
        }
    }
}

/// Applies the user's theme preference; observes the library so changes are live.
struct AppThemeModifier: ViewModifier {
    @EnvironmentObject private var library: LibraryStore

    func body(content: Content) -> some View {
        content.preferredColorScheme(scheme)
    }

    private var scheme: ColorScheme? {
        switch library.settings.theme {
        case .dark: return .dark
        case .light: return .light
        case .system: return nil
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model else { return .terminateNow }
        // Persist the library before quitting.
        Task { @MainActor in
            model.live.stop()
            await model.library.flush()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
