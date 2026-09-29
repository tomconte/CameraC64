import C64Core
import C64Tools
import Foundation

let usage = """
    Usage: c64conv <command> [options]

    Commands:
      testcard <mode> -o <file> [--seed <n>]
          A random picture that obeys the mode's limits. Modes: hires,
          multicolor, charset, multicolor-charset, ecm-charset.
      render <picture> -o <file.png> [--palette colodore|pepto] [--scale <n>] [--window]
          Draws a picture as the VIC-II shows it, border included unless
          --window is given.
      export <picture> -o <file>
          Writes a picture in another format.
      vice <file.prg|file.d64> -o <file.png> [--cycles <n>] [--scale <n>]
          Runs a program in VICE's x64sc and saves its screen.

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

    init(_ arguments: ArraySlice<String>) throws {
        var remaining = arguments
        while let argument = remaining.popFirst() {
            if argument == "--window" {
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

func write(_ frame: C64Frame, to file: URL, palette: C64Palette = .colodore, scale: Int = 1) throws {
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
    case "png":
        bytes = PNG.encode(VICII.render(frame), palette: palette, scale: scale)
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
        let png = PNG.encode(screen, palette: .pepto2001, scale: try arguments.integer("--scale", default: 1))
        try Data(png).write(to: arguments.output())

    case "help", "-h", "--help":
        print(usage)

    default:
        throw Failure(description: "Unknown command \(command)\n\n\(usage)")
    }
}

let command = CommandLine.arguments.dropFirst().first ?? "help"
do {
    try run(command, Arguments(CommandLine.arguments.dropFirst(2)))
} catch {
    FileHandle.standardError.write(Data("c64conv: \(error)\n".utf8))
    exit(1)
}
