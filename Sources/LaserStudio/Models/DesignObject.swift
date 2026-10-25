import SwiftUI
import AppKit
import CoreGraphics
import CoreText

struct PathSubpath: Equatable {
    var points: [CGPoint]
    var isClosed: Bool
}

enum ImageDitherMode: String, CaseIterable, Identifiable {
    case threshold = "Threshold"
    case ordered = "Ordered"
    case atkinson = "Atkinson"
    case dither = "Dither"
    case stucki = "Stucki"
    case jarvis = "Jarvis"
    case burkes = "Burkes"
    case newsprint = "Newsprint"
    case halftone = "Halftone"
    case sketch = "Sketch"
    case grayscale = "Grayscale"
    var id: String { rawValue }
}

enum OffsetDirection: String, CaseIterable, Identifiable {
    case outward = "Outward"
    case inward = "Inward"
    case both = "Both"
    var id: String { rawValue }
}

enum OffsetCornerStyle: String, CaseIterable, Identifiable {
    case round = "Round"
    case sharp = "Sharp"
    case bevel = "Bevel"
    var id: String { rawValue }
}

enum BooleanOperationKind: String, CaseIterable, Identifiable {
    case weld = "Weld"
    case union = "Union"
    case subtract = "Subtract"
    case intersect = "Intersect"
    var id: String { rawValue }
}

struct LightBurnLayerSwatch: Identifiable, Equatable {
    let index: Int
    let code: String
    let name: String
    let r: Double
    let g: Double
    let b: Double
    let isTool: Bool

    var id: Int { index }
    var isToolLayer: Bool { isTool }
    var color: Color { Color(red: r, green: g, blue: b) }
}

enum LightBurnPalette {
    static var toolLayers: [LightBurnLayerSwatch] {
        layers.filter(\.isTool)
    }
    static let layers: [LightBurnLayerSwatch] = [
        LightBurnLayerSwatch(index: 0,  code: "00", name: "Black",       r: 0x00/255.0, g: 0x00/255.0, b: 0x00/255.0, isTool: false),
        LightBurnLayerSwatch(index: 1,  code: "01", name: "Blue",        r: 0x00/255.0, g: 0x00/255.0, b: 0xFF/255.0, isTool: false),
        LightBurnLayerSwatch(index: 2,  code: "02", name: "Red",         r: 0xFF/255.0, g: 0x00/255.0, b: 0x00/255.0, isTool: false),
        LightBurnLayerSwatch(index: 3,  code: "03", name: "Green",       r: 0x00/255.0, g: 0xE0/255.0, b: 0x00/255.0, isTool: false),
        LightBurnLayerSwatch(index: 4,  code: "04", name: "Yellow",      r: 0xD0/255.0, g: 0xD0/255.0, b: 0x00/255.0, isTool: false),
        LightBurnLayerSwatch(index: 5,  code: "05", name: "Orange",      r: 0xFF/255.0, g: 0x80/255.0, b: 0x00/255.0, isTool: false),
        LightBurnLayerSwatch(index: 6,  code: "06", name: "Cyan",        r: 0x00/255.0, g: 0xE0/255.0, b: 0xE0/255.0, isTool: false),
        LightBurnLayerSwatch(index: 7,  code: "07", name: "Magenta",     r: 0xFF/255.0, g: 0x00/255.0, b: 0xFF/255.0, isTool: false),
        LightBurnLayerSwatch(index: 8,  code: "08", name: "Light Gray",  r: 0xB4/255.0, g: 0xB4/255.0, b: 0xB4/255.0, isTool: false),
        LightBurnLayerSwatch(index: 9,  code: "09", name: "Dark Blue",   r: 0x00/255.0, g: 0x00/255.0, b: 0xA0/255.0, isTool: false),
        LightBurnLayerSwatch(index: 10, code: "10", name: "Dark Red",    r: 0xA0/255.0, g: 0x00/255.0, b: 0x00/255.0, isTool: false),
        LightBurnLayerSwatch(index: 11, code: "11", name: "Dark Green",  r: 0x00/255.0, g: 0xA0/255.0, b: 0x00/255.0, isTool: false),
        LightBurnLayerSwatch(index: 12, code: "12", name: "Olive",       r: 0xA0/255.0, g: 0xA0/255.0, b: 0x00/255.0, isTool: false),
        LightBurnLayerSwatch(index: 13, code: "13", name: "Brown",       r: 0xC0/255.0, g: 0x80/255.0, b: 0x00/255.0, isTool: false),
        LightBurnLayerSwatch(index: 14, code: "14", name: "Teal",        r: 0x00/255.0, g: 0xA0/255.0, b: 0xFF/255.0, isTool: false),
        LightBurnLayerSwatch(index: 15, code: "15", name: "Purple",      r: 0xA0/255.0, g: 0x00/255.0, b: 0xA0/255.0, isTool: false),
        LightBurnLayerSwatch(index: 16, code: "16", name: "Gray",        r: 0x80/255.0, g: 0x80/255.0, b: 0x80/255.0, isTool: false),
        LightBurnLayerSwatch(index: 17, code: "17", name: "Slate Blue",  r: 0x7D/255.0, g: 0x87/255.0, b: 0xB9/255.0, isTool: false),
        LightBurnLayerSwatch(index: 18, code: "18", name: "Rose",        r: 0xBB/255.0, g: 0x77/255.0, b: 0x84/255.0, isTool: false),
        LightBurnLayerSwatch(index: 19, code: "19", name: "Royal Blue",  r: 0x4A/255.0, g: 0x6F/255.0, b: 0xE3/255.0, isTool: false),
        LightBurnLayerSwatch(index: 20, code: "20", name: "Coral",       r: 0xD3/255.0, g: 0x3F/255.0, b: 0x6A/255.0, isTool: false),
        LightBurnLayerSwatch(index: 21, code: "21", name: "Lime",        r: 0x8C/255.0, g: 0xD7/255.0, b: 0x8C/255.0, isTool: false),
        LightBurnLayerSwatch(index: 22, code: "22", name: "Tan",         r: 0xF0/255.0, g: 0xB9/255.0, b: 0x8D/255.0, isTool: false),
        LightBurnLayerSwatch(index: 23, code: "23", name: "Pink",        r: 0xF6/255.0, g: 0xC4/255.0, b: 0xE1/255.0, isTool: false),
        LightBurnLayerSwatch(index: 24, code: "24", name: "Sky",         r: 0xFA/255.0, g: 0x9E/255.0, b: 0xD4/255.0, isTool: false),
        LightBurnLayerSwatch(index: 25, code: "25", name: "Plum",        r: 0x50/255.0, g: 0x0A/255.0, b: 0x78/255.0, isTool: false),
        LightBurnLayerSwatch(index: 26, code: "26", name: "Sienna",      r: 0xB4/255.0, g: 0x5A/255.0, b: 0x00/255.0, isTool: false),
        LightBurnLayerSwatch(index: 27, code: "27", name: "Aqua",        r: 0x00/255.0, g: 0x96/255.0, b: 0x78/255.0, isTool: false),
        LightBurnLayerSwatch(index: 28, code: "28", name: "Lavender",    r: 0x8E/255.0, g: 0x7C/255.0, b: 0xC3/255.0, isTool: false),
        LightBurnLayerSwatch(index: 29, code: "29", name: "Gold",        r: 0xFF/255.0, g: 0xDB/255.0, b: 0x66/255.0, isTool: false),
        LightBurnLayerSwatch(index: 30, code: "T1", name: "Tool 1",      r: 0xF3/255.0, g: 0x68/255.0, b: 0x12/255.0, isTool: true),
        LightBurnLayerSwatch(index: 31, code: "T2", name: "Tool 2",      r: 0x0F/255.0, g: 0x8F/255.0, b: 0xD6/255.0, isTool: true)
    ]

    static func closestSwatch(for color: Color, isToolLayer: Bool = false) -> LightBurnLayerSwatch {
        let nsColor = NSColor(color).usingColorSpace(.sRGB) ?? NSColor.red
        let r = Double(nsColor.redComponent)
        let g = Double(nsColor.greenComponent)
        let b = Double(nsColor.blueComponent)
        let candidates = isToolLayer ? layers.filter(\.isTool) : layers.filter { !$0.isTool }
        var best = candidates.first ?? layers[0]
        var bestDistance = Double.greatestFiniteMagnitude
        for entry in candidates {
            let dr = r - entry.r, dg = g - entry.g, db = b - entry.b
            let dist = 2.0 * dr * dr + 4.0 * dg * dg + 3.0 * db * db
            if dist < bestDistance {
                bestDistance = dist
                best = entry
            }
        }
        return best
    }
}

struct DesignObject: Identifiable, Equatable {
    enum Kind: String {
        case rectangle = "Rectangle"
        case circle = "Circle"
        case polygon = "Polygon"
        case text = "Text"
        case line = "Line"
        case path = "Path"
        case image = "Image"
    }

    var id: UUID
    var kind: Kind
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var rotation: Double
    var label: String
    var fontFamily: String
    var fontBold: Bool
    var fontItalic: Bool
    var fontUnderline: Bool
    var fontStrikethrough: Bool
    var fontUppercase: Bool
    var color: Color
    var power: Double
    var minPower: Double
    var speed: Double
    var burnEnabled: Bool
    var layerMode: EngravingMode
    var passCount: Int
    var zOffset: Double
    var zPerPass: Double
    var kerfOffset: Double
    var useCustomInterval: Bool
    var lineInterval: Double
    var scanAngle: Double
    var crossHatch: Bool
    var bidirectionalFill: Bool
    var overscanEnabled: Bool
    var overscanPercent: Double
    var floodFill: Bool
    var constantPower: Bool
    var airAssist: Bool
    var perforationEnabled: Bool
    var perforationCutLength: Double
    var perforationSkipLength: Double
    var tabsEnabled: Bool
    var tabSize: Double
    var tabCount: Int
    var overcut: Double
    var isToolLayer: Bool
    var isLocked: Bool
    var cornerRadius: Double
    var polygonSides: Int
    var pathPoints: [CGPoint]
    var pathIsClosed: Bool
    var pathSubpaths: [PathSubpath]
    var imageData: Data?
    var imagePixels: Data?
    var imagePixelWidth: Int
    var imagePixelHeight: Int
    var imageInverted: Bool
    var minimumSpeed: Double
    var maximumSpeed: Double
    var variablePower: Bool
    var imageDitherMode: ImageDitherMode
    var imageDPI: Double
    var imagePassThrough: Bool
    var imageGamma: Double
    var imageContrast: Double
    var imageBrightness: Double
    var imageEnhanceRadius: Double
    var imageEnhanceAmount: Double
    var isVisible: Bool
    var groupID: UUID?

    var resolvedSubpaths: [PathSubpath] {
        if pathSubpaths.count > 1 { return pathSubpaths }
        if pathPoints.count > 1 { return [PathSubpath(points: pathPoints, isClosed: pathIsClosed)] }
        return pathSubpaths
    }

    var lightBurnSwatch: LightBurnLayerSwatch {
        LightBurnPalette.closestSwatch(for: color, isToolLayer: isToolLayer)
    }

    init(
        kind: Kind,
        x: Double,
        y: Double,
        width: Double,
        height: Double,
        label: String,
        rotation: Double = 0,
        color: Color = .red,
        power: Double = 18,
        minPower: Double = 10,
        speed: Double = 3000,
        burnEnabled: Bool = true,
        layerMode: EngravingMode = .line,
        passCount: Int = 1,
        zOffset: Double = 0,
        zPerPass: Double = 0,
        kerfOffset: Double = 0,
        useCustomInterval: Bool = false,
        lineInterval: Double = 0.1,
        scanAngle: Double = 0,
        crossHatch: Bool = false,
        bidirectionalFill: Bool = true,
        overscanEnabled: Bool = false,
        overscanPercent: Double = 2.5,
        floodFill: Bool = false,
        constantPower: Bool = false,
        airAssist: Bool = false,
        perforationEnabled: Bool = false,
        perforationCutLength: Double = 2.0,
        perforationSkipLength: Double = 1.0,
        tabsEnabled: Bool = false,
        tabSize: Double = 0.8,
        tabCount: Int = 4,
        overcut: Double = 0,
        isToolLayer: Bool = false,
        isLocked: Bool = false,
        cornerRadius: Double = 0,
        polygonSides: Int = 6,
        pathPoints: [CGPoint] = [],
        pathIsClosed: Bool = false,
        pathSubpaths: [PathSubpath] = [],
        imageData: Data? = nil,
        imagePixels: Data? = nil,
        imagePixelWidth: Int = 0,
        imagePixelHeight: Int = 0,
        imageInverted: Bool = false,
        minimumSpeed: Double = 1000,
        maximumSpeed: Double = 5000,
        variablePower: Bool = true,
        imageDitherMode: ImageDitherMode = .grayscale,
        imageDPI: Double = 254,
        imagePassThrough: Bool = false,
        imageGamma: Double = 1.0,
        imageContrast: Double = 0,
        imageBrightness: Double = 0,
        imageEnhanceRadius: Double = 0,
        imageEnhanceAmount: Double = 100,
        fontFamily: String = "Helvetica",
        fontBold: Bool = false,
        fontItalic: Bool = false,
        fontUnderline: Bool = false,
        fontStrikethrough: Bool = false,
        fontUppercase: Bool = false,
        isVisible: Bool = true,
        groupID: UUID? = nil
    ) {
        self.id = UUID()
        self.kind = kind
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.rotation = rotation
        self.label = label
        self.fontFamily = fontFamily
        self.fontBold = fontBold
        self.fontItalic = fontItalic
        self.fontUnderline = fontUnderline
        self.fontStrikethrough = fontStrikethrough
        self.fontUppercase = fontUppercase
        self.color = color
        self.power = power
        self.minPower = minPower
        self.speed = speed
        self.burnEnabled = burnEnabled
        self.layerMode = layerMode
        self.passCount = passCount
        self.zOffset = zOffset
        self.zPerPass = zPerPass
        self.kerfOffset = kerfOffset
        self.useCustomInterval = useCustomInterval
        self.lineInterval = lineInterval
        self.scanAngle = scanAngle
        self.crossHatch = crossHatch
        self.bidirectionalFill = bidirectionalFill
        self.overscanEnabled = overscanEnabled
        self.overscanPercent = overscanPercent
        self.floodFill = floodFill
        self.constantPower = constantPower
        self.airAssist = airAssist
        self.perforationEnabled = perforationEnabled
        self.perforationCutLength = perforationCutLength
        self.perforationSkipLength = perforationSkipLength
        self.tabsEnabled = tabsEnabled
        self.tabSize = tabSize
        self.tabCount = tabCount
        self.overcut = overcut
        self.isToolLayer = isToolLayer
        self.isLocked = isLocked
        self.cornerRadius = cornerRadius
        self.polygonSides = max(3, polygonSides)
        if !pathSubpaths.isEmpty {
            self.pathSubpaths = pathSubpaths
            self.pathPoints = pathPoints.isEmpty ? (pathSubpaths.first?.points ?? []) : pathPoints
            self.pathIsClosed = pathPoints.isEmpty ? (pathSubpaths.allSatisfy(\.isClosed)) : pathIsClosed
        } else if !pathPoints.isEmpty {
            self.pathPoints = pathPoints
            self.pathIsClosed = pathIsClosed
            self.pathSubpaths = [PathSubpath(points: pathPoints, isClosed: pathIsClosed)]
        } else {
            self.pathPoints = []
            self.pathIsClosed = pathIsClosed
            self.pathSubpaths = []
        }
        self.imageData = imageData
        self.imagePixels = imagePixels
        self.imagePixelWidth = imagePixelWidth
        self.imagePixelHeight = imagePixelHeight
        self.imageInverted = imageInverted
        self.minimumSpeed = minimumSpeed
        self.maximumSpeed = maximumSpeed
        self.variablePower = variablePower
        self.imageDitherMode = imageDitherMode
        self.imageDPI = imageDPI
        self.imagePassThrough = imagePassThrough
        self.imageGamma = imageGamma
        self.imageContrast = imageContrast
        self.imageBrightness = imageBrightness
        self.imageEnhanceRadius = imageEnhanceRadius
        self.imageEnhanceAmount = imageEnhanceAmount
        self.isVisible = isVisible
        self.groupID = groupID
    }
}
enum ShapeGeometry {
    static func localPolygonPoints(width: Double, height: Double, sides: Int, cornerRadius: Double = 0) -> [CGPoint] {
        let count = max(3, sides)
        let cx = width / 2, cy = height / 2
        let rx = width / 2, ry = height / 2
        var vertices: [CGPoint] = []
        for i in 0..<count {
            let angle = -Double.pi / 2 + 2 * Double.pi * Double(i) / Double(count)
            vertices.append(CGPoint(x: cx + rx * cos(angle), y: cy + ry * sin(angle)))
        }
        if cornerRadius > 0 {
            return filletPolygon(vertices, radius: cornerRadius, isClosed: true)
        }
        vertices.append(vertices[0])
        return vertices
    }

    static func localRoundedRectPoints(width: Double, height: Double, radius: Double) -> [CGPoint] {
        let r = min(max(0, radius), min(width, height) / 2)
        guard r > 0.01 else {
            return [
                CGPoint(x: 0, y: 0),
                CGPoint(x: width, y: 0),
                CGPoint(x: width, y: height),
                CGPoint(x: 0, y: height),
                CGPoint(x: 0, y: 0)
            ]
        }
        var pts: [CGPoint] = []
        let corners: [(cx: Double, cy: Double, startAngle: Double)] = [
            (width - r, r, -Double.pi / 2),
            (width - r, height - r, 0),
            (r, height - r, Double.pi / 2),
            (r, r, Double.pi)
        ]
        let steps = 8
        for corner in corners {
            for s in 0...steps {
                let theta = corner.startAngle + (Double.pi / 2) * Double(s) / Double(steps)
                pts.append(CGPoint(x: corner.cx + r * cos(theta), y: corner.cy + r * sin(theta)))
            }
        }
        if let first = pts.first { pts.append(first) }
        return pts
    }

    static func localSubpaths(for object: DesignObject) -> [PathSubpath] {
        switch object.kind {
        case .rectangle:
            return [PathSubpath(points: localRoundedRectPoints(width: object.width, height: object.height, radius: object.cornerRadius), isClosed: true)]
        case .circle:
            let steps = max(48, Int(max(object.width, object.height) * 1.5))
            let pts = (0...steps).map { i -> CGPoint in
                let a = 2 * Double.pi * Double(i) / Double(steps)
                return CGPoint(x: object.width / 2 + cos(a) * object.width / 2,
                               y: object.height / 2 + sin(a) * object.height / 2)
            }
            return [PathSubpath(points: pts, isClosed: true)]
        case .polygon:
            return [PathSubpath(points: localPolygonPoints(width: object.width, height: object.height, sides: object.polygonSides, cornerRadius: object.cornerRadius), isClosed: true)]
        case .line:
            return [PathSubpath(points: [CGPoint.zero, CGPoint(x: object.width, y: object.height)], isClosed: false)]
        case .path:
            return object.resolvedSubpaths
        case .text:
            let displayText = object.fontUppercase ? object.label.uppercased() : object.label
            let metrics = SystemFontCatalog.fittedTextMetrics(
                label: displayText, family: object.fontFamily,
                width: object.width, height: object.height,
                bold: object.fontBold, italic: object.fontItalic
            )
            let font = metrics.font
            let attributed = NSAttributedString(string: displayText, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
            let line = CTLineCreateWithAttributedString(attributed)
            var subpaths: [PathSubpath] = []
            let scale = Double(metrics.scale)
            let ascent = Double(metrics.ascent)
            let descent = Double(metrics.descent)
            let renderedW = Double(metrics.lineWidth) * scale
            let hOffset = (object.width - renderedW) / 2
            let vOffset = (object.height - (ascent + descent) * scale) / 2
            for runValue in CTLineGetGlyphRuns(line) as! [CTRun] {
                let count = CTRunGetGlyphCount(runValue)
                var glyphs = Array(repeating: CGGlyph(), count: count)
                var positions = Array(repeating: CGPoint.zero, count: count)
                CTRunGetGlyphs(runValue, CFRange(location: 0, length: 0), &glyphs)
                CTRunGetPositions(runValue, CFRange(location: 0, length: 0), &positions)
                for i in 0..<count {
                    guard let glyphPath = CTFontCreatePathForGlyph(font, glyphs[i], nil) else { continue }
                    let transform = CGAffineTransform(translationX: positions[i].x, y: positions[i].y)
                    let positioned = glyphPath.copy(using: [transform]) ?? glyphPath
                    var pts: [CGPoint] = []
                    var current = CGPoint.zero
                    positioned.applyWithBlock { ptr in
                        let el = ptr.pointee
                        switch el.type {
                        case .moveToPoint:
                            if pts.count > 1 { subpaths.append(PathSubpath(points: pts, isClosed: true)) }
                            current = el.points[0]
                            pts = [CGPoint(x: hOffset + Double(current.x) * scale, y: vOffset + (ascent - Double(current.y)) * scale)]
                        case .addLineToPoint:
                            current = el.points[0]
                            pts.append(CGPoint(x: hOffset + Double(current.x) * scale, y: vOffset + (ascent - Double(current.y)) * scale))
                        case .addQuadCurveToPoint:
                            let p0 = current, c = el.points[0], end = el.points[1]
                            for s in 1...8 {
                                let t = CGFloat(s) / 8, u = 1 - t
                                let p = CGPoint(x: u*u*p0.x + 2*u*t*c.x + t*t*end.x, y: u*u*p0.y + 2*u*t*c.y + t*t*end.y)
                                pts.append(CGPoint(x: hOffset + Double(p.x) * scale, y: vOffset + (ascent - Double(p.y)) * scale))
                            }
                            current = end
                        case .addCurveToPoint:
                            let p0 = current, c1 = el.points[0], c2 = el.points[1], end = el.points[2]
                            for s in 1...10 {
                                let t = CGFloat(s) / 10, u = 1 - t
                                let p = CGPoint(
                                    x: u*u*u*p0.x + 3*u*u*t*c1.x + 3*u*t*t*c2.x + t*t*t*end.x,
                                    y: u*u*u*p0.y + 3*u*u*t*c1.y + 3*u*t*t*c2.y + t*t*t*end.y
                                )
                                pts.append(CGPoint(x: hOffset + Double(p.x) * scale, y: vOffset + (ascent - Double(p.y)) * scale))
                            }
                            current = end
                        case .closeSubpath:
                            if let first = pts.first, pts.last != first { pts.append(first) }
                            if pts.count > 1 { subpaths.append(PathSubpath(points: pts, isClosed: true)) }
                            pts = []
                        @unknown default: break
                        }
                    }
                    if pts.count > 1 { subpaths.append(PathSubpath(points: pts, isClosed: true)) }
                }
            }
            let barThickness = max(0.35, (ascent + descent) * scale * 0.055)
            if object.fontUnderline && renderedW > 0.1 {
                let uPos = Double(CTFontGetUnderlinePosition(font))
                let uy = vOffset + (ascent - uPos) * scale
                let pts = [
                    CGPoint(x: hOffset, y: uy - barThickness / 2),
                    CGPoint(x: hOffset + renderedW, y: uy - barThickness / 2),
                    CGPoint(x: hOffset + renderedW, y: uy + barThickness / 2),
                    CGPoint(x: hOffset, y: uy + barThickness / 2),
                    CGPoint(x: hOffset, y: uy - barThickness / 2)
                ]
                subpaths.append(PathSubpath(points: pts, isClosed: true))
            }
            if object.fontStrikethrough && renderedW > 0.1 {
                let sy = vOffset + (ascent * 0.65) * scale
                let pts = [
                    CGPoint(x: hOffset, y: sy - barThickness / 2),
                    CGPoint(x: hOffset + renderedW, y: sy - barThickness / 2),
                    CGPoint(x: hOffset + renderedW, y: sy + barThickness / 2),
                    CGPoint(x: hOffset, y: sy + barThickness / 2),
                    CGPoint(x: hOffset, y: sy - barThickness / 2)
                ]
                subpaths.append(PathSubpath(points: pts, isClosed: true))
            }
            return subpaths
        case .image:
            return []
        }
    }

    static func workspaceSubpaths(for object: DesignObject) -> [PathSubpath] {
        let center = CGPoint(x: object.x + object.width / 2, y: object.y + object.height / 2)
        let rad = object.rotation * .pi / 180
        return localSubpaths(for: object).map { sub in
            let pts = sub.points.map { pt -> CGPoint in
                let wx = object.x + pt.x
                let wy = object.y + pt.y
                guard rad != 0 else { return CGPoint(x: wx, y: wy) }
                let dx = wx - center.x, dy = wy - center.y
                return CGPoint(x: center.x + dx * cos(rad) - dy * sin(rad),
                               y: center.y + dx * sin(rad) + dy * cos(rad))
            }
            return PathSubpath(points: pts, isClosed: sub.isClosed)
        }
    }

    static func convertToPath(_ object: DesignObject) -> DesignObject {
        guard object.kind != .image else { return object }
        let wsSubpaths = workspaceSubpaths(for: object)
        let allPoints = wsSubpaths.flatMap(\.points)
        guard let minX = allPoints.map(\.x).min(),
              let maxX = allPoints.map(\.x).max(),
              let minY = allPoints.map(\.y).min(),
              let maxY = allPoints.map(\.y).max() else { return object }
        let localSubpaths = wsSubpaths.map { sub in
            PathSubpath(points: sub.points.map { CGPoint(x: $0.x - minX, y: $0.y - minY) }, isClosed: sub.isClosed)
        }
        var copy = object
        copy.kind = .path
        copy.x = minX
        copy.y = minY
        copy.width = max(0.5, maxX - minX)
        copy.height = max(0.5, maxY - minY)
        copy.rotation = 0
        copy.pathSubpaths = localSubpaths
        copy.pathPoints = localSubpaths.first?.points ?? []
        copy.pathIsClosed = localSubpaths.allSatisfy(\.isClosed)
        return copy
    }

    /// Breaks a compound vector `.path` or `.text` object into individual subpath `DesignObject`s
    /// (just like LightBurn's "Ungroup" on imported SVGs, traced vectors, or compound paths).
    static func breakApartSubpaths(_ object: DesignObject) -> [DesignObject] {
        guard object.kind == .path || object.kind == .text else { return [object] }
        let wsSubpaths = workspaceSubpaths(for: object).filter { $0.points.count >= 2 }
        guard wsSubpaths.count > 1 else { return [object] }
        return wsSubpaths.enumerated().compactMap { index, sub in
            guard let minX = sub.points.map(\.x).min(),
                  let maxX = sub.points.map(\.x).max(),
                  let minY = sub.points.map(\.y).min(),
                  let maxY = sub.points.map(\.y).max() else { return nil }
            let localPoints = sub.points.map { CGPoint(x: $0.x - minX, y: $0.y - minY) }
            let localSub = PathSubpath(points: localPoints, isClosed: sub.isClosed)
            var part = object
            part.id = UUID()
            part.groupID = nil
            part.kind = .path
            part.label = "\(object.label) (\(index + 1))"
            part.x = minX
            part.y = minY
            part.width = max(0.25, maxX - minX)
            part.height = max(0.25, maxY - minY)
            part.rotation = 0
            part.pathSubpaths = [localSub]
            part.pathPoints = localPoints
            part.pathIsClosed = sub.isClosed
            return part
        }
    }

    /// Combines multiple vector objects into a single compound `.path` object.
    static func combineIntoCompoundPath(_ objects: [DesignObject]) -> DesignObject? {
        let vectorObjs = objects.filter { $0.kind != .image }
        guard let first = vectorObjs.first else { return nil }
        let wsSubpaths = vectorObjs.flatMap { workspaceSubpaths(for: $0) }.filter { $0.points.count >= 2 }
        let allPoints = wsSubpaths.flatMap(\.points)
        guard let minX = allPoints.map(\.x).min(),
              let maxX = allPoints.map(\.x).max(),
              let minY = allPoints.map(\.y).min(),
              let maxY = allPoints.map(\.y).max() else { return nil }
        let localSubpaths = wsSubpaths.map { sub in
            PathSubpath(points: sub.points.map { CGPoint(x: $0.x - minX, y: $0.y - minY) }, isClosed: sub.isClosed)
        }
        var combined = first
        combined.id = UUID()
        combined.groupID = nil
        combined.kind = .path
        combined.x = minX
        combined.y = minY
        combined.width = max(0.25, maxX - minX)
        combined.height = max(0.25, maxY - minY)
        combined.rotation = 0
        combined.pathSubpaths = localSubpaths
        combined.pathPoints = localSubpaths.first?.points ?? []
        combined.pathIsClosed = localSubpaths.allSatisfy(\.isClosed)
        return combined
    }

    /// Explodes a path into individual straight line/segment `.path` objects (LightBurn's Alt+B Break Apart).
    static func breakApartSegments(_ object: DesignObject) -> [DesignObject] {
        guard object.kind != .image else { return [object] }
        let wsSubpaths = workspaceSubpaths(for: object)
        var segments: [DesignObject] = []
        var segIndex = 1
        for sub in wsSubpaths {
            guard sub.points.count >= 2 else { continue }
            for i in 0..<(sub.points.count - 1) {
                let p0 = sub.points[i]
                let p1 = sub.points[i + 1]
                guard hypot(p1.x - p0.x, p1.y - p0.y) > 0.001 else { continue }
                let minX = min(p0.x, p1.x), maxX = max(p0.x, p1.x)
                let minY = min(p0.y, p1.y), maxY = max(p0.y, p1.y)
                let localPts = [CGPoint(x: p0.x - minX, y: p0.y - minY), CGPoint(x: p1.x - minX, y: p1.y - minY)]
                var seg = object
                seg.id = UUID()
                seg.groupID = nil
                seg.kind = .path
                seg.label = "\(object.label) [Seg \(segIndex)]"
                seg.x = minX
                seg.y = minY
                seg.width = max(0.1, maxX - minX)
                seg.height = max(0.1, maxY - minY)
                seg.rotation = 0
                seg.pathSubpaths = [PathSubpath(points: localPts, isClosed: false)]
                seg.pathPoints = localPts
                seg.pathIsClosed = false
                segments.append(seg)
                segIndex += 1
            }
        }
        return segments.isEmpty ? [object] : segments
    }

    static func filletPolygon(_ points: [CGPoint], radius: Double, isClosed: Bool) -> [CGPoint] {
        var verts = points
        if isClosed, verts.count > 2, let f = verts.first, let l = verts.last, hypot(f.x - l.x, f.y - l.y) < 0.001 {
            verts.removeLast()
        }
        guard verts.count >= 3, radius > 0.01 else {
            if isClosed, let f = verts.first, verts.last != f { verts.append(f) }
            return verts
        }
        var result: [CGPoint] = []
        let n = verts.count
        for i in 0..<n {
            if !isClosed && (i == 0 || i == n - 1) {
                result.append(verts[i])
                continue
            }
            let prev = verts[(i - 1 + n) % n]
            let curr = verts[i]
            let next = verts[(i + 1) % n]
            let v1 = CGPoint(x: prev.x - curr.x, y: prev.y - curr.y)
            let v2 = CGPoint(x: next.x - curr.x, y: next.y - curr.y)
            let len1 = hypot(v1.x, v1.y)
            let len2 = hypot(v2.x, v2.y)
            guard len1 > 0.01, len2 > 0.01 else {
                result.append(curr)
                continue
            }
            let u1 = CGPoint(x: v1.x / len1, y: v1.y / len1)
            let u2 = CGPoint(x: v2.x / len2, y: v2.y / len2)
            let dot = max(-0.999, min(0.999, u1.x * u2.x + u1.y * u2.y))
            let halfAngle = acos(dot) / 2
            let tanHalf = tan(halfAngle)
            guard tanHalf > 0.001 else {
                result.append(curr)
                continue
            }
            let trim = min(radius / tanHalf, min(len1, len2) * 0.45)
            let pStart = CGPoint(x: curr.x + u1.x * trim, y: curr.y + u1.y * trim)
            let pEnd = CGPoint(x: curr.x + u2.x * trim, y: curr.y + u2.y * trim)
            for s in 0...6 {
                let t = CGFloat(s) / 6, u = 1 - t
                let x = u * u * pStart.x + 2 * u * t * curr.x + t * t * pEnd.x
                let y = u * u * pStart.y + 2 * u * t * curr.y + t * t * pEnd.y
                result.append(CGPoint(x: x, y: y))
            }
        }
        if isClosed, let first = result.first { result.append(first) }
        return result
    }

    static func offsetSubpath(_ subpath: PathSubpath, distance: Double, cornerStyle: OffsetCornerStyle) -> PathSubpath? {
        var verts = subpath.points
        let isClosed = subpath.isClosed
        if isClosed, verts.count > 2, let f = verts.first, let l = verts.last, hypot(f.x - l.x, f.y - l.y) < 0.01 {
            verts.removeLast()
        }
        guard verts.count >= 2 else { return nil }
        // Ensure consistent winding (clockwise in Y-down space) so positive distance = outward
        var signedArea = 0.0
        if verts.count >= 3 {
            for i in 0..<verts.count {
                let p1 = verts[i], p2 = verts[(i + 1) % verts.count]
                signedArea += Double(p1.x * p2.y - p2.x * p1.y)
            }
        }
        let sign: Double = signedArea >= 0 ? 1.0 : -1.0
        let d = CGFloat(distance * sign)
        let n = verts.count
        var out: [CGPoint] = []
        for i in 0..<n {
            let prev = verts[(i - 1 + n) % n]
            let curr = verts[i]
            let next = verts[(i + 1) % n]
            let e1 = CGPoint(x: curr.x - prev.x, y: curr.y - prev.y)
            let e2 = CGPoint(x: next.x - curr.x, y: next.y - curr.y)
            let l1 = max(0.0001, hypot(e1.x, e1.y))
            let l2 = max(0.0001, hypot(e2.x, e2.y))
            let n1 = CGPoint(x: e1.y / l1, y: -e1.x / l1)
            let n2 = CGPoint(x: e2.y / l2, y: -e2.x / l2)
            if !isClosed && i == 0 {
                out.append(CGPoint(x: curr.x + n2.x * d, y: curr.y + n2.y * d))
                continue
            }
            if !isClosed && i == n - 1 {
                out.append(CGPoint(x: curr.x + n1.x * d, y: curr.y + n1.y * d))
                continue
            }
            let p1 = CGPoint(x: curr.x + n1.x * d, y: curr.y + n1.y * d)
            let p2 = CGPoint(x: curr.x + n2.x * d, y: curr.y + n2.y * d)
            switch cornerStyle {
            case .bevel:
                out.append(p1)
                if hypot(p1.x - p2.x, p1.y - p2.y) > 0.05 { out.append(p2) }
            case .round:
                let a1 = atan2(n1.y * (d >= 0 ? 1 : -1), n1.x * (d >= 0 ? 1 : -1))
                var a2 = atan2(n2.y * (d >= 0 ? 1 : -1), n2.x * (d >= 0 ? 1 : -1))
                var diff = a2 - a1
                while diff <= -.pi { diff += 2 * .pi }
                while diff > .pi { diff -= 2 * .pi }
                a2 = a1 + diff
                let steps = max(2, Int(abs(diff) * 6))
                let absD = abs(d)
                for s in 0...steps {
                    let theta = a1 + diff * CGFloat(s) / CGFloat(steps)
                    out.append(CGPoint(x: curr.x + cos(theta) * absD, y: curr.y + sin(theta) * absD))
                }
            case .sharp:
                var bx = n1.x + n2.x, by = n1.y + n2.y
                let bl = hypot(bx, by)
                if bl < 0.01 {
                    out.append(p1)
                } else {
                    bx /= bl; by /= bl
                    let cosHalf = max(0.25, bx * n1.x + by * n1.y)
                    let miter = d / cosHalf
                    out.append(CGPoint(x: curr.x + bx * miter, y: curr.y + by * miter))
                }
            }
        }
        if isClosed, let first = out.first { out.append(first) }
        return out.count >= 2 ? PathSubpath(points: out, isClosed: isClosed) : nil
    }

    static func offsetObject(from objects: [DesignObject], distance: Double, direction: OffsetDirection, cornerStyle: OffsetCornerStyle, workspace: CGSize) -> DesignObject? {
        let base = objects.first { $0.kind != .image }
        guard let base else { return nil }
        var generated: [PathSubpath] = []
        let distances: [Double]
        switch direction {
        case .outward: distances = [abs(distance)]
        case .inward: distances = [-abs(distance)]
        case .both: distances = [abs(distance), -abs(distance)]
        }
        for obj in objects where obj.kind != .image {
            let subs = workspaceSubpaths(for: obj)
            for dist in distances {
                for sub in subs {
                    if let off = offsetSubpath(sub, distance: dist, cornerStyle: cornerStyle) {
                        generated.append(off)
                    }
                }
            }
        }
        return makePathObject(fromWorkspaceSubpaths: generated, template: base, label: "\(base.label) Offset", workspace: workspace)
    }

    static func booleanOperation(_ kind: BooleanOperationKind, objects: [DesignObject], workspace: CGSize) -> DesignObject? {
        let vectorObjects = objects.filter { $0.kind != .image }
        guard vectorObjects.count >= 2, let primary = vectorObjects.first else { return nil }
        // Rasterize onto a high-res grid and trace exact boundaries for robust 2D boolean operations
        let allSubpaths = vectorObjects.flatMap { workspaceSubpaths(for: $0) }
        let allPts = allSubpaths.flatMap(\.points)
        guard let minX = allPts.map(\.x).min(), let maxX = allPts.map(\.x).max(),
              let minY = allPts.map(\.y).min(), let maxY = allPts.map(\.y).max() else { return nil }
        let pad: CGFloat = 2.0
        let box = CGRect(x: minX - pad, y: minY - pad, width: max(4, maxX - minX + pad * 2), height: max(4, maxY - minY + pad * 2))
        let maxDim = 640.0
        let scale = min(maxDim / Double(box.width), maxDim / Double(box.height))
        let gridW = max(16, Int((Double(box.width) * scale).rounded()))
        let gridH = max(16, Int((Double(box.height) * scale).rounded()))

        func rasterizeMask(for obj: DesignObject) -> [UInt8] {
            var mask = [UInt8](repeating: 0, count: gridW * gridH)
            guard let ctx = CGContext(
                data: &mask, width: gridW, height: gridH,
                bitsPerComponent: 8, bytesPerRow: gridW,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return mask }
            // Flip Y so row 0 is top (box.minY)
            ctx.translateBy(x: 0, y: CGFloat(gridH))
            ctx.scaleBy(x: CGFloat(scale), y: -CGFloat(scale))
            ctx.translateBy(x: -box.minX, y: -box.minY)
            let path = CGMutablePath()
            for sub in workspaceSubpaths(for: obj) where sub.points.count >= 2 {
                path.move(to: sub.points[0])
                for pt in sub.points.dropFirst() { path.addLine(to: pt) }
                path.closeSubpath()
            }
            ctx.setShouldAntialias(false)
            ctx.setFillColor(gray: 1.0, alpha: 1.0)
            ctx.addPath(path)
            ctx.drawPath(using: .eoFill)
            return mask
        }

        var combined = rasterizeMask(for: primary)
        for other in vectorObjects.dropFirst() {
            let maskB = rasterizeMask(for: other)
            for idx in 0..<(gridW * gridH) {
                let a = combined[idx] > 127
                let b = maskB[idx] > 127
                let out: Bool
                switch kind {
                case .weld, .union: out = a || b
                case .subtract: out = a && !b
                case .intersect: out = a && b
                }
                combined[idx] = out ? 255 : 0
            }
        }
        for idx in 0..<(gridW * gridH) {
            combined[idx] = combined[idx] > 127 ? 0 : 255 // ImageTracer treats <= threshold (dark) as inside
        }
        let tempImage = DesignObject(
            kind: .image, x: Double(box.minX), y: Double(box.minY),
            width: Double(box.width), height: Double(box.height),
            label: "\(primary.label) \(kind.rawValue)",
            color: primary.color, power: primary.power, speed: primary.speed,
            imagePixels: Data(combined), imagePixelWidth: gridW, imagePixelHeight: gridH
        )
        let options = ImageTraceOptions(cutoff: 0, threshold: 128, inverted: false, minimumRegion: 2, smoothness: 0.6, simplifyTolerance: 0.45)
        let contours = ImageTracer.trace(image: tempImage, options: options)
        let mmPerPxX = Double(box.width) / Double(gridW)
        let mmPerPxY = Double(box.height) / Double(gridH)
        let wsSubpaths = contours.compactMap { contour -> PathSubpath? in
            guard contour.count >= 3 else { return nil }
            let pts = contour.map { CGPoint(x: Double(box.minX) + Double($0.x) * mmPerPxX, y: Double(box.minY) + Double($0.y) * mmPerPxY) }
            return PathSubpath(points: pts, isClosed: true)
        }
        return makePathObject(fromWorkspaceSubpaths: wsSubpaths, template: primary, label: "\(primary.label) \(kind.rawValue)", workspace: workspace)
    }

    static func makePathObject(fromWorkspaceSubpaths subpaths: [PathSubpath], template: DesignObject, label: String, workspace: CGSize) -> DesignObject? {
        let valid = subpaths.filter { $0.points.count >= 2 }
        let allPts = valid.flatMap(\.points)
        guard !valid.isEmpty,
              let minX = allPts.map(\.x).min(), let maxX = allPts.map(\.x).max(),
              let minY = allPts.map(\.y).min(), let maxY = allPts.map(\.y).max() else { return nil }
        let clampedMinX = max(0, Double(minX))
        let clampedMinY = max(0, Double(minY))
        let localSubpaths = valid.map { sub in
            PathSubpath(
                points: sub.points.map {
                    CGPoint(x: min(workspace.width, max(0, Double($0.x))) - clampedMinX,
                            y: min(workspace.height, max(0, Double($0.y))) - clampedMinY)
                },
                isClosed: sub.isClosed
            )
        }
        var result = template
        result = DesignObject(
            kind: .path,
            x: clampedMinX,
            y: clampedMinY,
            width: max(0.5, min(workspace.width - clampedMinX, Double(maxX - minX))),
            height: max(0.5, min(workspace.height - clampedMinY, Double(maxY - minY))),
            label: label,
            color: template.color,
            power: template.power,
            minPower: template.minPower,
            speed: template.speed,
            burnEnabled: template.burnEnabled,
            layerMode: template.layerMode,
            passCount: template.passCount,
            pathSubpaths: localSubpaths
        )
        return result
    }
}

