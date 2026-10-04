import C64Core
import Foundation

/// The quality benchmark (plan, section 10): a fixed set of photos, each
/// converted in every standard mode for several monitors, and each picture
/// scored as its monitor shows it, so that "better" is a number.
public enum Benchmark {
    /// A photo of the set.
    public struct Photo: Sendable {
        public var name: String
        public var description: String
        public var image: RGBImage

        public init(name: String, description: String, image: RGBImage) {
            self.name = name
            self.description = description
            self.image = image
        }
    }

    public enum Error: Swift.Error, CustomStringConvertible {
        case badManifest(line: String)
        case missingPhoto(String)

        public var description: String {
            switch self {
            case .badManifest(let line): "The photo list has a bad line: \(line)"
            case .missingPhoto(let name): "\(name) is missing: run Tools/Benchmark/get-photos.sh"
            }
        }
    }

    /// Each mode, and for PETSCII, the characters it may use: all of them,
    /// or only the graphics characters.
    public static let modes: [(name: String, spec: ModeSpec, petsciiCharacters: CharacterROM.Selection)] = [
        ("hires", .hires, .all), ("multicolour", .multicolor, .all), ("petscii", .petscii, .all),
        ("petscii-graphics", .petscii, .graphics),
    ]
    /// The amber and green monitors make the same pictures as the
    /// black-and-white one, in another tint.
    public static let monitors: [(name: String, display: DisplayModel)] = [
        ("sharp", .sharp), ("tv", .tv), ("monitor", .commodoreMonitor), ("bw", .blackAndWhite),
    ]

    /// Reads the photos a list names from a directory, each with its
    /// exposure change. Each line of the list has a file name, its SHA-256,
    /// the exposure change in stops and a description; # starts a comment.
    public static func photos(list: URL, directory: URL) throws -> [Photo] {
        let text = try String(contentsOf: list, encoding: .utf8)
        return try text.split(separator: "\n").filter { !$0.hasPrefix("#") && !$0.isEmpty }.map { line in
            let fields = line.split(separator: " ", maxSplits: 3).map(String.init)
            guard fields.count == 4, let exposure = Double(fields[2]) else {
                throw Error.badManifest(line: String(line))
            }
            let file = directory.appendingPathComponent(fields[0])
            let name = String(fields[0].prefix { $0 != "." })
            return try photo(
                named: exposure == 0 ? name : "\(name)-dark", description: fields[3], file: file, exposure: exposure)
        }
    }

    /// A photo from a PNG file, made darker or brighter by some stops.
    public static func photo(named name: String, description: String, file: URL, exposure: Double = 0) throws -> Photo {
        guard let data = FileManager.default.contents(atPath: file.path) else { throw Error.missingPhoto(file.path) }
        var image = try PNG.decodeImage(Array(data))
        if exposure != 0 {
            let gain = Float(pow(2, exposure))
            for y in 0..<image.height {
                for x in 0..<image.width {
                    let light = LinearRGB(image[x, y])
                    image[x, y] = LinearRGB(r: light.r * gain, g: light.g * gain, b: light.b * gain).rgb
                }
            }
        }
        return Photo(name: name, description: description, image: image)
    }

    /// A chart of every hue, across, at every lightness, down.
    public static func chart() -> Photo {
        var image = RGBImage(width: 640, height: 400, fill: RGB(0, 0, 0))
        for y in 0..<400 {
            for x in 0..<640 {
                let angle = Float(x) / 640 * 2 * .pi
                let color = OKLab(l: 0.05 + 0.9 * Float(y) / 399, a: 0.13 * cos(angle), b: 0.13 * sin(angle))
                image[x, y] = color.linear.rgb
            }
        }
        return Photo(name: "chart", description: "Every hue at every lightness: gradients", image: image)
    }

    /// One picture's result.
    public struct Entry: Sendable {
        public var photo: String
        public var mode: String
        public var monitor: String
        public var score: Double
        /// How long the conversion took, in seconds.
        public var seconds: Double
        /// The picture's display window, as the monitor shows it.
        public var shown: RGBImage

        public var key: String { "\(photo) \(mode) \(monitor)" }
    }

    /// What each photo is scored against: the photo on the hires grid, with
    /// the converter's crop and its default, automatic tones.
    public static func reference(_ photo: Photo) -> Target {
        Target(photo.image, width: Screen.windowWidth, height: Screen.windowHeight)
    }

    /// A frame's display window as a monitor shows it, and its score.
    public static func score(
        _ frame: C64Frame, against reference: Target, on display: DisplayModel, palette: C64Palette = .colodore
    ) -> (score: Double, shown: RGBImage) {
        let shown = display.show(VICII.render(frame).window, palette: palette)
        return (Quality.score(shown, target: reference, monochrome: display.isMonochrome), shown)
    }

    /// Converts each photo in each mode for each monitor, and scores every
    /// picture.
    public static func run(_ photos: [Photo], dithering: Float = Converter.Settings().dithering) -> [Entry] {
        var entries: [Entry] = []
        for (modeName, spec, characters) in modes {
            for (monitorName, display) in monitors {
                let converter = Converter(
                    spec: spec,
                    settings: Converter.Settings(display: display, dithering: dithering, petsciiCharacters: characters))
                for photo in photos {
                    let start = DispatchTime.now().uptimeNanoseconds
                    let frame = converter.convert(photo.image).frame
                    let seconds = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9
                    let (score, shown) = score(frame, against: reference(photo), on: display)
                    entries.append(
                        Entry(
                            photo: photo.name, mode: modeName, monitor: monitorName, score: score, seconds: seconds,
                            shown: shown))
                }
            }
        }
        return entries
    }

    // MARK: - Scores

    /// Reads scores written by `write(_:to:)`: each line a photo, a mode, a
    /// monitor and a score.
    public static func scores(in file: URL) throws -> [String: Double] {
        var scores: [String: Double] = [:]
        for line in try String(contentsOf: file, encoding: .utf8).split(separator: "\n") where !line.hasPrefix("#") {
            let fields = line.split(separator: " ")
            guard fields.count == 4, let score = Double(fields[3]) else { throw Error.badManifest(line: String(line)) }
            scores[fields[0...2].joined(separator: " ")] = score
        }
        return scores
    }

    public static func write(_ entries: [Entry], to file: URL) throws {
        var lines = [
            "# Quality benchmark scores (Tools/README.md): the mean OKLab distance x 100 between each picture,",
            "# as its monitor shows it, and its photo, after the eye's blur. Lower is better.",
            "# `c64conv benchmark --update-baseline` rewrites this file.",
        ]
        lines += entries.map { "\($0.key) \(String(format: "%.3f", $0.score))" }
        try (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
    }

    /// How the scores compare with a baseline.
    public struct Comparison: Sendable {
        /// Pictures that score worse than they may, with both scores.
        public var regressions: [(key: String, baseline: Double, score: Double)]
        /// Pictures in only one of the two.
        public var unmatched: [String]
        public var baselineMean: Double
        public var mean: Double

        public var passed: Bool { regressions.isEmpty && unmatched.isEmpty && mean <= baselineMean * 1.005 }
    }

    /// Compares scores with a baseline: each picture may score up to 2%
    /// worse, and the mean 0.5%, which leaves room for the small differences
    /// between platforms' maths libraries.
    public static func compare(_ entries: [Entry], with baseline: [String: Double]) -> Comparison {
        let keys = Set(entries.map(\.key))
        var comparison = Comparison(
            regressions: [], unmatched: Array(keys.symmetricDifference(baseline.keys)).sorted(), baselineMean: 0,
            mean: 0)
        let matched = entries.filter { baseline[$0.key] != nil }
        for entry in matched where entry.score > baseline[entry.key]! * 1.02 {
            comparison.regressions.append((entry.key, baseline[entry.key]!, entry.score))
        }
        if !matched.isEmpty {
            comparison.mean = matched.reduce(0) { $0 + $1.score } / Double(matched.count)
            comparison.baselineMean = matched.reduce(0) { $0 + baseline[$1.key]! } / Double(matched.count)
        }
        return comparison
    }

    // MARK: - Report

    /// A table of the scores in Markdown, one row per photo and mode, with
    /// each score's change from the baseline.
    public static func markdown(_ entries: [Entry], baseline: [String: Double]?) -> String {
        var lines = ["| Photo | Mode | " + monitors.map(\.name).joined(separator: " | ") + " |"]
        lines.append("|---|---|" + String(repeating: "---:|", count: monitors.count))
        var rows: [String: [Entry]] = [:]
        var order: [String] = []
        for entry in entries {
            let row = "\(entry.photo) | \(entry.mode)"
            if rows[row] == nil { order.append(row) }
            rows[row, default: []].append(entry)
        }
        for row in order {
            let cells = monitors.map { monitor -> String in
                guard let entry = rows[row]!.first(where: { $0.monitor == monitor.name }) else { return "" }
                return format(entry.score, baseline: baseline?[entry.key])
            }
            lines.append("| \(row) | " + cells.joined(separator: " | ") + " |")
        }
        let mean = entries.reduce(0) { $0 + $1.score } / Double(max(entries.count, 1))
        let baselineMean = baseline.map { scores in
            entries.reduce(0) { $0 + (scores[$1.key] ?? $1.score) } / Double(max(entries.count, 1))
        }
        lines.append("")
        lines.append("Mean score: \(format(mean, baseline: baselineMean)). Lower is better.")
        return lines.joined(separator: "\n") + "\n"
    }

    private static func format(_ score: Double, baseline: Double?) -> String {
        guard let baseline, baseline > 0 else { return String(format: "%.2f", score) }
        let change = (score / baseline - 1) * 100
        return abs(change) < 0.05 ? String(format: "%.2f", score) : String(format: "%.2f (%+.1f%%)", score, change)
    }

    /// Writes a page with every picture next to its photo, and their scores,
    /// with an image64 baseline if one was run, into a directory.
    public static func writeReport(
        _ entries: [Entry], photos: [Photo], baseline: [String: Double]?, image64: [Entry] = [], to directory: URL
    ) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        func save(_ image: RGBImage, _ name: String) throws -> String {
            try Data(PNG.encode(image)).write(to: directory.appendingPathComponent(name))
            return name
        }
        // Pictures at the PAL pixel shape, twice the size.
        let (width, height) = (
            Int((Double(2 * Screen.windowWidth) * Screen.pixelAspectRatio).rounded()), 2 * Screen.windowHeight
        )
        func figure(_ file: String, _ caption: String) -> String {
            "<figure><img src=\"\(file)\" width=\"\(width)\" height=\"\(height)\" alt=\"\(caption)\"><figcaption>\(caption)</figcaption></figure>"
        }
        var html = """
            <!doctype html>
            <html lang="en"><head><meta charset="utf-8"><title>Quality benchmark</title>
            <style>
            body { font: 14px -apple-system, system-ui, sans-serif; margin: 24px; color: #222; background: #fafafa; }
            table { border-collapse: collapse; } td, th { padding: 2px 10px; border-bottom: 1px solid #ddd; text-align: right; }
            td:first-child, td:nth-child(2), th { text-align: left; }
            .row { display: flex; flex-wrap: wrap; gap: 12px; } figure { margin: 0 0 12px; }
            img { image-rendering: pixelated; display: block; } figcaption { color: #555; padding-top: 4px; }
            </style></head><body>
            <h1>Quality benchmark</h1>
            <p>Each photo converted in each mode for each monitor, and shown as that monitor shows it. The score is the
            mean OKLab distance &times; 100 between the picture and the photo, after the eye's blur: lower is better.</p>

            """
        html += "<table><tr><th>Photo</th><th>Mode</th>" + monitors.map { "<th>\($0.name)</th>" }.joined() + "</tr>"
        for photo in photos {
            for mode in modes.map(\.name) {
                html += "<tr><td>\(photo.name)</td><td>\(mode)</td>"
                for (monitor, _) in monitors {
                    let entry = entries.first { $0.photo == photo.name && $0.mode == mode && $0.monitor == monitor }
                    html += "<td>" + (entry.map { format($0.score, baseline: baseline?[$0.key]) } ?? "") + "</td>"
                }
                html += "</tr>"
            }
        }
        html += "</table>\n"
        for photo in photos {
            html += "<h2>\(photo.name): \(photo.description)</h2>\n"
            let original = try save(reference(photo).rgbImage, "\(photo.name).png")
            for mode in modes.map(\.name) {
                html += "<div class=\"row\">" + figure(original, "Photo")
                for entry in entries where entry.photo == photo.name && entry.mode == mode {
                    let file = try save(entry.shown, "\(entry.key.replacingOccurrences(of: " ", with: "-")).png")
                    html += figure(file, "\(mode), \(entry.monitor): \(String(format: "%.2f", entry.score))")
                }
                for entry in image64 where entry.photo == photo.name && entry.mode == mode {
                    let file = try save(
                        entry.shown, "image64-\(entry.key.replacingOccurrences(of: " ", with: "-")).png")
                    html += figure(file, "image64 \(mode), \(entry.monitor): \(String(format: "%.2f", entry.score))")
                }
                html += "</div>\n"
            }
        }
        html += "</body></html>\n"
        try html.write(to: directory.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
    }
}

/// image64's command-line tool (github.com/nschneir/image64, MIT), which the
/// benchmark can score as a baseline for the bitmap modes. It runs on macOS.
public struct Image64: Sendable {
    public let executable: URL

    public init(executable: URL) {
        self.executable = executable
    }

    /// The tool at $IMAGE64, or on the PATH.
    public static func find() -> Image64? {
        let environment = ProcessInfo.processInfo.environment
        var candidates = environment["IMAGE64"].map { [$0] } ?? []
        for directory in (environment["PATH"] ?? "").split(separator: ":") {
            candidates.append("\(directory)/image64")
        }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }.map {
            Image64(executable: URL(fileURLWithPath: $0))
        }
    }

    /// Converts a picture of the display window's 320 × 200 pixels, which
    /// image64 takes whole, with its default settings: Floyd–Steinberg
    /// dithering and Colodore's palette.
    public func convert(_ picture: RGBImage, spec: ModeSpec) throws -> C64Frame {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("image64-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("photo.png")
        try Data(PNG.encode(picture)).write(to: input)
        let output = directory.appendingPathComponent(spec == .hires ? "picture.art" : "picture.koa")
        let process = Process()
        process.executableURL = executable
        process.arguments = ["convert", input.path, "-o", output.path]
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard let data = FileManager.default.contents(atPath: output.path) else {
            throw Benchmark.Error.missingPhoto(output.path)
        }
        return spec == .hires ? try C64Frame(artStudio: Array(data)) : try C64Frame(koala: Array(data))
    }

    /// The modes image64 converts: the bitmap modes.
    public static let modes = Benchmark.modes.filter { $0.spec.pixels == .bitmap }

    /// Converts each photo in each of its modes with image64, and scores it on
    /// each monitor as the benchmark scores the converter's pictures.
    public func run(_ photos: [Benchmark.Photo]) throws -> [Benchmark.Entry] {
        var entries: [Benchmark.Entry] = []
        for (modeName, spec, _) in Self.modes {
            for photo in photos {
                let reference = Benchmark.reference(photo)
                let start = DispatchTime.now().uptimeNanoseconds
                let frame = try convert(reference.rgbImage, spec: spec)
                let seconds = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9
                for (monitorName, display) in Benchmark.monitors {
                    let (score, shown) = Benchmark.score(frame, against: reference, on: display)
                    entries.append(
                        Benchmark.Entry(
                            photo: photo.name, mode: modeName, monitor: monitorName, score: score, seconds: seconds,
                            shown: shown))
                }
            }
        }
        return entries
    }
}
