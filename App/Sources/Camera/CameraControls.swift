import SwiftUI
import UIKit

/// The strip above the TV with the phone upright: flash, the CRT switch, the
/// badge, which is the TV's power switch, and settings. In landscape, they
/// move to the column beside the TV (`ControlsColumn`).
struct TopBar: View {
    var model: CameraModel
    var onFlash: () -> Void
    var onCRT: () -> Void
    var onPower: () -> Void
    var onSettings: () -> Void

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                if model.stage == .live {
                    CaseSwitch(
                        title: "FLASH", isOn: model.flashOn, accessibilityName: model.flashSwitchLabel,
                        action: onFlash)
                }
                Spacer()
                CaseSwitch(title: "CRT", isOn: model.crtShown, accessibilityName: model.crtSwitchLabel, action: onCRT)
                SettingsKey(action: onSettings)
                    .padding(.leading, 1)
            }
            .padding(.leading, 12)
            .padding(.trailing, 1)
            // As the 2013 app's title bar did, the badge switches the TV off
            // and on.
            Button(action: onPower) {
                CameraBadge()
                    .padding(.horizontal, 8)
                    .frame(height: ScreenMetrics.topBarHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .powerSwitchAccessibility(tvOn: model.tvOn)
        }
        .frame(height: ScreenMetrics.topBarHeight)
    }
}

extension CameraModel {
    /// What VoiceOver reads for the flash switch.
    var flashSwitchLabel: String { flashOn ? "Flash on" : "Flash off" }

    /// What VoiceOver reads for the CRT switch.
    var crtSwitchLabel: String {
        guard monitor.hasCRT else { return "CRT effect, not on Sharp" }
        return crtOn ? "CRT effect on" : "CRT effect off"
    }
}

extension View {
    /// What VoiceOver reads for the badge, which switches the TV off and on.
    func powerSwitchAccessibility(tvOn: Bool) -> some View {
        accessibilityLabel(tvOn ? "TV on" : "TV off")
            .accessibilityHint(tvOn ? "Switches the TV and the camera off" : "Switches the TV back on")
    }
}

/// The mode dial: the graphics modes by name, each with its lamp, the selected
/// one lit. A swipe on the TV moves along it too.
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
                            .font(Look.dialFont)
                            .tracking(0.8)
                            .engraved(isSelected ? Look.labelSelected : Look.label)
                        LED(isOn: isSelected, size: 5)
                    }
                    .fixedSize()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mode.name)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}

/// The monitor bank on the camera: six keys with lamps, like the 2013 app's
/// MON SELEC panel. The review has its own (`ReviewMonitorBank`), and so does
/// landscape (`CompactMonitorBank`).
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
        .accessibilityLabel(monitor.name)
        .accessibilityAddTraits(monitor == selection ? .isSelected : [])
    }
}

/// A monitor key: a square key, down for the monitor chosen, its lamp, and the
/// monitor's name engraved beside it.
struct MonitorKeyStyle: ButtonStyle {
    var isSelected: Bool
    /// The key's side.
    var keySize: CGFloat = 30
    /// The space between the key, its lamp and the name.
    var spacing: CGFloat = 10
    var height: CGFloat = 38

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: spacing) {
            SkinImage(element: Skin.monitorKey, state: isSelected || configuration.isPressed, width: keySize)
            LED(isOn: isSelected)
            configuration.label
                .font(Look.caseLabelFont)
                .tracking(0.8)
                .engraved(isSelected ? Look.labelSelected : Look.label)
                .fixedSize()
            Spacer(minLength: 0)
        }
        .frame(height: height)
        .contentShape(Rectangle())
    }
}

/// The row at the bottom: the last picture, the big key, and the camera switch.
/// After a shot, the big key goes back to the camera, and until the next one,
/// the last picture opens it again. In landscape, they move to the column
/// beside the TV (`ShutterColumn`).
struct ShutterRow: View {
    var stage: CameraModel.Stage
    var lastShot: PictureMode?
    /// The last picture's display window, once it is made.
    var thumbnail: CGImage?
    var showsCaption: Bool
    var onLastPicture: () -> Void
    var onKey: () -> Void
    var onFlip: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            LastPictureButton(lastShot: lastShot, thumbnail: thumbnail, action: onLastPicture)
                .padding(.top, 4)
            Spacer()
            VStack(spacing: 6) {
                CaptureKey(stage: stage, action: onKey)
                if showsCaption {
                    Text(stage == .live ? "CAPTURE" : "BACK TO CAMERA")
                        .font(Look.caseLabelFont)
                        .tracking(1.6)
                        .engraved(Look.label)
                        .ventClearing(cornerRadius: 7)
                }
            }
            Spacer()
            if stage == .live {
                FlipKey(action: onFlip)
                    .padding(.top, 4)
            } else {
                Color.clear
                    .frame(width: 56, height: 56)
            }
        }
        .padding(.horizontal, 28)
    }
}

/// The big brown key: it takes a picture, or in a review, goes back to the
/// camera.
struct CaptureKey: View {
    var stage: CameraModel.Stage
    var width: CGFloat = 170
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            EmptyView()
        }
        .buttonStyle(CaptureKeyStyle(width: width))
        .accessibilityLabel(stage == .live ? "Capture" : "Back to the camera")
        .ventClearing(cornerRadius: .infinity)
    }
}

/// The last picture, which opens it again for review until the next shot.
struct LastPictureButton: View {
    var lastShot: PictureMode?
    /// The last picture's display window, once it is made.
    var thumbnail: CGImage?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            picture
        }
        .buttonStyle(.plain)
        .accessibilityLabel(lastShot == nil ? "No pictures yet" : "Last picture")
        .ventClearing(cornerRadius: 8)
    }

    /// Its frame, with the picture in its window, or the window dark until
    /// there is one.
    private var picture: some View {
        SkinImage(element: Skin.lastPictureFrame, width: Skin.lastPictureFrame.face.width)
            .overlay(alignment: .topLeading) {
                if lastShot != nil, let thumbnail {
                    let window = Skin.lastPictureWindow
                    Image(decorative: thumbnail, scale: 1)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFill()
                        .frame(width: window.width, height: window.height)
                        .clipShape(RoundedRectangle(cornerRadius: Skin.lastPictureWindowRadius))
                        .offset(x: window.minX, y: window.minY)
                }
            }
            .contentShape(Rectangle())
    }
}

/// The key that turns the camera round, between the back and front cameras.
struct FlipKey: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            EmptyView()
        }
        .buttonStyle(SkinKeyStyle(element: Skin.flipKey, width: Skin.flipKey.face.width))
        .accessibilityLabel("Switch camera")
        .ventClearing(cornerRadius: 12)
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
                                .engraved(isSelected ? Look.labelSelected : Look.label)
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
}

/// The review's actions, with the phone upright. In landscape, they are in
/// the column beside the TV (`ActionGrid`).
struct ActionRow: View {
    var actions: [ReviewAction]
    /// What Share offers, or nothing while the picture is being made.
    var files: [SharedFile]
    /// Whether the picture is on its way to a C64.
    var sending: Bool
    /// Whether the TV is on.
    var tvOn = true
    var showsCaptions: Bool
    var onAction: (ReviewAction) -> Void

    private var keyWidth: CGFloat { showsCaptions ? 52 : 48 }

    var body: some View {
        HStack(alignment: .top, spacing: showsCaptions ? 14 : 12) {
            ForEach(actions) { action in
                VStack(spacing: 5) {
                    ActionKey(
                        action: action, files: files, sending: sending, tvOn: tvOn, width: keyWidth,
                        onAction: onAction)
                    if showsCaptions {
                        Text(action.title)
                            .font(.system(size: 9.5, weight: .bold).width(.condensed))
                            .tracking(0.5)
                            .engraved(Look.label)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
            }
        }
    }
}

/// A key for one of the review's actions. Share offers the picture as on TV
/// first, then the pixel-exact PNG and the C64 files.
struct ActionKey: View {
    var action: ReviewAction
    /// What Share offers, or nothing while the picture is being made.
    var files: [SharedFile]
    /// Whether the picture is on its way to a C64.
    var sending: Bool
    /// Whether the TV is on. While it is off, Share switches it back on, as
    /// every key does, instead of opening its menu.
    var tvOn: Bool
    var width: CGFloat
    var onAction: (ReviewAction) -> Void

    var body: some View {
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
                EmptyView()
            }
            .menuStyle(.button)
            .buttonStyle(key)
            .disabled(files.isEmpty)
            .accessibilityLabel(action.accessibilityName)
        case .send where sending:
            Button {
            } label: {
                ProgressView()
                    .tint(Look.pillInk)
            }
            .buttonStyle(SkinKeyStyle(element: Skin.actionKey(action), width: width, held: true))
            .disabled(true)
            .accessibilityLabel("Sending to C64")
        case .share, .save, .send, .delete:
            Button {
                onAction(action)
            } label: {
                EmptyView()
            }
            .buttonStyle(key)
            .accessibilityLabel(action.accessibilityName)
        }
    }

    /// The action's key, with its icon and colour, as the skin draws it.
    private var key: SkinKeyStyle { SkinKeyStyle(element: Skin.actionKey(action), width: width) }
}
