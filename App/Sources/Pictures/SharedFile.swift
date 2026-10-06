import C64Core
import CoreGraphics
import CoreTransferable
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The C64 files' types. No app owns them, so App/Info.plist imports them.
nonisolated extension UTType {
    /// A program file (.prg): its load address, then the program.
    static let c64Program = UTType(importedAs: "com.camerac64.prg", conformingTo: .data)
    /// A 1541 floppy disk image (.d64).
    static let d64DiskImage = UTType(importedAs: "com.camerac64.d64", conformingTo: .data)
    /// A Koala Painter picture (.kla or .koa): a multicolour bitmap.
    static let koalaPicture = UTType(importedAs: "com.camerac64.koala", conformingTo: .data)
    /// An OCP Art Studio picture (.art): a hires bitmap.
    static let artStudioPicture = UTType(importedAs: "com.camerac64.art-studio", conformingTo: .data)
}

/// A file the review shares (docs/UX.md, section 6): the picture as on TV,
/// the pixel-exact PNG, or one of the C64 files. Its contents are made only
/// when it is shared, from the picture and its C64 memory.
nonisolated struct SharedFile: Transferable, Sendable {
    /// What a file holds.
    nonisolated enum Kind: Hashable, Sendable {
        /// The picture as on TV: the monitor's display model, the CRT layer
        /// when it is on, and the border, as a PNG.
        case pictureAsOnTV
        /// The display window in the palette's colours, one pixel for each
        /// C64 pixel, as a PNG: square pixels, for C64 tools.
        case pixelExactPicture
        /// A program that shows the picture, until a key resets the C64.
        case program
        /// A 1541 disk image holding that program.
        case diskImage
        /// A Koala Painter file, for a multicolour bitmap.
        case koala
        /// An Art Studio file, for a hires bitmap.
        case artStudio

        /// What Share calls it.
        var title: String {
            switch self {
            case .pictureAsOnTV: "Picture as on TV"
            case .pixelExactPicture: "Pixel-Exact PNG"
            case .program: "C64 Program (.prg)"
            case .diskImage: "C64 Disk Image (.d64)"
            case .koala: "Koala Painter File (.kla)"
            case .artStudio: "Art Studio File (.art)"
            }
        }

        /// Its symbol in Share's menu.
        var symbol: String {
            switch self {
            case .pictureAsOnTV: "tv"
            case .pixelExactPicture: "square.grid.3x3"
            case .program: "terminal"
            case .diskImage: "opticaldisc"
            case .koala, .artStudio: "paintpalette"
            }
        }

        var contentType: UTType {
            switch self {
            case .pictureAsOnTV, .pixelExactPicture: .png
            case .program: .c64Program
            case .diskImage: .d64DiskImage
            case .koala: .koalaPicture
            case .artStudio: .artStudioPicture
            }
        }

        /// The end of the file's name, after the shot's name.
        var nameEnding: String {
            switch self {
            case .pictureAsOnTV: ".png"
            case .pixelExactPicture: " 320x200.png"
            case .program: ".prg"
            case .diskImage: ".d64"
            case .koala: ".kla"
            case .artStudio: ".art"
            }
        }
    }

    enum Failure: Error {
        /// The picture could not be drawn or encoded.
        case notMade
    }

    /// The name of the disk in a disk image.
    static let diskName = "CAMERA C64"

    let kind: Kind
    /// The file's name, its extension included.
    let fileName: String
    let picture: ShownPicture
    /// The CRT layer's look, for the picture as on TV, or nil for none.
    let crt: CRT?
    /// The program's name on a disk image.
    let programName: String

    /// The files a picture can be shared as, in the order Share offers them:
    /// the picture as on TV first, then the pixel-exact PNG and the C64
    /// files. `name` is the shot's (`name(mode:taken:)`), and `programName`
    /// the program's on a disk image.
    static func files(of picture: ShownPicture, crt: CRT?, name: String, programName: String) -> [SharedFile] {
        kinds(for: picture.frame).map { kind in
            SharedFile(
                kind: kind, fileName: name + kind.nameEnding, picture: picture, crt: crt, programName: programName)
        }
    }

    /// What a frame can be shared as: Koala files hold multicolour bitmaps,
    /// and Art Studio files hires ones.
    static func kinds(for frame: C64Frame) -> [Kind] {
        let kinds: [Kind] = [.pictureAsOnTV, .pixelExactPicture, .program, .diskImage]
        switch frame.mode {
        case .multicolorBitmap: return kinds + [.koala]
        case .hiresBitmap: return kinds + [.artStudio]
        case .standardText, .multicolorText, .extendedColorText: return kinds
        }
    }

    /// A shot's name in its files' names: its mode and when it was taken,
    /// such as "C64 Multicolour 2026-10-06 21.04.12".
    static func name(mode: String, taken date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return "C64 \(mode) \(formatter.string(from: date))"
    }

    /// The file's contents.
    func contents() async throws -> Data {
        let frame = picture.frame
        switch kind {
        case .pictureAsOnTV:
            let (picture, crt) = (picture, crt)
            let png = await MainActor.run { TVView.pngAsOnTV(of: picture, crt: crt) }
            guard let png else { throw Failure.notMade }
            return png
        case .pixelExactPicture:
            guard let image = VICII.render(frame).window.rgbImage(.colodore).cgImage, let png = Self.png(image)
            else { throw Failure.notMade }
            return png
        case .program:
            return Data(frame.prg())
        case .diskImage:
            let program = D64Image.File(name: programName, contents: frame.prg())
            return Data(try D64Image(name: Self.diskName, files: [program]).bytes())
        case .koala:
            return Data(frame.koala())
        case .artStudio:
            return Data(frame.artStudio())
        }
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .png) { try await $0.writtenFile() }
            .exportingCondition { $0.kind.contentType == .png }
        FileRepresentation(exportedContentType: .c64Program) { try await $0.writtenFile() }
            .exportingCondition { $0.kind == .program }
        FileRepresentation(exportedContentType: .d64DiskImage) { try await $0.writtenFile() }
            .exportingCondition { $0.kind == .diskImage }
        FileRepresentation(exportedContentType: .koalaPicture) { try await $0.writtenFile() }
            .exportingCondition { $0.kind == .koala }
        FileRepresentation(exportedContentType: .artStudioPicture) { try await $0.writtenFile() }
            .exportingCondition { $0.kind == .artStudio }
    }

    /// Where shared files are written, each in a folder of its own, so that
    /// it keeps its name. The app empties it when it starts.
    static let folder = URL.temporaryDirectory.appending(path: "Shared", directoryHint: .isDirectory)

    /// Removes the files shared before.
    static func removeOldFiles() {
        try? FileManager.default.removeItem(at: folder)
    }

    /// The file, written where the share sheet can read it.
    private func writtenFile() async throws -> SentTransferredFile {
        let data = try await contents()
        let directory = Self.folder.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appending(path: fileName, directoryHint: .notDirectory)
        try data.write(to: file)
        return SentTransferredFile(file)
    }

    /// An image as a PNG file.
    static func png(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                data as CFMutableData, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
