import SwiftUI

// The camera screen's case recalls the vent along the back of the C64's case:
// grooves across it, each a dark groove over a line of light (design/README.md,
// and the mockups in design/svg). They run across the top of the screen with
// the phone upright, round the Dynamic Island as the C64's run round its
// badge; and in bands that fill the case's free space, never behind a key:
// above the shutter row's panel with the phone upright, and below the
// controls beside the TV in landscape.

/// Something the vent's grooves stop short of, such as the Dynamic Island.
nonisolated struct VentClearing: Equatable, Sendable {
    /// Where it is, in the vent's coordinates.
    var frame: CGRect
    var cornerRadius: CGFloat
}

/// Where the grooves go: they stop short of each element, and of the case's
/// sides, and leave out pieces too short to read as grooves.
nonisolated struct VentLayout: Sendable {
    /// How far apart the grooves are.
    var pitch: CGFloat = 6.5
    /// How high each groove's dark part is, and the light below it.
    var groove: CGFloat = 2.3
    var light: CGFloat = 1
    /// How far the grooves stop short of each element.
    var margin: CGFloat = 5
    /// How far in from the case's sides they stop.
    var edge: CGFloat = 12
    /// Pieces shorter than this are left out.
    var shortest: CGFloat = 14

    /// Where a groove starts and ends across the case.
    private typealias Span = (start: CGFloat, end: CGFloat)

    /// The dark part of each groove across `width`, from `top` to `bottom`;
    /// its light is just below it. With `cornerRadius`, the case's top corners
    /// are rounded, as the screen's are, and the grooves follow them.
    func grooves(
        width: CGFloat, from top: CGFloat, to bottom: CGFloat, clearings: [VentClearing], cornerRadius: CGFloat = 0
    ) -> [CGRect] {
        var grooves: [CGRect] = []
        var y = top
        while y + groove + light <= bottom {
            let low = y + groove + light
            var inset: CGFloat = 0
            if cornerRadius > edge, cornerRadius - y > 0 {
                inset = Self.cornerInset(cornerRadius - edge, depth: cornerRadius - y)
            }
            var spans: [Span] = [(edge + inset, width - edge - inset)]
            for clearing in clearings {
                guard let cut = leftOut(clearing, from: y, to: low) else { continue }
                spans = spans.flatMap { span -> [Span] in
                    [(span.start, min(span.end, cut.start)), (max(span.start, cut.end), span.end)]
                }
            }
            for span in spans where span.end - span.start >= shortest {
                grooves.append(CGRect(x: span.start, y: y, width: span.end - span.start, height: groove))
            }
            y += pitch
        }
        return grooves
    }

    /// The span a groove from `top` to `low` leaves out round an element.
    private func leftOut(_ clearing: VentClearing, from top: CGFloat, to low: CGFloat) -> Span? {
        let frame = clearing.frame.insetBy(dx: -margin, dy: -margin)
        guard low > frame.minY, top < frame.maxY else { return nil }
        let radius = min(clearing.cornerRadius + margin, frame.width / 2, frame.height / 2)
        // Where the groove is nearest the element's middle, the clearing is widest.
        let level = min(max(frame.midY, top), low)
        let depth = max(frame.minY + radius - level, level - (frame.maxY - radius))
        let inset = Self.cornerInset(radius, depth: depth)
        return (frame.minX + inset, frame.maxX - inset)
    }

    /// Whole grooves across a band `width` by `height`, as many as fit,
    /// centred in it.
    func band(width: CGFloat, height: CGFloat) -> [CGRect] {
        let depth = groove + light
        guard height >= depth else { return [] }
        let count = Int((height - depth) / pitch) + 1
        let top = (height - CGFloat(count - 1) * pitch - depth) / 2
        return grooves(width: width, from: top, to: height, clearings: [])
    }

    /// How far in a rounded corner of `radius` is, `depth` from the end of its curve.
    static func cornerInset(_ radius: CGFloat, depth: CGFloat) -> CGFloat {
        let depth = min(max(depth, 0), radius)
        return radius - (radius * radius - depth * depth).squareRoot()
    }

    /// Draws each groove, dark, over its line of light.
    func draw(
        _ grooves: [CGRect], in context: inout GraphicsContext, groove grooveColor: Color, light lightColor: Color
    ) {
        for rect in grooves {
            let line = CGRect(x: rect.minX, y: rect.maxY, width: rect.width, height: light)
            context.fill(Path(roundedRect: line, cornerRadius: line.height / 2), with: .color(lightColor))
            context.fill(Path(roundedRect: rect, cornerRadius: rect.height / 2), with: .color(grooveColor))
        }
    }
}

/// A band of the vent's grooves, filling the free space it is given: whole
/// grooves across it, centred, `edge` in from its sides.
struct VentBand: View {
    var edge: CGFloat = 12

    var body: some View {
        let layout = VentLayout(edge: edge)
        let (groove, light) = (Look.ventGroove, Look.ventLight)
        Canvas { context, size in
            let grooves = layout.band(width: size.width, height: size.height)
            layout.draw(grooves, in: &context, groove: groove, light: light)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The vent across the top of the screen with the phone upright, above the
/// top bar, in the room the status bar would take: it stops short of the
/// Dynamic Island, or the notch, and follows the screen's corners. It fills
/// the title bar's background, from the top of the screen down.
struct TopVent: View {
    var layout = VentLayout()

    var body: some View {
        GeometryReader { proxy in
            let layout = layout
            let (groove, light) = (Look.ventGroove, Look.ventLight)
            // It fills the title bar's background, which reaches up into the
            // safe area: what is above the bar is the room the status bar
            // would take. (Ignoring the safe area, it is told of none.)
            let room = max(0, proxy.size.height - ScreenMetrics.topBarHeight)
            let cutout = Self.cutout(width: proxy.size.width, room: room)
            let corners = Self.screenCornerRadius
            Canvas { context, size in
                let grooves = layout.grooves(
                    width: size.width, from: 9, to: room + 3, clearings: cutout, cornerRadius: corners)
                layout.draw(grooves, in: &context, groove: groove, light: light)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// About how round the corners of the screens with this room are.
    private static let screenCornerRadius: CGFloat = 50

    /// About where the Dynamic Island or the notch is, from how much room the
    /// top of the screen leaves: there is no way to ask.
    private static func cutout(width: CGFloat, room: CGFloat) -> [VentClearing] {
        if room >= 56 {
            return [VentClearing(frame: CGRect(x: width / 2 - 63, y: 11, width: 126, height: 37), cornerRadius: 18.5)]
        } else if room >= 40 {
            return [VentClearing(frame: CGRect(x: width / 2 - 100, y: -10, width: 200, height: 42), cornerRadius: 20)]
        }
        return []
    }
}
