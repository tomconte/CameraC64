import C64Core
import Foundation
import Observation
import SwiftUI

/// A graphics mode, as the mode dial and the mode strip offer it.
///
/// PETSCII comes twice (docs/UX.md, section 5): with only the graphics
/// characters, for the classic PETSCII look, and with all of them, whose
/// letters, digits and punctuation make pictures look like BBS art.
enum PictureMode: CaseIterable, Identifiable {
    case hires
    case multicolour
    /// PETSCII with only the graphics characters.
    case petscii
    /// PETSCII with all the characters.
    case bbs

    var id: Self { self }

    var name: String {
        switch self {
        case .hires: "HIRES"
        case .multicolour: "MULTICOLOUR"
        case .petscii: "PETSCII"
        case .bbs: "BBS"
        }
    }

    /// A shorter name where space is tight, as on the landscape dial.
    var shortName: String { self == .multicolour ? "MULTI" : name }

    /// The name in file names, such as "Multicolour".
    var title: String {
        switch self {
        case .hires: "Hires"
        case .multicolour: "Multicolour"
        case .petscii: "PETSCII"
        case .bbs: "BBS"
        }
    }

    /// One line on what the mode does.
    var summary: String {
        switch self {
        case .hires: "320 × 200, 2 colours in each 8 × 8 cell"
        case .multicolour: "160 × 200 wide pixels, 4 colours in each 4 × 8 cell"
        case .petscii: "40 × 25 graphics characters, one colour each"
        case .bbs: "PETSCII with letters and digits, like BBS art"
        }
    }

    /// The mode as C64Core describes it.
    var spec: ModeSpec {
        switch self {
        case .hires: .hires
        case .multicolour: .multicolor
        case .petscii, .bbs: .petscii
        }
    }

    /// The characters a PETSCII picture may use. The other modes have none,
    /// and the converter ignores it for them.
    var petsciiCharacters: CharacterROM.Selection {
        self == .petscii ? .graphics : .all
    }

    /// What the converter optimises for, for a monitor.
    func converterSettings(on monitor: Monitor) -> Converter.Settings {
        Converter.Settings(display: monitor.display, petsciiCharacters: petsciiCharacters)
    }

    /// The mode `steps` places along the dial, stopping at either end.
    func moved(by steps: Int) -> PictureMode {
        let modes = Self.allCases
        let index = (modes.firstIndex(of: self) ?? 0) + steps
        return modes[min(max(index, 0), modes.count - 1)]
    }
}

/// A monitor preset: one of the plan's display models (section 7).
enum Monitor: CaseIterable, Identifiable {
    case tv
    case commodoreMonitor
    case sharp
    case blackAndWhite
    case amber
    case green

    var id: Self { self }

    var name: String {
        switch self {
        case .tv: "TV"
        case .commodoreMonitor: "MONITOR"
        case .sharp: "SHARP"
        case .blackAndWhite: "B&W"
        case .amber: "AMBER"
        case .green: "GREEN"
        }
    }

    /// A shorter name where space is tight, as on the landscape keys.
    var shortName: String { self == .commodoreMonitor ? "MON" : name }

    var summary: String {
        switch self {
        case .tv: "PAL TV: colours blur and blend"
        case .commodoreMonitor: "Commodore monitor: sharper brightness"
        case .sharp: "No blending or CRT, as in an emulator"
        case .blackAndWhite: "Black-and-white TV"
        case .amber: "Amber monitor"
        case .green: "Green monitor"
        }
    }

    /// Whether the monitor is a cathode-ray tube, which the CRT layer shows.
    /// Sharp stands for a flat screen.
    var hasCRT: Bool { self != .sharp }

    /// Whether the monitor's phosphor glows on after the beam has passed, so
    /// that whatever moves in the viewfinder leaves a fading trail.
    var hasAfterglow: Bool { self == .amber || self == .green }

    /// How the monitor shows a picture, and what the converter optimises for.
    var display: DisplayModel {
        switch self {
        case .tv: .tv
        case .commodoreMonitor: .commodoreMonitor
        case .sharp: .sharp
        case .blackAndWhite: .blackAndWhite
        case .amber: .amber
        case .green: .green
        }
    }
}

/// The state of the camera screen (docs/UX.md, sections 3 to 5). The camera
/// itself is `LiveCamera`.
@Observable
final class CameraModel {
    enum Stage {
        /// The TV shows what the camera sees.
        case live
        /// The TV holds the finished picture after a shot.
        case review
    }

    /// A short message shown on the TV for a moment.
    struct Message: Equatable {
        let id = UUID()
        var title: String
        var detail: String?
    }

    /// Where the camera was asked to focus, shown on the TV for a moment.
    struct FocusMark: Equatable {
        let id = UUID()
        /// Across and down the picture, from 0 to 1.
        var point: CGPoint
    }

    private(set) var stage = Stage.live
    private(set) var mode = PictureMode.multicolour
    /// The mode the review shows. The mode strip changes it.
    var reviewMode = PictureMode.multicolour
    private(set) var monitor = Monitor.tv
    /// The zoom as the buttons show it: 1 for the main camera.
    private(set) var zoom = 1.0
    /// How much brighter or darker than the camera's own exposure, in stops.
    private(set) var exposureBias: Float = 0
    private(set) var focus: FocusMark?
    private(set) var flashOn = false
    /// Whether the CRT switch is on. Sharp shows no CRT layer either way.
    private(set) var crtOn = true
    private(set) var frontCamera = false
    /// The mode of the last picture taken, or nil before the first shot.
    private(set) var lastShot: PictureMode?
    /// Counts the shots, so each one can give haptic feedback.
    private(set) var shotCount = 0
    /// When the finished picture started filling in, or nil once it has.
    private(set) var fillStart: Date?
    /// Whether the picture is on its way to a C64.
    private(set) var sending = false
    private(set) var message: Message?

    func select(_ newMode: PictureMode) {
        guard newMode != mode else { return }
        mode = newMode
        show(newMode.name, newMode.summary)
    }

    /// Moves along the mode dial, as a swipe on the TV does.
    func step(by steps: Int) {
        select(mode.moved(by: steps))
    }

    func select(_ newMonitor: Monitor) {
        guard newMonitor != monitor else { return }
        monitor = newMonitor
        show(newMonitor.name, newMonitor.summary)
    }

    /// Zooms to a button's value.
    func select(zoom newZoom: Double) {
        zoom = newZoom
        show("\(ZoomButtons.name(newZoom)) ZOOM")
    }

    /// Zooms as a pinch does, without a message.
    func pinch(to newZoom: Double) {
        zoom = newZoom
    }

    func setExposureBias(_ bias: Float) {
        guard bias != exposureBias else { return }
        exposureBias = bias
        show(String(format: "EXPOSURE %+.1f", bias))
    }

    /// Marks where the camera focuses, for a moment. Focusing also sets the
    /// exposure back to the camera's own.
    func showFocus(at point: CGPoint) {
        let mark = FocusMark(point: point)
        focus = mark
        exposureBias = 0
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            if self.focus == mark {
                self.focus = nil
            }
        }
    }

    func toggleFlash() {
        flashOn.toggle()
        show(flashOn ? "FLASH ON" : "FLASH OFF")
    }

    /// Whether the TV shows the CRT layer: the switch is on, and the monitor
    /// is a tube.
    var crtShown: Bool { crtOn && monitor.hasCRT }

    func toggleCRT() {
        guard monitor.hasCRT else {
            show("NO CRT ON SHARP", "Sharp is a flat screen")
            return
        }
        crtOn.toggle()
        show(crtOn ? "CRT EFFECT ON" : "CRT EFFECT OFF")
    }

    /// Turns the camera round, back to 1× and the camera's own exposure.
    func flipCamera() {
        frontCamera.toggle()
        zoom = 1
        exposureBias = 0
        show(frontCamera ? "FRONT CAMERA" : "BACK CAMERA")
    }

    /// Takes a picture: the TV holds a cleared screen for review until the
    /// picture is made.
    func capture() {
        lastShot = mode
        reviewMode = mode
        shotCount += 1
        stage = .review
        fillStart = nil
    }

    /// The shot's picture is made. Unless `animated` is false, it fills in
    /// cell by cell, the way a C64 stores it.
    func pictureReady(animated: Bool) {
        guard stage == .review, animated else { return }
        startFill()
    }

    /// The camera took no photo: back to it, with the last picture as it was.
    func captureFailed(lastShot previous: PictureMode?) {
        lastShot = previous
        backToLive()
        show("NO PICTURE", "The camera took none")
    }

    /// Opens the last picture for review again, until the next shot.
    func showLastShot() {
        guard let lastShot else {
            show("NO PICTURES YET")
            return
        }
        reviewMode = lastShot
        fillStart = nil
        stage = .review
    }

    func backToLive() {
        stage = .live
        fillStart = nil
    }

    /// Discards the shot, as the 2013 app did: the last picture is gone too.
    func deleteShot() {
        lastShot = nil
        backToLive()
        show("PICTURE DELETED")
    }

    /// The picture as on TV was saved to Photos, or `failure` says why not.
    /// A shot that Settings saves by itself says so only if it fails.
    func saved(_ failure: PhotoLibrary.Failure?, everyShot: Bool = false) {
        if let failure {
            show("NOT SAVED", failure.detail)
        } else if !everyShot {
            show("SAVED TO PHOTOS")
        }
    }

    /// Send to C64 has begun.
    func sendingStarted() {
        sending = true
        show("SENDING TO C64")
    }

    /// Send to C64 has ended: the C64 shows the picture, or `failure` says
    /// why not.
    func sendingEnded(_ failure: Ultimate.Failure?) {
        sending = false
        if let failure {
            show(failure.title, failure.detail)
        } else {
            show("SENT TO C64")
        }
    }

    func show(_ title: String, _ detail: String? = nil) {
        let message = Message(title: title, detail: detail)
        self.message = message
        Task {
            try? await Task.sleep(for: .seconds(1.8))
            if self.message == message {
                self.message = nil
            }
        }
    }

    private func startFill() {
        let start = Date.now
        fillStart = start
        Task {
            try? await Task.sleep(for: .seconds(TVView.fillDuration + 0.1))
            if self.fillStart == start {
                self.fillStart = nil
            }
        }
    }
}
