import XCTest
import SwiftUI
@testable import LaserStudio

final class GCodeGeneratorTests: XCTestCase {
    private func make(_ kind: DesignObject.Kind, label: String = "Shape") -> DesignObject {
        DesignObject(kind: kind, x: 10, y: 20, width: 30, height: 40, label: label, color: .red, power: 20, speed: 1234)
    }

    private func generate(_ object: DesignObject, mode: EngravingMode = .line) throws -> [String] {
        var layer = object
        layer.layerMode = mode
        return try GCodeGenerator.make(objects: [layer], material: "test", sMax: 1000, kerf: 0.4)
    }

    func testDesignObjectEqualityDetectsGeometryChanges() {
        let original = make(.rectangle)
        var moved = original
        moved.x += 1
        XCTAssertNotEqual(original, moved)

        var resized = original
        resized.width += 1
        XCTAssertNotEqual(original, resized)

        var disabled = original
        disabled.burnEnabled = false
        XCTAssertNotEqual(original, disabled)

        var filled = original
        filled.layerMode = .fill
        XCTAssertNotEqual(original, filled)

        var alternateFont = original
        alternateFont.fontFamily = "Courier"
        XCTAssertNotEqual(original, alternateFont)
    }

    @MainActor
    func testRay5LaserAndHomingSettingsAreHardcoded() {
        let controller = GRBLController()
        XCTAssertTrue(controller.settingsLoaded)
        XCTAssertEqual(controller.sMax, 1000)
        XCTAssertEqual(controller.laserModeEnabled, true)
        controller.handleResponse("$32=0")
        controller.handleResponse("$30=1200")
        XCTAssertTrue(controller.settingsLoaded)
        XCTAssertEqual(controller.sMax, 1000)
        XCTAssertEqual(controller.laserModeEnabled, true)
        XCTAssertTrue(controller.homingSettingLoaded)
        XCTAssertEqual(controller.homingEnabled, true)
        controller.handleResponse("$22=0")
        XCTAssertTrue(controller.homingSettingLoaded)
        XCTAssertEqual(controller.homingEnabled, true)
        controller.handleResponse("<Idle|WPos:12.5,34.0|FS:0,0>")
        XCTAssertEqual(controller.controllerState, "Idle")
        XCTAssertEqual(controller.workspacePosition?.x, 12.5)
        XCTAssertEqual(controller.workspacePosition?.y, 34.0)
    }

    @MainActor
    func testReportedHomingSettingDoesNotOverrideHardcodedValue() {
        let controller = GRBLController()
        controller.handleResponse("$22 = 0.000 ")
        XCTAssertTrue(controller.settingsLoaded)
        XCTAssertEqual(controller.sMax, 1000)
        XCTAssertEqual(controller.laserModeEnabled, true)
        XCTAssertTrue(controller.homingSettingLoaded)
        XCTAssertEqual(controller.homingEnabled, true)
    }

    @MainActor
    func testHomeRunsHomingBeforeSendingOrdinaryGCode() {
        XCTAssertEqual(GRBLController.workspaceOriginCommands(homingEnabled: true),
                       ["$22=1", "$H", "M5", "G10 L20 P1 X0 Y0", "G90 G54 G0 X0 Y0"])
        XCTAssertEqual(GRBLController.workspaceOriginCommands(homingEnabled: false), ["M5"])
    }

    func testRectangleTracesAllFourEdgesAndCloses() throws {
        let code = try generate(make(.rectangle))
        let cuts = code.filter { $0.hasPrefix("G1 ") }
        XCTAssertEqual(cuts.count, 4)
        XCTAssertTrue(cuts[0].contains("X40.000 Y380.000"))
        XCTAssertTrue(cuts[1].contains("X40.000 Y340.000"))
        XCTAssertTrue(cuts[2].contains("X10.000 Y340.000"))
        XCTAssertTrue(cuts[3].contains("X10.000 Y380.000"))
    }

    func testWorkspaceFrontLeftMapsToMachineOrigin() throws {
        let object = DesignObject(kind: .rectangle, x: 0, y: 360, width: 30, height: 40, label: "Origin")
        let code = try GCodeGenerator.make(objects: [object], material: "test", sMax: 1000, kerf: 0.4)
        XCTAssertTrue(code.contains("G0 X0.000 Y40.000"))
        XCTAssertTrue(code.contains("G1 X0.000 Y0.000 F3000.000 S180"))
    }

    func testCircleUsesClosedContour() throws {
        let cuts = try generate(make(.circle)).filter { $0.hasPrefix("G1 ") }
        XCTAssertGreaterThan(cuts.count, 48)
        XCTAssertTrue(cuts.last?.contains("X40.000 Y360.000") == true)
    }

    func testTextProducesGlyphOutlines() throws {
        let cuts = try generate(make(.text, label: "Ray5")).filter { $0.hasPrefix("G1 ") }
        XCTAssertGreaterThan(cuts.count, 20)
    }

    func testSelectedTextFontChangesGeneratedOutlines() throws {
        let helvetica = make(.text, label: "Ray5")
        var courier = helvetica
        courier.fontFamily = "Courier"
        XCTAssertNotEqual(try generate(helvetica), try generate(courier))
    }

    func testPowerAndSpeedUseGRBLUnits() throws {
        let code = try generate(make(.rectangle))
        XCTAssertTrue(code.contains { $0.contains("F1234.000 S200") })
    }

    func testImageLayerUsesVariablePowerAndGrayscaleSpeedRange() throws {
        let image = DesignObject(kind: .image, x: 10, y: 20, width: 2, height: 1, label: "Raster",
                                 power: 100, imagePixels: Data([0, 128, 255, 64]),
                                 imagePixelWidth: 4, imagePixelHeight: 1,
                                 minimumSpeed: 1000, maximumSpeed: 5000, variablePower: true)
        let code = try GCodeGenerator.make(objects: [image], material: "test", sMax: 1000, kerf: 0.25)
        XCTAssertTrue(code.contains { $0.contains("F1000 S1000") }, "Black pixels should use max power and min speed")
        XCTAssertTrue(code.contains { $0.contains("F5000 S0") }, "White pixels should be off at max speed")
        XCTAssertTrue(code.contains { $0.contains("S498") }, "Gray pixels should receive intermediate variable power")
    }

    func testImageLayerCanUseBinaryPower() throws {
        let image = DesignObject(kind: .image, x: 10, y: 20, width: 2, height: 1, label: "Binary",
                                 power: 20, imagePixels: Data([0, 255]), imagePixelWidth: 2, imagePixelHeight: 1,
                                 minimumSpeed: 1000, maximumSpeed: 5000, variablePower: false)
        let code = try GCodeGenerator.make(objects: [image], material: "test", sMax: 1000, kerf: 0.5)
        let powers = Set(code.filter { $0.hasPrefix("G1 ") }.compactMap { line -> String? in
            line.split(separator: " ").first(where: { $0.hasPrefix("S") }).map(String.init)
        })
        XCTAssertEqual(powers, Set(["S0", "S200"]))
    }

    func testFillModeAddsHatchMoves() throws {
        let outline = try generate(make(.rectangle))
        let filled = try generate(make(.rectangle), mode: .fill)
        XCTAssertGreaterThan(filled.filter { $0.hasPrefix("G1 ") }.count, outline.filter { $0.hasPrefix("G1 ") }.count)
    }

    func testOnlyBurnEnabledLayersAreGenerated() throws {
        let active = make(.rectangle, label: "Active")
        let skipped = DesignObject(kind: .rectangle, x: 390, y: 20, width: 30, height: 40,
                                   label: "Skipped", burnEnabled: false)
        let code = try GCodeGenerator.make(objects: [active, skipped], material: "test", sMax: 1000, kerf: 0.4)
        XCTAssertTrue(code.contains("G0 X10.000 Y380.000"))
        XCTAssertFalse(code.contains("G0 X390.000 Y380.000"))
    }

    func testEachLayerUsesItsOwnLineOrFillMode() throws {
        let line = make(.rectangle, label: "Line")
        var fill = make(.rectangle, label: "Fill")
        fill.x = 100
        fill.layerMode = .fill
        let code = try GCodeGenerator.make(objects: [line, fill], material: "test", sMax: 1000, kerf: 0.4)
        XCTAssertGreaterThan(code.filter { $0.hasPrefix("G1 ") }.count, 8)
    }

    func testGenerationRequiresAtLeastOneBurnEnabledLayer() {
        var skipped = make(.rectangle, label: "Skipped")
        skipped.burnEnabled = false
        XCTAssertThrowsError(try GCodeGenerator.make(objects: [skipped], material: "test", sMax: 1000, kerf: 0.4))
    }

    func testOffsetModeAddsNestedContours() throws {
        let outline = try generate(make(.circle))
        let offset = try generate(make(.circle), mode: .offset)
        XCTAssertGreaterThan(offset.filter { $0.hasPrefix("G1 ") }.count, outline.filter { $0.hasPrefix("G1 ") }.count)
    }

    func testFeedRateIsClampedToRay5Maximum() throws {
        let fast = DesignObject(kind: .rectangle, x: 10, y: 20, width: 30, height: 40, label: "Fast", speed: 12000)
        let code = try generate(fast)
        XCTAssertTrue(code.contains { $0.contains("F10000.000") })
    }

    func testOutOfBoundsObjectIsRejected() {
        let object = DesignObject(kind: .rectangle, x: 390, y: 20, width: 30, height: 40, label: "Outside")
        XCTAssertThrowsError(try generate(object))
    }

    func testSVGImportProducesScaledClosedVectorPath() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("laserstudio-test.svg")
        defer { try? FileManager.default.removeItem(at: url) }
        try "<svg viewBox=\"0 0 100 100\"><rect x=\"10\" y=\"20\" width=\"30\" height=\"40\"/></svg>".write(to: url, atomically: true, encoding: .utf8)
        let imported = try SVGImporter.load(url)
        XCTAssertEqual(imported.count, 1)
        XCTAssertEqual(imported[0].kind, .path)
        XCTAssertTrue(imported[0].pathIsClosed)
        XCTAssertFalse(try generate(imported[0]).filter { $0.hasPrefix("G1 ") }.isEmpty)
    }

    func testSVGImportSupportsArcCommands() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("laserstudio-arc-test.svg")
        defer { try? FileManager.default.removeItem(at: url) }
        try "<svg viewBox=\"0 0 100 100\"><path d=\"M0 0 A10 10 0 0 1 20 20 a10,10 0 0120,20\"/></svg>".write(to: url, atomically: true, encoding: .utf8)
        let imported = try SVGImporter.load(url)
        XCTAssertEqual(imported.count, 1)
        XCTAssertEqual(imported[0].kind, .path)
        XCTAssertGreaterThan(imported[0].pathPoints.count, 2)
    }

    private func importSVG(_ body: String, attributes: String = "viewBox=\"0 0 100 100\"") throws -> [DesignObject] {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("laserstudio-\(UUID().uuidString).svg")
        defer { try? FileManager.default.removeItem(at: url) }
        try "<svg \(attributes)>\(body)</svg>".write(to: url, atomically: true, encoding: .utf8)
        return try SVGImporter.load(url)
    }

    func testSVGDefaultsAllVectorLayersToLineModeLikeLightBurn() throws {
        let imported = try importSVG("""
            <rect x="10" y="10" width="30" height="30" fill="#ff0000"/>
            <circle cx="70" cy="30" r="10" stroke="#0000ff" fill="none"/>
            """)
        XCTAssertEqual(imported.count, 2)
        XCTAssertTrue(imported.allSatisfy { $0.layerMode == .line })
        XCTAssertNotEqual(imported[0].color, imported[1].color)
        XCTAssertNotNil(imported[0].groupID)
        XCTAssertEqual(imported[0].groupID, imported[1].groupID)
    }

    func testSVGCombinesSameColorPathsIntoCompoundLayer() throws {
        let imported = try importSVG("""
            <rect x="0" y="0" width="80" height="80" stroke="#ff0000" fill="none"/>
            <rect x="20" y="20" width="40" height="40" fill="#ff0000"/>
            <circle cx="90" cy="90" r="5" stroke="#0000ff"/>
            """)
        XCTAssertEqual(imported.count, 2)
        XCTAssertEqual(imported[0].resolvedSubpaths.count, 2)
        XCTAssertEqual(imported[1].resolvedSubpaths.count, 1)
    }

    func testSVGStrokeColorTakesPrecedenceOverFillColor() throws {
        let imported = try importSVG("""
            <rect x="0" y="0" width="20" height="20" stroke="#0000ff" fill="#ff0000"/>
            <rect x="30" y="0" width="20" height="20" fill="#0000ff"/>
            """)
        // Both map to Blue (Layer 01) because stroke takes precedence on the first rect.
        XCTAssertEqual(imported.count, 1)
        XCTAssertEqual(imported[0].resolvedSubpaths.count, 2)
    }

    func testSVGPreservesPhysicalMillimeterAndInchDimensions() throws {
        let mmImported = try importSVG(
            "<rect x=\"0\" y=\"0\" width=\"50\" height=\"25\"/>",
            attributes: "width=\"50mm\" height=\"25mm\" viewBox=\"0 0 50 25\""
        )
        XCTAssertEqual(mmImported.count, 1)
        XCTAssertEqual(mmImported[0].width, 50.0, accuracy: 0.01)
        XCTAssertEqual(mmImported[0].height, 25.0, accuracy: 0.01)
        XCTAssertEqual(mmImported[0].x, (400.0 - 50.0) / 2.0, accuracy: 0.01)
        XCTAssertEqual(mmImported[0].y, (400.0 - 25.0) / 2.0, accuracy: 0.01)

        let inchImported = try importSVG(
            "<rect x=\"0\" y=\"0\" width=\"100\" height=\"100\"/>",
            attributes: "width=\"2in\" height=\"2in\" viewBox=\"0 0 100 100\""
        )
        XCTAssertEqual(inchImported[0].width, 50.8, accuracy: 0.01)
        XCTAssertEqual(inchImported[0].height, 50.8, accuracy: 0.01)
    }

    func testSVGSkipsDefsAndInstantiatesUseElements() throws {
        let imported = try importSVG("""
            <defs><rect id="box" x="0" y="0" width="20" height="20" stroke="#ff0000"/></defs>
            <use href="#box" x="10" y="10"/>
            <use xlink:href="#box" x="40" y="10"/>
            """, attributes: "width=\"100mm\" height=\"100mm\" viewBox=\"0 0 100 100\"")
        XCTAssertEqual(imported.count, 1)
        XCTAssertEqual(imported[0].resolvedSubpaths.count, 2)
        XCTAssertEqual(imported[0].width, 50.0, accuracy: 0.01)
        XCTAssertEqual(imported[0].height, 20.0, accuracy: 0.01)
    }

    func testSVGTriangleFillRespectsPolygonContour() throws {
        var imported = try importSVG("<polygon points=\"0,0 100,0 0,100\" fill=\"black\"/>",
                                     attributes: "width=\"100mm\" height=\"100mm\" viewBox=\"0 0 100 100\"")
        imported[0].layerMode = .fill
        let shape = imported[0]
        let code = try GCodeGenerator.make(objects: imported, material: "test", sMax: 1000, kerf: 5)
        func value(_ prefix: Character, in line: String) -> Double? {
            line.split(separator: " ").first { $0.first == prefix }.flatMap { Double($0.dropFirst()) }
        }
        let burns = code.filter { $0.hasPrefix("G1 ") }
        XCTAssertFalse(burns.isEmpty)
        // The bottom-right quarter of the bounding box lies outside the triangle and must stay unburned.
        // G-code Y is flipped (machine Y = 400 - design Y).
        let outsideBurns = burns.filter { line in
            guard let x = value("X", in: line), let y = value("Y", in: line) else { return false }
            return x > shape.x + shape.width * 0.75 && (400 - y) > shape.y + shape.height * 0.75
        }
        XCTAssertTrue(outsideBurns.isEmpty)
    }
}
