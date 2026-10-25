import CoreText
import Foundation
import SwiftUI

enum SVGImporter {
    private struct RGB: Equatable, Hashable {
        var r: Double, g: Double, b: Double
        static let black = RGB(r: 0, g: 0, b: 0)
    }

    private struct LightBurnLayerColor: Equatable, Hashable {
        let code: String
        let name: String
        let rgb: RGB
        let displayColor: Color
    }

    /// Standard LightBurn 30-layer palette + T1/T2 tool layers.
    /// Layer 00 (Black #000000) uses a bright high-contrast display color so paths remain clearly visible on the dark canvas.
    private static let lightBurnPalette: [LightBurnLayerColor] = [
        LightBurnLayerColor(code: "00", name: "Black", rgb: RGB(r: 0.00, g: 0.00, b: 0.00), displayColor: Color(red: 0.92, green: 0.94, blue: 0.97)),
        LightBurnLayerColor(code: "01", name: "Blue", rgb: RGB(r: 0.00, g: 0.00, b: 1.00), displayColor: Color(red: 0.18, green: 0.52, blue: 1.00)),
        LightBurnLayerColor(code: "02", name: "Red", rgb: RGB(r: 1.00, g: 0.00, b: 0.00), displayColor: Color(red: 1.00, green: 0.22, blue: 0.22)),
        LightBurnLayerColor(code: "03", name: "Green", rgb: RGB(r: 0.00, g: 0.88, b: 0.00), displayColor: Color(red: 0.00, green: 0.88, blue: 0.00)),
        LightBurnLayerColor(code: "04", name: "Yellow", rgb: RGB(r: 0.82, g: 0.82, b: 0.00), displayColor: Color(red: 0.90, green: 0.90, blue: 0.00)),
        LightBurnLayerColor(code: "05", name: "Orange", rgb: RGB(r: 1.00, g: 0.50, b: 0.00), displayColor: Color(red: 1.00, green: 0.50, blue: 0.00)),
        LightBurnLayerColor(code: "06", name: "Cyan", rgb: RGB(r: 0.00, g: 0.88, b: 0.88), displayColor: Color(red: 0.00, green: 0.88, blue: 0.88)),
        LightBurnLayerColor(code: "07", name: "Magenta", rgb: RGB(r: 1.00, g: 0.00, b: 1.00), displayColor: Color(red: 1.00, green: 0.00, blue: 1.00)),
        LightBurnLayerColor(code: "08", name: "Silver", rgb: RGB(r: 0.71, g: 0.71, b: 0.71), displayColor: Color(red: 0.71, green: 0.71, blue: 0.71)),
        LightBurnLayerColor(code: "09", name: "Dark Blue", rgb: RGB(r: 0.00, g: 0.00, b: 0.63), displayColor: Color(red: 0.25, green: 0.40, blue: 0.88)),
        LightBurnLayerColor(code: "10", name: "Dark Red", rgb: RGB(r: 0.63, g: 0.00, b: 0.00), displayColor: Color(red: 0.80, green: 0.16, blue: 0.16)),
        LightBurnLayerColor(code: "11", name: "Dark Green", rgb: RGB(r: 0.00, g: 0.63, b: 0.00), displayColor: Color(red: 0.00, green: 0.68, blue: 0.00)),
        LightBurnLayerColor(code: "12", name: "Olive", rgb: RGB(r: 0.63, g: 0.63, b: 0.00), displayColor: Color(red: 0.70, green: 0.70, blue: 0.00)),
        LightBurnLayerColor(code: "13", name: "Brown", rgb: RGB(r: 0.75, g: 0.50, b: 0.00), displayColor: Color(red: 0.78, green: 0.52, blue: 0.05)),
        LightBurnLayerColor(code: "14", name: "Sky Blue", rgb: RGB(r: 0.00, g: 0.63, b: 1.00), displayColor: Color(red: 0.00, green: 0.63, blue: 1.00)),
        LightBurnLayerColor(code: "15", name: "Purple", rgb: RGB(r: 0.63, g: 0.00, b: 0.63), displayColor: Color(red: 0.72, green: 0.20, blue: 0.72)),
        LightBurnLayerColor(code: "16", name: "Gray", rgb: RGB(r: 0.50, g: 0.50, b: 0.50), displayColor: Color(red: 0.56, green: 0.56, blue: 0.56)),
        LightBurnLayerColor(code: "17", name: "Slate", rgb: RGB(r: 0.49, g: 0.53, b: 0.73), displayColor: Color(red: 0.49, green: 0.53, blue: 0.73)),
        LightBurnLayerColor(code: "18", name: "Rose", rgb: RGB(r: 0.73, g: 0.47, b: 0.52), displayColor: Color(red: 0.73, green: 0.47, blue: 0.52)),
        LightBurnLayerColor(code: "19", name: "Royal Blue", rgb: RGB(r: 0.29, g: 0.44, b: 0.89), displayColor: Color(red: 0.29, green: 0.44, blue: 0.89)),
        LightBurnLayerColor(code: "20", name: "Crimson", rgb: RGB(r: 0.83, g: 0.25, b: 0.42), displayColor: Color(red: 0.83, green: 0.25, blue: 0.42)),
        LightBurnLayerColor(code: "21", name: "Mint", rgb: RGB(r: 0.55, g: 0.84, b: 0.55), displayColor: Color(red: 0.55, green: 0.84, blue: 0.55)),
        LightBurnLayerColor(code: "22", name: "Peach", rgb: RGB(r: 0.94, g: 0.73, b: 0.55), displayColor: Color(red: 0.94, green: 0.73, blue: 0.55)),
        LightBurnLayerColor(code: "23", name: "Pale Pink", rgb: RGB(r: 0.96, g: 0.77, b: 0.88), displayColor: Color(red: 0.96, green: 0.77, blue: 0.88)),
        LightBurnLayerColor(code: "24", name: "Pink", rgb: RGB(r: 0.98, g: 0.62, b: 0.83), displayColor: Color(red: 0.98, green: 0.62, blue: 0.83)),
        LightBurnLayerColor(code: "25", name: "Indigo", rgb: RGB(r: 0.31, g: 0.04, b: 0.47), displayColor: Color(red: 0.52, green: 0.24, blue: 0.72)),
        LightBurnLayerColor(code: "26", name: "Rust", rgb: RGB(r: 0.71, g: 0.35, b: 0.00), displayColor: Color(red: 0.75, green: 0.40, blue: 0.08)),
        LightBurnLayerColor(code: "27", name: "Teal", rgb: RGB(r: 0.00, g: 0.28, b: 0.33), displayColor: Color(red: 0.12, green: 0.52, blue: 0.58)),
        LightBurnLayerColor(code: "28", name: "Lime", rgb: RGB(r: 0.53, g: 0.98, b: 0.53), displayColor: Color(red: 0.53, green: 0.98, blue: 0.53)),
        LightBurnLayerColor(code: "29", name: "Gold", rgb: RGB(r: 1.00, g: 0.86, b: 0.40), displayColor: Color(red: 1.00, green: 0.86, blue: 0.40)),
        LightBurnLayerColor(code: "T1", name: "Tool 1", rgb: RGB(r: 0.95, g: 0.41, b: 0.15), displayColor: Color(red: 0.95, green: 0.41, blue: 0.15)),
        LightBurnLayerColor(code: "T2", name: "Tool 2", rgb: RGB(r: 0.05, g: 0.59, b: 0.85), displayColor: Color(red: 0.05, green: 0.59, blue: 0.85))
    ]

    private static func closestLightBurnLayer(for rgb: RGB) -> LightBurnLayerColor {
        var best = lightBurnPalette[0]
        var bestDist = Double.greatestFiniteMagnitude
        for entry in lightBurnPalette {
            let dr = rgb.r - entry.rgb.r
            let dg = rgb.g - entry.rgb.g
            let db = rgb.b - entry.rgb.b
            let dist = dr * dr + dg * dg + db * db
            if dist < bestDist {
                bestDist = dist
                best = entry
            }
        }
        return best
    }

    private enum Paint: Equatable {
        case none
        case solid(RGB)
        case unsupported
    }

    /// Inheritable presentation properties tracked while walking the SVG tree.
    private struct Style {
        var fill: Paint = .solid(.black)
        var fillOpacity: Double = 1
        var stroke: Paint = .none
        var strokeOpacity: Double = 1
        var strokeWidth: Double = 1
        var opacity: Double = 1
        var color: RGB = .black
        var displayNone: Bool = false
        var visibilityHidden: Bool = false
        var fontFamily: String = "Helvetica"
        var fontSize: Double = 16
        var fontBold: Bool = false
        var fontItalic: Bool = false
        var textAnchor: String = "start"

        var isHidden: Bool {
            displayNone || visibilityHidden || opacity <= 0
        }

        /// LightBurn color precedence: visible stroke color takes precedence over visible fill color;
        /// otherwise falls back to Black (Layer 00).
        func resolvedLayerRGB(isStrokedOnlyElement: Bool = false) -> RGB {
            if strokeOpacity > 0, strokeWidth > 0, case .solid(let strokeRGB) = stroke {
                return strokeRGB
            }
            if !isStrokedOnlyElement, fillOpacity > 0, case .solid(let fillRGB) = fill {
                return fillRGB
            }
            return .black
        }
    }

    private struct RawShape {
        var points: [CGPoint]
        var closed: Bool
        var name: String
        var color: RGB
    }

    static func load(_ url: URL, workspace: CGSize = CGSize(width: 400, height: 400)) throws -> [DesignObject] {
        let svgData = try Data(contentsOf: url)
        let rawText = String(data: svgData, encoding: .utf8) ?? ""
        let defaultDPI: Double = rawText.localizedCaseInsensitiveContains("Adobe Illustrator") ? 72.0 : 96.0
        let preloadedCSS = Parser.extractGlobalCSS(from: rawText)
        let baseName = url.deletingPathExtension().lastPathComponent

        let delegate = Parser(defaultDPI: defaultDPI, initialCSSRules: preloadedCSS)
        let parser = XMLParser(data: svgData)
        parser.shouldProcessNamespaces = false
        parser.delegate = delegate
        guard parser.parse() else {
            if let raster = try? ImageImporter.load(svgData: svgData, label: baseName) {
                return [raster]
            }
            throw parser.parserError ?? ImportError.invalidSVG
        }
        if delegate.shapes.isEmpty {
            return [try ImageImporter.load(svgData: svgData, label: baseName)]
        }

        // Compute coordinate mapping from SVG user units to millimeters (LightBurn physical scaling).
        let (scaleX, scaleY) = delegate.userUnitsToMillimetersScale()

        struct ScaledShape {
            var subpath: PathSubpath
            var layer: LightBurnLayerColor
            var name: String
        }

        let scaledShapes: [ScaledShape] = delegate.shapes.compactMap { shape in
            let pts = shape.points.map { CGPoint(x: $0.x * scaleX, y: $0.y * scaleY) }
            guard pts.count > 1 else { return nil }
            let minX = pts.map(\.x).min() ?? 0, maxX = pts.map(\.x).max() ?? 0
            let minY = pts.map(\.y).min() ?? 0, maxY = pts.map(\.y).max() ?? 0
            guard maxX > minX || maxY > minY else { return nil }
            return ScaledShape(
                subpath: PathSubpath(points: pts, isClosed: shape.closed),
                layer: closestLightBurnLayer(for: shape.color),
                name: shape.name
            )
        }

        guard !scaledShapes.isEmpty else {
            return [try ImageImporter.load(svgData: svgData, label: baseName)]
        }

        let allPoints = scaledShapes.flatMap(\.subpath.points)
        guard let globalMinX = allPoints.map(\.x).min(),
              let globalMaxX = allPoints.map(\.x).max(),
              let globalMinY = allPoints.map(\.y).min(),
              let globalMaxY = allPoints.map(\.y).max() else {
            throw ImportError.invalidSVG
        }

        let totalWidth = max(0.001, globalMaxX - globalMinX)
        let totalHeight = max(0.001, globalMaxY - globalMinY)

        // Preserve exact physical dimensions unless the artwork exceeds the workspace bounds.
        let maxAllowedWidth = max(1, workspace.width * 0.98)
        let maxAllowedHeight = max(1, workspace.height * 0.98)
        let fitScale: Double
        if totalWidth > maxAllowedWidth || totalHeight > maxAllowedHeight {
            fitScale = min(maxAllowedWidth / totalWidth, maxAllowedHeight / totalHeight)
        } else {
            fitScale = 1.0
        }

        let finalTotalWidth = totalWidth * fitScale
        let finalTotalHeight = totalHeight * fitScale
        let targetOriginX = (workspace.width - finalTotalWidth) / 2.0
        let targetOriginY = (workspace.height - finalTotalHeight) / 2.0

        // Group subpaths by LightBurn layer color (preserving first-seen layer order).
        var orderedLayers: [LightBurnLayerColor] = []
        var groupedByLayer: [LightBurnLayerColor: [ScaledShape]] = [:]
        for item in scaledShapes {
            if groupedByLayer[item.layer] == nil {
                orderedLayers.append(item.layer)
                groupedByLayer[item.layer] = []
            }
            groupedByLayer[item.layer]?.append(item)
        }

        let sharedGroupID: UUID? = orderedLayers.count > 1 ? UUID() : nil

        return orderedLayers.compactMap { layerColor -> DesignObject? in
            guard let items = groupedByLayer[layerColor], !items.isEmpty else { return nil }
            let transformedSubpaths: [PathSubpath] = items.map { item in
                let converted = item.subpath.points.map { pt in
                    CGPoint(
                        x: targetOriginX + (pt.x - globalMinX) * fitScale,
                        y: targetOriginY + (pt.y - globalMinY) * fitScale
                    )
                }
                return PathSubpath(points: converted, isClosed: item.subpath.isClosed)
            }
            let layerPoints = transformedSubpaths.flatMap(\.points)
            guard let minX = layerPoints.map(\.x).min(),
                  let maxX = layerPoints.map(\.x).max(),
                  let minY = layerPoints.map(\.y).min(),
                  let maxY = layerPoints.map(\.y).max() else { return nil }

            let localSubpaths = transformedSubpaths.map { sub in
                PathSubpath(
                    points: sub.points.map { CGPoint(x: $0.x - minX, y: $0.y - minY) },
                    isClosed: sub.isClosed
                )
            }
            let firstSubpath = localSubpaths[0]
            let allClosed = localSubpaths.allSatisfy(\.isClosed)
            let label = orderedLayers.count == 1
                ? (items.count == 1 && !items[0].name.isEmpty ? items[0].name : baseName)
                : "\(baseName) [C\(layerColor.code) \(layerColor.name)]"

            return DesignObject(
                kind: .path,
                x: minX,
                y: minY,
                width: max(0.5, maxX - minX),
                height: max(0.5, maxY - minY),
                label: label,
                color: layerColor.displayColor,
                layerMode: .line,
                pathPoints: firstSubpath.points,
                pathIsClosed: allClosed || firstSubpath.isClosed,
                pathSubpaths: localSubpaths,
                groupID: sharedGroupID
            )
        }
    }

    private final class Parser: NSObject, XMLParserDelegate {
        struct DefItem {
            var points: [CGPoint]
            var closed: Bool
            var name: String
            var isStrokedOnly: Bool
            var style: Style
            var hasExplicitColor: Bool
        }

        private struct TextContext {
            var x: Double
            var y: Double
            var dx: Double
            var dy: Double
            var text: String
            var style: Style
            var transforms: [CGAffineTransform]
            var id: String?
        }

        let defaultDPI: Double
        var shapes: [RawShape] = []
        var viewBox: CGRect?
        var svgWidthAttr: String?
        var svgHeightAttr: String?
        var preserveAspectRatioNone = false
        private var sawRootSVG = false
        private var transformStack: [[CGAffineTransform]] = [[]]
        private var styleStack: [Style] = [Style()]
        private var cssRules: [(selector: String, declarations: [String: String])] = []
        private var cssBuffer: String?
        private var nonRenderingDepth = 0
        private var activeDefGroupIDs: [String?] = []
        private var defsByID: [String: [DefItem]] = [:]
        private var textStack: [TextContext] = []

        private static let nonRenderingTags: Set<String> = [
            "defs", "symbol", "clippath", "mask", "pattern", "marker",
            "lineargradient", "radialgradient", "filter", "metadata",
            "style", "script", "title", "desc"
        ]

        init(defaultDPI: Double = 96.0, initialCSSRules: [(selector: String, declarations: [String: String])] = []) {
            self.defaultDPI = defaultDPI
            self.cssRules = initialCSSRules
        }

        static func extractGlobalCSS(from svgString: String) -> [(selector: String, declarations: [String: String])] {
            let pattern = "<style[^>]*>([\\s\\S]*?)</style>"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
            let ns = svgString as NSString
            let matches = regex.matches(in: svgString, range: NSRange(location: 0, length: ns.length))
            let helper = Parser()
            var rules: [(selector: String, declarations: [String: String])] = []
            for m in matches where m.numberOfRanges > 1 {
                let block = ns.substring(with: m.range(at: 1))
                rules.append(contentsOf: helper.parseCSS(block))
            }
            return rules
        }

        func userUnitsToMillimetersScale() -> (Double, Double) {
            let pxToMM = 25.4 / defaultDPI
            let widthMM = parseLengthInMM(svgWidthAttr, viewBoxSpan: viewBox.map { Double($0.width) })
            let heightMM = parseLengthInMM(svgHeightAttr, viewBoxSpan: viewBox.map { Double($0.height) })

            if let vb = viewBox, vb.width > 0, vb.height > 0 {
                let vbW = Double(vb.width), vbH = Double(vb.height)
                if let wMM = widthMM, let hMM = heightMM, wMM > 0, hMM > 0 {
                    let sx = wMM / vbW
                    let sy = hMM / vbH
                    if preserveAspectRatioNone {
                        return (sx, sy)
                    }
                    let uniform = min(sx, sy)
                    return (uniform, uniform)
                } else if let wMM = widthMM, wMM > 0 {
                    let s = wMM / vbW
                    return (s, s)
                } else if let hMM = heightMM, hMM > 0 {
                    let s = hMM / vbH
                    return (s, s)
                } else {
                    return (pxToMM, pxToMM)
                }
            }
            return (pxToMM, pxToMM)
        }

        private func parseLengthInMM(_ raw: String?, viewBoxSpan: Double?) -> Double? {
            guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                  !raw.isEmpty else { return nil }
            guard let val = parseNumbers(raw)?.first, val > 0 else { return nil }
            let pxToMM = 25.4 / defaultDPI
            if raw.hasSuffix("mm") { return val }
            if raw.hasSuffix("cm") { return val * 10.0 }
            if raw.hasSuffix("in") { return val * 25.4 }
            if raw.hasSuffix("pt") { return val * (25.4 / 72.0) }
            if raw.hasSuffix("pc") { return val * (25.4 / 6.0) }
            if raw.hasSuffix("q") { return val * 0.25 }
            if raw.hasSuffix("%") {
                if let span = viewBoxSpan, span > 0 {
                    return (val / 100.0) * span * pxToMM
                }
                return nil
            }
            return val * pxToMM
        }

        private func parseUserLength(_ raw: String?, default fallback: Double = 0) -> Double {
            guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                  !raw.isEmpty,
                  let val = parseNumbers(raw)?.first else { return fallback }
            let mmToUser = defaultDPI / 25.4
            if raw.hasSuffix("mm") { return val * mmToUser }
            if raw.hasSuffix("cm") { return val * 10.0 * mmToUser }
            if raw.hasSuffix("in") { return val * 25.4 * mmToUser }
            if raw.hasSuffix("pt") { return val * (defaultDPI / 72.0) }
            if raw.hasSuffix("pc") { return val * (defaultDPI / 6.0) }
            if raw.hasSuffix("q") { return val * 0.25 * mmToUser }
            return val
        }

        private func localTagName(_ name: String, qualifiedName qName: String?) -> String {
            let candidate = (qName ?? name).lowercased()
            if let colon = candidate.lastIndex(of: ":") {
                return String(candidate[candidate.index(after: colon)...])
            }
            return candidate
        }

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName qName: String?, attributes a: [String: String] = [:]) {
            let tag = localTagName(name, qualifiedName: qName)
            var transforms = transformStack.last ?? []
            if let value = a["transform"], let parsed = parseTransforms(value) {
                transforms.append(contentsOf: parsed)
            }
            if tag == "svg", sawRootSVG {
                let x = parseUserLength(a["x"]), y = parseUserLength(a["y"])
                if x != 0 || y != 0 {
                    transforms.append(CGAffineTransform(translationX: x, y: y))
                }
            }
            transformStack.append(transforms)

            var style = styleStack.last ?? Style()
            applyStyle(&style, element: tag, attributes: a)
            styleStack.append(style)

            if Self.nonRenderingTags.contains(tag) {
                nonRenderingDepth += 1
            }
            activeDefGroupIDs.append(a["id"])

            if tag == "style" { cssBuffer = "" }

            switch tag {
            case "svg":
                if !sawRootSVG {
                    sawRootSVG = true
                    svgWidthAttr = a["width"]
                    svgHeightAttr = a["height"]
                    if let par = a["preserveAspectRatio"]?.lowercased(), par.contains("none") {
                        preserveAspectRatioNone = true
                    }
                    if let value = a["viewBox"] ?? a["viewbox"], let numbers = parseNumbers(value), numbers.count >= 4 {
                        viewBox = CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
                    }
                }
            case "rect":
                let x = parseUserLength(a["x"]), y = parseUserLength(a["y"])
                let w = parseUserLength(a["width"]), h = parseUserLength(a["height"])
                guard w > 0, h > 0 else { break }
                let rawRx = a["rx"].map { parseUserLength($0) }
                let rawRy = a["ry"].map { parseUserLength($0) }
                let rx = min(w / 2, max(0, rawRx ?? rawRy ?? 0))
                let ry = min(h / 2, max(0, rawRy ?? rawRx ?? 0))
                let pts = Self.roundedRectPoints(x: x, y: y, width: w, height: h, rx: rx, ry: ry)
                add(pts, closed: true, name: a["id"] ?? "Rectangle", attributes: a)
            case "circle", "ellipse":
                let cx = parseUserLength(a["cx"]), cy = parseUserLength(a["cy"])
                let rx = tag == "circle" ? parseUserLength(a["r"]) : parseUserLength(a["rx"])
                let ry = tag == "circle" ? rx : parseUserLength(a["ry"])
                guard rx > 0, ry > 0 else { break }
                let steps = max(64, min(180, Int(ceil(max(rx, ry) * 1.5))))
                let points = (0...steps).map { i -> CGPoint in
                    let angle = 2 * Double.pi * Double(i) / Double(steps)
                    return CGPoint(x: cx + rx * cos(angle), y: cy + ry * sin(angle))
                }
                add(points, closed: true, name: a["id"] ?? "Ellipse", attributes: a)
            case "line":
                let x1 = parseUserLength(a["x1"]), y1 = parseUserLength(a["y1"])
                let x2 = parseUserLength(a["x2"]), y2 = parseUserLength(a["y2"])
                add([CGPoint(x: x1, y: y1), CGPoint(x: x2, y: y2)], closed: false, name: a["id"] ?? "Line", isStrokedOnly: true, attributes: a)
            case "polygon", "polyline":
                let points = parseNumbers(a["points"] ?? "")
                if let points, points.count >= 4 {
                    let coords = stride(from: 0, to: points.count - 1, by: 2).map { CGPoint(x: points[$0], y: points[$0 + 1]) }
                    add(coords, closed: tag == "polygon", name: a["id"] ?? "Path", attributes: a)
                }
            case "path":
                if let d = a["d"], let contours = parsePath(d) {
                    for (index, contour) in contours.enumerated() {
                        add(contour.points, closed: contour.closed, name: a["id"] ?? "Path \(index + 1)", attributes: a)
                    }
                }
            case "use":
                let href = a["href"] ?? a["xlink:href"] ?? ""
                let targetID = href.hasPrefix("#") ? String(href.dropFirst()) : href
                if !targetID.isEmpty, let defItems = defsByID[targetID] {
                    let ux = parseUserLength(a["x"]), uy = parseUserLength(a["y"])
                    var useTransforms = transforms
                    if ux != 0 || uy != 0 {
                        useTransforms.append(CGAffineTransform(translationX: ux, y: uy))
                    }
                    let hasUseOwnColor = hasExplicitColorAttribute(a)
                    for item in defItems {
                        let effectiveStyle = (item.hasExplicitColor && !hasUseOwnColor) ? item.style : style
                        guard !effectiveStyle.isHidden else { continue }
                        let transformed = useTransforms.reversed().reduce(item.points) { currentPoints, transform in
                            currentPoints.map { $0.applying(transform) }
                        }
                        let color = effectiveStyle.resolvedLayerRGB(isStrokedOnlyElement: item.isStrokedOnly)
                        if nonRenderingDepth == 0 {
                            shapes.append(RawShape(points: transformed, closed: item.closed, name: a["id"] ?? item.name, color: color))
                        }
                    }
                }
            case "text", "tspan":
                let inheritedX = textStack.last?.x ?? 0
                let inheritedY = textStack.last?.y ?? 0
                let x = a["x"] != nil ? parseUserLength(a["x"], default: inheritedX) : inheritedX
                let y = a["y"] != nil ? parseUserLength(a["y"], default: inheritedY) : inheritedY
                let dx = parseUserLength(a["dx"]), dy = parseUserLength(a["dy"])
                textStack.append(TextContext(x: x, y: y, dx: dx, dy: dy, text: "", style: style, transforms: transforms, id: a["id"]))
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName qName: String?) {
            let tag = localTagName(name, qualifiedName: qName)
            if tag == "text" || tag == "tspan" {
                if let ctx = textStack.popLast() {
                    let trimmed = ctx.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty, !ctx.style.isHidden, nonRenderingDepth == 0 {
                        let contours = Self.glyphContours(for: trimmed, x: ctx.x + ctx.dx, y: ctx.y + ctx.dy, style: ctx.style)
                        let color = ctx.style.resolvedLayerRGB(isStrokedOnlyElement: false)
                        for contour in contours where contour.count > 1 {
                            let transformed = ctx.transforms.reversed().reduce(contour) { pts, t in pts.map { $0.applying(t) } }
                            shapes.append(RawShape(points: transformed, closed: true, name: ctx.id ?? trimmed, color: color))
                        }
                    }
                }
            }
            if tag == "style", let css = cssBuffer {
                cssRules.append(contentsOf: parseCSS(css))
                cssBuffer = nil
            }
            if Self.nonRenderingTags.contains(tag), nonRenderingDepth > 0 {
                nonRenderingDepth -= 1
            }
            if !activeDefGroupIDs.isEmpty { activeDefGroupIDs.removeLast() }
            if transformStack.count > 1 { transformStack.removeLast() }
            if styleStack.count > 1 { styleStack.removeLast() }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            cssBuffer?.append(string)
            if !textStack.isEmpty {
                textStack[textStack.count - 1].text.append(string)
            }
        }

        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            if let text = String(data: CDATABlock, encoding: .utf8) {
                cssBuffer?.append(text)
            }
        }

        private func hasExplicitColorAttribute(_ a: [String: String]) -> Bool {
            if a["stroke"] != nil || a["fill"] != nil || a["class"] != nil { return true }
            if let inline = a["style"]?.lowercased(), inline.contains("stroke") || inline.contains("fill") { return true }
            return false
        }

        private func add(_ points: [CGPoint], closed: Bool, name: String, isStrokedOnly: Bool = false, attributes a: [String: String] = [:]) {
            guard points.count > 1 else { return }
            let style = styleStack.last ?? Style()
            let transformed = (transformStack.last ?? []).reversed().reduce(points) { currentPoints, transform in
                currentPoints.map { $0.applying(transform) }
            }
            var finalPoints = transformed
            if closed, let first = finalPoints.first, finalPoints.last != first {
                finalPoints.append(first)
            }

            let defItem = DefItem(
                points: finalPoints,
                closed: closed,
                name: name,
                isStrokedOnly: isStrokedOnly,
                style: style,
                hasExplicitColor: hasExplicitColorAttribute(a)
            )
            for defID in activeDefGroupIDs.compactMap({ $0 }) where !defID.isEmpty {
                defsByID[defID, default: []].append(defItem)
            }

            guard nonRenderingDepth == 0, !style.isHidden else { return }
            let color = style.resolvedLayerRGB(isStrokedOnlyElement: isStrokedOnly)
            shapes.append(RawShape(points: finalPoints, closed: closed, name: name, color: color))
        }

        private static func roundedRectPoints(x: Double, y: Double, width w: Double, height h: Double, rx: Double, ry: Double) -> [CGPoint] {
            guard rx > 0 && ry > 0 else {
                return [
                    CGPoint(x: x, y: y),
                    CGPoint(x: x + w, y: y),
                    CGPoint(x: x + w, y: y + h),
                    CGPoint(x: x, y: y + h),
                    CGPoint(x: x, y: y)
                ]
            }
            var pts: [CGPoint] = []
            let steps = 12
            func appendCorner(cx: Double, cy: Double, startAngle: Double, endAngle: Double) {
                for i in 0...steps {
                    let t = Double(i) / Double(steps)
                    let angle = startAngle + (endAngle - startAngle) * t
                    pts.append(CGPoint(x: cx + rx * cos(angle), y: cy + ry * sin(angle)))
                }
            }
            appendCorner(cx: x + w - rx, cy: y + ry, startAngle: -.pi / 2, endAngle: 0)
            appendCorner(cx: x + w - rx, cy: y + h - ry, startAngle: 0, endAngle: .pi / 2)
            appendCorner(cx: x + rx, cy: y + h - ry, startAngle: .pi / 2, endAngle: .pi)
            appendCorner(cx: x + rx, cy: y + ry, startAngle: .pi, endAngle: 1.5 * .pi)
            if let first = pts.first { pts.append(first) }
            return pts
        }

        private static func glyphContours(for text: String, x: Double, y: Double, style: Style) -> [[CGPoint]] {
            var symbolicTraits: CTFontSymbolicTraits = []
            if style.fontBold { symbolicTraits.insert(.traitBold) }
            if style.fontItalic { symbolicTraits.insert(.traitItalic) }
            let baseFont = CTFontCreateWithName(style.fontFamily as CFString, CGFloat(max(1, style.fontSize)), nil)
            let font = symbolicTraits.isEmpty
                ? baseFont
                : (CTFontCreateCopyWithSymbolicTraits(baseFont, CGFloat(max(1, style.fontSize)), nil, symbolicTraits, symbolicTraits) ?? baseFont)

            let attributed = NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
            let line = CTLineCreateWithAttributedString(attributed)
            let lineWidth = Double(CTLineGetTypographicBounds(line, nil, nil, nil))
            let anchorOffset: Double
            switch style.textAnchor {
            case "middle": anchorOffset = -lineWidth / 2
            case "end": anchorOffset = -lineWidth
            default: anchorOffset = 0
            }

            var contours: [[CGPoint]] = []
            for runValue in CTLineGetGlyphRuns(line) as! [CTRun] {
                let count = CTRunGetGlyphCount(runValue)
                var glyphs = Array(repeating: CGGlyph(), count: count)
                var positions = Array(repeating: CGPoint.zero, count: count)
                CTRunGetGlyphs(runValue, CFRange(location: 0, length: 0), &glyphs)
                CTRunGetPositions(runValue, CFRange(location: 0, length: 0), &positions)
                for index in 0..<count {
                    guard let glyphPath = CTFontCreatePathForGlyph(font, glyphs[index], nil) else { continue }
                    let gx = x + anchorOffset + Double(positions[index].x)
                    let gy = y - Double(positions[index].y)
                    var current = CGPoint.zero
                    var points: [CGPoint] = []
                    glyphPath.applyWithBlock { elementPtr in
                        let el = elementPtr.pointee
                        switch el.type {
                        case .moveToPoint:
                            if points.count > 1 { contours.append(points) }
                            let p = el.points[0]
                            current = CGPoint(x: gx + Double(p.x), y: gy - Double(p.y))
                            points = [current]
                        case .addLineToPoint:
                            let p = el.points[0]
                            current = CGPoint(x: gx + Double(p.x), y: gy - Double(p.y))
                            points.append(current)
                        case .addQuadCurveToPoint:
                            let p0 = current
                            let c = CGPoint(x: gx + Double(el.points[0].x), y: gy - Double(el.points[0].y))
                            let end = CGPoint(x: gx + Double(el.points[1].x), y: gy - Double(el.points[1].y))
                            for step in 1...8 {
                                let t = Double(step) / 8, u = 1 - t
                                points.append(CGPoint(x: u * u * p0.x + 2 * u * t * c.x + t * t * end.x,
                                                      y: u * u * p0.y + 2 * u * t * c.y + t * t * end.y))
                            }
                            current = end
                        case .addCurveToPoint:
                            let p0 = current
                            let c1 = CGPoint(x: gx + Double(el.points[0].x), y: gy - Double(el.points[0].y))
                            let c2 = CGPoint(x: gx + Double(el.points[1].x), y: gy - Double(el.points[1].y))
                            let end = CGPoint(x: gx + Double(el.points[2].x), y: gy - Double(el.points[2].y))
                            for step in 1...10 {
                                let t = Double(step) / 10, u = 1 - t
                                points.append(CGPoint(
                                    x: u * u * u * p0.x + 3 * u * u * t * c1.x + 3 * u * t * t * c2.x + t * t * t * end.x,
                                    y: u * u * u * p0.y + 3 * u * u * t * c1.y + 3 * u * t * t * c2.y + t * t * t * end.y
                                ))
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
                    if points.count > 1 { contours.append(points) }
                }
            }
            return contours
        }

        // MARK: Style & paint

        /// Resolves stroke, fill, visibility, and font properties.
        /// Precedence (low → high): presentation attributes, `<style>` rules (tag, class, id), inline `style=""`.
        private func applyStyle(_ style: inout Style, element: String, attributes a: [String: String]) {
            var declarations: [String: String] = [:]
            let presentationKeys = [
                "fill", "fill-opacity", "stroke", "stroke-opacity", "stroke-width",
                "color", "opacity", "display", "visibility",
                "font-family", "font-size", "font-weight", "font-style", "text-anchor"
            ]
            for key in presentationKeys {
                if let value = a[key] { declarations[key] = value }
            }
            let classes = (a["class"] ?? "").split(whereSeparator: \.isWhitespace).map { $0.lowercased() }
            let elementID = a["id"]?.lowercased()
            for rule in cssRules where selectorMatches(rule.selector, element: element, classes: classes, id: elementID) {
                declarations.merge(rule.declarations) { _, new in new }
            }
            if let inline = a["style"] {
                declarations.merge(parseDeclarations(inline)) { _, new in new }
            }

            if let value = declarations["color"], let rgb = parseColor(value) { style.color = rgb }
            if let value = declarations["fill"], let paint = parsePaint(value, style: style) { style.fill = paint }
            if let value = declarations["stroke"], let paint = parsePaint(value, style: style) { style.stroke = paint }

            if let value = declarations["fill-opacity"], let op = parseOpacity(value) { style.fillOpacity = op }
            if let value = declarations["stroke-opacity"], let op = parseOpacity(value) { style.strokeOpacity = op }
            if let value = declarations["opacity"], let op = parseOpacity(value) { style.opacity = op }

            if let value = declarations["stroke-width"] {
                if value.trimmingCharacters(in: .whitespaces).lowercased() == "0" || value.trimmingCharacters(in: .whitespaces).lowercased() == "0px" {
                    style.strokeWidth = 0
                } else {
                    style.strokeWidth = max(0, parseUserLength(value, default: style.strokeWidth))
                }
            }
            if let display = declarations["display"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
                style.displayNone = (display == "none")
            }
            if let visibility = declarations["visibility"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
                style.visibilityHidden = (visibility == "hidden" || visibility == "collapse")
            }
            if let family = declarations["font-family"] {
                let clean = family.split(separator: ",").first.map {
                    $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "'\"")))
                }
                if let clean, !clean.isEmpty { style.fontFamily = clean }
            }
            if let fSize = declarations["font-size"] {
                style.fontSize = max(1, parseUserLength(fSize, default: style.fontSize))
            }
            if let weight = declarations["font-weight"]?.lowercased() {
                style.fontBold = weight.contains("bold") || (Int(weight) ?? 400) >= 600
            }
            if let fStyle = declarations["font-style"]?.lowercased() {
                style.fontItalic = fStyle.contains("italic") || fStyle.contains("oblique")
            }
            if let anchor = declarations["text-anchor"]?.lowercased() {
                style.textAnchor = anchor.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        private func parseOpacity(_ value: String) -> Double? {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let numeric = trimmed.replacingOccurrences(of: "%", with: "")
            guard let v = Double(numeric) else { return nil }
            return min(1, max(0, trimmed.contains("%") ? v / 100.0 : v))
        }

        /// Supports comma lists of `*`, `tag`, `.class`, `#id` and `tag.class` simple selectors (case-insensitive).
        private func selectorMatches(_ list: String, element: String, classes: [String], id: String?) -> Bool {
            list.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.contains { selector in
                let simple = selector.split(whereSeparator: { $0.isWhitespace || $0 == ">" || $0 == "+" || $0 == "~" }).last.map(String.init) ?? selector
                if simple == "*" || simple == element { return true }
                if simple.hasPrefix("#") { return id == String(simple.dropFirst()) }
                let pieces = simple.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
                guard pieces.count >= 2, pieces[0].isEmpty || pieces[0] == element else { return false }
                return pieces.dropFirst().allSatisfy { classes.contains($0) }
            }
        }

        private func parseDeclarations(_ source: String) -> [String: String] {
            var result: [String: String] = [:]
            for part in source.split(separator: ";") {
                let pair = part.split(separator: ":", maxSplits: 1)
                guard pair.count == 2 else { continue }
                var value = pair[1].trimmingCharacters(in: .whitespacesAndNewlines)
                if let range = value.range(of: "!important") { value = String(value[..<range.lowerBound]).trimmingCharacters(in: .whitespaces) }
                result[pair[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] = value
            }
            return result
        }

        private func parseCSS(_ source: String) -> [(selector: String, declarations: [String: String])] {
            var text = source
            while let start = text.range(of: "/*"), let end = text.range(of: "*/", range: start.upperBound..<text.endIndex) {
                text.removeSubrange(start.lowerBound..<end.upperBound)
            }
            var rules: [(selector: String, declarations: [String: String])] = []
            for block in text.split(separator: "}") {
                let parts = block.split(separator: "{", maxSplits: 1)
                guard parts.count == 2 else { continue }
                let selector = parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !selector.isEmpty, !selector.hasPrefix("@") else { continue }
                rules.append((selector, parseDeclarations(String(parts[1]))))
            }
            return rules
        }

        /// Returns nil for values that should leave the inherited paint untouched (`inherit`, invalid).
        private func parsePaint(_ value: String, style: Style) -> Paint? {
            let v = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            switch v {
            case "none", "transparent": return Paint.none
            case "currentcolor": return .solid(style.color)
            case "inherit", "": return nil
            default:
                if v.hasPrefix("url(") { return .unsupported }
                if let rgb = parseColor(v) { return .solid(rgb) }
                return nil
            }
        }

        private func parseColor(_ value: String) -> RGB? {
            let v = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if v.hasPrefix("#") {
                var hex = String(v.dropFirst())
                guard hex.allSatisfy(\.isHexDigit) else { return nil }
                if hex.count == 3 || hex.count == 4 { hex = hex.prefix(hex.count).map { "\($0)\($0)" }.joined() }
                guard hex.count == 6 || hex.count == 8, let int = UInt64(hex.prefix(6), radix: 16) else { return nil }
                return RGB(r: Double((int >> 16) & 255) / 255, g: Double((int >> 8) & 255) / 255, b: Double(int & 255) / 255)
            }
            if v.hasPrefix("rgb"), let open = v.firstIndex(of: "("), let close = v.lastIndex(of: ")") {
                let parts = v[v.index(after: open)..<close].split(whereSeparator: { $0 == "," || $0 == " " || $0 == "/" })
                guard parts.count >= 3 else { return nil }
                let channels = parts.prefix(3).compactMap { part -> Double? in
                    let s = String(part)
                    if s.hasSuffix("%") { return Double(s.dropLast()).map { min(1, max(0, $0 / 100)) } }
                    return Double(s).map { min(1, max(0, $0 / 255)) }
                }
                guard channels.count == 3 else { return nil }
                return RGB(r: channels[0], g: channels[1], b: channels[2])
            }
            return Self.namedColors[v].map { RGB(r: Double(($0 >> 16) & 255) / 255, g: Double(($0 >> 8) & 255) / 255, b: Double($0 & 255) / 255) }
        }

        private static let namedColors: [String: UInt32] = [
            "black": 0x000000, "white": 0xFFFFFF, "red": 0xFF0000, "green": 0x008000, "blue": 0x0000FF,
            "yellow": 0xFFFF00, "cyan": 0x00FFFF, "aqua": 0x00FFFF, "magenta": 0xFF00FF, "fuchsia": 0xFF00FF,
            "gray": 0x808080, "grey": 0x808080, "silver": 0xC0C0C0, "maroon": 0x800000, "olive": 0x808000,
            "lime": 0x00FF00, "teal": 0x008080, "navy": 0x000080, "purple": 0x800080, "orange": 0xFFA500,
            "pink": 0xFFC0CB, "brown": 0xA52A2A, "gold": 0xFFD700, "darkgray": 0xA9A9A9, "darkgrey": 0xA9A9A9,
            "lightgray": 0xD3D3D3, "lightgrey": 0xD3D3D3, "dimgray": 0x696969, "dimgrey": 0x696969,
            "darkred": 0x8B0000, "darkgreen": 0x006400, "darkblue": 0x00008B, "crimson": 0xDC143C,
            "tomato": 0xFF6347, "coral": 0xFF7F50, "salmon": 0xFA8072, "khaki": 0xF0E68C, "indigo": 0x4B0082,
            "violet": 0xEE82EE, "turquoise": 0x40E0D0, "tan": 0xD2B48C, "beige": 0xF5F5DC, "ivory": 0xFFFFF0
        ]

        private func parseTransforms(_ source: String) -> [CGAffineTransform]? {
            let pattern = "([A-Za-z]+)\\s*\\(([^)]*)\\)"
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
            let nsSource = source as NSString
            let matches = regex.matches(in: source, range: NSRange(location: 0, length: nsSource.length))
            guard !matches.isEmpty else { return source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? [] : nil }
            var parsed: [CGAffineTransform] = []
            var previousEnd = 0
            for match in matches {
                let gap = nsSource.substring(with: NSRange(location: previousEnd, length: match.range.location - previousEnd))
                guard gap.allSatisfy({ $0.isWhitespace || $0 == "," }),
                      let nameRange = Range(match.range(at: 1), in: source),
                      let valueRange = Range(match.range(at: 2), in: source),
                      let values = parseNumbers(String(source[valueRange])) else { return nil }
                let name = source[nameRange].lowercased()
                let transform: CGAffineTransform
                switch name {
                case "matrix" where values.count == 6:
                    transform = CGAffineTransform(a: values[0], b: values[1], c: values[2], d: values[3], tx: values[4], ty: values[5])
                case "translate" where (1...2).contains(values.count):
                    transform = CGAffineTransform(translationX: values[0], y: values.count == 2 ? values[1] : 0)
                case "scale" where (1...2).contains(values.count):
                    transform = CGAffineTransform(scaleX: values[0], y: values.count == 2 ? values[1] : values[0])
                case "rotate" where values.count == 1 || values.count == 3:
                    let angle = values[0] * .pi / 180
                    if values.count == 3 {
                        let center = CGPoint(x: values[1], y: values[2])
                        parsed.append(CGAffineTransform(translationX: center.x, y: center.y))
                        parsed.append(CGAffineTransform(rotationAngle: angle))
                        parsed.append(CGAffineTransform(translationX: -center.x, y: -center.y))
                        previousEnd = NSMaxRange(match.range)
                        continue
                    }
                    transform = CGAffineTransform(rotationAngle: angle)
                case "skewx" where values.count == 1:
                    transform = CGAffineTransform(a: 1, b: 0, c: tan(values[0] * .pi / 180), d: 1, tx: 0, ty: 0)
                case "skewy" where values.count == 1:
                    transform = CGAffineTransform(a: 1, b: tan(values[0] * .pi / 180), c: 0, d: 1, tx: 0, ty: 0)
                default: return nil
                }
                parsed.append(transform)
                previousEnd = NSMaxRange(match.range)
            }
            let trailing = nsSource.substring(from: previousEnd)
            guard trailing.allSatisfy({ $0.isWhitespace || $0 == "," }) else { return nil }
            return parsed
        }

        private func number(_ value: String?, default fallback: Double = 0) -> Double {
            guard let value, let match = parseNumbers(value)?.first else { return fallback }
            return match
        }

        private func parseNumbers(_ value: String) -> [Double]? {
            let pattern = "[-+]?(?:[0-9]*\\.)?[0-9]+(?:[eE][-+]?[0-9]+)?"
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
            let range = NSRange(value.startIndex..., in: value)
            return regex.matches(in: value, range: range).compactMap { match in
                guard let r = Range(match.range, in: value) else { return nil }
                return Double(value[r])
            }
        }

        private func parsePath(_ source: String) -> [(points: [CGPoint], closed: Bool)]? {
            let chars = Array(source.unicodeScalars)
            var idx = 0

            func skipSeparators() {
                while idx < chars.count {
                    let c = chars[idx]
                    if CharacterSet.whitespacesAndNewlines.contains(c) || c == "," {
                        idx += 1
                    } else {
                        break
                    }
                }
            }

            func readCommand() -> Character? {
                skipSeparators()
                guard idx < chars.count else { return nil }
                let c = chars[idx]
                if CharacterSet.letters.contains(c) && c != "e" && c != "E" {
                    idx += 1
                    return Character(c)
                }
                return nil
            }

            func readNumber() -> Double? {
                skipSeparators()
                guard idx < chars.count else { return nil }
                let startIdx = idx
                if chars[idx] == "+" || chars[idx] == "-" { idx += 1 }
                var hasDigits = false
                while idx < chars.count, ("0"..."9").contains(chars[idx]) {
                    idx += 1
                    hasDigits = true
                }
                if idx < chars.count, chars[idx] == "." {
                    idx += 1
                    while idx < chars.count, ("0"..."9").contains(chars[idx]) {
                        idx += 1
                        hasDigits = true
                    }
                }
                guard hasDigits else {
                    idx = startIdx
                    return nil
                }
                if idx < chars.count, (chars[idx] == "e" || chars[idx] == "E") {
                    let expBacktrack = idx
                    idx += 1
                    if idx < chars.count, (chars[idx] == "+" || chars[idx] == "-") { idx += 1 }
                    var expDigits = false
                    while idx < chars.count, ("0"..."9").contains(chars[idx]) {
                        idx += 1
                        expDigits = true
                    }
                    if !expDigits { idx = expBacktrack }
                }
                let str = String(String.UnicodeScalarView(chars[startIdx..<idx]))
                return Double(str)
            }

            func readFlag() -> Bool? {
                skipSeparators()
                guard idx < chars.count else { return nil }
                let c = chars[idx]
                if c == "0" { idx += 1; return false }
                if c == "1" { idx += 1; return true }
                return nil
            }

            var paths: [(points: [CGPoint], closed: Bool)] = []
            var points: [CGPoint] = [], current = CGPoint.zero, start = CGPoint.zero
            var command: Character?
            var previousSegment: Character?
            var previousCubicControl: CGPoint?
            var previousQuadraticControl: CGPoint?

            func finish(_ close: Bool = false) {
                if close, let first = points.first, points.last != first { points.append(first) }
                if points.count > 1 { paths.append((points, close)) }
                points = []
            }

            func ensureSubpathStarted() {
                if points.isEmpty {
                    points.append(current)
                    start = current
                }
            }

            while true {
                skipSeparators()
                if idx >= chars.count { break }
                if let nextCmd = readCommand() {
                    command = nextCmd
                }
                guard let cmd = command else { break }
                let relative = cmd.isLowercase
                switch cmd.uppercased() {
                case "M", "L":
                    guard let x = readNumber(), let y = readNumber() else { return paths.isEmpty ? nil : paths }
                    let point = CGPoint(x: relative ? current.x + x : x, y: relative ? current.y + y : y)
                    if cmd.uppercased() == "M" {
                        finish()
                        start = point
                        command = relative ? "l" : "L"
                    } else {
                        ensureSubpathStarted()
                    }
                    current = point
                    points.append(point)
                    previousSegment = cmd.uppercased().first
                case "H":
                    guard let x = readNumber() else { return paths.isEmpty ? nil : paths }
                    ensureSubpathStarted()
                    current.x = relative ? current.x + x : x
                    points.append(current)
                    previousSegment = "H"
                case "V":
                    guard let y = readNumber() else { return paths.isEmpty ? nil : paths }
                    ensureSubpathStarted()
                    current.y = relative ? current.y + y : y
                    points.append(current)
                    previousSegment = "V"
                case "Q":
                    guard let x1 = readNumber(), let y1 = readNumber(), let x = readNumber(), let y = readNumber() else { return paths.isEmpty ? nil : paths }
                    ensureSubpathStarted()
                    let p0 = current, c = CGPoint(x: relative ? current.x + x1 : x1, y: relative ? current.y + y1 : y1)
                    let end = CGPoint(x: relative ? current.x + x : x, y: relative ? current.y + y : y)
                    for step in 1...12 { let t = Double(step) / 12, u = 1 - t; points.append(CGPoint(x: u*u*p0.x + 2*u*t*c.x + t*t*end.x, y: u*u*p0.y + 2*u*t*c.y + t*t*end.y)) }
                    current = end; previousQuadraticControl = c; previousSegment = "Q"
                case "T":
                    guard let x = readNumber(), let y = readNumber() else { return paths.isEmpty ? nil : paths }
                    ensureSubpathStarted()
                    let end = CGPoint(x: relative ? current.x + x : x, y: relative ? current.y + y : y)
                    let control = (previousSegment == "Q" || previousSegment == "T")
                        ? CGPoint(x: 2 * current.x - (previousQuadraticControl?.x ?? current.x), y: 2 * current.y - (previousQuadraticControl?.y ?? current.y))
                        : current
                    let p0 = current
                    for step in 1...12 { let t = Double(step) / 12, u = 1 - t; points.append(CGPoint(x: u*u*p0.x + 2*u*t*control.x + t*t*end.x, y: u*u*p0.y + 2*u*t*control.y + t*t*end.y)) }
                    current = end; previousQuadraticControl = control; previousSegment = "T"
                case "C":
                    guard let x1 = readNumber(), let y1 = readNumber(), let x2 = readNumber(), let y2 = readNumber(), let x = readNumber(), let y = readNumber() else { return paths.isEmpty ? nil : paths }
                    ensureSubpathStarted()
                    let p0 = current, c1 = CGPoint(x: relative ? current.x + x1 : x1, y: relative ? current.y + y1 : y1)
                    let c2 = CGPoint(x: relative ? current.x + x2 : x2, y: relative ? current.y + y2 : y2)
                    let end = CGPoint(x: relative ? current.x + x : x, y: relative ? current.y + y : y)
                    for step in 1...16 { let t = Double(step) / 16, u = 1 - t; points.append(CGPoint(x: u*u*u*p0.x + 3*u*u*t*c1.x + 3*u*t*t*c2.x + t*t*t*end.x, y: u*u*u*p0.y + 3*u*u*t*c1.y + 3*u*t*t*c2.y + t*t*t*end.y)) }
                    current = end; previousCubicControl = c2; previousSegment = "C"
                case "S":
                    guard let x2 = readNumber(), let y2 = readNumber(), let x = readNumber(), let y = readNumber() else { return paths.isEmpty ? nil : paths }
                    ensureSubpathStarted()
                    let c1 = (previousSegment == "C" || previousSegment == "S")
                        ? CGPoint(x: 2 * current.x - (previousCubicControl?.x ?? current.x), y: 2 * current.y - (previousCubicControl?.y ?? current.y))
                        : current
                    let c2 = CGPoint(x: relative ? current.x + x2 : x2, y: relative ? current.y + y2 : y2)
                    let end = CGPoint(x: relative ? current.x + x : x, y: relative ? current.y + y : y)
                    let p0 = current
                    for step in 1...16 { let t = Double(step) / 16, u = 1 - t; points.append(CGPoint(x: u*u*u*p0.x + 3*u*u*t*c1.x + 3*u*t*t*c2.x + t*t*t*end.x, y: u*u*u*p0.y + 3*u*u*t*c1.y + 3*u*t*t*c2.y + t*t*t*end.y)) }
                    current = end; previousCubicControl = c2; previousSegment = "S"
                case "A":
                    guard let rx = readNumber(), let ry = readNumber(), let rotation = readNumber(),
                          let largeArc = readFlag(), let sweep = readFlag(),
                          let x = readNumber(), let y = readNumber() else { return paths.isEmpty ? nil : paths }
                    ensureSubpathStarted()
                    let end = CGPoint(x: relative ? current.x + x : x, y: relative ? current.y + y : y)
                    points.append(contentsOf: arcPoints(from: current, to: end, radiusX: rx, radiusY: ry,
                                                        rotation: rotation, largeArc: largeArc, sweep: sweep))
                    current = end; previousSegment = "A"
                case "Z":
                    current = start
                    finish(true)
                    command = relative ? "m" : "M"
                    previousSegment = "Z"
                default:
                    return paths.isEmpty ? nil : paths
                }
            }
            finish()
            return paths.isEmpty ? nil : paths
        }

        private func arcPoints(from start: CGPoint, to end: CGPoint, radiusX: Double, radiusY: Double,
                               rotation: Double, largeArc: Bool, sweep: Bool) -> [CGPoint] {
            let x1 = Double(start.x), y1 = Double(start.y), x2 = Double(end.x), y2 = Double(end.y)
            var rx = abs(radiusX), ry = abs(radiusY)
            guard rx > 0, ry > 0, start != end else { return [end] }
            let phi = rotation * .pi / 180
            let cosPhi = cos(phi), sinPhi = sin(phi)
            let dx = (x1 - x2) / 2, dy = (y1 - y2) / 2
            let xPrime = cosPhi * dx + sinPhi * dy
            let yPrime = -sinPhi * dx + cosPhi * dy
            let radiusScale = xPrime * xPrime / (rx * rx) + yPrime * yPrime / (ry * ry)
            if radiusScale > 1 {
                let factor = sqrt(radiusScale)
                rx *= factor; ry *= factor
            }
            let rx2 = rx * rx, ry2 = ry * ry
            let numerator = max(0, rx2 * ry2 - rx2 * yPrime * yPrime - ry2 * xPrime * xPrime)
            let denominator = rx2 * yPrime * yPrime + ry2 * xPrime * xPrime
            let sign = largeArc == sweep ? -1.0 : 1.0
            let coefficient = denominator == 0 ? 0 : sign * sqrt(numerator / denominator)
            let centerXPrime = coefficient * rx * yPrime / ry
            let centerYPrime = coefficient * -ry * xPrime / rx
            let centerX = cosPhi * centerXPrime - sinPhi * centerYPrime + (x1 + x2) / 2
            let centerY = sinPhi * centerXPrime + cosPhi * centerYPrime + (y1 + y2) / 2
            let u = ((xPrime - centerXPrime) / rx, (yPrime - centerYPrime) / ry)
            let v = ((-xPrime - centerXPrime) / rx, (-yPrime - centerYPrime) / ry)
            let startAngle = atan2(u.1, u.0)
            var deltaAngle = atan2(u.0 * v.1 - u.1 * v.0, u.0 * v.0 + u.1 * v.1)
            if !sweep && deltaAngle > 0 { deltaAngle -= 2 * .pi }
            if sweep && deltaAngle < 0 { deltaAngle += 2 * .pi }
            let segmentCount = min(180, max(2, Int(ceil(abs(deltaAngle) / (.pi / 18)))) )
            return (1...segmentCount).map { index in
                let angle = startAngle + deltaAngle * Double(index) / Double(segmentCount)
                let x = centerX + cosPhi * rx * cos(angle) - sinPhi * ry * sin(angle)
                let y = centerY + sinPhi * rx * cos(angle) + cosPhi * ry * sin(angle)
                return index == segmentCount ? end : CGPoint(x: x, y: y)
            }
        }
    }

    private enum ImportError: LocalizedError {
        case invalidSVG
        var errorDescription: String? {
            switch self {
            case .invalidSVG: "The SVG file is invalid or contains unsupported path commands."
            }
        }
    }
}
