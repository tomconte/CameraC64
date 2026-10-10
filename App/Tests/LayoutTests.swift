import SwiftUI
import Testing

@testable import CameraC64

/// The camera screen's controls on every iPhone iOS 26 runs on, measured as
/// SwiftUI lays them out.
@MainActor
struct LayoutTests {
    /// An iPhone screen held upright, in points, and the safe area the app
    /// keeps clear above and below it, with the status bar hidden.
    private struct Phone {
        var name: String
        var width: CGFloat
        var height: CGFloat
        var top: CGFloat
        var bottom: CGFloat
    }

    /// One iPhone of each screen size, with the largest safe area among the
    /// models of that size. The iPhone SE counts its status bar, in case it
    /// shows.
    private static let phones = [
        Phone(name: "iPhone SE", width: 375, height: 667, top: 20, bottom: 0),
        Phone(name: "iPhone 11 Pro, 12 mini, 13 mini", width: 375, height: 812, top: 50, bottom: 34),
        Phone(name: "iPhone 12, 13, 14, 16e", width: 390, height: 844, top: 47, bottom: 34),
        Phone(name: "iPhone 14 Pro, 15, 16", width: 393, height: 852, top: 59, bottom: 34),
        Phone(name: "iPhone 16 Pro, 17, 17 Pro", width: 402, height: 874, top: 62, bottom: 34),
        Phone(name: "iPhone 11, 11 Pro Max", width: 414, height: 896, top: 48, bottom: 34),
        Phone(name: "iPhone Air", width: 420, height: 912, top: 68, bottom: 34),
        Phone(name: "iPhone 12 and 13 Pro Max, 14 Plus", width: 428, height: 926, top: 47, bottom: 34),
        Phone(name: "iPhone 14 and 15 Pro Max, 15 and 16 Plus", width: 430, height: 932, top: 59, bottom: 34),
        Phone(name: "iPhone 16 and 17 Pro Max", width: 440, height: 956, top: 62, bottom: 34),
    ]

    /// The height a phone leaves below the TV for the controls.
    private func panelHeight(on phone: Phone) -> CGFloat {
        phone.height - phone.top - phone.bottom - ScreenMetrics.topBarHeight - phone.width / TVGeometry.aspectRatio
    }

    /// The size SwiftUI gives a view offered a width and a height.
    private func size(of view: some View, width: CGFloat, height: CGFloat) -> CGSize {
        UIHostingController(rootView: view).sizeThatFits(in: CGSize(width: width, height: height))
    }

    /// The review's controls with the phone upright, in a layout, or as the
    /// review picks it.
    private func reviewPanel(_ layout: ReviewLayout?) -> some View {
        ReviewPanel(
            mode: .multicolour, monitor: .tv, thumbnails: [:], onSelectMode: { _ in }, onSelectMonitor: { _ in },
            layout: layout,
            actions: {
                ActionRow(
                    actions: ReviewAction.all(canSend: true), files: [], sending: false, showsCaptions: $0,
                    onAction: { _ in })
            },
            shutter: {
                ShutterRow(
                    stage: .review, lastShot: .multicolour, thumbnail: nil, showsCaption: $0, onLastPicture: {},
                    onKey: {}, onFlip: {})
            })
    }

    /// The size a view takes with all the room it wants.
    private func idealSize(of view: some View) -> CGSize {
        size(of: view.fixedSize(), width: 2000, height: 2000)
    }

    /// The camera screen's state in the camera, or with a shot in review.
    private func model(_ stage: CameraModel.Stage) -> CameraModel {
        let model = CameraModel()
        if stage == .review {
            model.capture()
        }
        return model
    }

    /// The column on the left of the TV in landscape.
    private func controlsColumn(_ stage: CameraModel.Stage) -> some View {
        ControlsColumn(
            model: model(stage), thumbnails: [:], onFlash: {}, onCRT: {}, onPower: {}, onSettings: {},
            onSelectMode: { _ in }, onSelectMonitor: { _ in }, onSelectReviewMode: { _ in })
    }

    /// The column on the right of the TV in landscape.
    private func shutterColumn(_ stage: CameraModel.Stage) -> some View {
        ShutterColumn(
            stage: stage, lastShot: .multicolour, thumbnail: nil, onLastPicture: {}, onKey: {}, onFlip: {},
            actions: {
                ActionGrid(actions: ReviewAction.all(canSend: true), files: [], sending: false, onAction: { _ in })
            })
    }

    /// With the phone upright, the review's controls, the monitor keys
    /// included, fit below the TV on every iPhone, and with their captions on
    /// all but the iPhone SE. (Sizes may round up to a pixel.)
    @Test func reviewFitsEveryIPhone() {
        for phone in Self.phones {
            let room = panelHeight(on: phone)
            let panel = size(of: reviewPanel(nil), width: phone.width, height: room)
            #expect(panel.width <= phone.width, "\(phone.name): \(panel.width) points wide")
            #expect(panel.height <= room + 0.5, "\(phone.name): \(panel.height) points in \(room)")
            if phone.height > 667 {
                let roomy = size(of: reviewPanel(.roomy), width: phone.width, height: room)
                #expect(roomy.height <= room + 0.5, "\(phone.name), roomy: \(roomy.height) points in \(room)")
            }
        }
    }

    /// In landscape, the TV sits between two columns of controls, which fit
    /// beside it on every iPhone, in the camera and in a review, and share
    /// what it leaves of the screen.
    @Test func landscapeColumnsFitEveryIPhone() {
        for phone in Self.phones {
            // The screen inside its safe area, which stays in portrait.
            let screen = CGSize(width: phone.width, height: phone.height - phone.top - phone.bottom)
            let tv = TVGeometry.size(fitting: ScreenMetrics.tvArea(in: screen, turned: true), turned: true)
            // A column as the user sees it: as high as the screen is wide.
            let column = CGSize(width: ScreenMetrics.columnWidth(in: screen, besideTV: tv), height: screen.width)
            #expect(column.width >= ScreenMetrics.landscapeColumnWidth, "\(phone.name): \(column.width) points")
            #expect(abs(2 * column.width + tv.width - screen.height) < 0.001, "\(phone.name)")
            // A TV as high as the screen is wide comes back from its 4:3 shape
            // a hair over.
            #expect(tv.height <= screen.width + 0.001, "\(phone.name): the TV is \(tv.height) points high")
            for stage in [CameraModel.Stage.live, .review] {
                let controls = idealSize(of: controlsColumn(stage))
                #expect(
                    controls.width <= column.width && controls.height <= column.height,
                    "\(phone.name), \(stage): the controls take \(controls) of \(column)")
                let shutter = idealSize(of: shutterColumn(stage))
                #expect(
                    shutter.width <= column.width && shutter.height <= column.height,
                    "\(phone.name), \(stage): the big key's column takes \(shutter) of \(column)")
            }
        }
    }

    /// In landscape, every monitor key's label, its lamp and the monitor's
    /// short name, fits on the key's face, 4 points clear of either side.
    @Test func landscapeMonitorLabelsFitTheirKeys() {
        let face = CompactMonitorBank.keySize.width
        for monitor in Monitor.allCases {
            let label = size(of: CompactMonitorBank.label(monitor, isSelected: true), width: 500, height: 500)
            #expect(label.width + 8 <= face, "\(monitor.name): \(label.width) points on \(face)")
        }
    }
}
