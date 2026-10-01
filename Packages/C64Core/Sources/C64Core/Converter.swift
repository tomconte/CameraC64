import Foundation

/// Turns photos into pictures in a bitmap mode (plan, section 6).
///
/// For each cell, it tries every set of colours the cell can show: the 120
/// pairs of a hires cell, or the 1,820 sets of four of a multicolour cell,
/// where it then picks the background that gives the lowest total. The result
/// is optimal for the converter's measure of the error, which adds up, pixel by
/// pixel:
///
/// - the squared OKLab distance from the target to the closest colour the
///   pixel can take in its cell's set, or to a mix of two of the set's colours
///   that ordered dithering can show, as in Yliluoma's ordered dithering for
///   arbitrary palettes. Mixes are computed in linear light.
/// - for a mix, a penalty for the texture the dithering leaves, which comes
///   from the display model: on a TV, two colours of the same brightness blend
///   with almost no texture.
///
/// Each pixel then shows its best choice through a 4 × 4 Bayer pattern fixed
/// to the screen, so the dithering stays still from one viewfinder frame to
/// the next. For a monochrome monitor, the same search runs on brightness
/// only, with one colour for each brightness, a grey where there is one.
public struct Converter: Sendable {
    /// What the converter optimises for.
    public struct Settings: Hashable, Sendable {
        /// The colours the picture is shown in.
        public var palette: C64Palette
        /// The monitor the picture is made for: its blending decides how
        /// visible dithering is, and a monochrome monitor makes the search
        /// work on brightness only.
        public var display: DisplayModel
        /// How freely pixels mix two colours by dithering, from 0, never, to
        /// 1, whenever the mix is closer, whatever texture it leaves.
        public var dithering: Float
        /// The border colour, or nil for the colour most common along the
        /// picture's edges.
        public var border: C64Color?

        public init(
            palette: C64Palette = .colodore, display: DisplayModel = .tv, dithering: Float = 0.85,
            border: C64Color? = nil
        ) {
            precondition((0...1).contains(dithering), "Dithering goes from 0 to 1")
            self.palette = palette
            self.display = display
            self.dithering = dithering
            self.border = border
        }
    }

    /// The modes the converter can search: bitmaps whose pixels take any
    /// colour from maps of one cell size, and at most one shared background.
    public static func supports(_ spec: ModeSpec) -> Bool {
        guard spec.pixels == .bitmap, spec.maps.allSatisfy({ $0.values == .any }) else { return false }
        let shared = spec.maps.filter { $0.granularity == .global }
        let cells = Set(spec.maps.map(\.granularity)).subtracting([.global])
        guard shared.count <= 1, cells.count == 1, case .cell(let width, let height) = cells.first else {
            return false
        }
        return spec.width % width == 0 && spec.height % height == 0 && (2...4).contains(spec.maps.count)
    }

    public let spec: ModeSpec
    public let settings: Settings

    /// The mode's cells, in its pixels.
    let cellWidth: Int
    let cellHeight: Int
    let cellsAcross: Int
    let cellsDown: Int
    /// The index of the map that holds the shared background, if any.
    let backgroundMap: Int?
    /// The maps that hold a colour per cell.
    let cellMaps: [Int]
    /// How many colours a cell can show, the background included.
    let setSize: Int

    /// The colours the search considers: all 16, or one per brightness on a
    /// monochrome monitor.
    let candidates: [C64Color]
    /// For each pair of candidates i < j, in order, the two candidates.
    let pairFirst: [Int32]
    let pairSecond: [Int32]
    /// The pair number of candidates i and j at i × count + j, either way
    /// round.
    let pairNumbers: [Int32]
    /// How many mixing ratios dithering offers between two colours: 15, from
    /// 1/16 to 15/16 of the second, or none without dithering.
    let levels: Int
    /// Each candidate as the monitor shows it, as -2L, -2a, -2b and the
    /// squared length, so a squared distance takes three multiplications.
    let singleTerms: [Float]
    /// The same for each pair's mixes, `levels` per pair, with each mix's
    /// texture penalty added to its squared length.
    let mixTerms: [Float]

    public init(spec: ModeSpec, settings: Settings = Settings()) {
        precondition(
            Self.supports(spec), "The converter handles bitmaps with colours per cell and at most one background")
        self.spec = spec
        self.settings = settings
        backgroundMap = spec.maps.firstIndex { $0.granularity == .global }
        cellMaps = spec.maps.indices.filter { spec.maps[$0].granularity != .global }
        guard case .cell(let width, let height) = spec.maps[cellMaps[0]].granularity else {
            preconditionFailure("A cell map")
        }
        (cellWidth, cellHeight) = (width, height)
        (cellsAcross, cellsDown) = (spec.width / width, spec.height / height)
        setSize = spec.maps.count

        let (palette, display) = (settings.palette, settings.display)
        // What the search compares the target with: the colours as the monitor
        // shows them, or their brightness as a grey on a monochrome monitor.
        var shown: [LinearRGB]
        if display.isMonochrome {
            var greys: [UInt8: C64Color] = [:]
            for color in C64Color.allCases {
                let grey = display.untinted.color(of: color, palette: palette).r
                if let known = greys[grey], Self.greys.contains(known) || !Self.greys.contains(color) {
                    continue
                }
                greys[grey] = color
            }
            candidates = greys.values.sorted { $0.rawValue < $1.rawValue }
            shown = candidates.map { LinearRGB(display.untinted.color(of: $0, palette: palette)) }
        } else {
            candidates = C64Color.allCases
            shown = candidates.map { LinearRGB(palette[$0]) }
        }
        precondition(candidates.count >= setSize, "Fewer colours than a cell can show")

        let count = candidates.count
        var (first, second): ([Int32], [Int32]) = ([], [])
        var numbers = [Int32](repeating: -1, count: count * count)
        for i in 0..<count {
            for j in i + 1..<count {
                numbers[i * count + j] = Int32(first.count)
                numbers[j * count + i] = Int32(first.count)
                first.append(Int32(i))
                second.append(Int32(j))
            }
        }
        (pairFirst, pairSecond, pairNumbers) = (first, second, numbers)

        let monochrome = display.isMonochrome
        func terms(_ color: OKLab, penalty: Float = 0) -> [Float] {
            let (a, b) = monochrome ? (0, 0) : (color.a, color.b)
            return [-2 * color.l, -2 * a, -2 * b, color.l * color.l + a * a + b * b + penalty]
        }
        singleTerms = shown.flatMap { terms(OKLab($0)) }
        levels = settings.dithering > 0 ? 15 : 0
        var mixes: [Float] = []
        if levels > 0 {
            let patterns = display.patterns(pixelWidth: spec.pixelWidth)
            for (i, j) in zip(first, second) {
                // Each mix as the monitor shows it, with the texture it leaves
                // counting as error, less as dithering is allowed more.
                let pairMixes = display.mixes(
                    candidates[Int(i)], candidates[Int(j)], palette: palette, patterns: patterns)
                for mix in pairMixes {
                    mixes += terms(OKLab(mix.color), penalty: (1 - settings.dithering) * mix.texture)
                }
            }
        }
        mixTerms = mixes
    }

    /// Colours that look the same on a colour TV and in monochrome.
    private static let greys: Set<C64Color> = [.black, .darkGrey, .grey, .lightGrey, .white]

    /// Squared distances scale to 16 bits, with a squared distance of 1/4 at
    /// the top: anything that far off counts as equally wrong.
    private static let costScale: Float = 262_144

    // MARK: - Converting

    /// Converts a photo: prepares its target for the mode, then converts that.
    public func convert(
        _ photo: RGBImage, crop: Crop? = nil, tones: Tones = Tones(), keeping previous: Conversion? = nil
    ) -> Conversion {
        convert(Target(photo, for: spec, crop: crop, tones: tones), keeping: previous)
    }

    /// Converts a target with the mode's pixel grid.
    ///
    /// With the previous frame's conversion, as in the viewfinder, a cell
    /// keeps its colours, and the picture its background, unless the new ones
    /// are clearly better, so the picture does not flicker.
    public func convert(_ target: Target, keeping previous: Conversion? = nil) -> Conversion {
        precondition(target.width == spec.width && target.height == spec.height, "The target needs the mode's grid")
        let count = candidates.count
        let cellCount = cellsAcross * cellsDown
        let slots = backgroundMap == nil ? 1 : count
        let previousSets = previous.flatMap(previousSets(in:))

        // Search every cell: its best set for each background, or overall.
        var scores = [UInt32](repeating: .max, count: cellCount * slots)
        var sets = [UInt32](repeating: Self.noSet, count: cellCount * slots)
        var previousScores = [UInt32](repeating: .max, count: cellCount)
        scores.withUnsafeMutableBufferPointer { scores in
            sets.withUnsafeMutableBufferPointer { sets in
                previousScores.withUnsafeMutableBufferPointer { previousScores in
                    let shared = Shared((scores.baseAddress!, sets.baseAddress!, previousScores.baseAddress!))
                    concurrently(cellsDown) { cellRow in
                        let (scores, sets, previousScores) = shared.value
                        let workspace = Workspace(self, pixels: cellWidth * cellHeight)
                        defer { workspace.deallocate() }
                        for cell in cellRow * cellsAcross..<(cellRow + 1) * cellsAcross {
                            workspace.load(cell, of: target, for: self)
                            pairCosts(workspace)
                            search(workspace, scores: scores + cell * slots, sets: sets + cell * slots)
                            if let previousSets, previousSets[cell] != Self.noSet {
                                previousScores[cell] = score(of: previousSets[cell], workspace)
                            }
                        }
                    }
                }
            }
        }

        // The shared background with the lowest total, unless the previous
        // one is nearly as good.
        var slot = 0
        if backgroundMap != nil {
            var totals = [UInt64](repeating: 0, count: count)
            for cell in 0..<cellCount {
                for candidate in 0..<count {
                    totals[candidate] += UInt64(scores[cell * count + candidate])
                }
            }
            slot = totals.indices.min { totals[$0] < totals[$1] }!
            if let previous, let backgroundMap,
                let kept = candidates.firstIndex(of: previous.picture.colors[backgroundMap][0]),
                totals[kept] <= totals[slot] + totals[slot] / 32
            {
                slot = kept
            }
        }

        // Each cell's set, with the previous one kept unless clearly worse.
        let pixelsPerCell = UInt32(cellWidth * cellHeight)
        var chosen = (0..<cellCount).map { sets[$0 * slots + slot] }
        if let previousSets {
            for cell in 0..<cellCount where previousSets[cell] != Self.noSet {
                let best = scores[cell * slots + slot]
                let containsBackground = backgroundMap == nil || Self.members(previousSets[cell]).contains(slot)
                if containsBackground && previousScores[cell] <= best + best / 12 + pixelsPerCell * 32 {
                    chosen[cell] = previousSets[cell]
                }
            }
        }

        // Dither each pixel with its cell's colours.
        var values = [UInt8](repeating: 0, count: spec.width * spec.height)
        var colors = spec.maps.map { [C64Color](repeating: .black, count: spec.valueCount($0)) }
        if let backgroundMap {
            colors[backgroundMap][0] = candidates[slot]
        }
        var cellColors = [C64Color](repeating: .black, count: cellCount * cellMaps.count)
        values.withUnsafeMutableBufferPointer { values in
            cellColors.withUnsafeMutableBufferPointer { cellColors in
                let shared = Shared((values.baseAddress!, cellColors.baseAddress!))
                let (chosen, background) = (chosen, backgroundMap == nil ? nil : slot)
                concurrently(cellsDown) { cellRow in
                    let (values, cellColors) = shared.value
                    let workspace = Workspace(self, pixels: cellWidth * cellHeight)
                    defer { workspace.deallocate() }
                    for cell in cellRow * cellsAcross..<(cellRow + 1) * cellsAcross {
                        workspace.load(cell, of: target, for: self)
                        dither(
                            cell, set: chosen[cell], background: background, workspace,
                            values: values, cellColors: cellColors + cell * cellMaps.count)
                    }
                }
            }
        }
        for (index, map) in cellMaps.enumerated() {
            colors[map] = (0..<cellCount).map { cellColors[$0 * cellMaps.count + index] }
        }

        var picture = ModePicture(spec: spec, pixels: values, colors: colors, borderColor: .black)
        picture.borderColor = settings.border ?? picture.image().edgeColor
        do {
            return Conversion(picture: picture, frame: try C64Frame(picture))
        } catch {
            preconditionFailure("The converter broke the mode's limits: \(error)")
        }
    }

    // MARK: - Sets

    /// A set of up to four candidates, one per byte from the lowest, with
    /// unused bytes at 0xFF.
    static let noSet = UInt32.max

    private static func pack(_ members: [Int]) -> UInt32 {
        var packed = noSet
        for (index, member) in members.enumerated() {
            packed &= ~(0xFF << (8 * index))
            packed |= UInt32(member) << (8 * index)
        }
        return packed
    }

    static func members(_ set: UInt32) -> [Int] {
        (0..<4).map { Int((set >> (8 * $0)) & 0xFF) }.filter { $0 != 0xFF }
    }

    /// Each cell's set in a previous conversion, if it can be kept: from
    /// this converter's mode, with colours among the candidates.
    private func previousSets(in previous: Conversion) -> [UInt32]? {
        let picture = previous.picture
        guard picture.spec == spec else { return nil }
        return (0..<cellsAcross * cellsDown).map { cell in
            var members: [Int] = []
            for (index, map) in spec.maps.enumerated() {
                let color = picture.colors[index][map.granularity == .global ? 0 : cell]
                guard let candidate = candidates.firstIndex(of: color), !members.contains(candidate) else {
                    return Self.noSet
                }
                members.append(candidate)
            }
            return Self.pack(members.sorted())
        }
    }

    // MARK: - The search

    /// Scratch memory for one cell at a time.
    struct Workspace {
        let pixels: Int
        /// The cell's target, and each pixel's squared length.
        let l: UnsafeMutablePointer<Float>
        let a: UnsafeMutablePointer<Float>
        let b: UnsafeMutablePointer<Float>
        let lengths: UnsafeMutablePointer<Float>
        /// For each candidate, then each pixel: the squared distance, less the
        /// pixel's squared length.
        let singles: UnsafeMutablePointer<Float>
        /// For each pair, then each pixel: the cost of the pixel's best choice
        /// among the pair's two colours and their mixes.
        let rows: UnsafeMutablePointer<UInt16>
        let best: UnsafeMutablePointer<Float>
        let partial: UnsafeMutablePointer<UInt16>

        init(_ converter: Converter, pixels: Int) {
            self.pixels = pixels
            l = .allocate(capacity: pixels)
            a = .allocate(capacity: pixels)
            b = .allocate(capacity: pixels)
            lengths = .allocate(capacity: pixels)
            singles = .allocate(capacity: converter.candidates.count * pixels)
            rows = .allocate(capacity: converter.pairFirst.count * pixels)
            best = .allocate(capacity: pixels)
            partial = .allocate(capacity: pixels)
        }

        func deallocate() {
            for pointer in [l, a, b, lengths, singles, best] {
                pointer.deallocate()
            }
            rows.deallocate()
            partial.deallocate()
        }

        /// Loads a cell's target and each candidate's distance to it.
        func load(_ cell: Int, of target: Target, for converter: Converter) {
            let (cellWidth, cellHeight) = (converter.cellWidth, converter.cellHeight)
            let left = cell % converter.cellsAcross * cellWidth
            let top = cell / converter.cellsAcross * cellHeight
            let monochrome = converter.settings.display.isMonochrome
            target.colors.withUnsafeBufferPointer { colors in
                for row in 0..<cellHeight {
                    for column in 0..<cellWidth {
                        let color = colors[(top + row) * target.width + left + column]
                        let pixel = row * cellWidth + column
                        l[pixel] = color.l
                        a[pixel] = monochrome ? 0 : color.a
                        b[pixel] = monochrome ? 0 : color.b
                        lengths[pixel] = l[pixel] * l[pixel] + a[pixel] * a[pixel] + b[pixel] * b[pixel]
                    }
                }
            }
            converter.singleTerms.withUnsafeBufferPointer { terms in
                for candidate in 0..<converter.candidates.count {
                    let term = terms.baseAddress! + candidate * 4
                    let (tl, ta, tb, length) = (term[0], term[1], term[2], term[3])
                    let distances = singles + candidate * pixels
                    for pixel in 0..<pixels {
                        distances[pixel] = length + l[pixel] * tl + a[pixel] * ta + b[pixel] * tb
                    }
                }
            }
        }
    }

    /// Each pair's cost for each of the cell's pixels: its better colour, or
    /// its best mix, whichever is closer.
    func pairCosts(_ workspace: Workspace) {
        let pixels = workspace.pixels
        let (l, a, b, best) = (workspace.l, workspace.a, workspace.b, workspace.best)
        mixTerms.withUnsafeBufferPointer { mixTerms in
            for pair in 0..<pairFirst.count {
                let first = workspace.singles + Int(pairFirst[pair]) * pixels
                let second = workspace.singles + Int(pairSecond[pair]) * pixels
                for pixel in 0..<pixels {
                    best[pixel] = min(first[pixel], second[pixel])
                }
                for level in 0..<levels {
                    let term = mixTerms.baseAddress! + (pair * levels + level) * 4
                    let (tl, ta, tb, length) = (term[0], term[1], term[2], term[3])
                    for pixel in 0..<pixels {
                        best[pixel] = min(best[pixel], length + l[pixel] * tl + a[pixel] * ta + b[pixel] * tb)
                    }
                }
                let row = workspace.rows + pair * pixels
                for pixel in 0..<pixels {
                    let cost = (best[pixel] + workspace.lengths[pixel]) * Self.costScale
                    // Rounding errors can make a cost a little negative.
                    row[pixel] = cost < 65535 ? (cost > 0 ? UInt16(cost) : 0) : 65535
                }
            }
        }
    }

    /// Tries every set of colours for the cell: keeps the best set
    /// containing each candidate as the background, or the best overall.
    func search(
        _ workspace: Workspace, scores: UnsafeMutablePointer<UInt32>, sets: UnsafeMutablePointer<UInt32>
    ) {
        let (count, pixels, rows, partial) = (candidates.count, workspace.pixels, workspace.rows, workspace.partial)
        let shared = backgroundMap != nil
        func row(_ i: Int, _ j: Int) -> UnsafeMutablePointer<UInt16> {
            rows + Int(pairNumbers[i * count + j]) * pixels
        }
        // Keeps a set if it beats the best so far overall, or the best so far
        // with one of its members as the background.
        func record(_ score: UInt32, _ set: UInt32, _ member: Int) {
            if score < scores[member] {
                scores[member] = score
                sets[member] = set
            }
        }
        switch setSize {
        case 2:
            for i in 0..<count {
                for j in i + 1..<count {
                    let ij = row(i, j)
                    var score: UInt32 = 0
                    for pixel in 0..<pixels {
                        score &+= UInt32(ij[pixel])
                    }
                    let set = UInt32(i) | UInt32(j) << 8 | 0xFFFF_0000
                    if shared {
                        record(score, set, i)
                        record(score, set, j)
                    } else {
                        record(score, set, 0)
                    }
                }
            }
        case 3:
            for i in 0..<count {
                for j in i + 1..<count {
                    let ij = row(i, j)
                    for k in j + 1..<count {
                        let (ik, jk) = (row(i, k), row(j, k))
                        var score: UInt32 = 0
                        for pixel in 0..<pixels {
                            score &+= UInt32(min(ij[pixel], min(ik[pixel], jk[pixel])))
                        }
                        let set = UInt32(i) | UInt32(j) << 8 | UInt32(k) << 16 | 0xFF00_0000
                        if shared {
                            record(score, set, i)
                            record(score, set, j)
                            record(score, set, k)
                        } else {
                            record(score, set, 0)
                        }
                    }
                }
            }
        default:
            for i in 0..<count {
                for j in i + 1..<count {
                    let ij = row(i, j)
                    for k in j + 1..<count {
                        let (ik, jk) = (row(i, k), row(j, k))
                        for pixel in 0..<pixels {
                            partial[pixel] = min(ij[pixel], min(ik[pixel], jk[pixel]))
                        }
                        for m in k + 1..<count {
                            let (im, jm, km) = (row(i, m), row(j, m), row(k, m))
                            var score: UInt32 = 0
                            for pixel in 0..<pixels {
                                score &+= UInt32(min(partial[pixel], min(im[pixel], min(jm[pixel], km[pixel]))))
                            }
                            let set = UInt32(i) | UInt32(j) << 8 | UInt32(k) << 16 | UInt32(m) << 24
                            if shared {
                                record(score, set, i)
                                record(score, set, j)
                                record(score, set, k)
                                record(score, set, m)
                            } else {
                                record(score, set, 0)
                            }
                        }
                    }
                }
            }
        }
    }

    /// The cost of one set of colours for the cell.
    func score(of set: UInt32, _ workspace: Workspace) -> UInt32 {
        let members = Self.members(set)
        let (count, pixels) = (candidates.count, workspace.pixels)
        var score: UInt32 = 0
        for pixel in 0..<pixels {
            var best = UInt16.max
            for (index, i) in members.enumerated() {
                for j in members[(index + 1)...] {
                    best = min(best, workspace.rows[Int(pairNumbers[i * count + j]) * pixels + pixel])
                }
            }
            score += UInt32(best)
        }
        return score
    }

    // MARK: - Dithering

    /// Gives each of the cell's pixels its value: the colour of its best
    /// choice in the set, or for a mix, one of the two colours as the Bayer
    /// pattern decides. Writes the cell's colours for each cell map.
    private func dither(
        _ cell: Int, set: UInt32, background: Int?, _ workspace: Workspace, values: UnsafeMutablePointer<UInt8>,
        cellColors: UnsafeMutablePointer<C64Color>
    ) {
        let members = Self.members(set)
        // The background takes its own map; the cell maps take the other
        // colours in order.
        var maps = [Int](repeating: 0, count: candidates.count)
        var cellMapIndex = 0
        for member in members {
            if member == background, let backgroundMap {
                maps[member] = backgroundMap
            } else {
                maps[member] = cellMaps[cellMapIndex]
                cellColors[cellMapIndex] = candidates[member]
                cellMapIndex += 1
            }
        }
        let (l, a, b, pixels) = (workspace.l, workspace.a, workspace.b, workspace.pixels)
        let left = cell % cellsAcross * cellWidth
        let top = cell / cellsAcross * cellHeight
        mixTerms.withUnsafeBufferPointer { mixTerms in
            for pixel in 0..<pixels {
                var best = Float.infinity
                var choice = (first: members[0], second: members[0], level: 0)
                for member in members {
                    let cost = workspace.singles[member * pixels + pixel]
                    if cost < best {
                        best = cost
                        choice = (member, member, 0)
                    }
                }
                for (index, i) in members.enumerated() {
                    for j in members[(index + 1)...] {
                        let pair = Int(pairNumbers[i * candidates.count + j])
                        for level in stride(from: 1, through: levels, by: 1) {
                            let term = mixTerms.baseAddress! + (pair * levels + level - 1) * 4
                            let cost = term[3] + l[pixel] * term[0] + a[pixel] * term[1] + b[pixel] * term[2]
                            if cost < best {
                                best = cost
                                choice = (i, j, level)
                            }
                        }
                    }
                }
                let (x, y) = (left + pixel % cellWidth, top + pixel / cellWidth)
                let shown = Bayer.showsSecond(level: choice.level, x: x, y: y) ? choice.second : choice.first
                values[y * spec.width + x] = UInt8(maps[shown])
            }
        }
    }
}

/// A converted picture, and the C64 memory that shows it.
public struct Conversion: Hashable, Sendable {
    public let picture: ModePicture
    public let frame: C64Frame
}
