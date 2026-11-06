import AVKit
import SwiftUI

/// Native `AVPlayerView` with floating controls, full-screen toggle and
/// Picture-in-Picture enabled.
struct NativePlayerView: NSViewRepresentable {
    let player: AVPlayer
    var gravity: AppSettings.VideoGravity

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .floating
        view.showsFullScreenToggleButton = true
        view.allowsPictureInPicturePlayback = true
        view.updatesNowPlayingInfoCenter = true
        view.videoGravity = gravity.avGravity
        view.setAccessibilityIdentifier("video-player")
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player { view.player = player }
        if view.videoGravity != gravity.avGravity { view.videoGravity = gravity.avGravity }
    }
}

extension AppSettings.VideoGravity {
    var avGravity: AVLayerVideoGravity {
        switch self {
        case .fit: return .resizeAspect
        case .fill: return .resizeAspectFill
        case .stretch: return .resize
        }
    }
}

/// Video surface plus World TV overlays: channel badge, loading, reconnect
/// and error states.
struct PlayerSurface: View {
    @EnvironmentObject private var live: LiveTVViewModel
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var catalog: CatalogViewModel
    @State private var hovering = false

    var body: some View {
        ZStack {
            Color.black
            NativePlayerView(player: player.player, gravity: library.settings.videoGravity)

            if let channel = live.current {
                VStack {
                    if hovering || player.state != .playing {
                        infoBadge(channel)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    Spacer()
                }
                .padding(14)
                .allowsHitTesting(false)
            } else {
                EmptyStateView(symbol: "play.tv", title: "Pick a channel",
                               message: "Choose a channel from the list to start watching.")
            }

            stateOverlay
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onHover { isHovering in withAnimation(.easeOut(duration: 0.2)) { hovering = isHovering } }
        .animation(.easeInOut(duration: 0.2), value: player.state)
    }

    private func infoBadge(_ channel: Channel) -> some View {
        HStack(spacing: 10) {
            ChannelLogoView(channel: channel, size: 34, cornerRadius: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(channel.name).font(.headline)
                HStack(spacing: 6) {
                    if let country = catalog.country(channel.countryCode) {
                        Text("\(country.flag) \(country.name)")
                    }
                    if let programme = catalog.currentProgramme(for: channel) {
                        Text("· \(programme.title)").lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            if let quality = player.qualityLabel { Pill(text: quality) }
            Pill(text: player.state.label,
                 color: player.state == .playing ? Theme.live : Color.white.opacity(0.15),
                 foreground: .white)
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private var stateOverlay: some View {
        switch player.state {
        case .loading, .buffering:
            ProgressView()
                .controlSize(.large)
                .padding(18)
                .background(.ultraThinMaterial, in: Circle())
                .accessibilityLabel(player.state.label)
        case .reconnecting(let attempt, let total):
            VStack(spacing: 10) {
                ProgressView().controlSize(.large)
                Text("Reconnecting… (\(attempt) of \(total))").font(.callout.weight(.medium))
            }
            .padding(20)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        case .failed(let message):
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.tv.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.orange)
                Text("This channel isn't available right now").font(.headline)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
                if live.current?.streams.contains(where: \.isGeoBlocked) == true {
                    Text("The source marks this stream as geo-blocked; it may only work in its home country.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 380)
                }
                HStack {
                    Button("Try Again") { player.retry() }
                        .buttonStyle(.borderedProminent)
                    if live.canStep {
                        Button("Next Channel") { live.next() }
                    }
                }
            }
            .padding(24)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .environment(\.colorScheme, .dark)
            .accessibilityIdentifier("player-error")
        default:
            EmptyView()
        }
    }
}

/// Transport bar under the video.
struct PlayerControlsBar: View {
    @EnvironmentObject private var live: LiveTVViewModel
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var library: LibraryStore

    var body: some View {
        HStack(spacing: 14) {
            Button { live.previous() } label: { Image(systemName: "backward.end.fill") }
                .help("Previous channel (⌘←)")
                .disabled(!live.canStep)
            Button { player.togglePlayPause() } label: {
                Image(systemName: player.state == .paused || player.state.errorMessage != nil ? "play.fill" : "pause.fill")
                    .frame(width: 18)
            }
            .help("Play / Pause (⌘P)")
            .disabled(live.current == nil)
            Button { live.next() } label: { Image(systemName: "forward.end.fill") }
                .help("Next channel (⌘→)")
                .disabled(!live.canStep)

            Divider().frame(height: 18)

            Button { player.isMuted.toggle() } label: {
                Image(systemName: player.isMuted || player.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .frame(width: 20)
            }
            .help("Mute (⌥⌘M)")
            Slider(value: Binding(get: { Double(player.volume) }, set: { player.volume = Float($0) }), in: 0...1)
                .frame(width: 110)
                .accessibilityLabel("Volume")

            Spacer()

            if let current = live.current {
                Text(player.state.label).font(.caption).foregroundStyle(.secondary)
                if player.bitrate > 0 {
                    Text(String(format: "%.1f Mbps", player.bitrate / 1_000_000))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Button { library.toggleFavorite(current) } label: {
                    Image(systemName: library.library.isFavorite(current.id) ? "star.fill" : "star")
                        .foregroundStyle(library.library.isFavorite(current.id) ? Color.yellow : Color.secondary)
                }
                .help("Favorite (⌘D)")
            }

            Menu {
                Picker("Aspect Ratio", selection: $library.settings.videoGravity) {
                    ForEach(AppSettings.VideoGravity.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                Image(systemName: "aspectratio")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Aspect ratio")

            Button { player.retry() } label: { Image(systemName: "arrow.clockwise") }
                .help("Reconnect (⌘R)")
                .disabled(live.current == nil)
        }
        .buttonStyle(.borderless)
        .font(.system(size: 14))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface))
    }
}
