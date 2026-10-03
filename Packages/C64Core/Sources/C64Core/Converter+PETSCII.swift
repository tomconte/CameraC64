import Foundation

/// PETSCII: the converter's search for text in the C64's own characters
/// (plan, section 6).
///
/// Each cell shows one character, in one colour, on a background the whole
/// picture shares. For each background, each cell tries the 256 characters of
/// each of the character ROM's two sets in each of the other colours; the set
/// and background with the lowest total win, as the background does in
/// multicolour, and each cell takes its best character and colour for them.
/// The settings can leave only the graphics characters to try, for the classic
/// PETSCII look.
///
/// The characters' patterns are PETSCII's only dithering, so they are judged
/// by how they look from a distance through the monitor. A cell's error is
/// the squared OKLab distance, pixel by pixel, between the cell as the
/// monitor shows it and its target, both blurred as the eye blurs them,
/// brightness less than colour, as in the quality benchmark. Without the
/// blur, many characters would score alike, and the search would pick noisy
/// ones.
///
/// Done plainly, that is about 30 times the work of hires, so the search uses
/// a model of the error. The converter works out once how each character
/// looks in each pair of colours, and fits that to the character's own
/// pattern as the eye sees it: its lightness to the pattern in brightness, its
/// colour to the pattern in colour. The model's error for any character and
/// colours then takes 6 multiplications, or 2 for a monochrome monitor, and it
/// picks the set and background. It differs from the exact error only by what
/// the fit misses, whose length is known, so it also bounds the exact error
/// from below. Each cell then takes the character and colour with the lowest
/// exact error, which is worked out only where the bound could beat the best
/// so far: about a dozen times a cell. The sets share most of their
/// characters, and nearly every character's inverse is in its set too,
/// showing the same in the opposite colours, so 153 shapes stand for all 512
/// characters, and 60 for the 130 of `CharacterROM.Selection.graphics`.
extension Converter {
    /// How far the eye blurs brightness and colour when it judges a character,
    /// in hires pixels: as far as the quality benchmark's eye, which looks at
    /// a phone showing a point per C64 pixel from 30 cm (Tools/README.md).
    static let eyeLumaBlur = 1.0
    static let eyeChromaBlur = 2.0

    /// What the PETSCII search knows before it sees a picture: how each
    /// character the picture may use looks in each pair of colours, through
    /// the monitor and to the eye. It never changes once made, so threads
    /// share it.
    final class CharacterTables: @unchecked Sendable {
        /// A character, as the shape that shows it: the shape itself, or its
        /// inverse, which in one pair of colours looks like the shape in the
        /// opposite pair.
        struct Code: Hashable, Sendable {
            var shape: Int
            var inverted: Bool
        }

        /// The character ROM's sets that have characters the picture may use,
        /// in `CharacterROM.Set` order.
        let sets: [CharacterROM.Set]
        /// Each of those sets' 256 characters, or nil for those the picture
        /// may not use.
        let codes: [[Code?]]
        let shapeCount: Int
        /// For each shape, the sets that have it, and those that have its
        /// inverse: a bit for each of `sets`, bit 0 for the first.
        let directSets: [UInt8]
        let inverseSets: [UInt8]
        /// How many colours each cell chooses from.
        let count: Int
        /// One slot for each foreground and background, at foreground ×
        /// `count` + background. Slots with the same colour twice are unused.
        let slots: Int
        /// For brightness, then colour, then each of a cell's 64 pixels, a
        /// value for each shape: how much of the foreground the eye sees at
        /// that pixel, through the monitor.
        let basis: UnsafeMutablePointer<Float>
        /// For each shape, `rows` rows of a value per slot: how the shape looks
        /// to the eye in those colours, as the terms of a cell's error. The
        /// first row is the squared length of its appearance in OKLab. The
        /// next six, times -2, are its mean lightness, a and b, the slope of
        /// its lightness along the brightness basis, and those of its a and b
        /// along the colour basis. The last is the length of what that fit
        /// misses.
        let terms: UnsafeMutablePointer<Float>
        /// The same, with the slots at background × `count` + foreground.
        let columns: UnsafeMutablePointer<Float>
        static let rows = 8
        /// For each shape, the inverse of the Gram matrix of a constant and its
        /// brightness basis, then of a constant and its colour basis: three
        /// values each, as the matrices are symmetric.
        let inverseGrams: [Float]

        /// For each shape, 64 values for brightness, then 64 for colour: how
        /// much of the foreground the monitor shows at each pixel.
        private let shown: [Float]
        /// Each candidate's PAL signal, and its colour on the monitor.
        private let signals: [YUV]
        private let colors: [RGB]
        /// Whether the monitor shows each pixel as it is, and whether it shows
        /// brightness only.
        private let sharp: Bool
        private let monochrome: Bool

        init(
            candidates: [C64Color], palette: C64Palette, display: DisplayModel, characters: CharacterROM.Selection
        ) {
            // Each character the picture may use as a 64-bit number, a line
            // per byte from the top, and its shape: itself or its inverse,
            // whichever is lower.
            let sets = CharacterROM.Set.allCases.filter { !characters.codes(in: $0).isEmpty }
            var patterns: [UInt64] = []
            var shapes: [UInt64: Int] = [:]
            var codes: [[Code?]] = []
            for set in sets {
                let bytes = set.characters
                var setCodes = [Code?](repeating: nil, count: 256)
                for code in characters.codes(in: set) {
                    let pattern = (0..<8).reduce(UInt64(0)) { $0 << 8 | UInt64(bytes[code * 8 + $1]) }
                    let shape = min(pattern, ~pattern)
                    if shapes[shape] == nil {
                        shapes[shape] = patterns.count
                        patterns.append(shape)
                    }
                    setCodes[code] = Code(shape: shapes[shape]!, inverted: pattern != shape)
                }
                codes.append(setCodes)
            }
            var directSets = [UInt8](repeating: 0, count: patterns.count)
            var inverseSets = directSets
            for (set, setCodes) in codes.enumerated() {
                for case let code? in setCodes {
                    if code.inverted {
                        inverseSets[code.shape] |= 1 << set
                    } else {
                        directSets[code.shape] |= 1 << set
                    }
                }
            }
            let (shapeCount, count) = (patterns.count, candidates.count)
            let slots = count * count
            self.sets = sets
            self.codes = codes
            self.directSets = directSets
            self.inverseSets = inverseSets
            self.shapeCount = shapeCount
            self.count = count
            self.slots = slots

            // Each shape's pixels: the share of the foreground the monitor
            // shows in brightness and in colour, and the eye sees after it.
            let monitorLuma = CellBlur(gaussian: display.lumaBlur)
            let monitorChroma = CellBlur(gaussian: display.chromaBlur)
            let delayLine = display.delayLine ? CellBlur.delayLine : CellBlur.none
            let (eyeLuma, eyeChroma) = (CellBlur.eyeLuma, CellBlur.eyeChroma)
            var shown: [Float] = []
            var seen = [[Float]](repeating: [], count: shapeCount)
            for (shape, pattern) in patterns.enumerated() {
                let mask = (0..<64).map { Float((pattern >> UInt64(63 - $0)) & 1) }
                var luma = monitorLuma.applied(to: mask, across: true)
                var chroma = delayLine.applied(to: monitorChroma.applied(to: mask, across: true), across: false)
                shown += luma + chroma
                luma = eyeLuma.applied(to: eyeLuma.applied(to: luma, across: true), across: false)
                chroma = eyeChroma.applied(to: eyeChroma.applied(to: chroma, across: true), across: false)
                seen[shape] = luma + chroma
            }
            self.shown = shown
            basis = .allocate(capacity: 128 * shapeCount)
            for (shape, values) in seen.enumerated() {
                for (index, value) in values.enumerated() {
                    basis[index * shapeCount + shape] = value
                }
            }

            // Each shape's terms in every pair of colours: its appearance,
            // fitted to its basis by least squares.
            let rows = Self.rows
            terms = .allocate(capacity: shapeCount * rows * slots)
            columns = .allocate(capacity: shapeCount * rows * slots)
            sharp = display.lumaBlur == 0 && display.chromaBlur == 0 && !display.delayLine
            monochrome = display.isMonochrome
            signals = candidates.map { palette.signals[Int($0.rawValue)] }
            colors = candidates.map { display.untinted.color(of: $0, palette: palette) }
            let fits = seen.map { LeastSquares(Array($0[0..<64]), Array($0[64..<128])) }
            inverseGrams = fits.flatMap { fit in
                [
                    fit.lumaInverse.0, fit.lumaInverse.1, fit.lumaInverse.3, fit.chromaInverse.0, fit.chromaInverse.1,
                    fit.chromaInverse.3,
                ].map(Float.init)
            }
            concurrently(shapeCount) { shape in
                let (terms, columns) = (self.terms + shape * rows * slots, self.columns + shape * rows * slots)
                let fit = fits[shape]
                let eye = EyeView()
                defer { eye.deallocate() }
                for foreground in 0..<count {
                    for background in 0..<count {
                        let (slot, column) = (foreground * count + background, background * count + foreground)
                        guard foreground != background else {
                            terms[slot] = .infinity
                            columns[column] = .infinity
                            for row in 1..<rows {
                                terms[row * slots + slot] = 0
                                columns[row * slots + column] = 0
                            }
                            continue
                        }
                        fit.fit(self.look(shape, foreground, background, eye: eye), into: terms + slot, stride: slots)
                        for row in 0..<rows {
                            columns[row * slots + column] = terms[row * slots + slot]
                        }
                    }
                }
            }
        }

        deinit {
            basis.deallocate()
            terms.deallocate()
            columns.deallocate()
        }

        /// How a shape looks to the eye in a foreground and background, given
        /// as indices of the candidates: its lightness, a and b at each of its
        /// pixels, in the eye's memory.
        func look(_ shape: Int, _ foreground: Int, _ background: Int, eye: EyeView) -> UnsafeMutablePointer<Float> {
            // Each pixel's light as the monitor shows it, as DisplayModel.show
            // does.
            let shown = shape * 128
            let (one, two) = (signals[background], signals[foreground])
            for pixel in 0..<64 {
                let rgb: RGB
                if sharp {
                    rgb = self.shown[shown + pixel] == 0 ? colors[background] : colors[foreground]
                } else {
                    let y = Float(one.y + (two.y - one.y) * Double(self.shown[shown + pixel]))
                    if monochrome {
                        let grey = DisplayModel.signalTable[DisplayModel.tableIndex(y)]
                        rgb = RGB(grey, grey, grey)
                    } else {
                        let share = Double(self.shown[shown + 64 + pixel])
                        let (u, v) = (Float(one.u + (two.u - one.u) * share), Float(one.v + (two.v - one.v) * share))
                        rgb = RGB(
                            DisplayModel.signalTable[DisplayModel.tableIndex(y + 1.140 * v)],
                            DisplayModel.signalTable[DisplayModel.tableIndex(y - 0.396 * u - 0.581 * v)],
                            DisplayModel.signalTable[DisplayModel.tableIndex(y + 2.029 * u)])
                    }
                }
                eye.light(rgb, at: pixel)
            }
            return eye.look()
        }
    }

    // MARK: - Converting

    /// Converts a target in PETSCII. With the previous frame's conversion, as
    /// in the viewfinder, the picture keeps its set and background, and a
    /// cell its character and colour, unless new ones are clearly better.
    func convertCharacters(
        _ target: Target, tables: CharacterTables, keeping previous: Conversion?
    ) -> Conversion {
        let (count, shapeCount) = (tables.count, tables.shapeCount)
        let (cellCount, setCount) = (C64Frame.cellCount, tables.codes.count)
        let monochrome = settings.display.isMonochrome

        // Each cell's target as the eye sees it: its pixels' lightness, a and
        // b, their sums and squared length, and their correlations with each
        // shape's basis.
        let views = UnsafeMutablePointer<Float>.allocate(capacity: cellCount * 192)
        let sums = UnsafeMutablePointer<Float>.allocate(capacity: cellCount * 4)
        let correlations = UnsafeMutablePointer<Float>.allocate(capacity: cellCount * 3 * shapeCount)
        // Each cell's lowest error for each set and background.
        let bests = UnsafeMutablePointer<Float>.allocate(capacity: cellCount * setCount * count)
        defer {
            views.deallocate()
            sums.deallocate()
            correlations.deallocate()
            bests.deallocate()
        }
        let shared = Shared((views, sums, correlations, bests))
        concurrently(cellCount, inChunksOf: 8) { cells in
            let (views, sums, correlations, bests) = shared.value
            let eye = EyeView()
            let errors = UnsafeMutablePointer<Float>.allocate(capacity: tables.slots)
            // The lowest error so far for each background, among shapes in
            // each combination of sets, as they are and inverted.
            let lowest = UnsafeMutablePointer<Float>.allocate(capacity: 8 * count)
            defer {
                eye.deallocate()
                errors.deallocate()
                lowest.deallocate()
            }
            for cell in cells {
                let sum = sums + cell * 4
                eye.see(cell, of: target, monochrome: monochrome, sum: sum)
                (views + cell * 192).update(from: eye.seen, count: 192)
                let correlation = correlations + cell * 3 * shapeCount
                eye.correlate(with: tables.basis, shapeCount: shapeCount, into: correlation)
                lowest.initialize(repeating: .infinity, count: 8 * count)
                for shape in 0..<shapeCount {
                    Self.errors(
                        tables.terms + shape * CharacterTables.rows * tables.slots, stride: tables.slots,
                        slots: 0..<tables.slots, sum: sum, correlation: correlation + shape, shapeCount: shapeCount,
                        monochrome: monochrome, into: errors)
                    // As it is, the shape is a character on each background,
                    // in any foreground.
                    let direct = Int(tables.directSets[shape])
                    if direct != 0 {
                        let lowest = lowest + direct * count
                        for foreground in 0..<count {
                            let row = errors + foreground * count
                            for background in 0..<count {
                                lowest[background] = min(lowest[background], row[background])
                            }
                        }
                    }
                    // Inverted, it is a character on what was the foreground.
                    let inverse = Int(tables.inverseSets[shape])
                    if inverse != 0 {
                        let lowest = lowest + (4 + inverse) * count
                        for foreground in 0..<count {
                            lowest[foreground] = min(
                                lowest[foreground], Self.lowest(errors + foreground * count, count))
                        }
                    }
                }
                for set in 0..<setCount {
                    let best = bests + (cell * setCount + set) * count
                    for background in 0..<count {
                        var error = Float.infinity
                        for sets in 1..<4 where sets & 1 << set != 0 {
                            error = min(
                                error, lowest[sets * count + background], lowest[(4 + sets) * count + background])
                        }
                        best[background] = error + sum[3]
                    }
                }
            }
        }

        // The set and background with the lowest total, unless the previous
        // ones are nearly as good.
        var totals = [Double](repeating: 0, count: setCount * count)
        for cell in 0..<cellCount {
            for choice in totals.indices {
                totals[choice] += Double(bests[cell * setCount * count + choice])
            }
        }
        var choice = totals.indices.min { totals[$0] < totals[$1] }!
        let kept = previous.flatMap { previousChoice(in: $0, tables: tables) }
        if let kept, totals[kept.set * count + kept.background] <= totals[choice] + totals[choice] / 32 {
            choice = kept.set * count + kept.background
        }
        let (set, background) = (choice / count, choice % count)

        // For the set and background, how each character looks in each
        // foreground, exactly: its exact errors decide each cell. Inverted, a
        // shape shows the background colour, on the foreground.
        let codes = tables.codes[set]
        let used = (0..<shapeCount * 2).map { index in
            (index % 2 == 0 ? tables.directSets : tables.inverseSets)[index / 2] & 1 << set != 0
        }
        let looks = UnsafeMutablePointer<Float>.allocate(capacity: shapeCount * 2 * count * 192)
        defer { looks.deallocate() }
        // The terms of every shape, as it is and inverted, with this
        // background, next to each other, so the search reads them in order.
        let rows = CharacterTables.rows
        let onBackground = UnsafeMutablePointer<Float>.allocate(capacity: shapeCount * 2 * rows * count)
        defer { onBackground.deallocate() }
        for index in 0..<shapeCount * 2 where used[index] {
            let terms = (index % 2 == 1 ? tables.terms : tables.columns) + index / 2 * rows * tables.slots
            for row in 0..<rows {
                (onBackground + (index * rows + row) * count).update(
                    from: terms + row * tables.slots + background * count, count: count)
            }
        }
        let sharedLooks = Shared(looks)
        concurrently(shapeCount) { shape in
            let looks = sharedLooks.value
            let eye = EyeView()
            defer { eye.deallocate() }
            for inverted in 0..<2 where used[shape * 2 + inverted] {
                for foreground in 0..<count where foreground != background {
                    let look =
                        inverted == 1
                        ? tables.look(shape, background, foreground, eye: eye)
                        : tables.look(shape, foreground, background, eye: eye)
                    (looks + ((shape * 2 + inverted) * count + foreground) * 192).update(from: look, count: 192)
                }
            }
        }

        // Each cell's best character and colour, with the previous ones kept
        // unless clearly worse. The model's best gets its exact error first.
        // The model's error differs from the exact one only by what its fit
        // misses, which has a known length, so it also bounds the exact error
        // from below: every other character whose bound beats the best so far
        // gets its exact error too. Each cell so gets the character and colour
        // with the lowest exact error, the lowest code and foreground winning
        // a tie.
        var characters = [Int](repeating: 0, count: cellCount)
        var foregrounds = [Int](repeating: 0, count: cellCount)
        let keptCells = kept.flatMap { $0.set == set && $0.background == background ? $0.cells : nil }
        // Each shape, as it is or inverted, by its first code in the set.
        let firstCodes = (0..<shapeCount * 2).map { index in
            codes.firstIndex { $0.map { $0.shape * 2 + ($0.inverted ? 1 : 0) } == index } ?? -1
        }
        let shapes = firstCodes.indices.filter { firstCodes[$0] >= 0 }
        characters.withUnsafeMutableBufferPointer { characters in
            foregrounds.withUnsafeMutableBufferPointer { foregrounds in
                let shared = Shared(
                    (characters.baseAddress!, foregrounds.baseAddress!, views, sums, correlations, looks, onBackground))
                concurrently(cellCount, inChunksOf: 8) { cells in
                    let (characters, foregrounds, views, sums, correlations, looks, onBackground) = shared.value
                    let errors = UnsafeMutablePointer<Float>.allocate(capacity: shapeCount * 2 * count)
                    // How far each shape's basis is from the cell's target:
                    // the length of what the model cannot see of it.
                    let unseen = UnsafeMutablePointer<Float>.allocate(capacity: shapeCount)
                    defer {
                        errors.deallocate()
                        unseen.deallocate()
                    }
                    for cell in cells {
                        let (sum, correlation) = (sums + cell * 4, correlations + cell * 3 * shapeCount)
                        let view = views + cell * 192
                        // The model's errors, and its best.
                        var (lowest, lowestAppearance) = (Float.infinity, 0)
                        for index in shapes {
                            let errors = errors + index * count
                            Self.errors(
                                onBackground + index * rows * count, stride: count, slots: 0..<count, sum: sum,
                                correlation: correlation + index / 2, shapeCount: shapeCount,
                                monochrome: monochrome, into: errors)
                            for foreground in 0..<count {
                                errors[foreground] += sum[3]
                            }
                            for foreground in 0..<count where errors[foreground] < lowest {
                                (lowest, lowestAppearance) = (errors[foreground], index * count + foreground)
                            }
                        }
                        var (best, bestCode, bestForeground) = (Float.infinity, 0, 0)
                        func consider(_ code: Int, _ appearance: Int) {
                            let error = Self.distance(looks + appearance * 192, view)
                            let foreground = appearance % count
                            if error < best || error == best && (code, foreground) < (bestCode, bestForeground) {
                                (best, bestCode, bestForeground) = (error, code, foreground)
                            }
                        }
                        consider(firstCodes[lowestAppearance / count], lowestAppearance)
                        for shape in 0..<shapeCount {
                            unseen[shape] = Self.unseen(
                                of: sum, correlation: correlation + shape, shapeCount: shapeCount,
                                inverseGrams: tables.inverseGrams, shape: shape)
                        }
                        // The model's errors become bounds, in place. Most
                        // shapes have none below the best, which takes a
                        // little slack for rounding.
                        for index in shapes {
                            let (bounds, missed) = (errors + index * count, onBackground + (index * rows + 7) * count)
                            let unseen = 2 * unseen[index / 2]
                            var lowestBound = Float.infinity
                            for foreground in 0..<count {
                                bounds[foreground] -= missed[foreground] * unseen
                                lowestBound = min(lowestBound, bounds[foreground])
                            }
                            guard lowestBound < best + 1e-4 * (best + 1) else { continue }
                            for foreground in 0..<count
                            where foreground != background && bounds[foreground] < best + 1e-4 * (best + 1) {
                                consider(firstCodes[index], index * count + foreground)
                            }
                        }
                        characters[cell] = bestCode
                        foregrounds[cell] = bestForeground
                        guard let previous = keptCells?[cell], previous.foreground != background,
                            let character = codes[previous.code]
                        else { continue }
                        let appearance =
                            (character.shape * 2 + (character.inverted ? 1 : 0)) * count + previous.foreground
                        // The margin grows by a squared distance of 1/8192 per
                        // pixel, as in the bitmap modes.
                        if Self.distance(looks + appearance * 192, view) <= best + best / 12 + 64 / 8192 {
                            characters[cell] = previous.code
                            foregrounds[cell] = previous.foreground
                        }
                    }
                }
            }
        }

        // The picture: each cell's character in its colour.
        let characterSet = tables.sets[set].characters
        var values = [UInt8](repeating: 0, count: spec.width * spec.height)
        for cell in 0..<cellCount {
            let (left, top) = (cell % 40 * 8, cell / 40 * 8)
            for line in 0..<8 {
                let bits = characterSet[characters[cell] * 8 + line]
                for column in 0..<8 {
                    values[(top + line) * spec.width + left + column] = bits >> (7 - column) & 1
                }
            }
        }
        let colors = [[candidates[background]], foregrounds.map { candidates[$0] }]
        var picture = ModePicture(spec: spec, pixels: values, colors: colors, borderColor: .black)
        picture.borderColor = settings.border ?? picture.image().edgeColor
        do {
            return Conversion(picture: picture, frame: try C64Frame(picture))
        } catch {
            preconditionFailure("The converter broke the mode's limits: \(error)")
        }
    }

    /// A cell's errors, less its target's squared length, for a shape in a
    /// range of slots: 6 multiplications each, or 2 on a monochrome monitor,
    /// where only lightness counts. The shape's correlations are `shapeCount`
    /// apart.
    static func errors(
        _ terms: UnsafePointer<Float>, stride: Int, slots: Range<Int>, sum: UnsafePointer<Float>,
        correlation: UnsafePointer<Float>, shapeCount: Int, monochrome: Bool, into errors: UnsafeMutablePointer<Float>
    ) {
        let (sl, sa, sb) = (sum[0], sum[1], sum[2])
        let (cl, ca, cb) = (correlation[0], correlation[shapeCount], correlation[2 * shapeCount])
        let terms = terms + slots.lowerBound
        let (length, meanL, meanA, meanB) = (terms, terms + stride, terms + 2 * stride, terms + 3 * stride)
        let (slopeL, slopeA, slopeB) = (terms + 4 * stride, terms + 5 * stride, terms + 6 * stride)
        if monochrome {
            for slot in 0..<slots.count {
                errors[slot] = length[slot] + meanL[slot] * sl + slopeL[slot] * cl
            }
        } else {
            for slot in 0..<slots.count {
                errors[slot] =
                    length[slot] + meanL[slot] * sl + meanA[slot] * sa + meanB[slot] * sb + slopeL[slot] * cl
                    + slopeA[slot] * ca + slopeB[slot] * cb
            }
        }
    }

    /// The length of the part of a cell's target that lies outside a shape's
    /// basis, in brightness for its lightness and in colour for its a and b:
    /// its squared length less that of its projection on the basis.
    static func unseen(
        of sum: UnsafePointer<Float>, correlation: UnsafePointer<Float>, shapeCount: Int, inverseGrams: [Float],
        shape: Int
    ) -> Float {
        var seen: Float = 0
        for component in 0..<3 {
            let (total, product) = (sum[component], correlation[component * shapeCount])
            let inverse = shape * 6 + (component == 0 ? 0 : 3)
            seen +=
                inverseGrams[inverse] * total * total + 2 * inverseGrams[inverse + 1] * total * product
                + inverseGrams[inverse + 2] * product * product
        }
        return max(sum[3] - seen, 0).squareRoot()
    }

    /// The squared distance between two cells' appearances: lightness, a and b
    /// for each pixel. Eight sums at a time, so the additions do not wait on
    /// each other.
    static func distance(_ one: UnsafePointer<Float>, _ two: UnsafePointer<Float>) -> Float {
        var sums: (Float, Float, Float, Float, Float, Float, Float, Float) = (0, 0, 0, 0, 0, 0, 0, 0)
        for index in stride(from: 0, to: 192, by: 8) {
            let (a, b) = (one + index, two + index)
            sums.0 += (a[0] - b[0]) * (a[0] - b[0])
            sums.1 += (a[1] - b[1]) * (a[1] - b[1])
            sums.2 += (a[2] - b[2]) * (a[2] - b[2])
            sums.3 += (a[3] - b[3]) * (a[3] - b[3])
            sums.4 += (a[4] - b[4]) * (a[4] - b[4])
            sums.5 += (a[5] - b[5]) * (a[5] - b[5])
            sums.6 += (a[6] - b[6]) * (a[6] - b[6])
            sums.7 += (a[7] - b[7]) * (a[7] - b[7])
        }
        return ((sums.0 + sums.1) + (sums.2 + sums.3)) + ((sums.4 + sums.5) + (sums.6 + sums.7))
    }

    /// The lowest of some errors, four at a time, so the comparisons do not
    /// wait on each other.
    private static func lowest(_ errors: UnsafePointer<Float>, _ count: Int) -> Float {
        var lowest: (Float, Float, Float, Float) = (.infinity, .infinity, .infinity, .infinity)
        var index = 0
        while index + 4 <= count {
            lowest.0 = min(lowest.0, errors[index])
            lowest.1 = min(lowest.1, errors[index + 1])
            lowest.2 = min(lowest.2, errors[index + 2])
            lowest.3 = min(lowest.3, errors[index + 3])
            index += 4
        }
        while index < count {
            lowest.0 = min(lowest.0, errors[index])
            index += 1
        }
        return min(min(lowest.0, lowest.1), min(lowest.2, lowest.3))
    }

    /// The previous conversion's set, background and cells, if this one can
    /// keep them: a PETSCII picture, in a set this one may use, with colours
    /// among the candidates. Its cells' characters may still be ones this one
    /// may not use.
    private func previousChoice(
        in previous: Conversion, tables: CharacterTables
    ) -> (set: Int, background: Int, cells: [(code: Int, foreground: Int)?])? {
        let (picture, frame) = (previous.picture, previous.frame)
        guard picture.spec == spec, frame.seesCharacterROM,
            let set = tables.sets.firstIndex(where: { $0.address == frame.graphicsAddress }),
            let background = candidates.firstIndex(of: picture.colors[0][0])
        else { return nil }
        let screen = frame.screen
        let cells = (0..<C64Frame.cellCount).map { cell -> (code: Int, foreground: Int)? in
            candidates.firstIndex(of: picture.colors[1][cell]).map { (Int(screen[cell]), $0) }
        }
        return (set, background, cells)
    }
}

// MARK: - The eye

/// A blur along the 8 pixels of a cell's lines or columns, reflecting at the
/// cell's edges, as an 8 × 8 matrix: output i takes `weights[i * 8 + j]` of
/// input j.
struct CellBlur: Sendable {
    var weights: [Float]
    /// The same, transposed: input j gives `transposed[j * 8 + i]` to output
    /// i.
    var transposed: [Float]

    static let none = CellBlur(weights: (0..<64).map { $0 / 8 == $0 % 8 ? 1 : 0 })

    /// The PAL delay line, down a cell: each line's colour averaged with the
    /// line above, and the top line's with itself.
    static let delayLine = CellBlur(
        weights: (0..<64).map { index in
            let (output, input) = (index / 8, index % 8)
            return (input == output ? 0.5 : 0) + (input == max(output - 1, 0) ? 0.5 : 0)
        })

    /// The eye's blur of brightness and of colour.
    static let eyeLuma = CellBlur(gaussian: Converter.eyeLumaBlur)
    static let eyeChroma = CellBlur(gaussian: Converter.eyeChromaBlur)

    init(weights: [Float]) {
        precondition(weights.count == 64)
        self.weights = weights
        transposed = (0..<64).map { weights[$0 % 8 * 8 + $0 / 8] }
    }

    /// A Gaussian blur with a standard deviation in pixels, or none for 0.
    init(gaussian deviation: Double) {
        guard let kernel = DisplayModel.gaussian(deviation) else {
            self = .none
            return
        }
        let radius = kernel.count / 2
        var weights = [Float](repeating: 0, count: 64)
        for output in 0..<8 {
            for (tap, weight) in kernel.enumerated() {
                var input = output + tap - radius
                while !(0..<8).contains(input) {
                    input = input < 0 ? -input - 1 : 15 - input
                }
                weights[output * 8 + input] += weight
            }
        }
        self.init(weights: weights)
    }

    /// Blurs an 8 × 8 plane in place, across its lines or down its columns.
    /// Each output line's 8 sums stay in registers, so they vectorise.
    func apply(to plane: UnsafeMutablePointer<Float>, across: Bool, scratch: UnsafeMutablePointer<Float>) {
        if across {
            // Input pixel i of a line gives `transposed[i * 8 + o]` of itself to
            // output pixel o.
            transposed.withUnsafeBufferPointer { weights in
                for line in 0..<8 {
                    var sums: (Float, Float, Float, Float, Float, Float, Float, Float) = (0, 0, 0, 0, 0, 0, 0, 0)
                    for input in 0..<8 {
                        let (spread, value) = (weights.baseAddress! + input * 8, plane[line * 8 + input])
                        sums.0 += spread[0] * value
                        sums.1 += spread[1] * value
                        sums.2 += spread[2] * value
                        sums.3 += spread[3] * value
                        sums.4 += spread[4] * value
                        sums.5 += spread[5] * value
                        sums.6 += spread[6] * value
                        sums.7 += spread[7] * value
                    }
                    Self.store(sums, at: scratch + line * 8)
                }
            }
        } else {
            // Input line i gives `weights[o * 8 + i]` of each of its pixels to
            // output line o.
            weights.withUnsafeBufferPointer { weights in
                for line in 0..<8 {
                    var sums: (Float, Float, Float, Float, Float, Float, Float, Float) = (0, 0, 0, 0, 0, 0, 0, 0)
                    for input in 0..<8 {
                        let (weight, values) = (weights[line * 8 + input], plane + input * 8)
                        sums.0 += weight * values[0]
                        sums.1 += weight * values[1]
                        sums.2 += weight * values[2]
                        sums.3 += weight * values[3]
                        sums.4 += weight * values[4]
                        sums.5 += weight * values[5]
                        sums.6 += weight * values[6]
                        sums.7 += weight * values[7]
                    }
                    Self.store(sums, at: scratch + line * 8)
                }
            }
        }
        plane.update(from: scratch, count: 64)
    }

    private static func store(
        _ sums: (Float, Float, Float, Float, Float, Float, Float, Float), at output: UnsafeMutablePointer<Float>
    ) {
        (output[0], output[1], output[2], output[3]) = (sums.0, sums.1, sums.2, sums.3)
        (output[4], output[5], output[6], output[7]) = (sums.4, sums.5, sums.6, sums.7)
    }

    /// An 8 × 8 plane blurred, across its lines or down its columns.
    func applied(to plane: [Float], across: Bool) -> [Float] {
        var plane = plane
        let scratch = UnsafeMutablePointer<Float>.allocate(capacity: 64)
        defer { scratch.deallocate() }
        plane.withUnsafeMutableBufferPointer { apply(to: $0.baseAddress!, across: across, scratch: scratch) }
        return plane
    }
}

/// Scratch memory for seeing one cell as the eye does: from its light, in
/// linear RGB, to OKLab after the eye's blur, which blurs brightness less
/// than colour.
struct EyeView {
    /// Each pixel's luminance, then what is left in each channel: its colour.
    let planes: UnsafeMutablePointer<Float>
    let scratch: UnsafeMutablePointer<Float>
    /// The cell as the eye sees it: lightness, a and b, 64 values each.
    let seen: UnsafeMutablePointer<Float>

    init() {
        planes = .allocate(capacity: 4 * 64)
        scratch = .allocate(capacity: 64)
        seen = .allocate(capacity: 3 * 64)
    }

    func deallocate() {
        planes.deallocate()
        scratch.deallocate()
        seen.deallocate()
    }

    /// Sets a pixel's light.
    func light(_ color: RGB, at pixel: Int) {
        light(LinearRGB(color), at: pixel)
    }

    func light(_ color: LinearRGB, at pixel: Int) {
        let luminance = 0.2126 * color.r + 0.7152 * color.g + 0.0722 * color.b
        planes[pixel] = luminance
        planes[64 + pixel] = color.r - luminance
        planes[128 + pixel] = color.g - luminance
        planes[192 + pixel] = color.b - luminance
    }

    /// Blurs the light as the eye does, and returns it in OKLab: lightness, a
    /// and b for each pixel.
    func look() -> UnsafeMutablePointer<Float> {
        CellBlur.eyeLuma.apply(to: planes, across: true, scratch: scratch)
        CellBlur.eyeLuma.apply(to: planes, across: false, scratch: scratch)
        for plane in 1..<4 {
            CellBlur.eyeChroma.apply(to: planes + plane * 64, across: true, scratch: scratch)
            CellBlur.eyeChroma.apply(to: planes + plane * 64, across: false, scratch: scratch)
        }
        for pixel in 0..<64 {
            let luminance = planes[pixel]
            let color = OKLab(
                LinearRGB(
                    r: luminance + planes[64 + pixel], g: luminance + planes[128 + pixel],
                    b: luminance + planes[192 + pixel]))
            seen[pixel] = color.l
            seen[64 + pixel] = color.a
            seen[128 + pixel] = color.b
        }
        return seen
    }

    /// Sees a cell of the target as the eye does, and writes the sum of its
    /// pixels' lightness, a and b, and their squared length. For a
    /// monochrome monitor, only lightness counts.
    func see(_ cell: Int, of target: Target, monochrome: Bool, sum: UnsafeMutablePointer<Float>) {
        let (left, top) = (cell % 40 * 8, cell / 40 * 8)
        target.colors.withUnsafeBufferPointer { colors in
            for pixel in 0..<64 {
                var color = colors[(top + pixel / 8) * target.width + left + pixel % 8]
                if monochrome {
                    color.a = 0
                    color.b = 0
                }
                light(color.linear, at: pixel)
            }
        }
        let seen = look()
        var (l, a, b, length): (Float, Float, Float, Float) = (0, 0, 0, 0)
        for pixel in 0..<64 {
            let (pl, pa, pb) = (seen[pixel], seen[64 + pixel], seen[128 + pixel])
            l += pl
            a += pa
            b += pb
            length += pl * pl + pa * pa + pb * pb
        }
        sum[0] = l
        sum[1] = a
        sum[2] = b
        sum[3] = length
    }

    /// The cell's correlations with every shape's basis, each a row of
    /// `shapeCount` sums: its lightness with the brightness basis, then its a
    /// and its b with the colour basis.
    func correlate(with basis: UnsafePointer<Float>, shapeCount: Int, into correlations: UnsafeMutablePointer<Float>) {
        correlations.initialize(repeating: 0, count: 3 * shapeCount)
        let (cl, ca, cb) = (correlations, correlations + shapeCount, correlations + 2 * shapeCount)
        // Four pixels at a time, so each sum is loaded and stored once for
        // four of them.
        for pixel in stride(from: 0, to: 64, by: 4) {
            let (l0, l1, l2, l3) = (seen[pixel], seen[pixel + 1], seen[pixel + 2], seen[pixel + 3])
            let (a0, a1, a2, a3) = (seen[64 + pixel], seen[65 + pixel], seen[66 + pixel], seen[67 + pixel])
            let (b0, b1, b2, b3) = (seen[128 + pixel], seen[129 + pixel], seen[130 + pixel], seen[131 + pixel])
            let luma = basis + pixel * shapeCount
            let (y0, y1, y2, y3) = (luma, luma + shapeCount, luma + 2 * shapeCount, luma + 3 * shapeCount)
            let chroma = basis + (64 + pixel) * shapeCount
            let (c0, c1, c2, c3) = (chroma, chroma + shapeCount, chroma + 2 * shapeCount, chroma + 3 * shapeCount)
            for shape in 0..<shapeCount {
                cl[shape] += y0[shape] * l0 + y1[shape] * l1 + y2[shape] * l2 + y3[shape] * l3
                ca[shape] += c0[shape] * a0 + c1[shape] * a1 + c2[shape] * a2 + c3[shape] * a3
                cb[shape] += c0[shape] * b0 + c1[shape] * b1 + c2[shape] * b2 + c3[shape] * b3
            }
        }
    }
}

/// The least-squares fit of a cell's appearance to a shape's basis: its
/// lightness to a constant and the shape's pixels as the eye sees them in
/// brightness, its a and b to a constant and the pixels as the eye sees them
/// in colour.
struct LeastSquares {
    let luma: [Double]
    let chroma: [Double]
    /// For brightness, then colour: the inverse of the basis's 2 × 2 Gram
    /// matrix, as its four values.
    let lumaInverse: (Double, Double, Double, Double)
    let chromaInverse: (Double, Double, Double, Double)

    init(_ luma: [Float], _ chroma: [Float]) {
        self.luma = luma.map(Double.init)
        self.chroma = chroma.map(Double.init)
        lumaInverse = Self.inverse(self.luma)
        chromaInverse = Self.inverse(self.chroma)
    }

    /// The inverse Gram matrix of a constant and a basis vector.
    private static func inverse(_ basis: [Double]) -> (Double, Double, Double, Double) {
        // A little ridge keeps the blank and solid shapes, whose bases are
        // constant, solvable.
        let (count, sum, squares) = (
            Double(basis.count) + 1e-6, basis.reduce(0, +), basis.reduce(1e-6) { $0 + $1 * $1 }
        )
        let determinant = count * squares - sum * sum
        return (squares / determinant, -sum / determinant, -sum / determinant, count / determinant)
    }

    /// Fits an appearance, its lightness, a and b for each pixel, and writes
    /// its terms `stride` apart: its squared length, then, times -2, its mean
    /// lightness, a and b, and the slopes of its lightness along brightness
    /// and of its a and b along colour, then the length of what the fit
    /// misses.
    func fit(_ appearance: UnsafePointer<Float>, into terms: UnsafeMutablePointer<Float>, stride: Int) {
        var length = 0.0
        // Each component's sum, and its dot product with its basis vector.
        var sums: (Double, Double, Double) = (0, 0, 0)
        var products: (Double, Double, Double) = (0, 0, 0)
        for pixel in 0..<64 {
            let (l, a, b) = (Double(appearance[pixel]), Double(appearance[64 + pixel]), Double(appearance[128 + pixel]))
            length += l * l + a * a + b * b
            sums = (sums.0 + l, sums.1 + a, sums.2 + b)
            products = (products.0 + luma[pixel] * l, products.1 + chroma[pixel] * a, products.2 + chroma[pixel] * b)
        }
        terms[0] = Float(length)
        let fits = [
            (sums.0, products.0, lumaInverse), (sums.1, products.1, chromaInverse), (sums.2, products.2, chromaInverse),
        ]
        // The fit's squared length is its coefficients' dot product with the
        // sums and products, and what it misses the rest.
        var missed = length
        for (component, (sum, product, inverse)) in fits.enumerated() {
            let (mean, slope) = (inverse.0 * sum + inverse.1 * product, inverse.2 * sum + inverse.3 * product)
            terms[(1 + component) * stride] = Float(-2 * mean)
            terms[(4 + component) * stride] = Float(-2 * slope)
            missed -= mean * sum + slope * product
        }
        terms[7 * stride] = Float(max(missed, 0).squareRoot())
    }
}
