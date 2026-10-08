import C64Core
import PhotosUI
import SwiftUI
import UIKit

/// The C64 screen's proportions (docs/UX.md, section 2).
enum TVGeometry {
    /// PAL pixels are about 0.94 as wide as tall.
    static let pixelAspect = CGFloat(Screen.pixelAspectRatio)
    /// What a TV shows: the 320 × 200 picture inside its border.
    static let visiblePixels = CGSize(width: Screen.width, height: Screen.height)
    static let picturePixels = CGSize(width: Screen.windowWidth, height: Screen.windowHeight)
    /// Width over height of the TV as seen, about 4:3.
    static let aspectRatio: CGFloat = visiblePixels.width * pixelAspect / visiblePixels.height

    /// The largest TV that fits the area, measured upright. When `turned`, the TV
    /// is shown a quarter turn round, so its width runs along the area's height.
    static func size(fitting area: CGSize, turned: Bool) -> CGSize {
        let room = turned ? CGSize(width: area.height, height: area.width) : area
        let width = max(0, min(room.width, room.height * aspectRatio))
        return CGSize(width: width, height: width / aspectRatio)
    }

    /// Where the picture sits inside a TV of the given size: a line nearer the
    /// top than the bottom, as on a C64.
    static func pictureFrame(inTV size: CGSize) -> CGRect {
        let (scaleX, scaleY) = (size.width / visiblePixels.width, size.height / visiblePixels.height)
        return CGRect(
            x: CGFloat(Screen.windowX) * scaleX, y: CGFloat(Screen.windowY) * scaleY,
            width: picturePixels.width * scaleX, height: picturePixels.height * scaleY)
    }
}

/// The TV: a C64 picture inside its border, as it looks on the chosen monitor,
/// through the CRT layer when it is on. Switching off and on, its tube closes
/// the picture into a line and a dot, and opens it again (`Tube`).
struct TVView: View {
    /// How long the finished picture takes to fill in after a shot.
    static let fillDuration: TimeInterval = 0.8

    /// What the TV shows.
    enum Content {
        /// The viewfinder's live picture.
        case live(ViewfinderFeed)
        /// A finished picture, or nil while it is being made.
        case picture(ShownPicture?)
        /// Static: there is no camera to show.
        case noSignal
    }

    var content: Content
    /// When the picture started filling in on a cleared screen, or nil to show it whole.
    var fillStart: Date?
    /// The photo the picture was made from, shown instead while `showsOriginal`.
    var original: Photo?
    var showsOriginal = false
    /// The CRT layer's look, or nil to show the monitor's picture as it is.
    var crt: CRT?
    /// The tube, as it switches off and on.
    var tube = Tube(.on)
    /// The colour of the monitor's phosphor, for the tube's line and dot:
    /// white on a colour monitor.
    var phosphor = RGB(255, 255, 255)
    var message: CameraModel.Message?
    /// Where the camera was just asked to focus, if it was.
    var focus: CameraModel.FocusMark?
    /// The zoom buttons to show on the border, or nil for none.
    var zoom: ZoomButtons?
    var onSelectZoom: (Double) -> Void = { _ in }

    var body: some View {
        GeometryReader { geometry in
            let frame = TVGeometry.pictureFrame(inTV: geometry.size)
            // What shows on the glass, only once the TV is on, or opening.
            let isOn = tube.target == .on
            tubeScreen(window: frame, size: geometry.size)
                .overlay(alignment: .topLeading) {
                    if isOn, let focus {
                        FocusMarkView()
                            .position(
                                x: frame.minX + focus.point.x * frame.width,
                                y: frame.minY + focus.point.y * frame.height)
                    }
                }
                .overlay(alignment: .top) {
                    if isOn, let message {
                        MessageView(message: message)
                            .padding(.top, frame.minY + 8)
                    }
                }
                .overlay(alignment: .bottom) {
                    if isOn, let zoom {
                        ZoomPills(buttons: zoom, onSelect: onSelectZoom)
                            .padding(.bottom, max(0, (geometry.size.height - frame.maxY - 34) / 2))
                    }
                }
        }
        .clipped()
    }

    /// The screen as the tube draws it, every frame while it switches off or
    /// warms up.
    @ViewBuilder private func tubeScreen(window: CGRect, size: CGSize) -> some View {
        if tube.isSettled {
            drawn(tube.raster(at: .now), window: window, size: size)
        } else {
            TimelineView(.animation) { context in
                drawn(tube.raster(at: context.date), window: window, size: size)
            }
        }
    }

    /// The screen with the tube's raster: the whole picture, or the tube's
    /// face behind the picture as it closes into a line, brighter as it
    /// closes.
    private func drawn(_ raster: Raster, window: CGRect, size: CGSize) -> some View {
        ZStack {
            if raster != .on {
                TubeFace(raster: raster, phosphor: phosphor, crt: crt)
            }
            if raster == .on {
                picture(window: window, size: size)
            } else if raster.pictureOpacity > 0 {
                picture(window: window, size: size)
                    .colorEffect(TubeFace.gain(raster.gain))
                    .scaleEffect(x: max(raster.width, 0.001), y: max(raster.height, 0.001))
                    .opacity(raster.pictureOpacity)
            }
        }
    }

    /// The whole screen, border included, or the original photo while it
    /// shows instead.
    private func picture(window: CGRect, size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            Color.black
            screen(window: window)
                .frame(width: size.width, height: size.height)
            if showsOriginal, let original {
                // Cropped as the converter crops it: the centre, in the window's shape.
                Image(decorative: original.preview, scale: 1, orientation: original.mirrored ? .upMirrored : .up)
                    .resizable()
                    .scaledToFill()
                    .frame(width: window.width, height: window.height)
                    .clipped()
                    .offset(x: window.minX, y: window.minY)
                    .accessibilityLabel("The original photo")
            }
        }
    }

    /// The whole screen, border included, filling in cell by cell after a shot.
    @ViewBuilder private func screen(window: CGRect) -> some View {
        switch content {
        case .live(let feed):
            LiveScreen(feed: feed, crt: crt)
        case .picture(let picture):
            if let picture {
                if let fillStart {
                    TimelineView(.animation) { context in
                        let progress = context.date.timeIntervalSince(fillStart) / Self.fillDuration
                        PictureScreen(picture: picture, crt: crt, window: window, progress: progress)
                    }
                } else {
                    PictureScreen(picture: picture, crt: crt, window: window)
                }
            }
        case .noSignal:
            NoSignal(crt: crt)
        }
    }

    /// A picture as on TV, border included, for sharing (docs/UX.md, section
    /// 6): with the CRT layer when it is on, drawn 4 pixels per point, so
    /// that its lines are about 4 pixels high.
    static func shareImage(of picture: ShownPicture, crt: CRT?) -> UIImage? {
        let (width, scale): (CGFloat, CGFloat) = (384, 4)
        let tv = TVView(content: .picture(picture), crt: crt)
            .frame(width: width, height: width / TVGeometry.aspectRatio)
            .environment(\.displayScale, scale)
        let renderer = ImageRenderer(content: tv)
        renderer.scale = scale
        renderer.isOpaque = true
        return renderer.uiImage
    }

    /// The picture as on TV as a PNG file, as Share and Save to Photos give
    /// it: never a JPEG, whose blocks would blur the C64's pixels.
    static func pngAsOnTV(of picture: ShownPicture, crt: CRT?) -> Data? {
        shareImage(of: picture, crt: crt)?.pngData()
    }
}

/// A finished picture, which fills in cell by cell after a shot.
private struct PictureScreen: View {
    var picture: ShownPicture
    var crt: CRT?
    /// Where the display window is.
    var window: CGRect
    /// How far the picture has filled in, from 0 to 1, or nil if it shows
    /// whole.
    var progress: Double?

    var body: some View {
        if let crt {
            let cells = progress.map { (min(max($0, 0), 1) * 1000).rounded(.down) } ?? 1000
            CRTScreen(source: picture.crt, crt: crt, revealed: cells)
                .accessibilityLabel("C64 picture")
        } else {
            let image = Image(decorative: picture.screen, scale: 1)
                .resizable()
                .interpolation(.none)
                .accessibilityLabel("C64 picture")
            if let progress {
                image.mask {
                    CellFill(progress: progress, window: window)
                }
            } else {
                image
            }
        }
    }
}

/// The viewfinder's newest picture. Only this view reads it, so only this
/// view redraws for each frame.
private struct LiveScreen: View {
    var feed: ViewfinderFeed
    var crt: CRT?

    var body: some View {
        if let picture = feed.picture {
            if let crt {
                CRTScreen(source: picture.crt, crt: crt)
                    .accessibilityLabel("C64 picture")
            } else {
                Image(decorative: picture.screen, scale: 1)
                    .resizable()
                    .interpolation(.none)
                    .accessibilityLabel("C64 picture")
            }
        }
    }
}

/// What a TV shows with no signal: static. It is the TV's own noise, not a C64
/// picture, and goes through the CRT layer when it is on. With Reduce Motion
/// on, it stands still.
struct NoSignal: View {
    var crt: CRT?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 25, paused: reduceMotion)) { context in
            let frame = UInt64(max(0, context.date.timeIntervalSinceReferenceDate * 25))
            if let crt {
                CRTScreen(source: CRTSource(Self.screen(seed: frame)), crt: crt)
            } else if let noise = Self.noise(seed: frame) {
                Image(decorative: noise, scale: 1)
                    .resizable()
                    .interpolation(.none)
            }
        }
        .accessibilityHidden(true)
    }

    /// Random greys: one frame of static.
    static func greys(seed: UInt64, count: Int) -> [UInt8] {
        var state = (seed &+ 1) &* 0x9E37_79B9_7F4A_7C15
        var bytes = [UInt8](repeating: 0, count: count)
        for index in bytes.indices {
            // Xorshift: plenty for static.
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            bytes[index] = UInt8(truncatingIfNeeded: state >> 32)
        }
        return bytes
    }

    /// One frame of static: random greys, a little larger than C64 pixels.
    static func noise(seed: UInt64, width: Int = 192, height: Int = 136) -> CGImage? {
        let bytes = greys(seed: seed, count: width * height)
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// One frame of static as a whole screen, for the CRT layer: the same
    /// grains, each 2 × 2 C64 pixels.
    static func screen(seed: UInt64) -> RGBImage {
        let (width, height) = (Screen.width, Screen.height)
        let grains = greys(seed: seed, count: (width / 2) * (height / 2))
        var bytes = [UInt8](repeating: 0, count: width * height * 3)
        for y in 0..<height {
            for x in 0..<width {
                let grey = grains[(y / 2) * (width / 2) + x / 2]
                let index = (y * width + x) * 3
                (bytes[index], bytes[index + 1], bytes[index + 2]) = (grey, grey, grey)
            }
        }
        return RGBImage(width: width, height: height, bytes: bytes)
    }
}

/// Where the camera focuses, for a moment after a tap on the picture.
struct FocusMarkView: View {
    var body: some View {
        Rectangle()
            .strokeBorder(Look.ledOn, lineWidth: 1.5)
            .frame(width: 52, height: 52)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Reveals a picture cell by cell, in the order a C64 stores a bitmap: 40 cells
/// across, then the next row of cells. The border shows from the start.
struct CellFill: View {
    /// From 0 (nothing shown) to 1 (all 1,000 cells shown).
    var progress: Double
    /// Where the display window is.
    var window: CGRect

    var body: some View {
        let cells = Int(min(max(progress, 0), 1) * 1000)
        Canvas { context, size in
            var border = Path(CGRect(origin: .zero, size: size))
            border.addRect(window)
            context.fill(border, with: .color(.white), style: FillStyle(eoFill: true))
            let cellWidth = window.width / 40
            let cellHeight = window.height / 25
            let fullRows = cells / 40
            let rest = cells % 40
            if fullRows > 0 {
                let rows = CGRect(
                    x: window.minX, y: window.minY, width: window.width, height: CGFloat(fullRows) * cellHeight)
                context.fill(Path(rows), with: .color(.white))
            }
            if rest > 0 {
                let row = CGRect(
                    x: window.minX, y: window.minY + CGFloat(fullRows) * cellHeight, width: CGFloat(rest) * cellWidth,
                    height: cellHeight)
                context.fill(Path(row), with: .color(.white))
            }
        }
    }
}

/// A short message on the TV, such as the new mode's name.
struct MessageView: View {
    var message: CameraModel.Message

    var body: some View {
        VStack(spacing: 2) {
            Text(message.title)
                .font(.system(size: 13, weight: .heavy).width(.condensed))
                .tracking(1)
            if let detail = message.detail {
                Text(detail)
                    .font(.system(size: 11, weight: .medium))
            }
        }
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.72)))
        .padding(.horizontal, 12)
    }
}

/// The zoom buttons: the values they offer, and the zoom now.
struct ZoomButtons: Equatable {
    var presets: [Double]
    var zoom: Double

    /// The button lit: the highest at or below the zoom.
    var lit: Double? { presets.last { $0 <= zoom + 0.01 } ?? presets.first }

    /// What a button shows: its value, as in ".5", "1" or "2", or for the lit
    /// one, the zoom now with a ×.
    func label(_ preset: Double) -> String {
        preset == lit ? Self.format(zoom) + "×" : Self.format(preset)
    }

    /// A zoom as the buttons write it: ".5", "1", "1.4".
    static func format(_ value: Double) -> String {
        let tenths = Int((value * 10).rounded())
        if tenths < 10 {
            return ".\(tenths)"
        }
        return tenths % 10 == 0 ? "\(tenths / 10)" : "\(tenths / 10).\(tenths % 10)"
    }

    /// A zoom as VoiceOver reads it, and messages show it: "0.5×".
    static func name(_ value: Double) -> String {
        (value < 0.95 ? "0" : "") + format(value) + "×"
    }
}

/// The zoom buttons: below the TV in portrait, on its border in landscape.
struct ZoomPills: View {
    var buttons: ZoomButtons
    var onSelect: (Double) -> Void

    var body: some View {
        HStack(spacing: 10) {
            ForEach(buttons.presets, id: \.self) { preset in
                let isLit = preset == buttons.lit
                Button {
                    onSelect(preset)
                } label: {
                    Text(buttons.label(preset))
                        .font(.system(size: 12, weight: isLit ? .heavy : .semibold))
                        .foregroundStyle(isLit ? Look.ledOn : Look.pillInk)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Look.pill))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Zoom \(ZoomButtons.name(preset))")
                .accessibilityAddTraits(isLit ? .isSelected : [])
            }
        }
    }
}

/// On the static, when there is no camera to show: why, and what to do
/// instead (docs/UX.md, section 3). Development builds can convert a photo
/// from the library instead, so that the review can be tried without a
/// camera.
struct NoCameraPanel: View {
    var trouble: LiveCamera.State
    @Binding var importedItem: PhotosPickerItem?
    var onAllow: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            VStack(spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .heavy).width(.condensed))
                    .tracking(1)
                Text(detail)
                    .font(.system(size: 11, weight: .medium))
            }
            HStack(spacing: 8) {
                if trouble == .notAllowed {
                    Button("ALLOW CAMERA", action: onAllow)
                }
                if trouble != .interrupted && BuildKind.isDevelopment {
                    PhotosPicker(selection: $importedItem, matching: .images) {
                        Text("IMPORT A PHOTO")
                    }
                }
            }
            .buttonStyle(TVButtonStyle())
        }
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.72)))
        .padding(.horizontal, 16)
    }

    private var title: String {
        switch trouble {
        case .notAllowed: "CAMERA NOT ALLOWED"
        case .interrupted: "CAMERA IN USE"
        default: "NO CAMERA"
        }
    }

    private var detail: String {
        switch (trouble, BuildKind.isDevelopment) {
        case (.notAllowed, true): "Allow it in Settings, or convert a photo."
        case (.notAllowed, false): "Allow it in Settings to take pictures."
        case (.interrupted, _): "Another app has the camera for now."
        case (_, true): "Convert a photo from your library instead."
        case (_, false): "The camera would not start."
        }
    }
}

/// A button on the TV's glass.
struct TVButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .heavy).width(.condensed))
            .tracking(0.8)
            .foregroundStyle(Look.ledOn)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(Capsule().fill(Look.pill))
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}
