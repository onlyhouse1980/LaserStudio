import SwiftUI

struct DesignObject: Identifiable, Equatable {
    enum Kind: String { case rectangle = "Rectangle", circle = "Circle", text = "Text", line = "Line", path = "Path", image = "Image" }
    let id: UUID
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
    var color: Color
    var power: Double
    var speed: Double
    var burnEnabled: Bool
    var layerMode: EngravingMode
    var pathPoints: [CGPoint]
    var pathIsClosed: Bool
    var imageData: Data?
    var imagePixels: Data?
    var imagePixelWidth: Int
    var imagePixelHeight: Int
    var imageInverted: Bool
    var minimumSpeed: Double
    var maximumSpeed: Double
    var variablePower: Bool
    var isVisible: Bool
    var groupID: UUID?

    init(kind: Kind, x: Double, y: Double, width: Double, height: Double, label: String, rotation: Double = 0, color: Color = .red, power: Double = 18, speed: Double = 3000, burnEnabled: Bool = true, layerMode: EngravingMode = .line, pathPoints: [CGPoint] = [], pathIsClosed: Bool = false, imageData: Data? = nil, imagePixels: Data? = nil, imagePixelWidth: Int = 0, imagePixelHeight: Int = 0, imageInverted: Bool = false, minimumSpeed: Double = 1000, maximumSpeed: Double = 5000, variablePower: Bool = true, fontFamily: String = "Helvetica", fontBold: Bool = false, fontItalic: Bool = false, isVisible: Bool = true, groupID: UUID? = nil) {
        self.id = UUID(); self.kind = kind; self.x = x; self.y = y; self.width = width; self.height = height
        self.rotation = rotation
        self.label = label; self.fontFamily = fontFamily; self.fontBold = fontBold; self.fontItalic = fontItalic
        self.color = color; self.power = power; self.speed = speed
        self.burnEnabled = burnEnabled; self.layerMode = layerMode
        self.pathPoints = pathPoints; self.pathIsClosed = pathIsClosed
        self.imageData = imageData; self.imagePixels = imagePixels
        self.imagePixelWidth = imagePixelWidth; self.imagePixelHeight = imagePixelHeight
        self.imageInverted = imageInverted
        self.minimumSpeed = minimumSpeed; self.maximumSpeed = maximumSpeed; self.variablePower = variablePower
        self.isVisible = isVisible; self.groupID = groupID
    }
    static func == (lhs: DesignObject, rhs: DesignObject) -> Bool {
        lhs.id == rhs.id && lhs.kind == rhs.kind && lhs.x == rhs.x && lhs.y == rhs.y && lhs.rotation == rhs.rotation &&
        lhs.width == rhs.width && lhs.height == rhs.height && lhs.label == rhs.label && lhs.fontFamily == rhs.fontFamily &&
        lhs.fontBold == rhs.fontBold && lhs.fontItalic == rhs.fontItalic &&
        lhs.color == rhs.color && lhs.power == rhs.power && lhs.speed == rhs.speed &&
        lhs.burnEnabled == rhs.burnEnabled && lhs.layerMode == rhs.layerMode &&
        lhs.pathPoints == rhs.pathPoints && lhs.pathIsClosed == rhs.pathIsClosed &&
        lhs.imageData == rhs.imageData && lhs.imagePixels == rhs.imagePixels &&
        lhs.imagePixelWidth == rhs.imagePixelWidth && lhs.imagePixelHeight == rhs.imagePixelHeight && lhs.imageInverted == rhs.imageInverted &&
        lhs.minimumSpeed == rhs.minimumSpeed && lhs.maximumSpeed == rhs.maximumSpeed && lhs.variablePower == rhs.variablePower &&
        lhs.isVisible == rhs.isVisible && lhs.groupID == rhs.groupID
    }
}
