import AVFoundation
import AVKit
import C64Core
import Combine
import PhotosUI
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
/// The TV shows what the camera sees, converted in the chosen mode for the
/// chosen monitor, and a shot holds its picture for review. Without a camera
/// it shows static, and a photo from the library can stand in for a shot.
struct CameraScreen: View {
    @State private var model = CameraModel()
    @State private var camera = LiveCamera()
    @State private var pictures = PictureMaker()
    @State private var held = HeldOrientationObserver()
    @State private var showingSettings = false
    @State private var poweredOn = false
    @State private var showingOriginal = false
    @State private var shareImage: UIImage?
    @State private var importedItem: PhotosPickerItem?
    /// The zoom when a pinch began.
    @State private var pinchStart: Double?
    @State private var dragKind: DragKind?
    @AppStorage(SettingName.petsciiGraphicsOnly) private var petsciiGraphicsOnly = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

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
                    // Taps land in the TV's own coordinates, before it turns. In a
                    // review, pressing and holding shows the original instead.
                    .contentShape(Rectangle())
                    .simultaneousGesture(focusTap(tvSize: tvSize), including: model.stage == .live ? .all : .subviews)
                    .rotationEffect(rotation)
                    .frame(width: area.width, height: area.height)
                    .background(Look.bezel)
                    .contentShape(Rectangle())
                    .simultaneousGesture(drag(orientation))
                    .simultaneousGesture(pinch)
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
        }
        // The CRT warms up while the camera starts (docs/UX.md, section 3).
        .task {
            await camera.start(model.frontCamera ? .front : .back)
        }
        .task {
            try? await Task.sleep(for: .seconds(2))
            powerOn()
        }
        .onChange(of: camera.feed.hasPicture) {
            powerOn()
        }
        .onChange(of: camera.state) {
            if camera.state != .starting && camera.state != .running {
                powerOn()
            }
        }
        .onChange(of: viewfinderSettings, initial: true) {
            camera.show(viewfinderSettings)
        }
        // Back from Settings, where the camera may have been allowed.
        .onChange(of: scenePhase) {
            if scenePhase == .active && camera.state == .notAllowed {
                Task { await camera.start(model.frontCamera ? .front : .back) }
            }
        }
        .onChange(of: importedItem) {
            if let item = importedItem {
                Task { await importPhoto(item) }
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: AVCaptureSession.wasInterruptedNotification)
                .receive(on: DispatchQueue.main)
        ) { _ in
            camera.wasInterrupted()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: AVCaptureSession.interruptionEndedNotification)
                .receive(on: DispatchQueue.main)
        ) { _ in
            camera.interruptionEnded()
        }
        // The volume buttons and a click of the Camera Control take a picture too.
        .onCameraCaptureEvent(isEnabled: model.stage == .live && camera.state == .running) { event in
            if event.phase == .ended {
                capture()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            held.deviceOrientationDidChange()
        }
        .task(id: shareKey) {
            renderShareImage()
        }
        // Every mode's picture of the shot for the monitor, for the mode strip
        // and the last shot's thumbnail, the review's first.
        .task(id: pictureSettings) {
            await pictures.makeAll(for: model.monitor, petsciiCharacters: petsciiCharacters, first: model.reviewMode)
        }
    }

    /// What every mode's pictures depend on.
    private struct PictureSettings: Equatable {
        var photo: UUID?
        var monitor: Monitor
        var petsciiCharacters: CharacterROM.Selection
    }

    private var pictureSettings: PictureSettings {
        PictureSettings(photo: pictures.photo?.id, monitor: model.monitor, petsciiCharacters: petsciiCharacters)
    }

    /// The characters PETSCII pictures may use, as Settings has it.
    private var petsciiCharacters: CharacterROM.Selection {
        petsciiGraphicsOnly ? .graphics : .all
    }

    /// A mode's picture for the chosen monitor.
    private func key(_ mode: PictureMode) -> PictureMaker.Key {
        PictureMaker.Key(mode, on: model.monitor, petsciiCharacters: petsciiCharacters)
    }

    /// What the viewfinder makes of the camera's frames, or nil when the TV
    /// shows something else: a review, or the sample picture of a mode
    /// without a converter yet.
    private var viewfinderSettings: Viewfinder.Settings? {
        guard model.stage == .live, let spec = model.mode.spec else { return nil }
        let settings = Converter.Settings(display: model.monitor.display, petsciiCharacters: petsciiCharacters)
        return Viewfinder.Settings(spec: spec, converter: settings, orientation: frameOrientation)
    }

    /// How the camera's frames are seen, as the phone is held.
    private var frameOrientation: ImageOrientation {
        held.orientation.frameOrientation(mirrored: camera.capabilities?.position == .front)
    }

    private func tv(showsZoom: Bool) -> some View {
        let live = model.stage == .live
        let mode = live ? model.mode : model.reviewMode
        let label = live ? "Viewfinder, \(mode.name)" : "Your picture, \(mode.name)"
        return TVView(
            content: tvContent,
            fillStart: model.fillStart,
            original: pictures.photo,
            showsOriginal: showingOriginal,
            crtOn: model.crtOn,
            poweredOn: poweredOn,
            message: model.message,
            focus: live ? model.focus : nil,
            zoom: showsZoom && live ? zoomButtons : nil,
            onSelectZoom: { selectZoom($0) }
        )
        .overlay {
            if live && mode.spec != nil, let trouble = cameraTrouble {
                NoCameraPanel(trouble: trouble, importedItem: $importedItem) {
                    openSettings()
                }
            }
        }
        .task(id: tvPictureKey) {
            if let tvPictureKey {
                await pictures.make(tvPictureKey)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }

    /// What the TV shows: the viewfinder, a shot's picture, a sample, or
    /// static.
    private var tvContent: TVView.Content {
        let live = model.stage == .live
        let mode = live ? model.mode : model.reviewMode
        guard live && mode.spec != nil else {
            return .picture(pictures.picture(key(mode)))
        }
        switch camera.state {
        case .running: return .live(camera.feed)
        case .starting: return .picture(nil)
        case .notAllowed, .unavailable, .interrupted: return .noSignal
        }
    }

    /// The TV's picture, when PictureMaker makes it: a shot's, or a sample.
    private var tvPictureKey: PictureMaker.Key? {
        let live = model.stage == .live
        let mode = live ? model.mode : model.reviewMode
        return live && mode.spec != nil ? nil : key(mode)
    }

    /// Why the TV shows static, if it does.
    private var cameraTrouble: LiveCamera.State? {
        switch camera.state {
        case .notAllowed, .unavailable, .interrupted: camera.state
        case .starting, .running: nil
        }
    }

    private var zoomButtons: ZoomButtons {
        ZoomButtons(presets: camera.capabilities?.zoomPresets ?? [1], zoom: model.zoom)
    }

    /// Each mode's picture of the display window, for the mode strip.
    private var thumbnails: [PictureMode: CGImage] {
        var thumbnails: [PictureMode: CGImage] = [:]
        for mode in PictureMode.allCases {
            thumbnails[mode] = pictures.picture(key(mode))?.window
        }
        return thumbnails
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
            ZoomPills(buttons: zoomButtons) { selectZoom($0) }
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
            ModeStrip(selection: model.reviewMode, thumbnails: thumbnails) { model.reviewMode = $0 }
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
            CompactModeStrip(selection: model.reviewMode, thumbnails: thumbnails, rotation: rotation) {
                model.reviewMode = $0
            }
            ActionRow(shareImage: shareImage, rotation: rotation, showsCaptions: false) { perform($0) }
            shutterRow(rotation: rotation, showsCaption: false)
        }
        .padding(.vertical, 8)
    }

    private func shutterRow(rotation: Angle, showsCaption: Bool) -> some View {
        ShutterRow(
            stage: model.stage,
            lastShot: model.lastShot,
            thumbnail: model.lastShot.flatMap { pictures.picture(key($0))?.window },
            rotation: rotation,
            showsCaption: showsCaption,
            onGallery: { model.showLastShot() },
            onKey: { pressBigKey() },
            onFlip: { flipCamera() })
    }

    // MARK: - Gestures

    /// A tap on the picture focuses the camera there.
    private func focusTap(tvSize: CGSize) -> some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                guard model.stage == .live, model.mode.spec != nil, camera.state == .running else { return }
                let window = TVGeometry.pictureFrame(inTV: tvSize)
                let point = CGPoint(
                    x: (value.location.x - window.minX) / window.width,
                    y: (value.location.y - window.minY) / window.height)
                guard (0...1).contains(point.x) && (0...1).contains(point.y) else { return }
                model.showFocus(at: point)
                camera.focus(onPicturePoint: point, orientation: frameOrientation)
            }
    }

    /// What a drag across the TV does: a swipe along the mode dial, or up and
    /// down, the exposure.
    private enum DragKind: Equatable {
        case swipe
        case exposure(from: Float)
    }

    private func drag(_ orientation: HeldOrientation) -> some Gesture {
        DragGesture(minimumDistance: 24)
            .onChanged { value in
                guard model.stage == .live, pinchStart == nil else { return }
                // A drag on the TV, as the user sees it.
                let movement = orientation.upright(value.translation)
                if dragKind == nil {
                    let upAndDown = abs(movement.height) > abs(movement.width)
                    let exposure = upAndDown && camera.state == .running
                    dragKind = exposure ? DragKind.exposure(from: model.exposureBias) : DragKind.swipe
                }
                if case .exposure(let start) = dragKind {
                    // A stop for every 100 points, in thirds of a stop, from
                    // two stops darker to two brighter.
                    let bias = min(max(start - Float(movement.height) / 100, -2), 2)
                    let thirds = (bias * 3).rounded() / 3
                    if thirds != model.exposureBias {
                        model.setExposureBias(thirds)
                        camera.setExposureBias(thirds)
                    }
                }
            }
            .onEnded { value in
                defer { dragKind = nil }
                guard model.stage == .live, dragKind == .swipe else { return }
                let movement = orientation.upright(value.translation)
                guard abs(movement.width) > max(40, abs(movement.height)) else { return }
                model.step(by: movement.width < 0 ? 1 : -1)
            }
    }

    /// A pinch on the TV zooms.
    private var pinch: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                guard model.stage == .live, let range = camera.capabilities?.zoomRange else { return }
                let start = pinchStart ?? model.zoom
                pinchStart = start
                let zoom = min(max(start * Double(value.magnification), range.lowerBound), range.upperBound)
                model.pinch(to: zoom)
                camera.zoom(to: zoom, animated: false)
            }
            .onEnded { _ in
                pinchStart = nil
            }
    }

    // MARK: - Actions

    private func selectZoom(_ zoom: Double) {
        model.select(zoom: zoom)
        camera.zoom(to: zoom, animated: true)
    }

    private func pressBigKey() {
        if model.stage == .live {
            capture()
        } else {
            model.backToLive()
        }
    }

    /// Takes a photo and holds its picture for review.
    private func capture() {
        guard model.stage == .live else { return }
        guard camera.state == .running else {
            model.show("NO CAMERA", "Import a photo instead")
            return
        }
        let (previous, mode) = (model.lastShot, model.mode)
        model.capture()
        Task {
            do {
                let photo = try await camera.takePhoto(flash: model.flashOn, held: held.orientation)
                await review(photo, in: mode)
            } catch {
                model.captureFailed(lastShot: previous)
            }
        }
    }

    /// Opens a photo from the library for review, as if it were a shot.
    private func importPhoto(_ item: PhotosPickerItem) async {
        importedItem = nil
        let data = try? await item.loadTransferable(type: Data.self)
        let photo = await Task.detached(priority: .userInitiated) {
            data.flatMap { Photo(data: $0, mirrored: false) }
        }.value
        guard let photo else {
            model.show("NO PICTURE", "That photo would not open")
            return
        }
        let mode = model.mode
        model.capture()
        await review(photo, in: mode)
    }

    /// Converts a photo, the picture for the review's mode first, which then
    /// fills in.
    private func review(_ photo: Photo, in mode: PictureMode) async {
        pictures.use(photo)
        await pictures.make(key(mode))
        model.pictureReady(animated: !reduceMotion)
    }

    private func flipCamera() {
        guard camera.state == .running else {
            model.show("NO CAMERA")
            return
        }
        model.flipCamera()
        let position: Camera.Position = model.frontCamera ? .front : .back
        Task { await camera.start(position) }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
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

    /// The CRT warms up while the camera starts: until its first frame comes,
    /// or it is clear none will.
    private func powerOn() {
        guard !poweredOn else { return }
        if reduceMotion {
            poweredOn = true
        } else {
            withAnimation(.easeOut(duration: 0.45)) {
                poweredOn = true
            }
        }
    }

    private struct ShareKey: Equatable {
        var stage: CameraModel.Stage
        var picture: PictureMaker.Key
        var crtOn: Bool
        /// Whether the picture is made yet.
        var ready: Bool
    }

    private var shareKey: ShareKey {
        ShareKey(
            stage: model.stage, picture: key(model.reviewMode), crtOn: model.crtOn,
            ready: pictures.picture(key(model.reviewMode)) != nil)
    }

    /// Draws the picture as on TV, border included, for sharing (docs/UX.md, section 6).
    private func renderShareImage() {
        guard model.stage == .review, let picture = pictures.picture(key(model.reviewMode)) else {
            shareImage = nil
            return
        }
        let width: CGFloat = 384
        let tv = TVView(content: .picture(picture), crtOn: model.crtOn)
            .frame(width: width, height: width / TVGeometry.aspectRatio)
        let renderer = ImageRenderer(content: tv)
        renderer.scale = 3
        shareImage = renderer.uiImage
    }
}

#Preview {
    CameraScreen()
}
