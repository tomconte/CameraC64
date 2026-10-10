import SwiftUI

// In landscape, the TV sits in the middle of the screen, between two columns
// of controls: on the left, the switches and the choices; on the right, the
// big key, whichever way the phone is turned. Each column is laid out as the
// user sees it, then turned with the phone, as the screen stays in portrait.

extension View {
    /// Lays out a column beside the TV in landscape upright, as the user sees
    /// it, at `size`, and turns it with the phone. On the screen, which stays
    /// in portrait, the column takes `size` turned a quarter round.
    func turned(_ rotation: Angle, size: CGSize) -> some View {
        frame(width: size.width, height: size.height)
            .rotationEffect(rotation)
            .frame(width: size.height, height: size.width)
    }
}

/// The column on the left of the TV in landscape: the badge, then flash, the
/// CRT switch and settings, which are in the top bar with the phone upright,
/// then the mode dial and the monitor keys, or in a review, the mode strip.
struct ControlsColumn: View {
    var model: CameraModel
    /// Each mode's picture of the display window, for the mode strip.
    var thumbnails: [PictureMode: CGImage]
    var onFlash: () -> Void
    var onCRT: () -> Void
    var onPower: () -> Void
    var onSettings: () -> Void
    var onSelectMode: (PictureMode) -> Void
    var onSelectMonitor: (Monitor) -> Void
    var onSelectReviewMode: (PictureMode) -> Void

    var body: some View {
        VStack(spacing: 12) {
            // As in the top bar, the badge switches the TV off and on.
            Button(action: onPower) {
                CameraBadge(compact: true)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .powerSwitchAccessibility(tvOn: model.tvOn)
            HStack(spacing: 6) {
                if model.stage == .live {
                    SwitchKey(
                        symbol: model.flashOn ? "bolt.fill" : "bolt.slash.fill", isOn: model.flashOn,
                        label: model.flashOn ? "Flash on" : "Flash off", action: onFlash)
                }
                SwitchKey(symbol: "tv", isOn: model.crtShown, label: model.crtSwitchLabel, action: onCRT)
                SwitchKey(symbol: "gearshape.fill", label: "Settings", action: onSettings)
            }
            if model.stage == .live {
                CompactModeDial(selection: model.mode, onSelect: onSelectMode)
                CompactMonitorBank(selection: model.monitor, onSelect: onSelectMonitor)
            } else {
                CompactModeStrip(selection: model.reviewMode, thumbnails: thumbnails, onSelect: onSelectReviewMode)
            }
        }
        .padding(.vertical, 6)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// The column on the right of the TV in landscape: the big key in the
/// middle, the camera switch above it, or in a review, the actions, and the
/// last picture below.
struct ShutterColumn<Actions: View>: View {
    /// The height of the slots above and below the big key, which keep it in
    /// the middle: room for the review's actions.
    static var slotHeight: CGFloat { 92 }

    var stage: CameraModel.Stage
    var lastShot: PictureMode?
    /// The last picture's display window, once it is made.
    var thumbnail: CGImage?
    var onLastPicture: () -> Void
    var onKey: () -> Void
    var onFlip: () -> Void
    /// The review's actions.
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if stage == .live {
                    FlipKey(action: onFlip)
                } else {
                    actions
                }
            }
            .frame(height: Self.slotHeight, alignment: .top)
            Spacer(minLength: 12)
            CaptureKey(stage: stage, width: 112, action: onKey)
            Spacer(minLength: 12)
            LastPictureButton(lastShot: lastShot, thumbnail: thumbnail, action: onLastPicture)
                .frame(height: Self.slotHeight, alignment: .bottom)
        }
        .padding(.vertical, 14)
    }
}

/// A small key on the case for one of the top bar's switches, in landscape,
/// with a lamp that shows whether it is on.
struct SwitchKey: View {
    var symbol: String
    /// Whether the lamp is lit, or nil for a key without a lamp.
    var isOn: Bool?
    var label: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                LED(isOn: isOn ?? false, size: 5)
                    .opacity(isOn == nil ? 0 : 1)
            }
        }
        .buttonStyle(KeyButtonStyle(width: 34, height: 42, cornerRadius: 8))
        .accessibilityLabel(label)
    }
}

/// The mode dial in landscape: the modes in rows of two, the selected one lit.
/// A swipe on the TV moves along it too.
struct CompactModeDial: View {
    var selection: PictureMode
    var onSelect: (PictureMode) -> Void

    var body: some View {
        Grid(horizontalSpacing: 4, verticalSpacing: 4) {
            ForEach(PictureMode.allCases.rows(of: 2), id: \.startIndex) { row in
                GridRow {
                    ForEach(row) { mode in
                        key(mode)
                    }
                }
            }
        }
    }

    private func key(_ mode: PictureMode) -> some View {
        let isSelected = mode == selection
        return Button {
            onSelect(mode)
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(isSelected ? Look.ledOn : Color.clear)
                    .frame(width: 6, height: 6)
                Text(mode.shortName)
            }
            .font(Look.caseLabelFont)
            .foregroundStyle(isSelected ? Look.labelSelected : Look.label)
            .fixedSize()
            .frame(width: 56, height: 24, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mode.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The monitor keys in landscape: three rows of two, colour monitors on the
/// left as on the camera's bank, with the lamp and name on each key.
struct CompactMonitorBank: View {
    static let keySize = CGSize(width: 54, height: 44)

    var selection: Monitor
    var onSelect: (Monitor) -> Void

    var body: some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 6) {
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
    }

    private func key(_ monitor: Monitor) -> some View {
        let isSelected = monitor == selection
        return Button {
            onSelect(monitor)
        } label: {
            Self.label(monitor, isSelected: isSelected)
        }
        .buttonStyle(KeyButtonStyle(width: Self.keySize.width, height: Self.keySize.height, cornerRadius: 6))
        .accessibilityLabel(monitor.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// A key's label: its lamp and the monitor's short name.
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

/// The mode strip in landscape: the shot in every mode, in rows of two.
struct CompactModeStrip: View {
    var selection: PictureMode
    /// Each mode's picture of the display window, once it is made.
    var thumbnails: [PictureMode: CGImage]
    var onSelect: (PictureMode) -> Void

    var body: some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            ForEach(PictureMode.allCases.rows(of: 2), id: \.startIndex) { row in
                GridRow {
                    ForEach(row) { mode in
                        picture(mode)
                    }
                }
            }
        }
    }

    private func picture(_ mode: PictureMode) -> some View {
        let isSelected = mode == selection
        return Button {
            onSelect(mode)
        } label: {
            VStack(spacing: 3) {
                ModeThumbnail(image: thumbnails[mode], isSelected: isSelected)
                    .frame(width: 54, height: 38)
                Text(mode.shortName)
                    .font(Look.smallFont)
                    .foregroundStyle(isSelected ? Look.labelSelected : Look.label)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mode.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The review's actions in landscape: keys in rows of two, without captions.
struct ActionGrid: View {
    var actions: [ReviewAction]
    /// What Share offers, or nothing while the picture is being made.
    var files: [SharedFile]
    /// Whether the picture is on its way to a C64.
    var sending: Bool
    /// Whether the TV is on.
    var tvOn = true
    var onAction: (ReviewAction) -> Void

    var body: some View {
        Grid(horizontalSpacing: 10, verticalSpacing: 8) {
            ForEach(actions.rows(of: 2), id: \.startIndex) { row in
                GridRow {
                    ForEach(row) { action in
                        ActionKey(
                            action: action, files: files, sending: sending, tvOn: tvOn, width: 48,
                            onAction: onAction)
                    }
                }
            }
        }
    }
}

extension Array {
    /// The elements in rows of `count`, for a grid.
    fileprivate func rows(of count: Int) -> [ArraySlice<Element>] {
        stride(from: 0, to: self.count, by: count).map { self[$0..<Swift.min($0 + count, self.count)] }
    }
}
