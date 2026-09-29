import C64Core
import Foundation

/// The VICE emulator's x64sc, used as the test oracle for the renderer (plan,
/// section 10). VICE is GPL software: the tools run it, and nothing of it is
/// copied or shipped.
public struct VICE: Sendable {
    public enum Error: Swift.Error, CustomStringConvertible {
        case noScreenshot(log: String)
        case unknownColor(x: Int, y: Int, rgb: [UInt8])
        case badScreenshot(String)

        public var description: String {
            switch self {
            case .noScreenshot(let log): "VICE saved no screenshot. Its log ends with:\n\(log)"
            case .unknownColor(let x, let y, let rgb): "Pixel (\(x), \(y)) has a colour outside the palette: \(rgb)"
            case .badScreenshot(let reason): "VICE's screenshot could not be read: \(reason)"
            }
        }
    }

    /// The palette VICE is told to use. Any palette with 16 distinct colours
    /// works, as each colour is mapped back to its index.
    static let palette = C64Palette.pepto2001

    public let executable: URL

    public init(executable: URL) {
        self.executable = executable
    }

    /// Finds x64sc: the path in $X64SC if set, then on the PATH, then where
    /// Homebrew and the session hook's build install it.
    public static func find() -> VICE? {
        let environment = ProcessInfo.processInfo.environment
        var candidates = environment["X64SC"].map { [$0] } ?? []
        for directory in (environment["PATH"] ?? "").split(separator: ":") {
            candidates.append("\(directory)/x64sc")
        }
        candidates += ["/opt/homebrew/bin/x64sc", "/usr/local/bin/x64sc", "/opt/vice/bin/x64sc"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }.map {
            VICE(executable: URL(fileURLWithPath: $0))
        }
    }

    /// The directory with VICE's C64 ROMs and palettes.
    var dataDirectory: URL {
        executable.resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("share/vice/C64")
    }

    /// The character ROM that comes with VICE, 4 KB: the upper case set,
    /// then the lower case set. The C64's character ROM is Commodore's: tests
    /// read it from VICE and never add it to the repository.
    public func characterROM() -> [UInt8]? {
        for name in ["chargen-901225-01.bin", "chargen"] {
            if let data = FileManager.default.contents(atPath: dataDirectory.appendingPathComponent(name).path),
                data.count == 4096
            {
                return Array(data)
            }
        }
        return nil
    }

    /// Starts a program (.prg) or disk image (.d64) on a PAL C64, lets it
    /// run for `cycles` (a second is about 985,000), and returns the screen:
    /// `Screen.width` × `Screen.height` colour indices, border included.
    /// Loading from a disk takes about 30 million cycles more.
    public func screen(running file: URL, cycles: Int = 4_000_000) throws -> IndexedImage {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "vice-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let paletteFile = directory.appendingPathComponent("palette.vpl")
        let lines = Self.palette.colors.map { color in
            [color.r, color.g, color.b].map { String($0, radix: 16, uppercase: true) }.map {
                $0.count == 1 ? "0" + $0 : $0
            }.joined(separator: " ")
        }
        try (["# Camera C64 test palette"] + lines).joined(separator: "\n").appending("\n")
            .write(to: paletteFile, atomically: true, encoding: .utf8)
        let screenshot = directory.appendingPathComponent("screen.png")
        let log = directory.appendingPathComponent("vice.log")

        let process = Process()
        process.executableURL = executable
        process.arguments = [
            "-default",
            // VICE crashes logging to a stdout that is not a terminal.
            "+logtostdout", "-logtofile", "-logfile", log.path,
            "-sounddev", "dummy", "-warp",
            // No CRT emulation, VICE's normal borders, and our palette as it is.
            "-VICIIfilter", "0", "-VICIIborders", "0",
            "-VICIIextpal", "-VICIIpalette", paletteFile.path,
            "-VICIIsaturation", "1000", "-VICIIcontrast", "1000", "-VICIIbrightness", "1000",
            "-VICIIgamma", "1000", "-VICIItint", "1000",
            // Programs go straight into memory; disk images load through an
            // emulated 1541. No random delay, so every run is the same.
            "-autostartprgmode", "1", "+autostart-delay-random",
            "-limitcycles", String(cycles), "-exitscreenshot", screenshot.path,
            "-autostart", file.path,
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()

        guard let png = FileManager.default.contents(atPath: screenshot.path) else {
            let text = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
            throw Error.noScreenshot(log: text.split(separator: "\n").suffix(20).joined(separator: "\n"))
        }
        let decoded: (width: Int, height: Int, rgb: [UInt8])
        do {
            decoded = try PNG.decode(Array(png))
        } catch {
            throw Error.badScreenshot("\(error)")
        }
        var indices: [RGB: UInt8] = [:]
        for (index, color) in Self.palette.colors.enumerated() {
            indices[color] = UInt8(index)
        }
        var pixels = [UInt8](repeating: 0, count: decoded.width * decoded.height)
        for pixel in pixels.indices {
            let rgb = Array(decoded.rgb[pixel * 3..<pixel * 3 + 3])
            guard let index = indices[RGB(rgb[0], rgb[1], rgb[2])] else {
                throw Error.unknownColor(x: pixel % decoded.width, y: pixel / decoded.width, rgb: rgb)
            }
            pixels[pixel] = index
        }
        return IndexedImage(width: decoded.width, height: decoded.height, pixels: pixels)
    }
}
