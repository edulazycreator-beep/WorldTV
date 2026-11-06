import SwiftUI

/// Grid EPG: channels down the side, time across the top.
struct TVGuideView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var catalog: CatalogViewModel
    @State private var timeZoneID = TimeZone.current.identifier
    @State private var startOffsetHours = 0
    @State private var selected: Programme?
    @State private var filter = ""

    private let hourWidth: CGFloat = 260
    private let rowHeight: CGFloat = 64
    private let channelColumnWidth: CGFloat = 210
    private let visibleHours = 6

    var body: some View {
        Group {
            if catalog.guide.isEmpty {
                EmptyStateView(
                    symbol: "list.bullet.rectangle.portrait",
                    title: catalog.guideState == .loading ? "Loading programme guide…" : "No programme guide yet",
                    message: "World TV reads XMLTV guides. Add one in Playlists — either a guide URL declared in your playlist or a standalone XMLTV file or address.",
                    actionTitle: "Open Playlists") { model.selection = .playlists }
            } else {
                guide
            }
        }
        .navigationTitle("TV Guide")
    }

    private var timeZone: TimeZone { TimeZone(identifier: timeZoneID) ?? .current }

    private var windowStart: Date {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        let now = Date()
        let hourStart = calendar.dateInterval(of: .hour, for: now)?.start ?? now
        let halfHour = calendar.component(.minute, from: now) >= 30 ? 30.0 * 60 : 0
        return hourStart.addingTimeInterval(halfHour - 30 * 60 + Double(startOffsetHours) * 3600)
    }

    private var guide: some View {
        let start = windowStart
        let end = start.addingTimeInterval(Double(visibleHours) * 3600)
        let channels = catalog.channelsWithGuide.filter {
            filter.isEmpty || $0.name.localizedCaseInsensitiveContains(filter)
        }

        return VStack(spacing: 0) {
            toolbarRow
            Divider()
            ScrollView([.vertical, .horizontal]) {
                VStack(alignment: .leading, spacing: 0) {
                    timeHeader(start: start)
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(channels) { channel in
                            row(channel: channel, start: start, end: end)
                            Divider()
                        }
                    }
                }
                .overlay(alignment: .topLeading) { nowLine(start: start, end: end) }
            }
        }
        .popover(item: $selected) { programme in
            ProgrammeDetail(programme: programme, timeZone: timeZone) {
                if let channel = catalog.channelsWithGuide.first(where: { catalog.guideID(for: $0) == programme.channelID }) {
                    selected = nil
                    model.play(channel, in: channels, title: "TV Guide")
                }
            }
        }
    }

    private var toolbarRow: some View {
        HStack(spacing: 12) {
            Button { startOffsetHours -= 3 } label: { Image(systemName: "chevron.left") }
                .help("Earlier")
            Button("Now") { startOffsetHours = 0 }
            Button { startOffsetHours += 3 } label: { Image(systemName: "chevron.right") }
                .help("Later")
            Text(dayLabel).font(.headline)
            Spacer()
            TextField("Filter channels", text: $filter).textFieldStyle(.roundedBorder).frame(width: 180)
            Picker("Time zone", selection: $timeZoneID) {
                Text("Local (\(TimeZone.current.abbreviation() ?? TimeZone.current.identifier))")
                    .tag(TimeZone.current.identifier)
                Text("UTC").tag("UTC")
                ForEach(Self.extraZones, id: \.self) { Text($0.replacingOccurrences(of: "_", with: " ")).tag($0) }
            }
            .frame(width: 230)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private static let extraZones = ["Asia/Jakarta", "Asia/Brunei", "Asia/Kuala_Lumpur", "Asia/Singapore",
                                     "Asia/Tokyo", "Asia/Seoul", "Asia/Kolkata", "Asia/Riyadh", "Europe/London",
                                     "Europe/Berlin", "Europe/Paris", "America/New_York", "America/Los_Angeles",
                                     "Australia/Sydney"]

    private var dayLabel: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        formatter.timeZone = timeZone
        formatter.doesRelativeDateFormatting = true
        return formatter.string(from: windowStart)
    }

    private func timeFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        formatter.timeZone = timeZone
        return formatter
    }

    private func timeHeader(start: Date) -> some View {
        let formatter = timeFormatter()
        return HStack(spacing: 0) {
            Color.clear.frame(width: channelColumnWidth, height: 30)
            ForEach(0..<(visibleHours * 2), id: \.self) { slot in
                Text(formatter.string(from: start.addingTimeInterval(Double(slot) * 1800)))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: hourWidth / 2, height: 30, alignment: .leading)
                    .padding(.leading, 6)
                    .overlay(alignment: .leading) { Rectangle().fill(Theme.stroke).frame(width: 1) }
            }
        }
        .background(Theme.surface)
    }

    private func row(channel: Channel, start: Date, end: Date) -> some View {
        let formatter = timeFormatter()
        let programmes = catalog.schedule(for: channel, from: start, to: end)
        return HStack(spacing: 0) {
            Button { model.play(channel, in: catalog.channelsWithGuide, title: "TV Guide") } label: {
                HStack(spacing: 8) {
                    ChannelLogoView(channel: channel, size: 34, cornerRadius: 8)
                    Text(channel.name).font(.callout.weight(.medium)).lineLimit(2)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .frame(width: channelColumnWidth, height: rowHeight)
                .background(Theme.surface)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Watch \(channel.name)")

            ZStack(alignment: .topLeading) {
                Color.clear.frame(width: hourWidth * CGFloat(visibleHours), height: rowHeight)
                ForEach(programmes) { programme in
                    let clippedStart = max(programme.start, start)
                    let clippedEnd = min(programme.stop, end)
                    let x = CGFloat(clippedStart.timeIntervalSince(start) / 3600) * hourWidth
                    let width = max(4, CGFloat(clippedEnd.timeIntervalSince(clippedStart) / 3600) * hourWidth - 3)
                    ProgrammeBlock(programme: programme, isNow: programme.isAiring(at: Date()),
                                   timeText: formatter.string(from: programme.start))
                        .frame(width: width, height: rowHeight - 8)
                        .offset(x: x + 1.5, y: 4)
                        .onTapGesture { selected = programme }
                }
            }
        }
    }

    private func nowLine(start: Date, end: Date) -> some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let now = context.date
            if now >= start && now <= end {
                Rectangle()
                    .fill(Theme.live)
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
                    .offset(x: channelColumnWidth + CGFloat(now.timeIntervalSince(start) / 3600) * hourWidth)
                    .allowsHitTesting(false)
            }
        }
    }
}

private struct ProgrammeBlock: View {
    let programme: Programme
    let isNow: Bool
    let timeText: String
    @State private var hovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(programme.title).font(.callout.weight(.semibold)).lineLimit(1)
            Text(timeText).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isNow ? Theme.accent.opacity(hovered ? 0.35 : 0.25)
                      : (hovered ? Theme.surfaceRaised : Theme.surface))
        )
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(isNow ? Theme.accent.opacity(0.6) : Theme.stroke))
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .help(programme.title)
    }
}

private struct ProgrammeDetail: View {
    let programme: Programme
    let timeZone: TimeZone
    var onWatch: () -> Void

    var body: some View {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.timeZone = timeZone
        let endFormatter = DateFormatter()
        endFormatter.dateStyle = .none
        endFormatter.timeStyle = .short
        endFormatter.timeZone = timeZone
        return VStack(alignment: .leading, spacing: 10) {
            Text(programme.title).font(.title3.weight(.bold))
            if let subtitle = programme.subtitle { Text(subtitle).font(.headline).foregroundStyle(.secondary) }
            Text("\(formatter.string(from: programme.start)) – \(endFormatter.string(from: programme.stop))")
                .font(.callout)
            Text(Formatters.duration(programme.stop.timeIntervalSince(programme.start)))
                .font(.caption).foregroundStyle(.secondary)
            if programme.isAiring(at: Date()) {
                ProgressView(value: programme.progress(at: Date())).tint(Theme.accent)
            }
            if !programme.categories.isEmpty {
                Text(programme.categories.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
            }
            if let description = programme.description {
                ScrollView { Text(description).font(.body).frame(maxWidth: .infinity, alignment: .leading) }
                    .frame(maxHeight: 180)
            }
            Button("Watch Channel", action: onWatch).buttonStyle(.borderedProminent)
        }
        .padding(18)
        .frame(width: 360)
    }
}
