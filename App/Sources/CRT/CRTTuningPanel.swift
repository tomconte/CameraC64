import SwiftUI
import UIKit

/// Sliders for the CRT layer's look, in development builds only (Settings →
/// Development → CRT Tuning). The panel covers the camera's controls, so the
/// TV stays in view while the sliders move. Copy puts the values on the
/// clipboard, to be sent and made the standard look.
struct CRTTuningPanel: View {
    @Binding var crt: CRT
    var onDone: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 14) {
                Text("CRT TUNING")
                    .font(Look.caseLabelFont)
                    .tracking(1.2)
                Spacer()
                Button("Standard") {
                    crt = .standard
                }
                Button("Copy") {
                    UIPasteboard.general.string = crt.text
                }
                Button("Done", action: onDone)
            }
            .font(.system(size: 13, weight: .semibold))
            ScrollView {
                VStack(spacing: 4) {
                    slider("Dark beams", $crt.beamMin, in: 0.1...0.5)
                    slider("Bright beams", $crt.beamMax, in: 0.2...0.8)
                    slider("Pixel edges", $crt.edge, in: 0...1)
                    slider("Glow", $crt.glow, in: 0...0.5)
                    slider("Curvature", $crt.curvature, in: 0...0.15)
                    slider("Vignette", $crt.vignette, in: 0...0.8)
                    slider("Corners", $crt.corner, in: 0...0.15)
                    slider("Brightness", $crt.brightness, in: 0.7...1.5)
                    slider("Afterglow", $crt.afterglow, in: 0...0.5)
                }
            }
            Text(crt.text)
                .font(.system(size: 11).monospaced())
                .foregroundStyle(Look.bezelInk)
        }
        .foregroundStyle(.white)
        .tint(Look.ledOn)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.85)))
        .padding(8)
    }

    private func slider(_ name: String, _ value: Binding<Double>, in range: ClosedRange<Double>) -> some View {
        HStack(spacing: 8) {
            Text(name)
                .frame(width: 92, alignment: .leading)
            Slider(value: value, in: range)
            Text(String(format: "%.3f", value.wrappedValue))
                .monospacedDigit()
                .frame(width: 44, alignment: .trailing)
        }
        .font(.system(size: 12, weight: .medium))
    }
}
