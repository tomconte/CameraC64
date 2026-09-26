import C64Core
import SwiftUI

/// Placeholder until the camera screen exists: shows the 16 C64 colours.
struct ContentView: View {
    private let palette = C64Palette.pepto2001

    var body: some View {
        VStack(spacing: 16) {
            Text("Camera C64")
                .font(.largeTitle.monospaced().bold())
            Text("Work in progress")
                .foregroundStyle(.secondary)
            HStack(spacing: 2) {
                ForEach(C64Color.allCases, id: \.self) { color in
                    Rectangle()
                        .fill(Color(palette[color]))
                        .frame(width: 16, height: 32)
                }
            }
        }
        .padding()
    }
}

extension Color {
    fileprivate init(_ rgb: RGB) {
        self.init(red: Double(rgb.r) / 255, green: Double(rgb.g) / 255, blue: Double(rgb.b) / 255)
    }
}

#Preview {
    ContentView()
}
