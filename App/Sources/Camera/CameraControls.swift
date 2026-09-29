import SwiftUI
import UIKit

/// The strip above the TV: flash, the CRT switch, the badge and settings.
struct TopBar: View {
    var model: CameraModel
    var rotation: Angle
    var showsTitle: Bool
    var onSettings: () -> Void

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                if model.stage == .live {
                    iconButton(
                        model.flashOn ? "bolt.fill" : "bolt.slash.fill",
                        label: model.flashOn ? "Flash on" : "Flash off",
                        color: model.flashOn ? Look.ledOn : Look.bezelInkDim
                    ) {
                        model.toggleFlash()
                    }
                }
                iconButton(
                    "tv",
                    label: model.crtOn ? "CRT effect on" : "CRT effect off",
                    color: model.crtOn ? Look.ledOn : Look.bezelInkDim
                ) {
                    model.toggleCRT()
                }
                Spacer()
                iconButton("gearshape.fill", label: "Settings", color: Look.bezelInk, action: onSettings)
            }
            .padding(.horizontal, 8)
            if showsTitle {
                if model.stage == .live {
                    CameraBadge()
                } else {
                    Label("KEPT IN GALLERY", systemImage: "checkmark")
                        .font(Look.caseLabelFont)
                        .tracking(1.2)
                        .foregroundStyle(Look.bezelInk)
                }
            }
        }
        .frame(height: ScreenMetrics.topBarHeight)
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
                        HStack(spacing: 3) {
                            Text(mode.name)
                            if mode.isAdvanced {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 8, weight: .bold))
                            }
                        }
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
                .accessibilityLabel(mode.isAdvanced ? "\(mode.name), advanced mode" : mode.name)
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
                        if mode.isAdvanced {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 7, weight: .bold))
                        }
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
                .accessibilityLabel(mode.isAdvanced ? "\(mode.name), advanced mode" : mode.name)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}

/// The monitor bank: six keys with lamps, like the 2013 app's MON SELEC panel.
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
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Look.caseLine, lineWidth: 1.5)
        }
        .overlay(alignment: .topLeading) {
            Text("MONITOR")
                .font(Look.smallFont)
                .tracking(1.4)
                .foregroundStyle(Look.label)
                .padding(.horizontal, 6)
                .background(Look.caseColor)
                .offset(x: 14, y: -7)
        }
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

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) {
            KeyFace(isPressed: configuration.isPressed, cornerRadius: 5)
                .frame(width: 30, height: 30)
            LED(isOn: isSelected)
            configuration.label
                .font(Look.caseLabelFont)
                .tracking(0.8)
                .foregroundStyle(isSelected ? Look.labelSelected : Look.label)
            Spacer(minLength: 0)
        }
        .frame(height: 38)
        .contentShape(Rectangle())
    }
}

/// The monitor bank in landscape: smaller keys with the lamp and name on them,
/// turned upright.
struct CompactMonitorBank: View {
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
            HStack(spacing: 4) {
                LED(isOn: isSelected, size: 6)
                Text(monitor.shortName)
            }
            .font(Look.smallFont)
            .foregroundStyle(isSelected ? Look.labelSelected : Look.ink)
            .fixedSize()
            .rotationEffect(rotation)
        }
        .buttonStyle(KeyButtonStyle(width: 56, height: 44, cornerRadius: 6))
        .accessibilityLabel(monitor.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The row at the bottom: the last picture, the big key, and the camera switch.
/// After a shot, the big key goes back to the camera.
struct ShutterRow: View {
    var stage: CameraModel.Stage
    var lastShot: PictureMode?
    var rotation: Angle
    var showsCaption: Bool
    var onGallery: () -> Void
    var onKey: () -> Void
    var onFlip: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            Button(action: onGallery) {
                thumbnail
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

    @ViewBuilder private var thumbnail: some View {
        if let lastShot {
            Image(lastShot.sample)
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

/// After a shot: the photo in every mode. Advanced modes show their result with
/// a lock.
struct ModeStrip: View {
    var selection: PictureMode
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
                            ModeThumbnail(mode: mode, isSelected: isSelected)
                                .frame(width: 78, height: 54)
                            Text(mode.name)
                                .font(Look.smallFont)
                                .tracking(0.8)
                                .foregroundStyle(isSelected ? Look.labelSelected : Look.label)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(mode.isAdvanced ? "\(mode.name), advanced mode" : mode.name)
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
                        ModeThumbnail(mode: mode, isSelected: isSelected)
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
                .accessibilityLabel(mode.isAdvanced ? "\(mode.name), advanced mode" : mode.name)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}

/// One picture in the mode strip, at the TV's 3:2 shape.
struct ModeThumbnail: View {
    var mode: PictureMode
    var isSelected: Bool

    var body: some View {
        Image(mode.sample)
            .resizable()
            .interpolation(.none)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .overlay(alignment: .topTrailing) {
                if mode.isAdvanced {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Look.key)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Look.bezel.opacity(0.85)))
                        .padding(3)
                }
            }
            .padding(3)
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Look.ledOn, lineWidth: 2)
                }
            }
    }
}

/// What the review can do with a picture.
enum ReviewAction: CaseIterable, Identifiable {
    case share
    case save
    case edit
    case send
    case delete

    var id: Self { self }

    var title: String {
        switch self {
        case .share: "SHARE"
        case .save: "SAVE"
        case .edit: "EDIT"
        case .send: "SEND TO C64"
        case .delete: "DELETE"
        }
    }

    /// The name VoiceOver reads.
    var accessibilityName: String {
        switch self {
        case .share: "Share"
        case .save: "Save to Photos"
        case .edit: "Edit"
        case .send: "Send to C64"
        case .delete: "Delete"
        }
    }

    var symbol: String {
        switch self {
        case .share: "square.and.arrow.up"
        case .save: "square.and.arrow.down"
        case .edit: "slider.horizontal.3"
        case .send: "antenna.radiowaves.left.and.right"
        case .delete: "trash"
        }
    }
}

/// The review's actions. Share sends the picture as on TV, border included.
struct ActionRow: View {
    /// The picture to share, or nil while it is being drawn.
    var shareImage: UIImage?
    var rotation: Angle
    var showsCaptions: Bool
    var onAction: (ReviewAction) -> Void

    private var keyWidth: CGFloat { showsCaptions ? 52 : 48 }

    var body: some View {
        HStack(alignment: .top, spacing: showsCaptions ? 10 : 12) {
            ForEach(ReviewAction.allCases) { action in
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
        if action == .share, let shareImage {
            let image = Image(uiImage: shareImage)
            ShareLink(item: image, preview: SharePreview("Camera C64 picture", image: image)) {
                icon(for: action)
            }
            .buttonStyle(KeyButtonStyle(width: keyWidth, height: 42))
            .accessibilityLabel(action.accessibilityName)
        } else {
            Button {
                onAction(action)
            } label: {
                icon(for: action)
            }
            .buttonStyle(KeyButtonStyle(width: keyWidth, height: 42))
            .disabled(action == .share)
            .accessibilityLabel(action.accessibilityName)
        }
    }

    private func icon(for action: ReviewAction) -> some View {
        Image(systemName: action.symbol)
            .font(.system(size: 18, weight: .semibold))
            .rotationEffect(rotation)
    }
}
