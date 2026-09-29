import SwiftUI

/// The C64 screen's proportions (docs/UX.md, section 2).
enum TVGeometry {
    /// PAL pixels are about 0.94 as wide as tall.
    static let pixelAspect: CGFloat = 0.936
    /// What a TV shows: the 320 × 200 picture inside its border.
    static let visiblePixels = CGSize(width: 384, height: 272)
    static let picturePixels = CGSize(width: 320, height: 200)
    /// Width over height of the TV as seen, about 4:3.
    static let aspectRatio: CGFloat = visiblePixels.width * pixelAspect / visiblePixels.height

    /// The largest TV that fits the area, measured upright. When `turned`, the TV
    /// is shown a quarter turn round, so its width runs along the area's height.
    static func size(fitting area: CGSize, turned: Bool) -> CGSize {
        let room = turned ? CGSize(width: area.height, height: area.width) : area
        let width = max(0, min(room.width, room.height * aspectRatio))
        return CGSize(width: width, height: width / aspectRatio)
    }

    /// Where the picture sits inside a TV of the given size.
    static func pictureFrame(inTV size: CGSize) -> CGRect {
        let width = size.width * picturePixels.width / visiblePixels.width
        let height = size.height * picturePixels.height / visiblePixels.height
        return CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
    }
}

/// The TV: a C64 picture inside its border, as it looks on the chosen monitor.
///
/// Placeholder: it shows bundled sample pictures and tints them for the mono
/// monitors. Once C64Core renders pictures from C64 memory through its display
/// models, those replace both (CLAUDE.md, core rule).
struct TVView: View {
    /// How long the finished picture takes to fill in after a shot.
    static let fillDuration: TimeInterval = 0.8

    var picture: String
    /// When the picture started filling in on a cleared screen, or nil to show it whole.
    var fillStart: Date?
    var showsOriginal = false
    var monitor = Monitor.tv
    var crtOn = false
    var poweredOn = true
    var message: CameraModel.Message?
    /// The zoom buttons to show on the border, or nil for none.
    var zoom: Zoom?
    var onSelectZoom: (Zoom) -> Void = { _ in }

    var body: some View {
        GeometryReader { geometry in
            let frame = TVGeometry.pictureFrame(inTV: geometry.size)
            ZStack(alignment: .topLeading) {
                Look.c64Border
                pictureLayer
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY)
                if crtOn {
                    Scanlines()
                }
            }
            .scaleEffect(x: 1, y: poweredOn ? 1 : 0.005)
            .brightness(poweredOn ? 0 : 0.5)
            .overlay(alignment: .top) {
                if let message {
                    MessageView(message: message)
                        .padding(.top, frame.minY + 8)
                }
            }
            .overlay(alignment: .bottom) {
                if let zoom {
                    ZoomPills(selection: zoom, onSelect: onSelectZoom)
                        .padding(.bottom, max(0, (geometry.size.height - frame.maxY - 34) / 2))
                }
            }
        }
        .clipped()
    }

    @ViewBuilder private var pictureLayer: some View {
        if showsOriginal {
            Image("SamplePhoto")
                .resizable()
                .accessibilityLabel("The original photo")
        } else {
            ZStack {
                if let fillStart {
                    TimelineView(.animation) { context in
                        let progress = context.date.timeIntervalSince(fillStart) / Self.fillDuration
                        c64Picture(picture)
                            .mask {
                                CellFill(progress: progress)
                            }
                    }
                } else {
                    c64Picture(picture)
                }
            }
            .grayscale(monitor.isMono ? 1 : 0)
            .colorMultiply(monitor.phosphor)
        }
    }

    private func c64Picture(_ name: String) -> some View {
        Image(name)
            .resizable()
            .interpolation(.none)
            .accessibilityLabel("C64 picture")
    }
}

/// Reveals a picture cell by cell, in the order a C64 stores a bitmap: 40 cells
/// across, then the next row of cells.
struct CellFill: View {
    /// From 0 (nothing shown) to 1 (all 1,000 cells shown).
    var progress: Double

    var body: some View {
        let cells = Int(min(max(progress, 0), 1) * 1000)
        Canvas { context, size in
            let cellWidth = size.width / 40
            let cellHeight = size.height / 25
            let fullRows = cells / 40
            let rest = cells % 40
            if fullRows > 0 {
                let rows = CGRect(x: 0, y: 0, width: size.width, height: CGFloat(fullRows) * cellHeight)
                context.fill(Path(rows), with: .color(.white))
            }
            if rest > 0 {
                let row = CGRect(
                    x: 0, y: CGFloat(fullRows) * cellHeight, width: CGFloat(rest) * cellWidth, height: cellHeight)
                context.fill(Path(row), with: .color(.white))
            }
        }
    }
}

/// The CRT layer's scanlines, one per C64 line. It is presentation only: the C64
/// picture underneath stays the same (plan, section 7).
struct Scanlines: View {
    var body: some View {
        let lines = Int(TVGeometry.visiblePixels.height)
        Canvas { context, size in
            let pitch = size.height / CGFloat(lines)
            for line in 0..<lines {
                let rect = CGRect(x: 0, y: (CGFloat(line) + 0.55) * pitch, width: size.width, height: pitch * 0.45)
                context.fill(Path(rect), with: .color(.black.opacity(0.22)))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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

/// The zoom buttons: below the TV in portrait, on its border in landscape.
struct ZoomPills: View {
    var selection: Zoom
    var onSelect: (Zoom) -> Void

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Zoom.allCases) { zoom in
                let isSelected = zoom == selection
                Button {
                    onSelect(zoom)
                } label: {
                    Text(zoom.label)
                        .font(.system(size: 12, weight: isSelected ? .heavy : .semibold))
                        .foregroundStyle(isSelected ? Look.ledOn : Look.pillInk)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Look.pill))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Zoom \(zoom.name)")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}
