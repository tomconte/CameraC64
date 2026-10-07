import SwiftUI

/// How the review lays out its controls.
enum ReviewLayout {
    /// With captions under the keys.
    case roomy
    /// Closer together, without captions, where the roomy layout does not
    /// fit, as on an iPhone SE.
    case tight
}

/// The controls below the TV in a review, with the phone upright (docs/UX.md,
/// section 5): the mode strip, the monitor bank, the actions and the shutter
/// row. They fit below the TV on every iPhone, and the roomy layout on all but
/// the smallest: `LayoutTests` measures them. In landscape, the review has no
/// monitor keys: the phone turns upright to change the monitor.
struct ReviewPanel<Actions: View, Shutter: View>: View {
    var mode: PictureMode
    var monitor: Monitor
    /// Each mode's picture of the display window, once it is made.
    var thumbnails: [PictureMode: CGImage]
    var onSelectMode: (PictureMode) -> Void
    var onSelectMonitor: (Monitor) -> Void
    /// The layout to keep to, or nil for the roomy one where it fits and the
    /// tight one elsewhere.
    var layout: ReviewLayout?
    /// The review's actions, with captions or without.
    @ViewBuilder var actions: (_ showsCaptions: Bool) -> Actions
    /// The shutter row, with its caption or without.
    @ViewBuilder var shutter: (_ showsCaption: Bool) -> Shutter

    var body: some View {
        if let layout {
            controls(layout)
        } else {
            ViewThatFits(in: .vertical) {
                controls(.roomy)
                controls(.tight)
            }
        }
    }

    private func controls(_ layout: ReviewLayout) -> some View {
        let roomy = layout == .roomy
        return VStack(spacing: roomy ? 12 : 8) {
            ModeStrip(selection: mode, thumbnails: thumbnails, onSelect: onSelectMode)
            ReviewMonitorBank(selection: monitor, onSelect: onSelectMonitor)
                .padding(.top, 6)
            actions(roomy)
            if roomy {
                Spacer(minLength: 8)
            }
            shutter(roomy)
        }
        .padding(.top, roomy ? 12 : 8)
        .padding(.bottom, roomy ? 6 : 4)
    }
}

/// The monitor bank in a review: the camera's monitor keys, smaller, in two
/// rows of three, colour monitors first, so that the review fits every iPhone
/// held upright. It is apart from the camera's bank (`MonitorBank`), so that
/// each can change on its own.
struct ReviewMonitorBank: View {
    var selection: Monitor
    var onSelect: (Monitor) -> Void

    var body: some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 4) {
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
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 6)
        .casePanel("MONITOR")
        .padding(.horizontal, 16)
    }

    private func key(_ monitor: Monitor) -> some View {
        Button {
            onSelect(monitor)
        } label: {
            Text(monitor.shortName)
        }
        .buttonStyle(MonitorKeyStyle(isSelected: monitor == selection, keySize: 26, spacing: 8, height: 32))
        .accessibilityLabel(monitor.name)
        .accessibilityAddTraits(monitor == selection ? .isSelected : [])
    }
}
