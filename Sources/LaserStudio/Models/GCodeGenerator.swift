import AppKit
import CoreText
import CoreGraphics

enum EngravingMode: String, CaseIterable, Identifiable {
    case line = "Line"
    case fill = "Fill"
    case offset = "Offset"
    case fillAndLine = "Fill+Line"
    var id: String { rawValue }
}

enum GCodeGenerator {
    static let ray5Workspace = 400.0
    static let ray5MaxFeedRate = 10000.0 // $110/$111 for this Ray5, mm/min

    static func make(objects: [DesignObject], material: String, sMax: Int, kerf: Double,
                     machine: LaserProfile = .ray5) throws -> [String] {
        guard (1...10000).contains(sMax) else { throw GenerationError.invalidSValue }
        let burnLayers = objects.filter { $0.burnEnabled && !$0.isToolLayer }
        guard !burnLayers.isEmpty else { throw GenerationError.noBurnLayers }
        var output = ["; LaserStudio · Longer RAY5 / GRBL", "; Material: \(material)", "; S max: \(sMax)", "G21", "G90", "G94", "M5"]
        for object in burnLayers {
            let bounds = rotatedBounds(for: object)
            guard bounds.minX >= 0, bounds.minY >= 0, object.width > 0, object.height > 0,
                  bounds.maxX <= machine.workspaceWidth, bounds.maxY <= machine.workspaceHeight else {
                throw GenerationError.outOfBounds(object.label, machine.workspaceWidth, machine.workspaceHeight)
            }
            let mode = object.layerMode
            let feed = min(machine.maxFeedRate, max(40, object.speed))
            let power = Int((Double(sMax) * min(100, max(0, object.power)) / 100).rounded())
            let effectiveSpacing = object.useCustomInterval ? max(0.02, object.lineInterval) : max(0.1, kerf)
            let laserCmd = object.constantPower ? "M3" : "M4"
            let passes = max(1, object.passCount)

            if object.airAssist { output.append("M8") }
            for passIndex in 0..<passes {
                let zVal = object.zOffset + Double(passIndex) * object.zPerPass
                if abs(zVal) > 0.0001 {
                    output.append("G0 Z\(fmt(zVal))")
                }
                if object.kind == .image {
                    let imgSpacing = object.useCustomInterval ? max(0.04, 25.4 / max(25.4, object.imageDPI)) : effectiveSpacing
                    output += try raster(for: object, sMax: sMax, spacing: imgSpacing, machine: machine)
                    continue
                }
                var contours = paths(for: object)
                if abs(object.kerfOffset) > 0.001 {
                    let kerfSubpaths = contours.compactMap { pts -> [CGPoint]? in
                        ShapeGeometry.offsetSubpath(PathSubpath(points: pts, isClosed: true), distance: object.kerfOffset, cornerStyle: .round)?.points
                    }
                    if !kerfSubpaths.isEmpty { contours = kerfSubpaths }
                }
                if mode == .offset && (object.kind == .text || object.kind == .path || object.kind == .polygon) {
                    let step = effectiveSpacing * 2 / max(object.width, object.height)
                    var scale = 1 - step
                    let centerX = object.x + object.width / 2, centerY = object.y + object.height / 2
                    while scale > 0.05 {
                        contours += contoursForOffset(paths(for: object), centerX: centerX, centerY: centerY, scale: scale)
                        scale -= step
                    }
                } else if mode == .offset {
                    var inset = effectiveSpacing
                    while inset * 2 < min(object.width, object.height) {
                        var inner = object
                        inner.x += inset; inner.y += inset
                        inner.width -= inset * 2; inner.height -= inset * 2
                        contours += paths(for: inner)
                        inset += effectiveSpacing
                    }
                }

                let hasFillablePath = object.kind != .path || object.pathIsClosed ||
                    object.resolvedSubpaths.contains(where: { $0.isClosed || $0.points.count > 2 })

                // In Fill+Line mode, LightBurn runs Fill first, then Line outline
                if (mode == .fill || mode == .fillAndLine) && hasFillablePath && mode == .fillAndLine {
                    let fillContours = (object.kind == .path || object.kind == .polygon) ? paths(for: object, closeFillableSubpaths: true) : contours
                    output += generateHatchForObject(object, fillContours: fillContours, spacing: effectiveSpacing, feed: feed, power: power, machine: machine)
                }

                if mode != .fill || !hasFillablePath || mode == .fillAndLine || object.kind == .rectangle || object.kind == .circle || object.kind == .line || object.kind == .text || object.kind == .path || object.kind == .polygon {
                    // Preserve existing behavior where contours are emitted, and apply perforation/tabs/overcut when enabled
                    for contour in contours where contour.count > 1 {
                        let processedSegments = applyLineModifiers(to: contour, object: object)
                        for seg in processedSegments where seg.count > 1 {
                            let first = seg[0]
                            output.append("M5")
                            output.append("G0 X\(fmt(first.x)) Y\(fmt(machine.workspaceHeight - first.y))")
                            output.append("\(laserCmd) S0")
                            for point in seg.dropFirst() {
                                output.append("G1 X\(fmt(point.x)) Y\(fmt(machine.workspaceHeight - point.y)) F\(fmt(feed)) S\(power)")
                            }
                            output.append("M5")
                        }
                    }
                }

                if mode == .fill && hasFillablePath {
                    let fillContours = (object.kind == .path || object.kind == .polygon) ? paths(for: object, closeFillableSubpaths: true) : contours
                    output += generateHatchForObject(object, fillContours: fillContours, spacing: effectiveSpacing, feed: feed, power: power, machine: machine)
                }
            }
            if object.airAssist { output.append("M9") }
        }
        output.append("M5")
        return output
    }

    private static func generateHatchForObject(
        _ object: DesignObject,
        fillContours: [[CGPoint]],
        spacing: Double,
        feed: Double,
        power: Int,
        machine: LaserProfile
    ) -> [String] {
        var lines: [String]
        let usesPolygonHatch = object.kind == .text || object.kind == .path || object.kind == .polygon ||
            object.cornerRadius > 0 || abs(object.scanAngle) > 0.1 || !object.bidirectionalFill || object.overscanEnabled
        if usesPolygonHatch || object.rotation != 0 {
            lines = hatch(paths: fillContours, spacing: spacing, feed: feed, power: power, machine: machine, object: object, angleOffset: 0)
        } else {
            lines = hatch(for: object, spacing: spacing, feed: feed, power: power, machine: machine)
        }
        if object.crossHatch {
            lines += hatch(paths: fillContours, spacing: spacing, feed: feed, power: power, machine: machine, object: object, angleOffset: 90)
        }
        return lines
    }

    private static func applyLineModifiers(to contour: [CGPoint], object: DesignObject) -> [[CGPoint]] {
        var working = contour
        if object.overcut > 0.01, working.count > 2, let first = working.first, let last = working.last, hypot(first.x - last.x, first.y - last.y) < 0.05 {
            var remaining = object.overcut
            for i in 0..<(working.count - 1) where remaining > 0 {
                let a = working[i], b = working[i + 1]
                let len = Double(hypot(b.x - a.x, b.y - a.y))
                guard len > 0.001 else { continue }
                if remaining >= len {
                    working.append(b)
                    remaining -= len
                } else {
                    let t = CGFloat(remaining / len)
                    working.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
                    remaining = 0
                }
            }
        }
        if object.perforationEnabled && object.perforationCutLength > 0.05 && object.perforationSkipLength > 0.05 {
            return splitContourPeriodic(working, cutLen: object.perforationCutLength, skipLen: object.perforationSkipLength)
        }
        if object.tabsEnabled && object.tabCount > 0 && object.tabSize > 0.05 {
            let totalLen = zip(working, working.dropFirst()).reduce(0.0) { $0 + Double(hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y)) }
            let period = max(object.tabSize * 2, totalLen / Double(max(1, object.tabCount)))
            return splitContourPeriodic(working, cutLen: max(0.2, period - object.tabSize), skipLen: object.tabSize)
        }
        return [working]
    }

    private static func splitContourPeriodic(_ contour: [CGPoint], cutLen: Double, skipLen: Double) -> [[CGPoint]] {
        guard contour.count > 1 else { return [] }
        var segments: [[CGPoint]] = []
        var currentSeg: [CGPoint] = [contour[0]]
        var isCutting = true
        var phaseRemaining = cutLen
        for (a, b) in zip(contour, contour.dropFirst()) {
            var start = a
            var dist = Double(hypot(b.x - a.x, b.y - a.y))
            guard dist > 0.0001 else { continue }
            let dirX = Double(b.x - a.x) / dist
            let dirY = Double(b.y - a.y) / dist
            while dist > 0.0001 {
                if dist <= phaseRemaining {
                    if isCutting { currentSeg.append(b) }
                    phaseRemaining -= dist
                    dist = 0
                } else {
                    let stepPt = CGPoint(x: Double(start.x) + dirX * phaseRemaining, y: Double(start.y) + dirY * phaseRemaining)
                    if isCutting {
                        currentSeg.append(stepPt)
                        if currentSeg.count > 1 { segments.append(currentSeg) }
                        currentSeg = []
                    } else {
                        currentSeg = [stepPt]
                    }
                    dist -= phaseRemaining
                    start = stepPt
                    isCutting.toggle()
                    phaseRemaining = isCutting ? cutLen : skipLen
                }
            }
        }
        if isCutting && currentSeg.count > 1 { segments.append(currentSeg) }
        return segments
    }

    private static func paths(for object: DesignObject, closeFillableSubpaths: Bool = false) -> [[CGPoint]] {
        let paths: [[CGPoint]]
        switch object.kind {
        case .rectangle:
            if object.cornerRadius > 0.01 {
                let local = ShapeGeometry.localRoundedRectPoints(width: object.width, height: object.height, radius: object.cornerRadius)
                paths = [local.map { CGPoint(x: object.x + $0.x, y: object.y + $0.y) }]
            } else {
                let a = CGPoint(x: object.x, y: object.y), b = CGPoint(x: object.x + object.width, y: object.y)
                let c = CGPoint(x: object.x + object.width, y: object.y + object.height), d = CGPoint(x: object.x, y: object.y + object.height)
                paths = [[a, b, c, d, a]]
            }
        case .circle:
            paths = [ellipsePoints(object, steps: max(48, Int(max(object.width, object.height) * 2)))]
        case .polygon:
            let local = ShapeGeometry.localPolygonPoints(width: object.width, height: object.height, sides: object.polygonSides, cornerRadius: object.cornerRadius)
            paths = [local.map { CGPoint(x: object.x + $0.x, y: object.y + $0.y) }]
        case .text:
            paths = textPaths(object)
        case .line:
            paths = [[CGPoint(x: object.x, y: object.y), CGPoint(x: object.x + object.width, y: object.y + object.height)]]
        case .path:
            paths = object.resolvedSubpaths.compactMap { subpath in
                guard subpath.points.count > 1 else { return nil }
                var points = subpath.points.map { CGPoint(x: object.x + $0.x, y: object.y + $0.y) }
                let shouldClose = subpath.isClosed || (closeFillableSubpaths && subpath.points.count > 2)
                if shouldClose, let first = points.first, points.last != first {
                    points.append(first)
                }
                return points
            }
        case .image:
            paths = []
        }
        return paths.map { path in path.map { rotate($0, around: objectCenter(object), degrees: object.rotation) } }
    }

    private static func raster(for object: DesignObject, sMax: Int, spacing: Double, machine: LaserProfile) throws -> [String] {
        guard let pixels = object.imagePixels, object.imagePixelWidth > 0, object.imagePixelHeight > 0,
              pixels.count >= object.imagePixelWidth * object.imagePixelHeight else {
            throw GenerationError.invalidImage(object.label)
        }
        // Bound job size for very large designs while retaining the chosen fill spacing where possible.
        let pixelLimit = 300_000.0
        let areaLimitedSpacing = sqrt(object.width * object.height / pixelLimit)
        let pitch = max(spacing, areaLimitedSpacing)
        let columns = max(1, Int(ceil(object.width / pitch)))
        let rows = max(1, Int(ceil(object.height / pitch)))
        let stepX = object.width / Double(columns)
        let stepY = object.height / Double(rows)
        let lowSpeed = min(machine.maxFeedRate, max(40, min(object.minimumSpeed, object.maximumSpeed)))
        let highSpeed = min(machine.maxFeedRate, max(lowSpeed, max(object.minimumSpeed, object.maximumSpeed)))
        let maxPower = Int((Double(sMax) * min(100, max(0, object.power)) / 100).rounded())
        let imageWidth = object.imagePixelWidth
        let imageHeight = object.imagePixelHeight
        let usesAdjustedPipeline =
            object.imageDitherMode != .grayscale ||
            abs(object.imageBrightness) > 0.01 ||
            abs(object.imageContrast) > 0.01 ||
            abs(object.imageGamma - 1.0) > 0.01 ||
            object.imageEnhanceRadius > 0.1
        let data = usesAdjustedPipeline ? ImageImporter.processedGrayscale(for: object) : [UInt8](pixels)
        let laserCmd = object.constantPower ? "M3" : "M4"
        var lines: [String] = []
        lines.reserveCapacity(rows * 4 + min(rows * columns, 300_000))

        for row in 0..<rows {
            let sourceY = min(imageHeight - 1, Int((Double(row) + 0.5) / Double(rows) * Double(imageHeight)))
            let reverse = object.bidirectionalFill ? row.isMultiple(of: 2) : false
            let startX = reverse ? object.width : 0
            let localY = (Double(row) + 0.5) * stepY
            let start = rotate(CGPoint(x: object.x + startX, y: object.y + localY), around: objectCenter(object), degrees: object.rotation)
            lines += ["M5", "G0 X\(fmt(start.x)) Y\(fmt(machine.workspaceHeight - start.y))", "\(laserCmd) S0"]

            var column = 0
            while column < columns {
                let sourceColumn = reverse ? columns - column - 1 : column
                let sourceX = min(imageWidth - 1, Int((Double(sourceColumn) + 0.5) / Double(columns) * Double(imageWidth)))
                let sourceGray = Double(data[sourceY * imageWidth + sourceX])
                let gray = usesAdjustedPipeline ? sourceGray : (object.imageInverted ? 255 - sourceGray : sourceGray)
                let darkness = 1 - gray / 255
                let targetPower: Int
                if object.variablePower && object.imageDitherMode == .grayscale {
                    targetPower = Int((Double(maxPower) * darkness).rounded())
                } else {
                    targetPower = darkness >= 0.5 ? maxPower : 0
                }
                let targetFeed = Int((lowSpeed + (highSpeed - lowSpeed) * (gray / 255)).rounded())

                var runEnd = column + 1
                while runEnd < columns {
                    let runSourceColumn = reverse ? columns - runEnd - 1 : runEnd
                    let runSourceX = min(imageWidth - 1, Int((Double(runSourceColumn) + 0.5) / Double(columns) * Double(imageWidth)))
                    let sourceRunGray = Double(data[sourceY * imageWidth + runSourceX])
                    let runGray = usesAdjustedPipeline ? sourceRunGray : (object.imageInverted ? 255 - sourceRunGray : sourceRunGray)
                    let runDarkness = 1 - runGray / 255
                    let runPower = (object.variablePower && object.imageDitherMode == .grayscale)
                        ? Int((Double(maxPower) * runDarkness).rounded())
                        : (runDarkness >= 0.5 ? maxPower : 0)
                    let runFeed = Int((lowSpeed + (highSpeed - lowSpeed) * (runGray / 255)).rounded())
                    guard runPower == targetPower, runFeed == targetFeed else { break }
                    runEnd += 1
                }
                let endX = reverse ? object.width - Double(runEnd) * stepX : Double(runEnd) * stepX
                let end = rotate(CGPoint(x: object.x + endX, y: object.y + localY), around: objectCenter(object), degrees: object.rotation)
                lines.append("G1 X\(fmt(end.x)) Y\(fmt(machine.workspaceHeight - end.y)) F\(targetFeed) S\(targetPower)")
                column = runEnd
            }
            lines.append("M5")
        }
        return lines
    }

    private static func ellipsePoints(_ object: DesignObject, steps: Int) -> [CGPoint] {
        (0...steps).map { index in
            let angle = 2 * Double.pi * Double(index) / Double(steps)
            return CGPoint(x: object.x + object.width / 2 + cos(angle) * object.width / 2,
                           y: object.y + object.height / 2 + sin(angle) * object.height / 2)
        }
    }

    private static func objectCenter(_ object: DesignObject) -> CGPoint {
        CGPoint(x: object.x + object.width / 2, y: object.y + object.height / 2)
    }

    private static func rotate(_ point: CGPoint, around center: CGPoint, degrees: Double) -> CGPoint {
        guard degrees.truncatingRemainder(dividingBy: 360) != 0 else { return point }
        let radians = degrees * .pi / 180
        let dx = point.x - center.x, dy = point.y - center.y
        return CGPoint(x: center.x + dx * cos(radians) - dy * sin(radians),
                       y: center.y + dx * sin(radians) + dy * cos(radians))
    }

    private static func rotatedBounds(for object: DesignObject) -> CGRect {
        let center = objectCenter(object)
        let corners = [CGPoint(x: object.x, y: object.y), CGPoint(x: object.x + object.width, y: object.y),
                       CGPoint(x: object.x + object.width, y: object.y + object.height), CGPoint(x: object.x, y: object.y + object.height)]
            .map { rotate($0, around: center, degrees: object.rotation) }
        let minX = corners.map(\.x).min() ?? CGFloat(object.x)
        let maxX = corners.map(\.x).max() ?? CGFloat(object.x + object.width)
        let minY = corners.map(\.y).min() ?? CGFloat(object.y)
        let maxY = corners.map(\.y).max() ?? CGFloat(object.y + object.height)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func contoursForOffset(_ paths: [[CGPoint]], centerX: Double, centerY: Double, scale: Double) -> [[CGPoint]] {
        paths.map { path in path.map { CGPoint(x: centerX + ($0.x - centerX) * scale, y: centerY + ($0.y - centerY) * scale) } }
    }

    private static func textPaths(_ object: DesignObject) -> [[CGPoint]] {
        let displayText = object.fontUppercase ? object.label.uppercased() : object.label
        let metrics = SystemFontCatalog.fittedTextMetrics(label: displayText, family: object.fontFamily,
                                                           width: object.width, height: object.height,
                                                           bold: object.fontBold, italic: object.fontItalic)
        let font = metrics.font
        let attributed = NSAttributedString(string: displayText, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
        let line = CTLineCreateWithAttributedString(attributed)
        var contours: [[CGPoint]] = []
        let scale = Double(metrics.scale)
        let ascent = Double(metrics.ascent)
        let descent = Double(metrics.descent)
        let renderedW = Double(metrics.lineWidth) * scale
        let horizontalOffset = object.x + (object.width - renderedW) / 2
        let verticalOffset = object.y + (object.height - (ascent + descent) * scale) / 2
        for runValue in CTLineGetGlyphRuns(line) as! [CTRun] {
            let run = runValue
            let count = CTRunGetGlyphCount(run)
            var glyphs = Array(repeating: CGGlyph(), count: count)
            var positions = Array(repeating: CGPoint.zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
            for index in 0..<count {
                guard let glyphPath = CTFontCreatePathForGlyph(font, glyphs[index], nil) else { continue }
                let transform = CGAffineTransform(translationX: positions[index].x, y: positions[index].y)
                let positioned = glyphPath.copy(using: [transform]) ?? glyphPath
                let paths = flatten(positioned).map { path in
                    path.map { point in CGPoint(x: horizontalOffset + point.x * scale, y: verticalOffset + (ascent - Double(point.y)) * scale) }
                }
                contours.append(contentsOf: paths.filter { $0.count > 1 })
            }
        }
        let barThickness = max(0.35, (ascent + descent) * scale * 0.055)
        if object.fontUnderline && renderedW > 0.1 {
            let uPos = Double(CTFontGetUnderlinePosition(font))
            let uy = verticalOffset + (ascent - uPos) * scale
            contours.append([
                CGPoint(x: horizontalOffset, y: uy - barThickness / 2),
                CGPoint(x: horizontalOffset + renderedW, y: uy - barThickness / 2),
                CGPoint(x: horizontalOffset + renderedW, y: uy + barThickness / 2),
                CGPoint(x: horizontalOffset, y: uy + barThickness / 2),
                CGPoint(x: horizontalOffset, y: uy - barThickness / 2)
            ])
        }
        if object.fontStrikethrough && renderedW > 0.1 {
            let sy = verticalOffset + (ascent * 0.65) * scale
            contours.append([
                CGPoint(x: horizontalOffset, y: sy - barThickness / 2),
                CGPoint(x: horizontalOffset + renderedW, y: sy - barThickness / 2),
                CGPoint(x: horizontalOffset + renderedW, y: sy + barThickness / 2),
                CGPoint(x: horizontalOffset, y: sy + barThickness / 2),
                CGPoint(x: horizontalOffset, y: sy - barThickness / 2)
            ])
        }
        return contours
    }

    private static func flatten(_ path: CGPath) -> [[CGPoint]] {
        var contours: [[CGPoint]] = []
        var points: [CGPoint] = []
        var current = CGPoint.zero
        let appendElement: (UnsafePointer<CGPathElement>) -> Void = { elementPointer in
            appendPathElement(elementPointer.pointee, contours: &contours, points: &points, current: &current)
        }
        path.applyWithBlock(appendElement)
        if points.count > 1 { contours.append(points) }
        return contours
    }

    private static func appendPathElement(_ element: CGPathElement,
                                          contours: inout [[CGPoint]],
                                          points: inout [CGPoint],
                                          current: inout CGPoint) {
        switch element.type {
        case .moveToPoint:
            if points.count > 1 { contours.append(points) }
            current = element.points[0]
            points = [current]
        case .addLineToPoint:
            current = element.points[0]
            points.append(current)
        case .addQuadCurveToPoint:
            let start = current
            let control = element.points[0]
            let end = element.points[1]
            for step in 1...8 {
                let t = CGFloat(step) / 8
                let u = 1 - t
                let x = u * u * start.x + 2 * u * t * control.x + t * t * end.x
                let y = u * u * start.y + 2 * u * t * control.y + t * t * end.y
                points.append(CGPoint(x: x, y: y))
            }
            current = end
        case .addCurveToPoint:
            let start = current
            let control1 = element.points[0]
            let control2 = element.points[1]
            let end = element.points[2]
            for step in 1...10 {
                let t = CGFloat(step) / 10
                let u = 1 - t
                let x = u * u * u * start.x + 3 * u * u * t * control1.x +
                    3 * u * t * t * control2.x + t * t * t * end.x
                let y = u * u * u * start.y + 3 * u * u * t * control1.y +
                    3 * u * t * t * control2.y + t * t * t * end.y
                points.append(CGPoint(x: x, y: y))
            }
            current = end
        case .closeSubpath:
            if let first = points.first, points.last != first { points.append(first) }
            if points.count > 1 { contours.append(points) }
            points = []
        @unknown default:
            break
        }
    }

    private static func hatch(for object: DesignObject, spacing: Double, feed: Double, power: Int, machine: LaserProfile) -> [String] {
        var lines: [String] = []
        let maxY = object.y + object.height
        var y = object.y + spacing
        var reverse = false
        while y < maxY {
            let inset: Double
            if object.kind == .circle {
                let ny = (y - object.y - object.height / 2) / (object.height / 2)
                inset = object.width / 2 * (1 - sqrt(max(0, 1 - ny * ny)))
            } else { inset = 0 }
            let left = object.x + inset, right = object.x + object.width - inset
            guard right > left else { y += spacing; continue }
            let startX = reverse ? right : left, endX = reverse ? left : right
            lines += ["M5", "G0 X\(fmt(startX)) Y\(fmt(machine.workspaceHeight - y))", "M4 S0",
                      "G1 X\(fmt(endX)) Y\(fmt(machine.workspaceHeight - y)) F\(fmt(feed)) S\(power)", "M5"]
            reverse.toggle(); y += spacing
        }
        return lines
    }

    private static func hatch(
        paths: [[CGPoint]],
        spacing: Double,
        feed: Double,
        power: Int,
        machine: LaserProfile,
        object: DesignObject? = nil,
        angleOffset: Double = 0
    ) -> [String] {
        let totalAngle = (object?.scanAngle ?? 0) + angleOffset
        let center: CGPoint = {
            if let object { return objectCenter(object) }
            let pts = paths.flatMap { $0 }
            let minX = pts.map(\.x).min() ?? 0, maxX = pts.map(\.x).max() ?? 0
            let minY = pts.map(\.y).min() ?? 0, maxY = pts.map(\.y).max() ?? 0
            return CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
        }()
        let rotatedPaths = abs(totalAngle) > 0.05
            ? paths.map { p in p.map { rotate($0, around: center, degrees: -totalAngle) } }
            : paths
        let allPoints = rotatedPaths.flatMap { $0 }
        guard let minY = allPoints.map(\.y).min(), let maxY = allPoints.map(\.y).max() else { return [] }
        let bidirectional = object?.bidirectionalFill ?? true
        let laserCmd = (object?.constantPower ?? false) ? "M3" : "M4"
        let overscanDist: Double = (object?.overscanEnabled ?? false)
            ? max(0.5, min(15.0, (feed / 1000.0) * ((object?.overscanPercent ?? 2.5) / 2.5)))
            : 0.0
        var lines: [String] = []
        var y = minY + spacing
        var reverse = false
        while y < maxY {
            var intersections: [Double] = []
            for path in rotatedPaths where path.count > 1 {
                for (a, b) in zip(path, path.dropFirst()) where (a.y <= y && b.y > y) || (b.y <= y && a.y > y) {
                    intersections.append(a.x + (y - a.y) * (b.x - a.x) / (b.y - a.y))
                }
            }
            intersections.sort()
            for pairIndex in stride(from: 0, through: max(-1, intersections.count - 2), by: 2) where pairIndex + 1 < intersections.count {
                let left = intersections[pairIndex], right = intersections[pairIndex + 1]
                let useReverse = bidirectional && reverse
                let startX = useReverse ? right : left
                let endX = useReverse ? left : right
                let pStart = rotate(CGPoint(x: startX, y: y), around: center, degrees: totalAngle)
                let pEnd = rotate(CGPoint(x: endX, y: y), around: center, degrees: totalAngle)
                if overscanDist > 0.01 {
                    let leadInX = useReverse ? right + overscanDist : left - overscanDist
                    let leadOutX = useReverse ? left - overscanDist : right + overscanDist
                    let pLeadIn = rotate(CGPoint(x: leadInX, y: y), around: center, degrees: totalAngle)
                    let pLeadOut = rotate(CGPoint(x: leadOutX, y: y), around: center, degrees: totalAngle)
                    let clampedInX = min(machine.workspaceWidth, max(0, Double(pLeadIn.x)))
                    let clampedInY = min(machine.workspaceHeight, max(0, Double(pLeadIn.y)))
                    let clampedOutX = min(machine.workspaceWidth, max(0, Double(pLeadOut.x)))
                    let clampedOutY = min(machine.workspaceHeight, max(0, Double(pLeadOut.y)))
                    lines += [
                        "M5",
                        "G0 X\(fmt(clampedInX)) Y\(fmt(machine.workspaceHeight - clampedInY))",
                        "\(laserCmd) S0",
                        "G1 X\(fmt(pStart.x)) Y\(fmt(machine.workspaceHeight - pStart.y)) F\(fmt(feed)) S0",
                        "G1 X\(fmt(pEnd.x)) Y\(fmt(machine.workspaceHeight - pEnd.y)) F\(fmt(feed)) S\(power)",
                        "G1 X\(fmt(clampedOutX)) Y\(fmt(machine.workspaceHeight - clampedOutY)) F\(fmt(feed)) S0",
                        "M5"
                    ]
                } else {
                    lines += [
                        "M5",
                        "G0 X\(fmt(pStart.x)) Y\(fmt(machine.workspaceHeight - pStart.y))",
                        "\(laserCmd) S0",
                        "G1 X\(fmt(pEnd.x)) Y\(fmt(machine.workspaceHeight - pEnd.y)) F\(fmt(feed)) S\(power)",
                        "M5"
                    ]
                }
                reverse.toggle()
            }
            y += spacing
        }
        return lines
    }

    private static func fmt(_ value: Double) -> String { String(format: "%.3f", value) }

    enum GenerationError: LocalizedError {
        case invalidSValue
        case outOfBounds(String, Double, Double)
        case noBurnLayers
        case invalidImage(String)
        var errorDescription: String? {
            switch self {
            case .invalidSValue: "GRBL S-value maximum must be between 1 and 10000."
            case .outOfBounds(let label, let width, let height): "\(label) is outside the \(Int(width)) × \(Int(height)) mm work area."
            case .noBurnLayers: "Turn Burn on for at least one layer before generating a job."
            case .invalidImage(let label): "\(label) does not contain usable image data. Reimport the image before generating the job."
            }
        }
    }
}
