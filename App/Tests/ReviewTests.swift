import C64Core
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import CameraC64

/// The review's actions: Share, Save to Photos, Send to C64 and Delete
/// (docs/UX.md, section 5).
@MainActor
struct ReviewTests {
    /// A mode's picture of the sample photo, on the black-and-white monitor,
    /// whose search is the quickest.
    private func picture(_ mode: PictureMode, on monitor: Monitor = .blackAndWhite) async throws -> ShownPicture {
        // Bound first: passed straight to a `Photo?` parameter, `#require`
        // would check a doubly optional value that is never nil.
        let photo = try #require(Photo.sample)
        let maker = PictureMaker(photo: photo)
        let key = PictureMaker.Key(mode, on: monitor)
        await maker.make(key)
        return try #require(maker.picture(key))
    }

    private func files(_ picture: ShownPicture) -> [SharedFile] {
        SharedFile.files(of: picture, crt: .standard, name: "C64 Test", programName: "Test")
    }

    /// A PNG file's pixels.
    private func decoded(_ png: Data) throws -> RGBImage {
        let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        return try #require(RGBImage(image))
    }

    /// Share offers the picture as on TV first, then the pixel-exact PNG and
    /// the C64 files: Art Studio files for hires, Koala for multicolour.
    @Test func shareOffersThePictureAsOnTVFirst() {
        #expect(
            SharedFile.kinds(for: C64Frame(mode: .hiresBitmap)) == [
                .pictureAsOnTV, .pixelExactPicture, .program, .diskImage, .artStudio,
            ])
        #expect(
            SharedFile.kinds(for: C64Frame(mode: .multicolorBitmap)) == [
                .pictureAsOnTV, .pixelExactPicture, .program, .diskImage, .koala,
            ])
        #expect(
            SharedFile.kinds(for: C64Frame(characterSet: .upperCase)) == [
                .pictureAsOnTV, .pixelExactPicture, .program, .diskImage,
            ])
    }

    /// Files are named after the shot's mode and time, each with its type's
    /// extension.
    @Test func sharedFilesAreNamedAfterTheShot() throws {
        let utc = try #require(TimeZone(identifier: "UTC"))
        let taken = try #require(ISO8601DateFormatter().date(from: "2026-10-06T21:04:12Z"))
        let name = SharedFile.name(mode: "Multicolour", taken: taken, timeZone: utc)
        #expect(name == "C64 Multicolour 2026-10-06 21.04.12")
        let picture = try #require(
            ShownPicture(
                RGBImage(width: Screen.width, height: Screen.height, fill: RGB(0, 0, 0)),
                frame: C64Frame(mode: .multicolorBitmap)))
        let files = SharedFile.files(of: picture, crt: nil, name: name, programName: "Multicolour")
        #expect(
            files.map(\.fileName) == [
                "C64 Multicolour 2026-10-06 21.04.12.png", "C64 Multicolour 2026-10-06 21.04.12 320x200.png",
                "C64 Multicolour 2026-10-06 21.04.12.prg", "C64 Multicolour 2026-10-06 21.04.12.d64",
                "C64 Multicolour 2026-10-06 21.04.12.kla",
            ])
        #expect(
            files.map(\.kind.contentType) == [.png, .png, .c64Program, .d64DiskImage, .koalaPicture])
    }

    /// The C64 files hold the picture's C64 memory, as C64Core writes it.
    @Test func c64FilesHoldThePicturesMemory() async throws {
        let multicolour = try await picture(.multicolour)
        let frame = multicolour.frame
        let byKind = Dictionary(uniqueKeysWithValues: files(multicolour).map { ($0.kind, $0) })
        #expect(try await byKind[.program]?.contents() == Data(frame.prg()))
        #expect(try await byKind[.koala]?.contents() == Data(frame.koala()))

        // The disk image holds the program, and is named after the app.
        let disk = try #require(try await byKind[.diskImage]?.contents())
        #expect(disk.count == D64Image.size)
        let start = Data(frame.prg().prefix(254))
        #expect(disk.range(of: start) != nil)
        #expect(disk.range(of: Data("CAMERA C64".utf8)) != nil)

        let hires = try await picture(.hires)
        let artStudio = try #require(files(hires).first { $0.kind == .artStudio })
        #expect(try await artStudio.contents() == Data(hires.frame.artStudio()))
    }

    /// The pixel-exact PNG is the display window in the palette's colours,
    /// one pixel for each C64 pixel, whatever the monitor.
    @Test func pixelExactPNGHasThePalettesColours() async throws {
        let hires = try await picture(.hires, on: .tv)
        let file = try #require(files(hires).first { $0.kind == .pixelExactPicture })
        let image = try decoded(try await file.contents())
        let window = VICII.render(hires.frame).window
        #expect(image.width == 320 && image.height == 200)
        var differences = 0
        for y in 0..<200 {
            for x in 0..<320 where image[x, y] != C64Palette.colodore[window[x, y]] {
                differences += 1
            }
        }
        #expect(differences == 0)
    }

    /// The picture as on TV is a PNG of the TV, border and CRT layer
    /// included, as Save to Photos saves it too.
    @Test func pictureAsOnTVIsAPNG() async throws {
        let multicolour = try await picture(.multicolour)
        let file = try #require(files(multicolour).first)
        #expect(file.kind == .pictureAsOnTV)
        let image = try decoded(try await file.contents())
        #expect(image.width == 1536)
        #expect(abs(Double(image.width) / Double(image.height) - TVGeometry.aspectRatio) < 0.01)
    }

    /// The app's Info.plist declares the C64 files' types, allows plain HTTP
    /// on the local network only, and says why the app uses the camera,
    /// Photos and the local network.
    @Test func infoPlistDeclaresWhatTheReviewNeeds() throws {
        let info = try #require(Bundle.main.infoDictionary)
        let declarations = try #require(info["UTImportedTypeDeclarations"] as? [[String: Any]])
        var extensions: [String: [String]] = [:]
        for declaration in declarations {
            let identifier = try #require(declaration["UTTypeIdentifier"] as? String)
            let tags = try #require(declaration["UTTypeTagSpecification"] as? [String: Any])
            extensions[identifier] = tags["public.filename-extension"] as? [String]
        }
        #expect(extensions[UTType.c64Program.identifier] == ["prg"])
        #expect(extensions[UTType.d64DiskImage.identifier] == ["d64"])
        #expect(extensions[UTType.koalaPicture.identifier] == ["kla", "koa"])
        #expect(extensions[UTType.artStudioPicture.identifier] == ["art"])

        let security = try #require(info["NSAppTransportSecurity"] as? [String: Any])
        #expect(security["NSAllowsLocalNetworking"] as? Bool == true)
        #expect(security["NSAllowsArbitraryLoads"] == nil)
        for key in ["NSCameraUsageDescription", "NSPhotoLibraryAddUsageDescription", "NSLocalNetworkUsageDescription"] {
            #expect((info[key] as? String)?.isEmpty == false, "\(key)")
        }
    }

    /// Settings takes the Ultimate's address as an IP address or a host
    /// name, with a port if need be, or as a URL.
    @Test func ultimateAddressesBecomeURLs() {
        func url(_ address: String) -> String? {
            Ultimate(address: address).url(route: "runners:run_prg")?.absoluteString
        }
        #expect(url("192.168.1.64") == "http://192.168.1.64/v1/runners:run_prg")
        #expect(url(" 192.168.1.64\n") == "http://192.168.1.64/v1/runners:run_prg")
        #expect(url("ultimate.local:8080") == "http://ultimate.local:8080/v1/runners:run_prg")
        #expect(url("http://192.168.1.64/") == "http://192.168.1.64/v1/runners:run_prg")
        #expect(url("") == nil)
        #expect(url("  ") == nil)
    }

    /// Send to C64 posts the program as it is, with the password if the
    /// Ultimate has one.
    @Test func sendToC64PostsTheProgram() throws {
        let program: [UInt8] = [0x01, 0x08, 0x0B, 0x08]
        let plain = try #require(Ultimate(address: "192.168.1.64").runRequest(program))
        #expect(plain.httpMethod == "POST")
        #expect(plain.url?.absoluteString == "http://192.168.1.64/v1/runners:run_prg")
        #expect(plain.httpBody == Data(program))
        #expect(plain.value(forHTTPHeaderField: "Content-Type") == "application/octet-stream")
        #expect(plain.value(forHTTPHeaderField: "X-Password") == nil)
        let locked = try #require(Ultimate(address: "192.168.1.64", password: "secret").runRequest(program))
        #expect(locked.value(forHTTPHeaderField: "X-Password") == "secret")
        #expect(Ultimate(address: "").runRequest(program) == nil)
    }

    /// What goes wrong on the way to the C64 is said in a way the user can act
    /// on.
    @Test func sendToC64SaysWhatWentWrong() {
        #expect(Ultimate.failure(URLError(.notConnectedToInternet)) == .noNetwork)
        #expect(Ultimate.failure(URLError(.timedOut)) == .notFound)
        #expect(Ultimate.failure(URLError(.cannotConnectToHost)) == .notFound)
        #expect(Ultimate.failure(URLError(.appTransportSecurityRequiresSecureConnection)) == .notLocal)
        #expect(Ultimate.errors(in: Data(#"{"errors": []}"#.utf8)).isEmpty)
        #expect(Ultimate.errors(in: Data(#"{"errors": ["Not a program"]}"#.utf8)) == ["Not a program"])
        #expect(Ultimate.errors(in: Data("<html></html>".utf8)).isEmpty)

        let model = CameraModel()
        model.sendingStarted()
        #expect(model.sending)
        model.sendingEnded(.wrongPassword)
        #expect(!model.sending)
        #expect(model.message?.title == "WRONG PASSWORD")
        model.sendingStarted()
        model.sendingEnded(nil)
        #expect(model.message?.title == "SENT TO C64")
    }

    /// Send to C64 is offered once an Ultimate is set up.
    @Test func sendToC64OnceAnUltimateIsSetUp() {
        #expect(ReviewAction.all(canSend: false) == [.share, .save, .delete])
        #expect(ReviewAction.all(canSend: true) == [.share, .save, .send, .delete])
    }

    /// Saving says so, but a shot that Settings saves by itself only says if
    /// it failed.
    @Test func savingSaysHowItWent() {
        let model = CameraModel()
        model.saved(nil)
        #expect(model.message?.title == "SAVED TO PHOTOS")
        model.saved(.notAllowed)
        #expect(model.message?.title == "NOT SAVED")
        #expect(model.message?.detail == PhotoLibrary.Failure.notAllowed.detail)
        let quiet = CameraModel()
        quiet.saved(nil, everyShot: true)
        #expect(quiet.message == nil)
    }
}
