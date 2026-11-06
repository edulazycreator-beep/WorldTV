import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var catalog: CatalogViewModel
    @EnvironmentObject private var library: LibraryStore

    var body: some View {
        TabView {
            playback.tabItem { Label("Playback", systemImage: "play.rectangle") }
            appearance.tabItem { Label("Appearance", systemImage: "paintbrush") }
            network.tabItem { Label("Network", systemImage: "network") }
            about.tabItem { Label("About", systemImage: "info.circle") }
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 440)
        .navigationTitle("Settings")
    }

    private var playback: some View {
        Form {
            Section("Video") {
                Picker("Aspect ratio", selection: $library.settings.videoGravity) {
                    ForEach(AppSettings.VideoGravity.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Prefer highest-quality stream", isOn: $library.settings.preferHighestQuality)
                Toggle("Hide channels marked geo-blocked", isOn: $library.settings.hideGeoBlocked)
            }
            Section("Playback") {
                Toggle("Start playing when a channel is selected", isOn: $library.settings.autoplayOnSelect)
                Toggle("Start muted", isOn: $library.settings.startMuted)
                HStack {
                    Text("Default volume")
                    Slider(value: $library.settings.defaultVolume, in: 0...1)
                    Text("\(Int(library.settings.defaultVolume * 100))%").monospacedDigit().frame(width: 40)
                }
                Stepper("Reconnect attempts: \(library.settings.reconnectAttempts)",
                        value: $library.settings.reconnectAttempts, in: 0...10)
            }
        }
        .formStyle(.grouped)
    }

    private var appearance: some View {
        Form {
            Picker("Theme", selection: $library.settings.theme) {
                ForEach(AppSettings.Theme.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.radioGroup)
            Text("World TV is designed for dark mode, which is the default.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    private var network: some View {
        Form {
            Section("Public channel directory") {
                Toggle("Use the iptv-org public directory", isOn: $library.settings.directoryEnabled)
                Stepper("Refresh every \(library.settings.directoryRefreshHours) hours",
                        value: $library.settings.directoryRefreshHours, in: 1...168)
                HStack {
                    if let updated = catalog.directoryUpdatedAt, updated > .distantPast {
                        Text("Last updated \(Formatters.dayTime.string(from: updated))").foregroundStyle(.secondary)
                    } else {
                        Text("Not downloaded yet").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Refresh Now") { Task { await catalog.refreshDirectory() } }
                        .disabled(catalog.directoryState == .loading)
                }
            }
            Section("Requests") {
                Stepper("Timeout: \(Int(library.settings.requestTimeout)) s",
                        value: $library.settings.requestTimeout, in: 5...60, step: 5)
                Stepper("Retries: \(library.settings.maxRetries)", value: $library.settings.maxRetries, in: 0...6)
                Text("Stream checks only download the playlist manifest or the first few kilobytes, never the video itself.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var about: some View {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "–"
        return Form {
            Section {
                HStack(spacing: 14) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("World TV").font(.title2.weight(.bold))
                        Text("Version \(version) (\(build))").foregroundStyle(.secondary)
                    }
                }
            }
            Section("Sources & legal") {
                Text("World TV does not host or redistribute any television content. The public directory comes from the iptv-org community database, which lists publicly available streams published by broadcasters. Each stream remains subject to its broadcaster's terms; some are geo-restricted.")
                    .fixedSize(horizontal: false, vertical: true)
                Text("Only import playlists you own or are authorized to use. World TV does not support DRM-protected or paid-TV streams.")
                    .fixedSize(horizontal: false, vertical: true)
                Link("iptv-org database", destination: URL(string: "https://github.com/iptv-org/database")!)
                Link("Report a broken stream to iptv-org", destination: URL(string: "https://github.com/iptv-org/iptv/issues")!)
            }
        }
        .formStyle(.grouped)
    }
}
