import SwiftUI
import Testing
import UIKit

@testable import CameraC64

/// The test bundle, which holds an image of the SVG features the skin uses.
private final class ScreenshotBundle {}

/// Pictures of the camera screen's controls on an iPhone 17, for people to
/// look at. They are drawn only when the tests run with `SCREENSHOTS` set to a
/// folder, as CI does, which keeps them with the run.
@MainActor
struct ScreenshotTests {
    /// The iPhone 17's screen upright, inside its safe area, in points.
    private static let screen = CGSize(width: 402, height: 874 - 62 - 34)

    @Test(.enabled(if: ProcessInfo.processInfo.environment["SCREENSHOTS"] != nil))
    func drawTheScreens() throws {
        let folder = try #require(ProcessInfo.processInfo.environment["SCREENSHOTS"])
        let url = URL(fileURLWithPath: folder, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let pictures: [(name: String, view: AnyView)] = [
            ("portrait-live", AnyView(portrait(.live))),
            ("portrait-review", AnyView(portrait(.review))),
            ("landscape-live", AnyView(landscape(.live))),
            ("landscape-review", AnyView(landscape(.review))),
            ("skin", AnyView(skinSheet)),
            ("svg-features", AnyView(svgFeatures)),
        ]
        for picture in pictures {
            let renderer = ImageRenderer(content: picture.view)
            renderer.scale = 2
            let image = try #require(renderer.uiImage, "\(picture.name) did not draw")
            try #require(image.pngData()).write(to: url.appendingPathComponent("\(picture.name).png"))
        }
    }

    /// The camera screen's state in the camera, or with a shot in review.
    private func model(_ stage: CameraModel.Stage) -> CameraModel {
        let model = CameraModel()
        if stage == .review {
            model.capture()
        }
        return model
    }

    /// The screen with the phone upright, a dark TV standing in for the
    /// picture, as `CameraScreen` lays it out.
    private func portrait(_ stage: CameraModel.Stage) -> some View {
        let model = model(stage)
        return VStack(spacing: 0) {
            TopBar(model: model, onFlash: {}, onCRT: {}, onPower: {}, onSettings: {})
                .background(TitleBarBackground())
            Look.bezel
                .frame(height: Self.screen.width / TVGeometry.aspectRatio)
            Group {
                if stage == .live {
                    livePanel(model)
                } else {
                    reviewPanel
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .vent()
            .background(CaseBackground())
        }
        .frame(width: Self.screen.width, height: Self.screen.height)
    }

    /// The camera's controls below the TV, as `CameraScreen` lays them out.
    private func livePanel(_ model: CameraModel) -> some View {
        VStack(spacing: 12) {
            ZoomPills(buttons: ZoomButtons(presets: [0.5, 1, 2], zoom: 1)) { _ in }
            ModeDial(selection: model.mode) { _ in }
            MonitorBank(selection: model.monitor) { _ in }
                .ventClearing(cornerRadius: 8, ceiling: true)
                .padding(.top, 6)
            Spacer(minLength: 8)
            ShutterRow(
                stage: .live, lastShot: nil, thumbnail: nil, showsCaption: true, onLastPicture: {}, onKey: {},
                onFlip: {})
        }
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    /// The review's controls below the TV.
    private var reviewPanel: some View {
        ReviewPanel(
            mode: .multicolour, monitor: .tv, thumbnails: [:], onSelectMode: { _ in }, onSelectMonitor: { _ in },
            layout: nil,
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

    /// The screen with the phone held sideways, as the user sees it: the TV
    /// between its two columns.
    private func landscape(_ stage: CameraModel.Stage) -> some View {
        let model = model(stage)
        let column = ScreenMetrics.landscapeColumnWidth
        return HStack(spacing: 0) {
            ControlsColumn(
                model: model, thumbnails: [:], onFlash: {}, onCRT: {}, onPower: {}, onSettings: {},
                onSelectMode: { _ in }, onSelectMonitor: { _ in }, onSelectReviewMode: { _ in }
            )
            .frame(width: column)
            .vent()
            // The TV, as high as the screen is wide.
            Look.bezel
                .frame(width: Self.screen.width * TVGeometry.aspectRatio)
            ShutterColumn(
                stage: stage, lastShot: .multicolour, thumbnail: nil, onLastPicture: {}, onKey: {}, onFlip: {},
                actions: {
                    ActionGrid(actions: ReviewAction.all(canSend: true), files: [], sending: false, onAction: { _ in })
                }
            )
            .frame(width: column)
            .vent()
        }
        .frame(height: Self.screen.width)
        .background(Look.caseColor)
    }

    /// The SVG features the skin uses, as `SkinTests` checks them.
    private var svgFeatures: some View {
        Image("svg-features", bundle: Bundle(for: ScreenshotBundle.self))
            .resizable()
            .frame(width: 100, height: 60)
    }

    /// Every element of the skin, in each of its states.
    private var skinSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(Skin.all, id: \.name) { element in
                HStack(spacing: 24) {
                    ForEach(element.images, id: \.self) { name in
                        SkinImage(
                            element: element, state: name.hasSuffix("-down") || name.hasSuffix("-on"),
                            width: element.face.width)
                    }
                }
            }
        }
        .padding(24)
        .background(Look.caseColor)
    }
}
