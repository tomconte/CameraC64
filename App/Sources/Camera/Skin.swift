import SwiftUI

/// An element of the camera screen's skin: one of the images that
/// `design/export_skin.py` puts into the asset catalog from `design/svg`
/// (docs/UX.md, section 7). Each image holds its element on a canvas with room
/// round it for its shadow and light; `face` is where the element itself is on
/// that canvas, in points. The words on it, and the lamps on some keys, are
/// the app's to draw.
nonisolated struct SkinElement: Equatable, Sendable {
    /// How an element's images tell its states apart.
    enum States: Hashable, Sendable {
        /// One image.
        case single
        /// A key, up and pressed: its name, then "-up" or "-down".
        case upAndDown
        /// A switch or a lamp: its name, then "-on" or "-off".
        case onAndOff
    }

    var name: String
    var states: States
    var canvas: CGSize
    var face: CGRect

    /// The image for a state: pressed or on, or not.
    func image(_ state: Bool = false) -> String {
        switch states {
        case .single: name
        case .upAndDown: "\(name)-\(state ? "down" : "up")"
        case .onAndOff: "\(name)-\(state ? "on" : "off")"
        }
    }

    /// Every image the element has.
    var images: [String] { states == .single ? [image()] : [image(false), image(true)] }

    /// How high the face is when it is drawn `width` points wide.
    func height(forWidth width: CGFloat) -> CGFloat { face.height * width / face.width }
}

/// The skin's elements, with their sizes as `design/README.md` lists them.
enum Skin {
    static let captureKey = element("capture", .upAndDown, canvas: (135, 72), face: (10.5, 12, 118.8, 38.5))
    static let monitorKey = element("monitor-key", .upAndDown, canvas: (36, 36), face: (3, 3, 30, 30))
    /// A monitor key in landscape, with its lamp and name on it.
    static let wideMonitorKey = element("monitor-key-wide", .upAndDown, canvas: (62, 54), face: (4, 4, 54, 44))
    static let settingsKey = element("settings-key", .upAndDown, canvas: (38, 40), face: (4, 4, 30, 30))
    static let flipKey = element("flip-key", .upAndDown, canvas: (64, 66), face: (4, 4, 56, 56))
    static let zoomButton = element("zoom-button", .upAndDown, canvas: (40, 40), face: (3, 3, 34, 34))
    /// The switch for flash and the CRT layer, as on the 2013 app.
    static let toggle = element("toggle", .onAndOff, canvas: (50, 22), face: (2, 2, 46, 18))
    static let lamp = element("led", .onAndOff, canvas: (22, 22), face: (6, 6, 10, 10))
    static let badge = element("badge", .single, canvas: (128, 20), face: (2.5, 1.5, 122, 17))
    static let lastPictureFrame = element("last-picture-frame", .single, canvas: (64, 64), face: (4, 4, 56, 56))
    /// Where the last picture goes in its frame, on the frame's face, and the
    /// radius of its corners.
    static let lastPictureWindow = CGRect(x: 3, y: 3, width: 50, height: 50)
    static let lastPictureWindowRadius: CGFloat = 6

    /// The key for one of the review's actions.
    static func actionKey(_ action: ReviewAction) -> SkinElement {
        element("action-\(action.skinName)", .upAndDown, canvas: (60, 52), face: (4, 4, 52, 42))
    }

    /// Every element, for the tests.
    static var all: [SkinElement] {
        [
            captureKey, monitorKey, wideMonitorKey, settingsKey, flipKey, zoomButton, toggle, lamp, badge,
            lastPictureFrame,
        ] + ReviewAction.all(canSend: true).map { actionKey($0) }
    }

    private static func element(
        _ name: String, _ states: SkinElement.States, canvas: (CGFloat, CGFloat),
        face: (CGFloat, CGFloat, CGFloat, CGFloat)
    ) -> SkinElement {
        SkinElement(
            name: name, states: states, canvas: CGSize(width: canvas.0, height: canvas.1),
            face: CGRect(x: face.0, y: face.1, width: face.2, height: face.3))
    }
}

extension ReviewAction {
    /// The action's name in its key's images.
    var skinName: String {
        switch self {
        case .share: "share"
        case .save: "save"
        case .send: "send"
        case .delete: "delete"
        }
    }
}

/// A skin element, its face filling the view's frame, `width` points wide. Its
/// canvas, with the shadow and light round the face, spills beyond the frame.
struct SkinImage: View {
    var element: SkinElement
    /// Pressed, or on, for an element with two states.
    var state = false
    var width: CGFloat

    var body: some View {
        let scale = width / element.face.width
        Image(decorative: element.image(state))
            .resizable()
            .frame(width: element.canvas.width * scale, height: element.canvas.height * scale)
            .offset(
                x: (element.canvas.width / 2 - element.face.midX) * scale,
                y: (element.canvas.height / 2 - element.face.midY) * scale
            )
            .frame(width: width, height: element.height(forWidth: width))
            .allowsHitTesting(false)
    }
}
