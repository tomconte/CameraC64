import SwiftUI

/// How the controls below the TV are laid out, in the camera and in a review.
enum PanelLayout {
    /// With captions under the keys, and grooves like the C64's vent in the
    /// room that is left.
    case roomy
    /// Closer together, without captions or grooves, where the roomy layout
    /// does not fit, as on an iPhone SE.
    case tight
}

/// The camera's controls below the TV, with the phone upright (docs/UX.md,
/// section 3): zoom, the mode dial, the monitor bank, grooves like the C64's
/// vent in the room that is left, and the shutter row in its panel. They fit
/// below the TV on every iPhone, and the roomy layout on all but the smallest:
/// `LayoutTests` measures them.
struct LivePanel<Shutter: View>: View {
    var zoom: ZoomButtons
    var mode: PictureMode
    var monitor: Monitor
    var onSelectZoom: (Double) -> Void
    var onSelectMode: (PictureMode) -> Void
    var onSelectMonitor: (Monitor) -> Void
    /// The layout to keep to, or nil for the roomy one where it fits and the
    /// tight one elsewhere.
    var layout: PanelLayout?
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

    private func controls(_ layout: PanelLayout) -> some View {
        let roomy = layout == .roomy
        return VStack(spacing: roomy ? 12 : 8) {
            ZoomPills(buttons: zoom, onSelect: onSelectZoom)
            ModeDial(selection: mode, onSelect: onSelectMode)
            MonitorBank(selection: monitor, onSelect: onSelectMonitor)
                .padding(.top, 6)
            if roomy {
                VentBand(edge: 16)
                    .frame(minHeight: 8, idealHeight: 8, maxHeight: .infinity)
            }
            shutter(roomy)
        }
        .padding(.top, roomy ? 12 : 8)
        .padding(.bottom, roomy ? 6 : 4)
    }
}
