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
/// chosen monitor, and a shot holds its picture for review, until the next
/// one: it can be shared, saved to Photos, sent to a C64 or deleted. Without a
/// camera the TV shows static, and in development builds, a photo from the
/// library can stand in for a shot.
struct CameraScreen: View {
    @State private var model = CameraModel()
    @State private var camera = LiveCamera()
    @State private var pictures = PictureMaker()
    @State private var held = HeldOrientationObserver()
    @State private var showingSettings = false
    @State private var poweredOn = false
    @State private var showingOriginal = false
    @State private var importedItem: PhotosPickerItem?
    /// The zoom when a pinch began.
    @State private var pinchStart: Double?
    @State private var dragKind: DragKind?
    @AppStorage(SettingName.saveEveryShot) private var savesEveryShot = false
    @AppStorage(SettingName.ultimateAddress) private var ultimateAddress = ""
    /// The CRT layer's look as a development build tunes it (`CRT.text`).
    @AppStorage(SettingName.crtLook) private var crtLookText = ""
    @AppStorage(SettingName.crtTuning) private var showsCRTTuning = false
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
                    .overlay {
                        if BuildKind.isDevelopment && showsCRTTuning {
                            CRTTuningPanel(crt: crtTuning) {
                                showsCRTTuning = false
                            }
                        }
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
            await camera.start(cameraPosition)
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
        // Back in the app, the camera runs again if iOS stopped it while the
        // app was away, as when it resets its media services, or if it was
        // allowed in Settings meanwhile.
        .onChange(of: scenePhase) {
            if scenePhase == .active && camera.state != .starting {
                Task { await camera.start(cameraPosition) }
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
            Task { await camera.interruptionEnded(cameraPosition) }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: AVCaptureSession.runtimeErrorNotification)
                .receive(on: DispatchQueue.main)
        ) { notification in
            let error = (notification.userInfo?[AVCaptureSessionErrorKey] as? AVError)?.code
            Task { await camera.sessionFailed(error, position: cameraPosition) }
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
        // Every mode's picture of the shot for the monitor, for the mode strip
        // and the last shot's thumbnail, the review's first.
        .task(id: pictureSettings) {
            await pictures.makeAll(for: model.monitor, first: model.reviewMode)
        }
    }

    /// What every mode's pictures depend on.
    private struct PictureSettings: Equatable {
        var photo: UUID?
        var monitor: Monitor
    }

    private var pictureSettings: PictureSettings {
        PictureSettings(photo: pictures.photo?.id, monitor: model.monitor)
    }

    /// The CRT layer's look: the standard one, or as a development build
    /// tunes it.
    private var crtLook: CRT {
        BuildKind.isDevelopment ? CRT(text: crtLookText) ?? .standard : .standard
    }

    /// The look the tuning panel changes, saved as text.
    private var crtTuning: Binding<CRT> {
        Binding {
            crtLook
        } set: { look in
            crtLookText = look.text
        }
    }

    /// The CRT layer as the TV shows it, or nil when it is off, or the
    /// monitor is Sharp.
    private var crt: CRT? {
        model.crtShown ? crtLook : nil
    }

    /// A mode's picture for the chosen monitor.
    private func key(_ mode: PictureMode) -> PictureMaker.Key {
        PictureMaker.Key(mode, on: model.monitor)
    }

    /// What the viewfinder makes of the camera's frames, or nil when the TV
    /// holds a shot. Frames are dropped while Settings covers the TV too,
    /// which leaves the processor to the speed benchmark.
    private var viewfinderSettings: Viewfinder.Settings? {
        guard model.stage == .live, !showingSettings else { return nil }
        let afterglow = model.crtShown && model.monitor.hasAfterglow ? crtLook.afterglow : 0
        return Viewfinder.Settings(
            spec: model.mode.spec, converter: model.mode.converterSettings(on: model.monitor),
            orientation: frameOrientation, afterglow: afterglow)
    }

    /// The camera chosen: the back one, or the front one.
    private var cameraPosition: Camera.Position {
        model.frontCamera ? .front : .back
    }

    /// How the camera's frames are seen, as the phone is held.
    private var frameOrientation: ImageOrientation {
        held.orientation.frameOrientation(frontCamera: camera.capabilities?.position == .front)
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
            crt: crt,
            poweredOn: poweredOn,
            message: model.message,
            focus: live ? model.focus : nil,
            zoom: showsZoom && live ? zoomButtons : nil,
            onSelectZoom: { selectZoom($0) }
        )
        .overlay {
            if live, let trouble = cameraTrouble {
                NoCameraPanel(trouble: trouble, importedItem: $importedItem) {
                    openSettings()
                }
            }
        }
        .task(id: reviewKey) {
            if let reviewKey {
                await pictures.make(reviewKey)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }

    /// What the TV shows: the viewfinder, a shot's picture, or static.
    private var tvContent: TVView.Content {
        if let reviewKey {
            return .picture(pictures.picture(reviewKey))
        }
        switch camera.state {
        case .running: return .live(camera.feed)
        case .starting: return .picture(nil)
        case .notAllowed, .unavailable, .interrupted: return .noSignal
        }
    }

    /// The picture the review shows, or nil when the TV shows the camera.
    private var reviewKey: PictureMaker.Key? {
        model.stage == .review ? key(model.reviewMode) : nil
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
            actionRow(rotation: .zero, showsCaptions: true)
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
            actionRow(rotation: rotation, showsCaptions: false)
            shutterRow(rotation: rotation, showsCaption: false)
        }
        .padding(.vertical, 8)
    }

    private func actionRow(rotation: Angle, showsCaptions: Bool) -> some View {
        ActionRow(
            actions: ReviewAction.all(canSend: canSend), files: sharedFiles, sending: model.sending,
            rotation: rotation, showsCaptions: showsCaptions
        ) { perform($0) }
    }

    /// Whether an Ultimate is set up, for Send to C64.
    private var canSend: Bool {
        !ultimateAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// What Share offers for the review's picture, once it is made.
    private var sharedFiles: [SharedFile] {
        let mode = model.reviewMode
        guard let reviewKey, let photo = pictures.photo, let picture = pictures.picture(reviewKey) else { return [] }
        let name = SharedFile.name(mode: mode.title, taken: photo.date)
        return SharedFile.files(of: picture, crt: crt, name: name, programName: mode.title)
    }

    private func shutterRow(rotation: Angle, showsCaption: Bool) -> some View {
        ShutterRow(
            stage: model.stage,
            lastShot: model.lastShot,
            thumbnail: model.lastShot.flatMap { pictures.picture(key($0))?.window },
            rotation: rotation,
            showsCaption: showsCaption,
            onLastPicture: { model.showLastShot() },
            onKey: { pressBigKey() },
            onFlip: { flipCamera() })
    }

    // MARK: - Gestures

    /// A tap on the picture focuses the camera there.
    private func focusTap(tvSize: CGSize) -> some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                guard model.stage == .live, camera.state == .running else { return }
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
            model.show("NO CAMERA", BuildKind.isDevelopment ? "Import a photo instead" : nil)
            // A camera that stopped on an error tries again.
            if camera.state == .unavailable {
                Task { await camera.start(cameraPosition) }
            }
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
                // The camera may have stopped, as when iOS resets its media
                // services: it runs again.
                await camera.start(cameraPosition)
            }
        }
    }

    /// Opens a photo from the library for review, as if it were a shot: in
    /// development builds, so that the review can be tried without a camera.
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
    /// fills in, and goes to Photos if Settings saves every shot.
    private func review(_ photo: Photo, in mode: PictureMode) async {
        pictures.use(photo)
        let shot = key(mode)
        await pictures.make(shot)
        model.pictureReady(animated: !reduceMotion)
        if savesEveryShot, let picture = pictures.picture(shot) {
            await save(picture, everyShot: true)
        }
    }

    private func flipCamera() {
        guard camera.state == .running else {
            model.show("NO CAMERA")
            return
        }
        model.flipCamera()
        let position = cameraPosition
        Task { await camera.start(position) }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
    }

    private func perform(_ action: ReviewAction) {
        guard let reviewKey else { return }
        switch action {
        case .share:
            break
        case .save:
            if let picture = pictures.picture(reviewKey) {
                Task { await save(picture, everyShot: false) }
            }
        case .send:
            sendToC64(reviewKey)
        case .delete:
            model.deleteShot()
            pictures.forget()
        }
    }

    /// Saves a picture to Photos, as on TV (docs/UX.md, section 5).
    private func save(_ picture: ShownPicture, everyShot: Bool) async {
        guard let png = TVView.pngAsOnTV(of: picture, crt: crt) else {
            model.saved(.notSaved, everyShot: everyShot)
            return
        }
        do throws(PhotoLibrary.Failure) {
            try await PhotoLibrary.add(png: png)
            model.saved(nil, everyShot: everyShot)
        } catch {
            model.saved(error, everyShot: everyShot)
        }
    }

    /// Shows a picture on the C64 of the Ultimate set up in Settings: its
    /// program runs there.
    private func sendToC64(_ key: PictureMaker.Key) {
        guard !model.sending, let picture = pictures.picture(key) else { return }
        let ultimate = Ultimate(address: ultimateAddress, password: Keychain.password(SettingName.ultimatePassword))
        let program = picture.frame.prg()
        model.sendingStarted()
        Task {
            do throws(Ultimate.Failure) {
                try await ultimate.run(program)
                model.sendingEnded(nil)
            } catch {
                model.sendingEnded(error)
            }
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
}

#Preview {
    CameraScreen()
}
