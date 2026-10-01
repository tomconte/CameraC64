import C64Core
import C64Tools
import Foundation

let usage = """
    Usage: c64conv <command> [options]

    Commands:
      testcard <mode> -o <file> [--seed <n>]
          A random picture that obeys the mode's limits. Modes: hires,
          multicolor, charset, multicolor-charset, ecm-charset.
      convert <photo.png> -o <file> [--mode hires|multicolor] [--monitor <name>]
              [--palette colodore|pepto] [--dithering <0-1>] [--neutral] [--scale <n>]
          Converts a photo into a picture in a mode, multicolour by default,
          made for a monitor: tv (the default), monitor, sharp, bw, green or
          amber. --neutral turns the automatic tones off. A .png output shows
          the picture on that monitor, border included.
      render <picture> -o <file.png> [--palette colodore|pepto] [--scale <n>] [--window]
          Draws a picture as the VIC-II shows it, border included unless
          --window is given.
      export <picture> -o <file>
          Writes a picture in another format.
      vice <file.prg|file.d64> -o <file.png> [--cycles <n>] [--palette colodore|pepto] [--scale <n>]
          Runs a program in VICE's x64sc and saves its screen.
      speed [--runs <n>]
          The speed benchmark: how long each stage of a 1920 x 1440 viewfinder
          frame takes here, as the app's hidden screen shows it on a phone.
      benchmark [--photos <dir>] [-o <dir>] [--summary <file.md>] [--dithering <0-1>] [--update-baseline]
          The quality benchmark: converts a chart, the app's sample photo and
          the photos in Tools/Benchmark/photos.txt (from get-photos.sh), and
          compares the scores with Tools/Benchmark/scores.txt, failing if they
          get worse. -o writes a page with every picture. With image64 on the
          PATH or in $IMAGE64, scores its pictures too.

    Pictures are read from .kla/.koa (Koala) and .art (Art Studio) files, and
    written as .prg, .d64, .kla/.koa, .art or .png, by the output's extension.
    """

struct Failure: Error, CustomStringConvertible {
    var description: String
}

/// The command line after the command: positional arguments and --options.
struct Arguments {
    var positional: [String] = []
    var options: [String: String] = [:]
    var flags: Set<String> = []

    static let flagNames: Set<String> = ["--window", "--neutral", "--update-baseline"]

    init(_ arguments: ArraySlice<String>) throws {
        var remaining = arguments
        while let argument = remaining.popFirst() {
            if Self.flagNames.contains(argument) {
                flags.insert(argument)
            } else if argument.hasPrefix("-") {
                guard let value = remaining.popFirst() else { throw Failure(description: "\(argument) needs a value") }
                options[argument] = value
            } else {
                positional.append(argument)
            }
        }
    }

    func output() throws -> URL {
        guard let path = options["-o"] else { throw Failure(description: "Missing -o <file>") }
        return URL(fileURLWithPath: path)
    }

    func integer(_ option: String, default value: Int) throws -> Int {
        guard let text = options[option] else { return value }
        guard let number = Int(text), number > 0 else { throw Failure(description: "\(option) needs a number") }
        return number
    }

    func number(_ option: String, default value: Float) throws -> Float {
        guard let text = options[option] else { return value }
        guard let number = Float(text) else { throw Failure(description: "\(option) needs a number") }
        return number
    }

    func mode() throws -> ModeSpec {
        switch options["--mode"] ?? "multicolor" {
        case "hires": .hires
        case "multicolor", "multicolour": .multicolor
        case let other: throw Failure(description: "Unknown mode \(other): use hires or multicolor")
        }
    }

    func monitor() throws -> DisplayModel {
        switch options["--monitor"] ?? "tv" {
        case "tv": .tv
        case "monitor": .commodoreMonitor
        case "sharp": .sharp
        case "bw": .blackAndWhite
        case "green": .green
        case "amber": .amber
        case let other: throw Failure(description: "Unknown monitor \(other)")
        }
    }

    func palette() throws -> C64Palette {
        switch options["--palette"] ?? "colodore" {
        case "colodore": .colodore
        case "pepto": .pepto2001
        case let other: throw Failure(description: "Unknown palette \(other)")
        }
    }
}

func read(_ path: String) throws -> C64Frame {
    guard let data = FileManager.default.contents(atPath: path) else {
        throw Failure(description: "Cannot read \(path)")
    }
    switch URL(fileURLWithPath: path).pathExtension.lowercased() {
    case "kla", "koa": return try C64Frame(koala: Array(data))
    case "art": return try C64Frame(artStudio: Array(data))
    default: throw Failure(description: "Cannot read \(path): use a .kla, .koa or .art file")
    }
}

func write(
    _ frame: C64Frame, to file: URL, palette: C64Palette = .colodore, monitor: DisplayModel = .sharp, scale: Int = 1
) throws {
    let bytes: [UInt8]
    switch file.pathExtension.lowercased() {
    case "prg":
        bytes = frame.prg()
    case "d64":
        let name = file.deletingPathExtension().lastPathComponent
        bytes = try D64Image(name: name, files: [.init(name: name, contents: frame.prg())]).bytes()
    case "kla", "koa":
        guard frame.mode == .multicolorBitmap else { throw Failure(description: "Koala files hold multicolor bitmaps") }
        bytes = frame.koala()
    case "art":
        guard frame.mode == .hiresBitmap else { throw Failure(description: "Art Studio files hold hires bitmaps") }
        bytes = frame.artStudio()
    case "png" where monitor == .sharp:
        bytes = PNG.encode(VICII.render(frame), palette: palette, scale: scale)
    case "png":
        bytes = PNG.encode(monitor.show(VICII.render(frame), palette: palette), scale: scale)
    default:
        throw Failure(description: "Cannot write \(file.lastPathComponent): use .prg, .d64, .kla, .koa, .art or .png")
    }
    try Data(bytes).write(to: file)
}

func run(_ command: String, _ arguments: Arguments) throws {
    switch command {
    case "testcard":
        let modes: [String: ModeSpec] = [
            "hires": .hires, "multicolor": .multicolor, "charset": .characterSet,
            "multicolor-charset": .multicolorCharacterSet, "ecm-charset": .extendedColorCharacterSet,
        ]
        guard let name = arguments.positional.first, let spec = modes[name] else {
            throw Failure(description: "testcard needs a mode: \(modes.keys.sorted().joined(separator: ", "))")
        }
        let seed = try arguments.integer("--seed", default: 1)
        try write(C64Frame(TestPictures.random(spec, seed: UInt64(seed))), to: arguments.output())

    case "convert":
        guard let input = arguments.positional.first else { throw Failure(description: "convert needs a photo") }
        guard let data = FileManager.default.contents(atPath: input) else {
            throw Failure(description: "Cannot read \(input)")
        }
        let photo = try PNG.decodeImage(Array(data))
        let (palette, monitor) = (try arguments.palette(), try arguments.monitor())
        let dithering = try arguments.number("--dithering", default: Converter.Settings().dithering)
        let settings = Converter.Settings(palette: palette, display: monitor, dithering: dithering)
        let converter = Converter(spec: try arguments.mode(), settings: settings)
        let tones = arguments.flags.contains("--neutral") ? Tones.neutral : Tones()
        let conversion = converter.convert(photo, tones: tones)
        try write(
            conversion.frame, to: arguments.output(), palette: palette, monitor: monitor,
            scale: try arguments.integer("--scale", default: 1))

    case "render":
        guard let input = arguments.positional.first else { throw Failure(description: "render needs a picture") }
        var screen = VICII.render(try read(input))
        if arguments.flags.contains("--window") {
            screen = screen.window
        }
        let png = PNG.encode(
            screen, palette: try arguments.palette(), scale: try arguments.integer("--scale", default: 1))
        try Data(png).write(to: arguments.output())

    case "export":
        guard let input = arguments.positional.first else { throw Failure(description: "export needs a picture") }
        try write(read(input), to: arguments.output())

    case "vice":
        guard let input = arguments.positional.first else { throw Failure(description: "vice needs a program") }
        guard let vice = VICE.find() else { throw Failure(description: "VICE's x64sc was not found") }
        let screen = try vice.screen(
            running: URL(fileURLWithPath: input), cycles: try arguments.integer("--cycles", default: 4_000_000))
        let png = PNG.encode(
            screen, palette: try arguments.palette(), scale: try arguments.integer("--scale", default: 1))
        try Data(png).write(to: arguments.output())

    case "benchmark":
        try benchmark(arguments)

    case "speed":
        let runs = try arguments.integer("--runs", default: 9)
        let frame = SpeedBenchmark.cameraFrame()
        print("A \(frame.width) x \(frame.height) frame, median of \(runs) runs:")
        print("target + conversion + rendering + display")
        for benchmarkCase in SpeedBenchmark.cases {
            let timing = SpeedBenchmark.measure(benchmarkCase, frame: frame, runs: runs)
            print("\(benchmarkCase.name): \(SpeedBenchmark.describe(timing))")
        }

    case "help", "-h", "--help":
        print(usage)

    default:
        throw Failure(description: "Unknown command \(command)\n\n\(usage)")
    }
}

func benchmark(_ arguments: Arguments) throws {
    var photos = [Benchmark.chart()]
    let sample = "App/Resources/Assets.xcassets/Samples/SamplePhoto.imageset/sample-photo.png"
    if FileManager.default.fileExists(atPath: sample) {
        photos.append(
            try Benchmark.photo(
                named: "sample", description: "The app's sample picture: a sunset, drawn",
                file: URL(fileURLWithPath: sample)))
    }
    let directory = URL(fileURLWithPath: arguments.options["--photos"] ?? "Tools/Benchmark/photos")
    photos += try Benchmark.photos(list: URL(fileURLWithPath: "Tools/Benchmark/photos.txt"), directory: directory)

    let dithering = try arguments.number("--dithering", default: Converter.Settings().dithering)
    let entries = Benchmark.run(photos, dithering: dithering)
    let baselineFile = URL(fileURLWithPath: "Tools/Benchmark/scores.txt")
    let baseline = try? Benchmark.scores(in: baselineFile)
    var summary = Benchmark.markdown(entries, baseline: baseline)
    for (mode, _) in Benchmark.modes {
        let times = entries.filter { $0.mode == mode && $0.monitor != "bw" }.map(\.seconds).sorted()
        summary += String(
            format: "Converting a photo in %@ takes %.0f ms (median).\n", mode, times[times.count / 2] * 1000)
    }
    var image64: [Benchmark.Entry] = []
    if let tool = Image64.find() {
        image64 = try tool.run(photos)
        summary +=
            "\nimage64, with its default settings, for comparison:\n\n" + Benchmark.markdown(image64, baseline: nil)
    }
    print(summary)
    if let file = arguments.options["--summary"] {
        // Added to the file, as GitHub's job summary expects.
        let existing = FileManager.default.contents(atPath: file) ?? Data()
        try (existing + Data(("## Quality benchmark\n\n" + summary).utf8)).write(to: URL(fileURLWithPath: file))
    }
    if let output = arguments.options["-o"] {
        try Benchmark.writeReport(
            entries, photos: photos, baseline: baseline, image64: image64, to: URL(fileURLWithPath: output))
    }

    if arguments.flags.contains("--update-baseline") {
        try Benchmark.write(entries, to: baselineFile)
        print("Wrote \(baselineFile.path)")
    } else if let baseline {
        let comparison = Benchmark.compare(entries, with: baseline)
        guard comparison.passed else {
            var lines = ["The quality benchmark got worse than \(baselineFile.path):"]
            lines += comparison.regressions.map {
                String(format: "  %@: %.3f, was %.3f", $0.key, $0.score, $0.baseline)
            }
            lines += comparison.unmatched.map { "  \($0): in only one of the two" }
            lines.append(String(format: "  mean: %.3f, was %.3f", comparison.mean, comparison.baselineMean))
            lines.append("If the change is wanted, run c64conv benchmark --update-baseline and commit the scores.")
            throw Failure(description: lines.joined(separator: "\n"))
        }
    }
}

let command = CommandLine.arguments.dropFirst().first ?? "help"
do {
    try run(command, Arguments(CommandLine.arguments.dropFirst(2)))
} catch {
    FileHandle.standardError.write(Data("c64conv: \(error)\n".utf8))
    exit(1)
}
