import C64Core
import SwiftUI
import UIKit

/// Whether this is a development build: a debug build, or the dev app that
/// TestFlight installs (docs/CI.md). Development builds show the speed
/// benchmark.
enum BuildKind {
    static var isDevelopment: Bool {
        #if DEBUG
            return true
        #else
            return Bundle.main.bundleIdentifier?.hasSuffix(".dev") == true
        #endif
    }
}

/// The speed benchmark (plan, section 10): how long each stage of a viewfinder
/// frame takes on this phone. A frame must take well under 33 ms on the oldest
/// supported iPhone, or the converter's search needs a Metal version.
struct SpeedBenchmarkView: View {
    private struct Result: Identifiable {
        var name: String
        var timing: SpeedBenchmark.Timing

        var id: String { name }
    }

    @State private var results: [Result] = []
    @State private var running = false
    /// As the camera sends them, turned as for a phone held sideways.
    private let frameSize = (width: 1440, height: 1920)

    var body: some View {
        List {
            Section {
                ForEach(results) { result in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.name)
                        Text(SpeedBenchmark.describe(result.timing))
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(result.timing.total < 1 / 30 ? Color.green : Color.orange)
                    }
                }
                if running {
                    ProgressView()
                }
            } header: {
                Text("A \(frameSize.width) × \(frameSize.height) frame, held sideways")
            } footer: {
                Text(
                    "Target + conversion + rendering + display, in milliseconds: the median of 9 runs. "
                        + "Green is fast enough for 30 frames a second.")
            }
            Section {
                Button("Run Again") {
                    Task { await run() }
                }
                .disabled(running)
                ShareLink(item: report) {
                    Label("Share Results", systemImage: "square.and.arrow.up")
                }
                .disabled(running || results.isEmpty)
            }
            Section("This Phone") {
                LabeledContent("Model", value: Self.model)
                LabeledContent("iOS", value: UIDevice.current.systemVersion)
                LabeledContent("Cores", value: "\(ProcessInfo.processInfo.activeProcessorCount)")
            }
        }
        .navigationTitle("Speed Benchmark")
        .task {
            await run()
        }
    }

    /// Times each case in turn, off the main thread.
    private func run() async {
        guard !running else { return }
        running = true
        results = []
        let size = frameSize
        let frame = await Task.detached(priority: .userInitiated) {
            SpeedBenchmark.cameraFrame(width: size.width, height: size.height)
        }.value
        for benchmarkCase in SpeedBenchmark.cases {
            let timing = await Task.detached(priority: .userInitiated) {
                SpeedBenchmark.measure(benchmarkCase, frame: frame)
            }.value
            results.append(Result(name: benchmarkCase.name, timing: timing))
        }
        running = false
    }

    /// The results as text, to send to the developers.
    private var report: String {
        var lines = [
            "Camera C64 speed benchmark",
            "\(Self.model), iOS \(UIDevice.current.systemVersion), "
                + "\(ProcessInfo.processInfo.activeProcessorCount) cores",
            "A \(frameSize.width) x \(frameSize.height) frame, held sideways: target + conversion + rendering + display",
        ]
        lines += results.map { "\($0.name): \(SpeedBenchmark.describe($0.timing))" }
        return lines.joined(separator: "\n")
    }

    /// The phone's model identifier, such as iPhone12,1 for an iPhone 11.
    private static var model: String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return "\(simulated) (Simulator)"
        }
        var system = utsname()
        uname(&system)
        return withUnsafeBytes(of: system.machine) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}

#Preview {
    NavigationStack {
        SpeedBenchmarkView()
    }
}
