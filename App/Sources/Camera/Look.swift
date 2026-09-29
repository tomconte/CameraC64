import SwiftUI

/// The camera screen's look: a TV above a C64, drawn in code for now.
///
/// Every colour, font and key style lives here, so a detailed skin can replace
/// them later without touching the layout or behaviour (docs/UX.md, section 7).
enum Look {
    // The C64 case and its keys.
    static let caseColor = Color(hex: 0xE6DFCC)
    static let caseLine = Color(hex: 0xCBC0A6)
    static let key = Color(hex: 0xF5F0E4)
    static let keyEdge = Color(hex: 0xB4A88E)
    static let ink = Color(hex: 0x4F4537)
    static let label = Color(hex: 0x7F725E)
    static let labelSelected = Color(hex: 0x2B2620)
    static let capture = Color(hex: 0x8A6D57)
    static let captureEdge = Color(hex: 0x6F5644)
    static let captureInk = Color(hex: 0xF1EADB)
    static let ledOn = Color(hex: 0xF4B23C)
    static let ledOff = Color(hex: 0x6B5238)

    // The monitor around the TV.
    static let bezel = Color(hex: 0x1C1B19)
    static let bezelInk = Color(hex: 0xD9D3C5)
    static let bezelInkDim = Color(hex: 0x8C867A)
    static let pill = Color(hex: 0x2B2925)
    static let pillInk = Color(hex: 0xE9E3D5)

    /// The C64 screen's border. Placeholder: the real border is a C64 colour
    /// chosen per picture. This is blue in the Colodore palette the samples use.
    static let c64Border = Color(hex: 0x2E2C9B)

    // The badge from the 2013 app's title bar.
    static let badge = Color(hex: 0x3E3A35)
    static let badgeInk = Color(hex: 0xF4F0E6)
    static let rainbow = [
        Color(hex: 0xD2463C), Color(hex: 0xE88A2B), Color(hex: 0xEDC63D), Color(hex: 0x5DAA57), Color(hex: 0x3F78C4),
    ]

    static let caseLabelFont = Font.system(size: 11, weight: .bold).width(.condensed)
    static let dialFont = Font.system(size: 13, weight: .bold).width(.condensed)
    static let smallFont = Font.system(size: 10, weight: .bold).width(.condensed)
    static let iconFont = Font.system(size: 19, weight: .semibold)
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

/// A beige key seen from above: its face sits on a darker edge and sinks when pressed.
struct KeyFace: View {
    var isPressed = false
    var cornerRadius: CGFloat = 6

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Look.keyEdge)
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Look.key)
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(Look.keyEdge, lineWidth: 1)
                }
                .padding(.bottom, 3)
                .offset(y: isPressed ? 2 : 0)
        }
    }
}

/// A key on the case, with an icon or a short label printed on it.
struct KeyButtonStyle: ButtonStyle {
    var width: CGFloat
    var height: CGFloat
    var cornerRadius: CGFloat = 10

    func makeBody(configuration: Configuration) -> some View {
        KeyFace(isPressed: configuration.isPressed, cornerRadius: cornerRadius)
            .frame(width: width, height: height)
            .overlay {
                configuration.label
                    .foregroundStyle(Look.ink)
                    .padding(.bottom, 3)
                    .offset(y: configuration.isPressed ? 2 : 0)
            }
    }
}

/// The big brown capture key, as on the 2013 app.
struct CaptureKeyStyle: ButtonStyle {
    var width: CGFloat = 170
    var height: CGFloat = 64

    func makeBody(configuration: Configuration) -> some View {
        ZStack(alignment: .top) {
            Capsule()
                .fill(Look.captureEdge)
            Capsule()
                .fill(Look.capture)
                .frame(height: height - 4)
                .overlay {
                    configuration.label
                        .foregroundStyle(Look.captureInk)
                }
                .offset(y: configuration.isPressed ? 3 : 0)
        }
        .frame(width: width, height: height)
    }
}

/// A small lamp, lit for the selected choice.
struct LED: View {
    var isOn: Bool
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(isOn ? Look.ledOn : Look.ledOff)
            .frame(width: size, height: size)
    }
}

/// The "Camera C64" badge from the 2013 app's title bar.
struct CameraBadge: View {
    var body: some View {
        HStack(spacing: 7) {
            Text("Camera")
                .font(.system(size: 11, weight: .bold))
            VStack(spacing: 1) {
                ForEach(Look.rainbow.indices, id: \.self) { index in
                    Rectangle()
                        .fill(Look.rainbow[index])
                        .frame(width: 30, height: 2)
                }
            }
            Text("C64")
                .font(.system(size: 12, weight: .heavy))
        }
        .foregroundStyle(Look.badgeInk)
        .padding(.horizontal, 12)
        .frame(height: 22)
        .background(Capsule().fill(Look.badge))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Camera C64")
    }
}
