import C64Core
import Foundation
import SwiftUI

/// The TV's tube as it switches off and on (docs/UX.md, section 3), as in the
/// 2013 app: switching off, the picture closes into a bright line, which
/// shrinks to a dot, which fades; switching on, the tube warms up the other
/// way, and its line opens into the picture once there is one to show.
///
/// How far the tube is on runs from 0, dark, through 1, a dot, and 2, a line,
/// to 3, the whole picture. Each step takes its own time, either way: the dot
/// fades slowly, as a tube's phosphor does. A tube that turns back halfway
/// goes back from where it is. Without the CRT layer, or with Reduce Motion
/// on, it switches at once.
nonisolated struct Tube: Equatable {
    /// Where a tube stands, or is going.
    nonisolated enum Level: Double {
        /// Dark: only the glass shows.
        case off = 0
        /// A bright dot in the middle.
        case dot
        /// A bright line across.
        case line
        /// The whole picture.
        case on
    }

    /// The seconds each step takes, switching off and warming up: the first
    /// is between dark and the dot, the last between the line and the whole
    /// picture.
    static let fallingSteps = [0.8, 0.22, 0.16]
    static let risingSteps = [0.06, 0.28, 0.45]

    /// How far on the tube was when it began moving, and when.
    private(set) var from: Double
    private(set) var start: Date
    /// Where it is going.
    private(set) var target: Level
    /// Whether it moves as a tube does, rather than at once.
    private(set) var animated: Bool

    /// A tube standing at a level.
    init(_ level: Level, animated: Bool = true) {
        from = level.rawValue
        start = .distantPast
        target = level
        self.animated = animated
    }

    /// Whether the tube stands where it was going. A moving tube keeps
    /// moving until `settled` replaces it, once it gets there.
    var isSettled: Bool { from == target.rawValue }

    /// The tube standing where it was going.
    var settled: Tube { Tube(target, animated: animated) }

    /// Sets the tube moving towards a level, from where it is at a time: as a
    /// tube does, or at once.
    mutating func move(to level: Level, animated: Bool, at date: Date = .now) {
        from = animated ? self.level(at: date) : level.rawValue
        start = date
        target = level
        self.animated = animated
    }

    /// How far on the tube is at a time, from 0, dark, to 3, the whole
    /// picture.
    func level(at date: Date) -> Double {
        let goal = target.rawValue
        var (level, time) = (from, date.timeIntervalSince(start))
        while level != goal && time > 0 {
            let step = Self.step(from: level, towards: goal)
            let needed = abs(step.end - level) * step.seconds
            if time < needed {
                return level + (step.end > level ? time : -time) / step.seconds
            }
            (level, time) = (step.end, time - needed)
        }
        return level
    }

    /// When the tube gets where it is going.
    var end: Date {
        let goal = target.rawValue
        var (level, seconds) = (from, 0.0)
        while level != goal {
            let step = Self.step(from: level, towards: goal)
            seconds += abs(step.end - level) * step.seconds
            level = step.end
        }
        return start + seconds
    }

    /// What the tube draws at a time. Switching at once, it shows the whole
    /// picture or nothing.
    func raster(at date: Date) -> Raster {
        let reached = level(at: date)
        guard animated else {
            return reached == Level.on.rawValue ? .on : .off
        }
        return Raster(level: reached)
    }

    /// The step a level is on, going towards another: the seconds a whole
    /// step takes, and the level where this one ends.
    private static func step(from level: Double, towards goal: Double) -> (seconds: Double, end: Double) {
        if goal > level {
            let step = Int(level.rounded(.down))
            return (risingSteps[step], min(Double(step + 1), goal))
        }
        let step = Int(level.rounded(.up)) - 1
        return (fallingSteps[step], max(Double(step), goal))
    }
}

/// What the tube draws: how much of the screen its raster covers, and how
/// bright its beam is.
nonisolated struct Raster: Equatable {
    /// How tall the raster is: 1 for the whole picture, 0 for a line.
    var height: Double
    /// How wide: 1 for the whole picture or a line, 0 for a dot.
    var width: Double
    /// How bright the beam is: 1, falling to 0 as the dot fades.
    var light: Double

    static let on = Raster(height: 1, width: 1, light: 1)
    static let off = Raster(height: 0, width: 0, light: 0)
}

nonisolated extension Raster {
    /// The raster at a level (`Tube.level(at:)`). Warming up, the dot
    /// stretches into a line, and the line opens into the picture, each fast
    /// at first, then slower. Switching off plays it backwards: the picture
    /// and the line close faster and faster, and the dot fades fast, then
    /// slowly, as phosphor does.
    init(level: Double) {
        func opened(_ step: Double) -> Double {
            let shut = 1 - min(max(step, 0), 1)
            return 1 - shut * shut
        }
        light = pow(min(max(level, 0), 1), 1.5)
        width = opened(level - 1)
        height = opened(level - 2)
    }

    /// How many times brighter the picture is, squeezed into the raster: the
    /// beam's light falls on less of the glass.
    var gain: Double { 1 / max(width * height, 1e-4) }

    /// How bright the line or the dot is: it takes over from the picture as
    /// the picture closes into a line, over its last 5%.
    var beam: Double {
        let closed = 1 - min(height / 0.05, 1)
        return light * closed * closed
    }

    /// How much of the picture shows: it gives way to the line.
    var pictureOpacity: Double { light - beam }
}

/// The tube's face (`tubeFace` in `CRT.metal`): its glass, as dark as a
/// switched-off tube's in a lit room, tinted by its phosphor, and the beam's
/// line or dot as the raster closes, in the phosphor's colour. Without the
/// CRT layer, the TV is a flat screen, black when it is off.
struct TubeFace: View {
    /// How thick the beam's line is, in points. As it shrinks, it rounds into
    /// a dot twice as thick, which shrinks a little as it fades.
    static let lineThickness = 3.0
    static let dotThickness = 6.0

    var raster: Raster
    /// The colour of the monitor's phosphor at full brightness.
    var phosphor: RGB
    /// The CRT layer's look, which gives the tube its shape, or nil without it.
    var crt: CRT?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Group {
            if let crt {
                Rectangle()
                    .fill(Self.shader(raster, phosphor: phosphor, crt: crt, scale: displayScale))
            } else {
                Color.black
            }
        }
        .accessibilityHidden(true)
    }

    /// The values `tubeFace` reads, in the order of its `TubeSettings`, for a
    /// face drawn with `scale` device pixels per point.
    static func settings(_ raster: Raster, phosphor: RGB, crt: CRT, scale: Double) -> [Float] {
        let dot = (1 - raster.width) * (1 - raster.width)
        let thickness = (lineThickness + (dotThickness - lineThickness) * dot) * (0.6 + 0.4 * raster.light)
        return [
            Double(phosphor.r) / 255, Double(phosphor.g) / 255, Double(phosphor.b) / 255,
            crt.corner, crt.curvature, scale, raster.width, thickness, raster.beam, 1 - raster.width,
        ].map(Float.init)
    }

    /// The shader that draws the face, `scale` device pixels per point.
    static func shader(_ raster: Raster, phosphor: RGB, crt: CRT, scale: CGFloat) -> Shader {
        var shader = ShaderLibrary.tubeFace(
            .boundingRect, .floatArray(settings(raster, phosphor: phosphor, crt: crt, scale: Double(scale))))
        // The glass is a smooth slope, which dithering keeps from banding.
        shader.dithersColor = true
        return shader
    }

    /// The colour effect that brightens the picture `gain` times as the
    /// raster closes, its phosphor saturating towards white (`tubeGain`).
    static func gain(_ gain: Double) -> Shader {
        ShaderLibrary.tubeGain(.float(gain))
    }
}
