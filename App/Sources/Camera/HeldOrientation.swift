import C64Core
import CoreMotion
import Observation
import SwiftUI
import UIKit

/// How the phone is held.
///
/// The app's screens stay in portrait, as Apple's Camera app does. When the
/// phone is turned, the TV turns so it stays upright, between two columns of
/// controls that turn with it.
enum HeldOrientation {
    case portrait
    /// Turned anticlockwise: the top of the phone points left.
    case landscapeLeft
    /// Turned clockwise: the top of the phone points right.
    case landscapeRight

    var isLandscape: Bool { self != .portrait }

    /// The turn that keeps content upright on the screen.
    var contentRotation: Angle {
        switch self {
        case .portrait: .zero
        case .landscapeLeft: .degrees(90)
        case .landscapeRight: .degrees(-90)
        }
    }

    /// Reads the orientation from gravity as the accelerometer measures it, in g.
    /// Returns nil when the phone lies flat or is upside down, so the previous
    /// orientation stays.
    init?(gravityX x: Double, y: Double) {
        if x <= -0.75 {
            self = .landscapeLeft
        } else if x >= 0.75 {
            self = .landscapeRight
        } else if y <= -0.75 {
            self = .portrait
        } else {
            return nil
        }
    }

    init?(_ device: UIDeviceOrientation) {
        switch device {
        case .portrait: self = .portrait
        case .landscapeLeft: self = .landscapeLeft
        case .landscapeRight: self = .landscapeRight
        default: return nil
        }
    }

    /// A movement on the screen as the user sees it, with the phone held this way.
    func upright(_ translation: CGSize) -> CGSize {
        switch self {
        case .portrait: translation
        case .landscapeLeft: CGSize(width: translation.height, height: -translation.width)
        case .landscapeRight: CGSize(width: -translation.height, height: translation.width)
        }
    }

    /// How many quarter turns clockwise a camera's pictures need to be upright
    /// with the phone held this way (docs/UX.md, section 1).
    ///
    /// AVFoundation sends both cameras' pictures sideways by default, as it
    /// always has: the back camera's are upright with the top of the phone to
    /// the left, the front camera's with it to the right. The front camera
    /// faces the user, so as the phone turns, its pictures turn the other way
    /// to the back camera's. The iPhone 17's front camera has a square sensor
    /// mounted upright, but AVFoundation turns its frames to match the earlier
    /// front cameras' while their rotation angle is left as it is, so the same
    /// turns hold (WWDC26, session 341).
    func uprightTurns(frontCamera: Bool) -> Int {
        switch self {
        case .portrait: 1
        case .landscapeLeft: frontCamera ? 2 : 0
        case .landscapeRight: frontCamera ? 0 : 2
        }
    }

    /// The turns a camera's frames need to be upright, as a rotation angle in
    /// degrees clockwise.
    func uprightAngle(frontCamera: Bool) -> CGFloat {
        CGFloat(uprightTurns(frontCamera: frontCamera) * 90)
    }

    /// How a camera's frames are seen with the phone held this way: turned
    /// upright, then, for the front camera, mirrored as a mirror shows the
    /// scene.
    func frameOrientation(frontCamera: Bool) -> ImageOrientation {
        let turns: [ImageOrientation] = [.up, .right, .down, .left]
        let upright = turns[uprightTurns(frontCamera: frontCamera)]
        return frontCamera ? upright.mirrored : upright
    }
}

/// Follows how the phone is held, even with rotation lock on: from the
/// accelerometer on a device, and from the device orientation in the Simulator,
/// which has no accelerometer.
@Observable
final class HeldOrientationObserver {
    private(set) var orientation = HeldOrientation.portrait

    private let motion = CMMotionManager()
    @ObservationIgnored private var usesDeviceOrientation = false

    func start() {
        if motion.isAccelerometerAvailable {
            guard !motion.isAccelerometerActive else { return }
            motion.accelerometerUpdateInterval = 0.2
            motion.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
                guard let self, let acceleration = data?.acceleration else { return }
                let x = acceleration.x
                let y = acceleration.y
                MainActor.assumeIsolated {
                    self.update(HeldOrientation(gravityX: x, y: y))
                }
            }
        } else {
            usesDeviceOrientation = true
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            deviceOrientationDidChange()
        }
    }

    /// Reads the device orientation again. Ignored when the accelerometer is in use.
    func deviceOrientationDidChange() {
        guard usesDeviceOrientation else { return }
        update(HeldOrientation(UIDevice.current.orientation))
    }

    private func update(_ reading: HeldOrientation?) {
        guard let reading, reading != orientation else { return }
        orientation = reading
    }
}
