import SwiftUI

/// A screen through the CRT layer (`CRT.metal`), filling its frame: the TV's
/// whole screen, border included.
struct CRTScreen: View {
    var source: CRTSource
    var crt: CRT
    /// While a picture fills in, how many of its display window's 1,000 cells
    /// show.
    var revealed: Double = 1000
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Rectangle()
            .fill(Self.shader(source, crt, scale: displayScale, revealed: revealed))
    }

    /// The shader that draws a screen, `scale` device pixels per point.
    static func shader(_ source: CRTSource, _ crt: CRT, scale: CGFloat, revealed: Double = 1000) -> Shader {
        var shader = ShaderLibrary.crtScreen(
            .boundingRect, .data(source.pixels), .data(source.glow),
            .floatArray(crt.shaderSettings(for: source, scale: Double(scale), revealed: revealed)))
        // The glow and the vignette are smooth slopes, which dithering keeps
        // from banding.
        shader.dithersColor = true
        return shader
    }
}
