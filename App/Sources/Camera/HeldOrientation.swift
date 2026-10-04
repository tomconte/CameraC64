import C64Core
import CoreMotion
import Observation
import SwiftUI
import UIKit

/// How the phone is held.
///
/// The app's screens stay in portrait, as Apple's Camera app does. When the
/// phone is turned, the TV and the labels turn so they stay upright, and the
/// controls stay where they are (docs/UX.md, section 3).
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

    /// How the camera's frames are seen with the phone held this way, so the
    /// picture is upright (docs/UX.md, section 1). The camera sends them
    /// upright for a phone held in portrait. A front camera's are then
    /// mirrored, as a mirror shows the scene: mirroring them before they are
    /// turned would show it upside down with the phone held sideways.
    func frameOrientation(mirrored: Bool) -> ImageOrientation {
        let upright: ImageOrientation =
            switch self {
            case .portrait: .up
            // The top of the phone points left, so the scene's top is along
            // the frame's right side.
            case .landscapeLeft: .left
            case .landscapeRight: .right
            }
        return mirrored ? upright.mirrored : upright
    }

    /// The video rotation angle that stores photos upright as the phone is
    /// held. AVFoundation measures it from the phone held sideways with its
    /// top to the left, for either camera.
    var photoRotationAngle: CGFloat {
        switch self {
        case .portrait: 90
        case .landscapeLeft: 0
        case .landscapeRight: 180
        }
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
