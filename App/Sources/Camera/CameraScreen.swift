import Combine
import SwiftUI
import UIKit

/// Sizes of the camera screen's parts, in points.
enum ScreenMetrics {
    static let topBarHeight: CGFloat = 44
    /// The controls below the TV in landscape. The TV gets the rest of the height.
    static let compactLivePanelHeight: CGFloat = 252
    static let compactReviewPanelHeight: CGFloat = 216

    /// The area the TV gets, in screen coordinates. In portrait it spans the
    /// width; in landscape it takes whatever the compact controls leave.
    static func tvArea(in size: CGSize, turned: Bool, stage: CameraModel.Stage) -> CGSize {
        guard turned else {
            return CGSize(width: size.width, height: size.width / TVGeometry.aspectRatio)
        }
        let panel = stage == .live ? compactLivePanelHeight : compactReviewPanelHeight
        return CGSize(width: size.width, height: max(0, size.height - topBarHeight - panel))
    }
}

/// The camera screen: a TV above a C64 (docs/UX.md, section 3).
///
/// Placeholder: there is no camera yet. The TV shows sample pictures, and a shot
/// holds the finished sample for review.
struct CameraScreen: View {
    @State private var model = CameraModel()
    @State private var held = HeldOrientationObserver()
    @State private var showingSettings = false
    @State private var poweredOn = false
    @State private var showingOriginal = false
    @State private var shareImage: UIImage?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let orientation = held.orientation
            let turned = orientation.isLandscape
            let rotation = orientation.contentRotation
            let area = ScreenMetrics.tvArea(in: geometry.size, turned: turned, stage: model.stage)
            let tvSize = TVGeometry.size(fitting: area, turned: turned)
            VStack(spacing: 0) {
                TopBar(model: model, rotation: rotation, showsTitle: !turned) {
                    showingSettings = true
                }
                .background {
                    Look.bezel.ignoresSafeArea(edges: .top)
                }
                tv(showsZoom: turned)
                    .frame(width: tvSize.width, height: tvSize.height)
                    .rotationEffect(rotation)
                    .frame(width: area.width, height: area.height)
                    .background(Look.bezel)
                    .contentShape(Rectangle())
                    .simultaneousGesture(swipe(orientation))
                    // Pressing and holding the TV shows the original photo, until the finger lifts.
                    .onLongPressGesture(minimumDuration: 60, maximumDistance: 20) {
                    } onPressingChanged: { pressing in
                        showingOriginal = pressing && model.stage == .review
                    }
                panel(turned: turned, rotation: rotation)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background {
                        Look.caseColor.ignoresSafeArea(edges: .bottom)
                    }
            }
            .animation(.spring(duration: 0.5, bounce: 0.15), value: orientation)
            .animation(.easeInOut(duration: 0.25), value: model.stage)
        }
        .background(Look.bezel)
        .statusBarHidden()
        .sensoryFeedback(.impact(weight: .medium), trigger: model.shotCount)
        .sensoryFeedback(.selection, trigger: model.mode)
        .sensoryFeedback(.selection, trigger: model.reviewMode)
        .sensoryFeedback(.selection, trigger: model.monitor)
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .onAppear {
            held.start()
            powerOn()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            held.deviceOrientationDidChange()
        }
        .task(id: shareKey) {
            renderShareImage()
        }
    }

    private func tv(showsZoom: Bool) -> some View {
        let live = model.stage == .live
        let label = live ? "Viewfinder, \(model.mode.name)" : "Your picture, \(model.reviewMode.name)"
        return TVView(
            picture: live ? model.mode.sample : model.reviewMode.sample,
            fillStart: model.fillStart,
            showsOriginal: showingOriginal,
            monitor: model.monitor,
            crtOn: model.crtOn,
            poweredOn: poweredOn,
            message: model.message,
            zoom: showsZoom && live ? model.zoom : nil,
            onSelectZoom: { model.select($0) }
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private func panel(turned: Bool, rotation: Angle) -> some View {
        switch (model.stage, turned) {
        case (.live, false):
            livePanel
        case (.live, true):
            compactLivePanel(rotation)
        case (.review, false):
            ViewThatFits(in: .vertical) {
                reviewPanel(showsMonitors: true)
                reviewPanel(showsMonitors: false)
            }
        case (.review, true):
            compactReviewPanel(rotation)
        }
    }

    private var livePanel: some View {
        VStack(spacing: 12) {
            ZoomPills(selection: model.zoom) { model.select($0) }
            ModeDial(selection: model.mode) { model.select($0) }
            MonitorBank(selection: model.monitor) { model.select($0) }
                .padding(.top, 6)
            Spacer(minLength: 8)
            shutterRow(rotation: .zero, showsCaption: true)
        }
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    private func reviewPanel(showsMonitors: Bool) -> some View {
        VStack(spacing: 12) {
            ModeStrip(selection: model.reviewMode) { model.reviewMode = $0 }
            if showsMonitors {
                MonitorBank(selection: model.monitor) { model.select($0) }
                    .padding(.top, 6)
            }
            ActionRow(shareImage: shareImage, rotation: .zero, showsCaptions: true) { perform($0) }
            Spacer(minLength: 8)
            shutterRow(rotation: .zero, showsCaption: true)
        }
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    private func compactLivePanel(_ rotation: Angle) -> some View {
        VStack(spacing: 8) {
            CompactModeDial(selection: model.mode, rotation: rotation) { model.select($0) }
            CompactMonitorBank(selection: model.monitor, rotation: rotation) { model.select($0) }
            shutterRow(rotation: rotation, showsCaption: false)
        }
        .padding(.vertical, 8)
    }

    private func compactReviewPanel(_ rotation: Angle) -> some View {
        VStack(spacing: 8) {
            CompactModeStrip(selection: model.reviewMode, rotation: rotation) { model.reviewMode = $0 }
            ActionRow(shareImage: shareImage, rotation: rotation, showsCaptions: false) { perform($0) }
            shutterRow(rotation: rotation, showsCaption: false)
        }
        .padding(.vertical, 8)
    }

    private func shutterRow(rotation: Angle, showsCaption: Bool) -> some View {
        ShutterRow(
            stage: model.stage,
            lastShot: model.lastShot,
            rotation: rotation,
            showsCaption: showsCaption,
            onGallery: { model.showLastShot() },
            onKey: { pressBigKey() },
            onFlip: { model.flipCamera() })
    }

    /// A swipe across the TV, as the user sees it, moves along the mode dial.
    private func swipe(_ orientation: HeldOrientation) -> some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                guard model.stage == .live else { return }
                let movement = orientation.upright(value.translation)
                guard abs(movement.width) > max(40, abs(movement.height)) else { return }
                model.step(by: movement.width < 0 ? 1 : -1)
            }
    }

    private func pressBigKey() {
        if model.stage == .live {
            model.capture(animated: !reduceMotion)
        } else {
            model.backToLive()
        }
    }

    private func perform(_ action: ReviewAction) {
        switch action {
        case .share: break
        case .save: model.notBuiltYet("SAVE TO PHOTOS")
        case .edit: model.notBuiltYet("EDIT")
        case .send: model.notBuiltYet("SEND TO C64")
        case .delete: model.deleteShot()
        }
    }

    /// The CRT warms up when the app opens, while the camera would be starting.
    private func powerOn() {
        guard !poweredOn else { return }
        if reduceMotion {
            poweredOn = true
        } else {
            withAnimation(.easeOut(duration: 0.45).delay(0.15)) {
                poweredOn = true
            }
        }
    }

    private struct ShareKey: Equatable {
        var stage: CameraModel.Stage
        var mode: PictureMode
        var monitor: Monitor
        var crtOn: Bool
    }

    private var shareKey: ShareKey {
        ShareKey(stage: model.stage, mode: model.reviewMode, monitor: model.monitor, crtOn: model.crtOn)
    }

    /// Draws the picture as on TV, border included, for sharing (docs/UX.md, section 6).
    private func renderShareImage() {
        guard model.stage == .review else {
            shareImage = nil
            return
        }
        let width: CGFloat = 384
        let tv = TVView(picture: model.reviewMode.sample, monitor: model.monitor, crtOn: model.crtOn)
            .frame(width: width, height: width / TVGeometry.aspectRatio)
        let renderer = ImageRenderer(content: tv)
        renderer.scale = 3
        shareImage = renderer.uiImage
    }
}

#Preview {
    CameraScreen()
}
