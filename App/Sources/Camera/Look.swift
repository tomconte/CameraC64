import SwiftUI

/// The camera screen's look: a TV above a C64, in the style of the 2013 app.
///
/// Its keys, lamps, switches and badge are the skin's images, drawn in
/// `design/svg` (`Skin`); every colour, font and style the screen adds to
/// them lives here, so the skin can change without touching the layout or
/// behaviour (docs/UX.md, section 7).
enum Look {
    // The C64 case, lit from above.
    static let caseColor = Color(hex: 0xCFC4AD)
    static let caseLight = Color(hex: 0xD6CAB3)
    static let caseShade = Color(hex: 0xC6BBA3)
    /// Words printed on a key.
    static let ink = Color(hex: 0x4F4537)
    /// Words engraved in the case.
    static let label = Color(hex: 0x857558)
    static let labelSelected = Color(hex: 0x3E3528)
    /// The light along the lower edge of engraved words.
    static let engravingLight = Color(hex: 0xEFE8DA).opacity(0.8)
    static let ledOn = Color(hex: 0xF4B23C)
    /// The vent's grooves in the case, and the light below each (`Vent`).
    static let ventGroove = Color(hex: 0x867861)
    static let ventLight = Color(hex: 0xFBF5EA).opacity(0.9)

    // The panel the monitor keys sit in, pressed into the case.
    static let panel = Color(hex: 0xCBBFA6)
    static let panelLip = Color(hex: 0xEAE2D3).opacity(0.9)
    static let panelShade = Color(hex: 0x6E5A3E)

    // The title bar above the TV, with the phone upright, as on the 2013 app.
    static let titleBarLight = Color(hex: 0xFBF2E1)
    static let titleBarMiddle = Color(hex: 0xE6DAC6)
    static let titleBarShade = Color(hex: 0xD2C5AD)
    static let titleBarEdge = Color(hex: 0x9B9281)
    static let titleBarEdgeShade = Color(hex: 0x6A6150)

    // The monitor around the TV.
    static let bezel = Color(hex: 0x1C1B19)
    static let bezelInk = Color(hex: 0xD9D3C5)
    static let bezelInkDim = Color(hex: 0x8C867A)
    /// The buttons on the TV when it has no camera to show, and the words on
    /// them and on the zoom buttons.
    static let pill = Color(hex: 0x2B2925)
    static let pillInk = Color(hex: 0xE9E3D5)

    static let caseLabelFont = Font.system(size: 11, weight: .bold).width(.condensed)
    static let dialFont = Font.system(size: 13, weight: .bold).width(.condensed)
    static let smallFont = Font.system(size: 10, weight: .bold).width(.condensed)
}

extension Color {
    /// A colour from a 24-bit sRGB value, such as 0xE6DFCC.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255)
    }
}

extension View {
    /// Words pressed into the case, in `color`: a lighter copy just below them
    /// catches the light.
    func engraved(_ color: Color) -> some View {
        foregroundStyle(color)
            .shadow(color: Look.engravingLight, radius: 0, x: 0, y: 0.5)
    }

    /// A panel pressed into the case, as the 2013 app's MON SELEC panel was,
    /// with its title engraved above it.
    func casePanel(_ title: String) -> some View {
        background {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Look.panelLip)
                    .offset(x: 0.6, y: 0.8)
                RoundedRectangle(cornerRadius: 8)
                    .fill(Look.panel)
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: Look.panelShade.opacity(0.45), location: 0),
                                .init(color: Look.panelShade.opacity(0), location: 0.25),
                            ],
                            startPoint: .top, endPoint: .bottom),
                        lineWidth: 1.6)
            }
        }
        .overlay(alignment: .topLeading) {
            Text(title)
                .font(Look.smallFont)
                .tracking(1.4)
                .engraved(Look.label)
                .fixedSize()
                .offset(x: 6, y: -14)
                .accessibilityHidden(true)
        }
    }
}

/// The title bar above the TV with the phone upright, as on the 2013 app:
/// beige, lit from above, with a dark line where it meets the TV, and the
/// vent's grooves above it.
struct TitleBarBackground: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: Look.titleBarLight, location: 0),
                .init(color: Look.titleBarMiddle, location: 0.55),
                .init(color: Look.titleBarShade, location: 1),
            ],
            startPoint: .top, endPoint: .bottom
        )
        .overlay {
            TopVent()
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 0) {
                Look.titleBarEdge.frame(height: 0.6)
                Look.titleBarEdgeShade.frame(height: 0.6)
            }
        }
    }
}

/// The case below the TV with the phone upright: its plastic, lit from above.
struct CaseBackground: View {
    var body: some View {
        LinearGradient(colors: [Look.caseLight, Look.caseShade], startPoint: .top, endPoint: .bottom)
    }
}

/// A key drawn from the skin, up, or pressed while touched. The words or the
/// lamp on it, the button's label, sink with it.
struct SkinKeyStyle: ButtonStyle {
    var element: SkinElement
    /// How wide the key's face is.
    var width: CGFloat
    /// Shown pressed whatever the finger does, as for the monitor chosen.
    var held = false
    /// The area that takes a touch, if it is larger than the key.
    var touch: CGSize?

    @Environment(\.isEnabled) private var isEnabled

    /// How far a pressed key's face sinks, on its canvas.
    private static let sink: CGFloat = 0.4

    init(element: SkinElement, width: CGFloat, held: Bool = false, touch: CGSize? = nil) {
        self.element = element
        self.width = width
        self.held = held
        self.touch = touch
    }

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed || held
        SkinImage(element: element, state: pressed, width: width)
            .overlay {
                configuration.label
                    .offset(y: pressed ? Self.sink * width / element.face.width : 0)
            }
            .opacity(isEnabled || held ? 1 : 0.6)
            .frame(width: touch?.width, height: touch?.height)
            .contentShape(Rectangle())
    }
}

/// The big brown capture key, as on the 2013 app, with its camera engraved
/// in it.
struct CaptureKeyStyle: ButtonStyle {
    var width: CGFloat = 170

    func makeBody(configuration: Configuration) -> some View {
        SkinImage(element: Skin.captureKey, state: configuration.isPressed, width: width)
            .contentShape(Capsule())
    }
}

/// A small lamp, lit for the selected choice.
struct LED: View {
    var isOn: Bool
    /// How wide the lamp is; its glow, when lit, spreads beyond.
    var size: CGFloat = 10

    var body: some View {
        SkinImage(element: Skin.lamp, state: isOn, width: size)
            .accessibilityHidden(true)
    }
}

/// The "Camera C64" badge from the 2013 app's title bar.
struct CameraBadge: View {
    /// A narrower badge, for the column beside the TV in landscape.
    var compact = false

    var body: some View {
        SkinImage(element: Skin.badge, width: compact ? 110 : Skin.badge.face.width)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Camera C64")
    }
}

/// One of the 2013 app's switches, for flash and the CRT layer, with its name
/// engraved beside it.
struct CaseSwitch: View {
    var title: String
    var isOn: Bool
    /// What VoiceOver reads.
    var accessibilityName: String
    /// The height it takes a touch in.
    var height: CGFloat = 44
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                    .font(Look.smallFont)
                    .engraved(Look.label)
                    .fixedSize()
                SkinImage(element: Skin.toggle, state: isOn, width: Skin.toggle.face.width)
            }
            .frame(height: height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityName)
    }
}

/// The key that opens Settings.
struct SettingsKey: View {
    /// The side of the square that takes a touch.
    var touch: CGFloat = 44
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            EmptyView()
        }
        .buttonStyle(
            SkinKeyStyle(
                element: Skin.settingsKey, width: Skin.settingsKey.face.width,
                touch: CGSize(width: touch, height: touch))
        )
        .accessibilityLabel("Settings")
    }
}
