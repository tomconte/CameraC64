import Foundation
import Observation
import SwiftUI

/// A graphics mode, as the mode dial and the mode strip offer it.
///
/// Placeholder: each mode shows a bundled sample picture until C64Core converts
/// and renders pictures (plan, milestones 1 and 2).
enum PictureMode: CaseIterable, Identifiable {
    case hires
    case multicolour
    case petscii
    case fli
    case afli

    var id: Self { self }

    var name: String {
        switch self {
        case .hires: "HIRES"
        case .multicolour: "MULTICOLOUR"
        case .petscii: "PETSCII"
        case .fli: "FLI"
        case .afli: "AFLI"
        }
    }

    /// A shorter name where space is tight, as on the landscape dial.
    var shortName: String { self == .multicolour ? "MULTI" : name }

    /// One line on what the mode does.
    var summary: String {
        switch self {
        case .hires: "320 × 200, 2 colours in each 8 × 8 cell"
        case .multicolour: "160 × 200 wide pixels, 4 colours in each 4 × 8 cell"
        case .petscii: "40 × 25 characters, one colour each"
        case .fli: "Multicolour with new colours on every line"
        case .afli: "Hires with new colours on every line"
        }
    }

    /// Part of the paid "Advanced modes" unlock.
    var isAdvanced: Bool { self == .fli || self == .afli }

    /// The sample picture as the finished conversion shows it.
    var finishedSample: String {
        switch self {
        case .hires: "SampleHires"
        case .multicolour: "SampleMulticolour"
        case .petscii: "SamplePetscii"
        case .fli: "SampleFLI"
        case .afli: "SampleAFLI"
        }
    }

    /// The sample picture as the viewfinder shows it: for multicolour, with the
    /// viewfinder's ordered dithering instead of the finished error diffusion.
    var liveSample: String { self == .multicolour ? "SampleMulticolourLive" : finishedSample }

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
        case .sharp: "No blending, as in an emulator"
        case .blackAndWhite: "Black-and-white TV"
        case .amber: "Amber monitor"
        case .green: "Green monitor"
        }
    }

    var isMono: Bool { self == .blackAndWhite || self == .amber || self == .green }

    /// Placeholder tint for the mono monitors, until C64Core's display models
    /// draw each monitor properly.
    var phosphor: Color {
        switch self {
        case .amber: Color(hex: 0xFFB43C)
        case .green: Color(hex: 0x5CFF7A)
        default: .white
        }
    }
}

/// The zoom buttons.
enum Zoom: CaseIterable, Identifiable {
    case half
    case one
    case two

    var id: Self { self }

    /// The label on the button.
    var label: String {
        switch self {
        case .half: ".5"
        case .one: "1×"
        case .two: "2"
        }
    }

    var name: String {
        switch self {
        case .half: "0.5×"
        case .one: "1×"
        case .two: "2×"
        }
    }
}

/// The state of the placeholder camera screen (docs/UX.md, sections 3 to 5).
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

    private(set) var stage = Stage.live
    private(set) var mode = PictureMode.multicolour
    /// The mode the review shows. The mode strip changes it.
    var reviewMode = PictureMode.multicolour
    private(set) var monitor = Monitor.tv
    private(set) var zoom = Zoom.one
    private(set) var flashOn = false
    private(set) var crtOn = true
    private(set) var frontCamera = false
    /// The mode of the last picture taken, or nil before the first shot.
    private(set) var lastShot: PictureMode?
    /// Counts the shots, so each one can give haptic feedback.
    private(set) var shotCount = 0
    /// When the finished picture started filling in, or nil once it has.
    private(set) var fillStart: Date?
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

    func select(_ newZoom: Zoom) {
        zoom = newZoom
        show("\(newZoom.name) ZOOM", "Comes with the camera")
    }

    func toggleFlash() {
        flashOn.toggle()
        show(flashOn ? "FLASH ON" : "FLASH OFF")
    }

    func toggleCRT() {
        crtOn.toggle()
        show(crtOn ? "CRT EFFECT ON" : "CRT EFFECT OFF")
    }

    func flipCamera() {
        frontCamera.toggle()
        show(frontCamera ? "FRONT CAMERA" : "BACK CAMERA", "Comes with the camera")
    }

    /// Takes a picture and holds it for review. Unless `animated` is false, the
    /// finished picture fills in cell by cell, the way a C64 stores it.
    func capture(animated: Bool) {
        lastShot = mode
        reviewMode = mode
        shotCount += 1
        stage = .review
        if animated {
            startFill()
        } else {
            fillStart = nil
        }
    }

    /// Opens the last picture for review, as the gallery will.
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

    func deleteShot() {
        lastShot = nil
        backToLive()
        show("PICTURE DELETED")
    }

    func notBuiltYet(_ feature: String) {
        show(feature, "Not built yet")
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
