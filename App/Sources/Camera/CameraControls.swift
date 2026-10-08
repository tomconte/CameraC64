import SwiftUI
import UIKit

/// The strip above the TV: flash, the CRT switch, the badge, which is the
/// TV's power switch, and settings.
struct TopBar: View {
    var model: CameraModel
    var rotation: Angle
    var showsTitle: Bool
    var onFlash: () -> Void
    var onCRT: () -> Void
    var onPower: () -> Void
    var onSettings: () -> Void

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                if model.stage == .live {
                    iconButton(
                        model.flashOn ? "bolt.fill" : "bolt.slash.fill",
                        label: model.flashOn ? "Flash on" : "Flash off",
                        color: model.flashOn ? Look.ledOn : Look.bezelInkDim,
                        action: onFlash)
                }
                iconButton(
                    "tv",
                    label: crtLabel,
                    color: model.crtShown ? Look.ledOn : Look.bezelInkDim,
                    action: onCRT)
                Spacer()
                iconButton("gearshape.fill", label: "Settings", color: Look.bezelInk, action: onSettings)
            }
            .padding(.horizontal, 8)
            if showsTitle {
                // As the 2013 app's title bar did, the badge switches the TV
                // off and on.
                Button(action: onPower) {
                    CameraBadge()
                        .padding(.horizontal, 8)
                        .frame(height: ScreenMetrics.topBarHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(model.tvOn ? "TV on" : "TV off")
                .accessibilityHint(model.tvOn ? "Switches the TV and the camera off" : "Switches the TV back on")
            }
        }
        .frame(height: ScreenMetrics.topBarHeight)
    }

    /// What VoiceOver reads for the CRT switch.
    private var crtLabel: String {
        guard model.monitor.hasCRT else { return "CRT effect, not on Sharp" }
        return model.crtOn ? "CRT effect on" : "CRT effect off"
    }

    private func iconButton(
        _ symbol: String, label: String, color: Color, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(Look.iconFont)
                .foregroundStyle(color)
                .rotationEffect(rotation)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// The mode dial: the graphics modes by name, the selected one lit. A swipe on
/// the TV moves along it too.
struct ModeDial: View {
    var selection: PictureMode
    var onSelect: (PictureMode) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ForEach(PictureMode.allCases) { mode in
                let isSelected = mode == selection
                Button {
                    onSelect(mode)
                } label: {
                    VStack(spacing: 6) {
                        Text(mode.name)
                        Circle()
                            .fill(isSelected ? Look.ledOn : Color.clear)
                            .frame(width: 6, height: 6)
                    }
                    .font(Look.dialFont)
                    .tracking(0.8)
                    .foregroundStyle(isSelected ? Look.labelSelected : Look.label)
                    .fixedSize()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mode.name)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}

/// The mode dial in landscape: the same row, each label turned upright.
struct CompactModeDial: View {
    var selection: PictureMode
    var rotation: Angle
    var onSelect: (PictureMode) -> Void

    var body: some View {
        HStack(spacing: 12) {
            ForEach(PictureMode.allCases) { mode in
                let isSelected = mode == selection
                Button {
                    onSelect(mode)
                } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(isSelected ? Look.ledOn : Color.clear)
                            .frame(width: 6, height: 6)
                        Text(mode.shortName)
                    }
                    .font(Look.smallFont)
                    .foregroundStyle(isSelected ? Look.labelSelected : Look.label)
                    .fixedSize()
                    .frame(width: 60, height: 24, alignment: .leading)
                    .rotationEffect(rotation)
                    .frame(width: 24, height: 60)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mode.name)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}

/// The monitor bank on the camera: six keys with lamps, like the 2013 app's
/// MON SELEC panel. The review has its own (`ReviewMonitorBank`).
struct MonitorBank: View {
    var selection: Monitor
    var onSelect: (Monitor) -> Void

    var body: some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 0) {
            GridRow {
                key(.tv)
                key(.blackAndWhite)
            }
            GridRow {
                key(.commodoreMonitor)
                key(.amber)
            }
            GridRow {
                key(.sharp)
                key(.green)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .casePanel("MONITOR")
        .padding(.horizontal, 24)
    }

    private func key(_ monitor: Monitor) -> some View {
        Button {
            onSelect(monitor)
        } label: {
            Text(monitor.name)
        }
        .buttonStyle(MonitorKeyStyle(isSelected: monitor == selection))
        .accessibilityAddTraits(monitor == selection ? .isSelected : [])
    }
}

/// A monitor key: a square key, its lamp, and the monitor's name printed beside it.
struct MonitorKeyStyle: ButtonStyle {
    var isSelected: Bool
    /// The key's side.
    var keySize: CGFloat = 30
    /// The space between the key, its lamp and the name.
    var spacing: CGFloat = 10
    var height: CGFloat = 38

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: spacing) {
            KeyFace(isPressed: configuration.isPressed, cornerRadius: 5)
                .frame(width: keySize, height: keySize)
            LED(isOn: isSelected)
            configuration.label
                .font(Look.caseLabelFont)
                .tracking(0.8)
                .foregroundStyle(isSelected ? Look.labelSelected : Look.label)
                .fixedSize()
            Spacer(minLength: 0)
        }
        .frame(height: height)
        .contentShape(Rectangle())
    }
}

/// The monitor bank on the camera in landscape: smaller keys with the lamp and
/// name on them, turned upright.
struct CompactMonitorBank: View {
    /// A key's size, as the screen is laid out. Its label turns upright with
    /// the phone, so it runs along the key's height, which is the key's width
    /// as the user sees it.
    static let keySize = CGSize(width: 56, height: 52)

    var selection: Monitor
    var rotation: Angle
    var onSelect: (Monitor) -> Void

    var body: some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 6) {
            GridRow {
                key(.tv)
                key(.commodoreMonitor)
                key(.sharp)
            }
            GridRow {
                key(.blackAndWhite)
                key(.amber)
                key(.green)
            }
        }
    }

    private func key(_ monitor: Monitor) -> some View {
        let isSelected = monitor == selection
        return Button {
            onSelect(monitor)
        } label: {
            Self.label(monitor, isSelected: isSelected)
                .rotationEffect(rotation)
        }
        .buttonStyle(KeyButtonStyle(width: Self.keySize.width, height: Self.keySize.height, cornerRadius: 6))
        .accessibilityLabel(monitor.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// A key's label, upright: its lamp and the monitor's short name.
    static func label(_ monitor: Monitor, isSelected: Bool) -> some View {
        HStack(spacing: 4) {
            LED(isOn: isSelected, size: 6)
            Text(monitor.shortName)
        }
        .font(Look.smallFont)
        .foregroundStyle(isSelected ? Look.labelSelected : Look.ink)
        .fixedSize()
    }
}

/// The row at the bottom: the last picture, the big key, and the camera switch.
/// After a shot, the big key goes back to the camera, and until the next one,
/// the last picture opens it again.
struct ShutterRow: View {
    var stage: CameraModel.Stage
    var lastShot: PictureMode?
    /// The last picture's display window, once it is made.
    var thumbnail: CGImage?
    var rotation: Angle
    var showsCaption: Bool
    var onLastPicture: () -> Void
    var onKey: () -> Void
    var onFlip: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            Button(action: onLastPicture) {
                lastPicture
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
            .accessibilityLabel(lastShot == nil ? "No pictures yet" : "Last picture")
            Spacer()
            VStack(spacing: 6) {
                Button(action: onKey) {
                    keyLabel
                }
                .buttonStyle(CaptureKeyStyle())
                .accessibilityLabel(stage == .live ? "Capture" : "Back to the camera")
                if showsCaption {
                    Text(stage == .live ? "CAPTURE" : "BACK TO CAMERA")
                        .font(Look.caseLabelFont)
                        .tracking(1.6)
                        .foregroundStyle(Look.label)
                }
            }
            Spacer()
            if stage == .live {
                Button(action: onFlip) {
                    Image(systemName: "arrow.triangle.2.circlepath.camera")
                        .font(.system(size: 20, weight: .semibold))
                        .rotationEffect(rotation)
                }
                .buttonStyle(KeyButtonStyle(width: 56, height: 56, cornerRadius: 12))
                .padding(.top, 4)
                .accessibilityLabel("Switch camera")
            } else {
                Color.clear
                    .frame(width: 56, height: 56)
            }
        }
        .padding(.horizontal, 28)
    }

    @ViewBuilder private var lastPicture: some View {
        if lastShot != nil, let thumbnail {
            Image(decorative: thumbnail, scale: 1)
                .resizable()
                .interpolation(.none)
                .scaledToFill()
                .frame(width: 52, height: 52)
                .rotationEffect(rotation)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Look.key, lineWidth: 2)
                }
                .frame(width: 56, height: 56)
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(Look.bezel.opacity(0.85))
                .frame(width: 56, height: 56)
        }
    }

    @ViewBuilder private var keyLabel: some View {
        if stage == .review && rotation == .zero {
            HStack(spacing: 8) {
                Image(systemName: "camera.fill")
                Text("LIVE")
                    .tracking(1.5)
            }
            .font(.system(size: 17, weight: .heavy).width(.condensed))
        } else {
            Image(systemName: "camera.fill")
                .font(.system(size: 26, weight: .medium))
                .rotationEffect(rotation)
        }
    }
}

/// After a shot: the photo in every mode of the dial.
struct ModeStrip: View {
    var selection: PictureMode
    /// Each mode's picture of the display window, once it is made.
    var thumbnails: [PictureMode: CGImage]
    var onSelect: (PictureMode) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(PictureMode.allCases) { mode in
                    let isSelected = mode == selection
                    Button {
                        onSelect(mode)
                    } label: {
                        VStack(spacing: 6) {
                            ModeThumbnail(image: thumbnails[mode], isSelected: isSelected)
                                .frame(width: 78, height: 54)
                            Text(mode.name)
                                .font(Look.smallFont)
                                .tracking(0.8)
                                .foregroundStyle(isSelected ? Look.labelSelected : Look.label)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(mode.name)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }
}

/// The mode strip in landscape: the same pictures, each turned upright.
struct CompactModeStrip: View {
    var selection: PictureMode
    var thumbnails: [PictureMode: CGImage]
    var rotation: Angle
    var onSelect: (PictureMode) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(PictureMode.allCases) { mode in
                let isSelected = mode == selection
                Button {
                    onSelect(mode)
                } label: {
                    VStack(spacing: 3) {
                        ModeThumbnail(image: thumbnails[mode], isSelected: isSelected)
                            .frame(width: 72, height: 51)
                        Text(mode.shortName)
                            .font(Look.smallFont)
                            .foregroundStyle(isSelected ? Look.labelSelected : Look.label)
                    }
                    .frame(width: 72, height: 66)
                    .rotationEffect(rotation)
                    .frame(width: 66, height: 72)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mode.name)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}

/// One picture in the mode strip, at the TV's 3:2 shape.
struct ModeThumbnail: View {
    /// The mode's picture, or nil while it is being made.
    var image: CGImage?
    var isSelected: Bool

    var body: some View {
        picture
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .padding(3)
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Look.ledOn, lineWidth: 2)
                }
            }
    }

    @ViewBuilder private var picture: some View {
        if let image {
            Image(decorative: image, scale: 1)
                .resizable()
                .interpolation(.none)
        } else {
            Look.bezel
        }
    }
}

/// What the review can do with a picture (docs/UX.md, section 5).
enum ReviewAction: Identifiable {
    case share
    case save
    case send
    case delete

    var id: Self { self }

    /// The actions, in order. Send to C64 is there once an Ultimate is set up.
    static func all(canSend: Bool) -> [ReviewAction] {
        canSend ? [.share, .save, .send, .delete] : [.share, .save, .delete]
    }

    var title: String {
        switch self {
        case .share: "SHARE"
        case .save: "SAVE"
        case .send: "SEND TO C64"
        case .delete: "DELETE"
        }
    }

    /// The name VoiceOver reads.
    var accessibilityName: String {
        switch self {
        case .share: "Share"
        case .save: "Save to Photos"
        case .send: "Send to C64"
        case .delete: "Delete"
        }
    }

    var symbol: String {
        switch self {
        case .share: "square.and.arrow.up"
        case .save: "square.and.arrow.down"
        case .send: "antenna.radiowaves.left.and.right"
        case .delete: "trash"
        }
    }
}

/// The review's actions. Share offers the picture as on TV first, then the
/// pixel-exact PNG and the C64 files.
struct ActionRow: View {
    var actions: [ReviewAction]
    /// What Share offers, or nothing while the picture is being made.
    var files: [SharedFile]
    /// Whether the picture is on its way to a C64.
    var sending: Bool
    /// Whether the TV is on. While it is off, Share switches it back on, as
    /// every key does, instead of opening its menu.
    var tvOn = true
    var rotation: Angle
    var showsCaptions: Bool
    var onAction: (ReviewAction) -> Void

    private var keyWidth: CGFloat { showsCaptions ? 52 : 48 }

    var body: some View {
        HStack(alignment: .top, spacing: showsCaptions ? 14 : 12) {
            ForEach(actions) { action in
                VStack(spacing: 5) {
                    key(for: action)
                    if showsCaptions {
                        Text(action.title)
                            .font(.system(size: 9.5, weight: .bold).width(.condensed))
                            .tracking(0.5)
                            .foregroundStyle(Look.label)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
            }
        }
    }

    @ViewBuilder private func key(for action: ReviewAction) -> some View {
        switch action {
        case .share where tvOn:
            Menu {
                ForEach(files, id: \.kind) { file in
                    let preview = Image(uiImage: UIImage(cgImage: file.picture.window))
                    ShareLink(item: file, preview: SharePreview(file.kind.title, image: preview)) {
                        Label(file.kind.title, systemImage: file.kind.symbol)
                    }
                }
            } label: {
                icon(for: action)
            }
            .menuStyle(.button)
            .buttonStyle(KeyButtonStyle(width: keyWidth, height: 42))
            .disabled(files.isEmpty)
            .accessibilityLabel(action.accessibilityName)
        case .send where sending:
            Button {
            } label: {
                ProgressView()
                    .tint(Look.ink)
            }
            .buttonStyle(KeyButtonStyle(width: keyWidth, height: 42))
            .disabled(true)
            .accessibilityLabel("Sending to C64")
        case .share, .save, .send, .delete:
            Button {
                onAction(action)
            } label: {
                icon(for: action)
            }
            .buttonStyle(KeyButtonStyle(width: keyWidth, height: 42))
            .accessibilityLabel(action.accessibilityName)
        }
    }

    private func icon(for action: ReviewAction) -> some View {
        Image(systemName: action.symbol)
            .font(.system(size: 18, weight: .semibold))
            .rotationEffect(rotation)
    }
}
