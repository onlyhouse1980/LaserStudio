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
        try "<svg viewBox=\"0 0 100 100\"><path d=\"M0 0 A10 10 0 0 1 20 20\"/></svg>".write(to: url, atomically: true, encoding: .utf8)
        let imported = try SVGImporter.load(url)
        XCTAssertEqual(imported.count, 1)
        XCTAssertEqual(imported[0].kind, .path)
        XCTAssertGreaterThan(imported[0].pathPoints.count, 2)
    }
}
