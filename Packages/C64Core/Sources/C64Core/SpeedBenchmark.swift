import Foundation

/// The speed benchmark (plan, section 10): how long each stage of a
/// viewfinder frame takes on the machine it runs on. The app shows it on a
/// hidden screen in TestFlight builds, and `c64conv speed` prints it.
///
/// A viewfinder frame must take well under 33 ms on the oldest supported
/// iPhone; if the converter cannot keep up, a Metal version of its search
/// will take over in the viewfinder.
public enum SpeedBenchmark {
    /// One thing to time: a mode, made for a monitor.
    public struct Case: Hashable, Sendable {
        public var mode: String
        public var spec: ModeSpec
        public var monitor: String
        public var display: DisplayModel

        public init(mode: String, spec: ModeSpec, monitor: String, display: DisplayModel) {
            self.mode = mode
            self.spec = spec
            self.monitor = monitor
            self.display = display
        }

        public var name: String { "\(mode), \(monitor)" }
    }

    /// Both bitmap modes, for a colour TV, a sharp display and a monochrome
    /// monitor, which each search differently.
    public static let cases: [Case] = [("Hires", ModeSpec.hires), ("Multicolour", .multicolor)].flatMap { mode in
        [("TV", DisplayModel.tv), ("Sharp", .sharp), ("B&W", .blackAndWhite)].map { monitor in
            Case(mode: mode.0, spec: mode.1, monitor: monitor.0, display: monitor.1)
        }
    }

    /// The median time of each stage of a frame, in seconds.
    public struct Timing: Hashable, Sendable {
        /// From a camera frame to the mode's target.
        public var target: Double
        public var conversion: Double
        public var rendering: Double
        /// Through the monitor's display model.
        public var display: Double

        public var total: Double { target + conversion + rendering + display }
    }

    /// A camera frame for the benchmark, laid out as the camera gives them:
    /// gradients and fine detail, the same every time.
    public static func cameraFrame(width: Int = 1920, height: Int = 1440) -> RGBImage {
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * 4
                let ripple = (x * 7 + y * 13) % 64
                bytes[index] = UInt8((x * 255 / width + ripple) % 256)
                bytes[index + 1] = UInt8((y * 255 / height + ripple / 2) % 256)
                bytes[index + 2] = UInt8((x + y) * 255 / (width + height))
            }
        }
        return RGBImage(width: width, height: height, layout: .bgra, bytes: bytes)
    }

    /// Times each stage `runs` times on a frame, after one run to warm up,
    /// and keeps the medians.
    public static func measure(_ benchmarkCase: Case, frame: RGBImage, runs: Int = 9) -> Timing {
        precondition(runs > 0)
        let settings = Converter.Settings(display: benchmarkCase.display)
        let converter = Converter(spec: benchmarkCase.spec, settings: settings)
        let clock = ContinuousClock()
        var times: [[Double]] = Array(repeating: [], count: 4)
        for run in 0...runs {
            var target: Target?
            var conversion: Conversion?
            var screen: IndexedImage?
            let stages = [
                clock.measure { target = Target(frame, for: benchmarkCase.spec) },
                clock.measure { conversion = converter.convert(target!) },
                clock.measure { screen = VICII.render(conversion!.frame) },
                clock.measure { _ = benchmarkCase.display.show(screen!, palette: converter.settings.palette) },
            ]
            guard run > 0 else { continue }
            for (stage, duration) in stages.enumerated() {
                times[stage].append(
                    Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18)
            }
        }
        let medians = times.map { $0.sorted()[$0.count / 2] }
        return Timing(target: medians[0], conversion: medians[1], rendering: medians[2], display: medians[3])
    }

    /// A line of the results: each stage in milliseconds, the total, and the
    /// frame rate it allows.
    public static func describe(_ timing: Timing) -> String {
        func milliseconds(_ seconds: Double) -> String {
            let value = seconds * 1000
            return value < 10 ? String(format: "%.1f", value) : String(format: "%.0f", value)
        }
        return [timing.target, timing.conversion, timing.rendering, timing.display].map(milliseconds)
            .joined(separator: " + ") + " = \(milliseconds(timing.total)) ms, \(Int(1 / timing.total)) fps"
    }
}
