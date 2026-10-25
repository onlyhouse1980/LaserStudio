import AppKit
import SwiftUI

// MARK: - Instant Hover Tooltip Badge

private struct HoverTooltipModifier: ViewModifier {
    let text: String
    var edge: Edge = .trailing
    var onHoverChange: ((Bool) -> Void)? = nil
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .help(text)
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.12)) {
                    isHovered = hovering
                }
                onHoverChange?(hovering)
            }
            .popover(isPresented: $isHovered, arrowEdge: edge) {
                Text(text)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .fixedSize()
                    .background(Color(red: 0.14, green: 0.15, blue: 0.18))
            }
    }
}

extension View {
    func hoverToolName(_ text: String, edge: Edge = .trailing, onHoverChange: ((Bool) -> Void)? = nil) -> some View {
        modifier(HoverTooltipModifier(text: text, edge: edge, onHoverChange: onHoverChange))
    }
}

// MARK: - LightBurn Custom Vector Sidebar Tool Icons

struct LightBurnToolIcon: View {
    let toolName: String
    var isSelected: Bool = false

    var body: some View {
        Canvas { ctx, size in
            let w = size.width
            let h = size.height
            let strokeColor: Color = isSelected ? .white : .primary.opacity(0.88)
            let accentColor: Color = isSelected ? .white : .orange

            switch toolName {
            case "Select":
                var cursor = Path()
                cursor.move(to: CGPoint(x: w * 0.26, y: h * 0.16))
                cursor.addLine(to: CGPoint(x: w * 0.26, y: h * 0.78))
                cursor.addLine(to: CGPoint(x: w * 0.44, y: h * 0.62))
                cursor.addLine(to: CGPoint(x: w * 0.56, y: h * 0.86))
                cursor.addLine(to: CGPoint(x: w * 0.66, y: h * 0.81))
                cursor.addLine(to: CGPoint(x: w * 0.54, y: h * 0.57))
                cursor.addLine(to: CGPoint(x: w * 0.76, y: h * 0.57))
                cursor.closeSubpath()
                ctx.fill(cursor, with: .color(strokeColor))

            case "Line":
                var line = Path()
                line.move(to: CGPoint(x: w * 0.20, y: h * 0.78))
                line.addLine(to: CGPoint(x: w * 0.80, y: h * 0.22))
                ctx.stroke(line, with: .color(strokeColor), lineWidth: 1.8)
                for pt in [CGPoint(x: w * 0.20, y: h * 0.78), CGPoint(x: w * 0.80, y: h * 0.22)] {
                    ctx.fill(Path(CGRect(x: pt.x - 2.4, y: pt.y - 2.4, width: 4.8, height: 4.8)), with: .color(accentColor))
                }

            case "Pen":
                var curve = Path()
                curve.move(to: CGPoint(x: w * 0.18, y: h * 0.76))
                curve.addCurve(
                    to: CGPoint(x: w * 0.82, y: h * 0.24),
                    control1: CGPoint(x: w * 0.22, y: h * 0.20),
                    control2: CGPoint(x: w * 0.78, y: h * 0.80)
                )
                ctx.stroke(curve, with: .color(strokeColor), lineWidth: 1.8)
                for pt in [CGPoint(x: w * 0.18, y: h * 0.76), CGPoint(x: w * 0.50, y: h * 0.50), CGPoint(x: w * 0.82, y: h * 0.24)] {
                    ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 2.2, y: pt.y - 2.2, width: 4.4, height: 4.4)), with: .color(accentColor))
                }

            case "Rectangle":
                let rect = CGRect(x: w * 0.18, y: h * 0.22, width: w * 0.64, height: h * 0.56)
                ctx.stroke(Path(rect), with: .color(strokeColor), lineWidth: 1.8)
                ctx.fill(Path(CGRect(x: rect.minX - 2, y: rect.minY - 2, width: 4, height: 4)), with: .color(accentColor))
                ctx.fill(Path(CGRect(x: rect.maxX - 2, y: rect.maxY - 2, width: 4, height: 4)), with: .color(accentColor))

            case "Circle":
                let ellipse = CGRect(x: w * 0.18, y: h * 0.20, width: w * 0.64, height: h * 0.60)
                ctx.stroke(Path(ellipseIn: ellipse), with: .color(strokeColor), lineWidth: 1.8)

            case "Polygon":
                var poly = Path()
                let cx = w * 0.5, cy = h * 0.5, r = min(w, h) * 0.34
                for i in 0..<6 {
                    let a = -Double.pi / 2 + Double(i) * Double.pi / 3
                    let pt = CGPoint(x: cx + CGFloat(cos(a)) * r, y: cy + CGFloat(sin(a)) * r)
                    if i == 0 { poly.move(to: pt) } else { poly.addLine(to: pt) }
                }
                poly.closeSubpath()
                ctx.stroke(poly, with: .color(strokeColor), lineWidth: 1.8)

            case "Node edit":
                var poly = Path()
                let p1 = CGPoint(x: w * 0.20, y: h * 0.74)
                let p2 = CGPoint(x: w * 0.45, y: h * 0.24)
                let p3 = CGPoint(x: w * 0.80, y: h * 0.64)
                poly.move(to: p1); poly.addLine(to: p2); poly.addLine(to: p3)
                ctx.stroke(poly, with: .color(strokeColor), lineWidth: 1.6)
                for pt in [p1, p2, p3] {
                    let r = CGRect(x: pt.x - 2.6, y: pt.y - 2.6, width: 5.2, height: 5.2)
                    ctx.fill(Path(r), with: .color(accentColor))
                }

            case "Position Laser":
                let cx = w * 0.5, cy = h * 0.5
                ctx.stroke(Path(ellipseIn: CGRect(x: cx - 5, y: cy - 5, width: 10, height: 10)), with: .color(strokeColor), lineWidth: 1.5)
                var cross = Path()
                cross.move(to: CGPoint(x: cx, y: h * 0.14)); cross.addLine(to: CGPoint(x: cx, y: h * 0.86))
                cross.move(to: CGPoint(x: w * 0.14, y: cy)); cross.addLine(to: CGPoint(x: w * 0.86, y: cy))
                ctx.stroke(cross, with: .color(accentColor), lineWidth: 1.4)

            case "Add Tabs":
                var p = Path()
                p.move(to: CGPoint(x: w * 0.16, y: h * 0.72))
                p.addLine(to: CGPoint(x: w * 0.16, y: h * 0.28))
                p.addLine(to: CGPoint(x: w * 0.38, y: h * 0.28))
                p.move(to: CGPoint(x: w * 0.62, y: h * 0.28))
                p.addLine(to: CGPoint(x: w * 0.84, y: h * 0.28))
                p.addLine(to: CGPoint(x: w * 0.84, y: h * 0.72))
                p.addLine(to: CGPoint(x: w * 0.16, y: h * 0.72))
                ctx.stroke(p, with: .color(strokeColor), lineWidth: 1.6)
                ctx.fill(Path(ellipseIn: CGRect(x: w * 0.43, y: h * 0.20, width: w * 0.14, height: h * 0.16)), with: .color(accentColor))

            case "Radius":
                var corner = Path()
                corner.move(to: CGPoint(x: w * 0.22, y: h * 0.78))
                corner.addLine(to: CGPoint(x: w * 0.22, y: h * 0.46))
                corner.addQuadCurve(to: CGPoint(x: w * 0.54, y: h * 0.22), control: CGPoint(x: w * 0.22, y: h * 0.22))
                corner.addLine(to: CGPoint(x: w * 0.78, y: h * 0.22))
                ctx.stroke(corner, with: .color(strokeColor), lineWidth: 1.8)
                ctx.fill(Path(ellipseIn: CGRect(x: w * 0.28, y: h * 0.28, width: 4.5, height: 4.5)), with: .color(accentColor))

            case "Offset Shapes":
                let outer = CGRect(x: w * 0.16, y: h * 0.18, width: w * 0.68, height: h * 0.64)
                let inner = outer.insetBy(dx: w * 0.14, dy: h * 0.14)
                ctx.stroke(Path(roundedRect: outer, cornerRadius: 4), with: .color(accentColor), lineWidth: 1.6)
                ctx.stroke(Path(roundedRect: inner, cornerRadius: 2), with: .color(strokeColor), lineWidth: 1.4)

            case "Weld", "Union":
                let r1 = CGRect(x: w * 0.16, y: h * 0.22, width: w * 0.42, height: h * 0.42)
                let r2 = CGRect(x: w * 0.40, y: h * 0.36, width: w * 0.44, height: h * 0.42)
                ctx.fill(Path(ellipseIn: r1), with: .color(strokeColor.opacity(0.35)))
                ctx.fill(Path(ellipseIn: r2), with: .color(strokeColor.opacity(0.35)))
                ctx.stroke(Path(ellipseIn: r1), with: .color(strokeColor), lineWidth: 1.5)
                ctx.stroke(Path(ellipseIn: r2), with: .color(accentColor), lineWidth: 1.5)

            case "Subtract":
                let r1 = CGRect(x: w * 0.16, y: h * 0.22, width: w * 0.44, height: h * 0.44)
                let r2 = CGRect(x: w * 0.40, y: h * 0.36, width: w * 0.44, height: h * 0.42)
                ctx.fill(Path(r1), with: .color(strokeColor.opacity(0.35)))
                ctx.stroke(Path(r1), with: .color(strokeColor), lineWidth: 1.5)
                ctx.stroke(Path(ellipseIn: r2), with: .color(accentColor), style: StrokeStyle(lineWidth: 1.5, dash: [2.5, 2]))

            case "Intersect":
                let r1 = CGRect(x: w * 0.16, y: h * 0.22, width: w * 0.46, height: h * 0.46)
                let r2 = CGRect(x: w * 0.38, y: h * 0.34, width: w * 0.46, height: h * 0.46)
                ctx.stroke(Path(ellipseIn: r1), with: .color(strokeColor.opacity(0.75)), lineWidth: 1.3)
                ctx.stroke(Path(ellipseIn: r2), with: .color(strokeColor.opacity(0.75)), lineWidth: 1.3)
                let inter = r1.intersection(r2)
                ctx.fill(Path(roundedRect: inter, cornerRadius: 3), with: .color(accentColor))

            case "Grid Array":
                for row in 0..<2 {
                    for col in 0..<3 {
                        let rx = w * 0.16 + CGFloat(col) * (w * 0.24)
                        let ry = h * 0.24 + CGFloat(row) * (h * 0.30)
                        let cell = CGRect(x: rx, y: ry, width: w * 0.18, height: h * 0.20)
                        ctx.stroke(Path(cell), with: .color(row == 0 && col == 0 ? accentColor : strokeColor), lineWidth: 1.4)
                    }
                }

            case "Circular Array":
                let cx = w * 0.5, cy = h * 0.5, rad = min(w, h) * 0.28
                for i in 0..<6 {
                    let a = Double(i) * Double.pi / 3
                    let px = cx + CGFloat(cos(a)) * rad
                    let py = cy + CGFloat(sin(a)) * rad
                    let dot = CGRect(x: px - 2.3, y: py - 2.3, width: 4.6, height: 4.6)
                    ctx.fill(Path(ellipseIn: dot), with: .color(i == 0 ? accentColor : strokeColor))
                }

            default:
                break
            }
        }
        .frame(width: 18, height: 18)
    }
}

// MARK: - LightBurn Bottom Color Palette Bar (00-29 + T1, T2)

struct LightBurnColorPaletteBar: View {
    let activeLayerIndex: Int
    let activeIsToolLayer: Bool
    let usedLayerIndices: Set<Int>
    let onSelectSwatch: (LightBurnLayerSwatch) -> Void

    init(
        activeLayerIndex: Int,
        activeIsToolLayer: Bool = false,
        activeIsTool: Bool? = nil,
        usedLayerIndices: Set<Int>,
        onSelectSwatch: @escaping (LightBurnLayerSwatch) -> Void
    ) {
        self.activeLayerIndex = activeLayerIndex
        self.activeIsToolLayer = activeIsTool ?? activeIsToolLayer
        self.usedLayerIndices = usedLayerIndices
        self.onSelectSwatch = onSelectSwatch
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 3) {
                ForEach(LightBurnPalette.layers.filter { !$0.isTool }) { swatch in
                    swatchButton(swatch)
                }
                Divider()
                    .frame(height: 18)
                    .padding(.horizontal, 3)
                ForEach(LightBurnPalette.toolLayers) { swatch in
                    swatchButton(swatch)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
        }
        .background(Color(red: 0.10, green: 0.11, blue: 0.13))
    }

    private func swatchButton(_ swatch: LightBurnLayerSwatch) -> some View {
        let isCurrent = swatch.index == activeLayerIndex && swatch.isTool == activeIsToolLayer
        let isUsed = usedLayerIndices.contains(swatch.index)
        return Button {
            onSelectSwatch(swatch)
        } label: {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(swatch.color)
                    .frame(width: 24, height: 20)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(isCurrent ? Color.white : Color.black.opacity(0.55), lineWidth: isCurrent ? 2.0 : 0.8)
                    )
                Text(swatch.code)
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(swatch.index == 0 || swatch.index == 1 || swatch.index == 7 || swatch.index == 8 || swatch.index == 9 ? .white : .black)
                    .shadow(color: .black.opacity(0.35), radius: 0.5, x: 0, y: 0)
                    .frame(width: 24, height: 20)
                if isUsed {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 4.5, height: 4.5)
                        .padding(2)
                }
            }
        }
        .buttonStyle(.plain)
        .hoverToolName(
            swatch.isTool ? "\(swatch.name) (Non-output Framing/Guide Layer)" : "Layer \(swatch.code) (\(swatch.name))",
            edge: .top
        )
    }
}

// MARK: - LightBurn Cut Settings Editor Dialog

struct CutSettingsEditorSheet: View {
    @Binding var object: DesignObject
    let maxFeedRate: Double
    var onApplyToSameColorLayers: ((DesignObject) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var applyToMatchingLayerColor = true

    private var swatch: LightBurnLayerSwatch {
        LightBurnPalette.closestSwatch(for: object.color, isToolLayer: object.isToolLayer)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header with Layer Color Swatch & Name
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(object.color)
                    .frame(width: 30, height: 24)
                    .overlay(
                        Text(swatch.code)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                            .shadow(radius: 1)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cut Settings Editor — Layer \(swatch.code) (\(object.label))")
                        .font(.headline)
                    Text(object.isToolLayer ? "Tool Layer (Framing / Guide Only — Never Outputs to Laser)" : "LightBurn Layer Cut / Scan / Image Parameters")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Output", isOn: $object.burnEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .disabled(object.isToolLayer)
                Toggle("Show", isOn: $object.isVisible)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                Toggle("Tool Layer (T1/T2)", isOn: $object.isToolLayer)
                    .toggleStyle(.checkbox)
            }

            Divider()

            HStack(alignment: .top, spacing: 16) {
                // Left Column: Common Cut Parameters
                VStack(alignment: .leading, spacing: 12) {
                    GroupBox("Layer Mode & Output") {
                        VStack(alignment: .leading, spacing: 10) {
                            if object.kind != .image {
                                Picker("Mode", selection: $object.layerMode) {
                                    Text("Line").tag(EngravingMode.line)
                                    Text("Fill").tag(EngravingMode.fill)
                                    Text("Fill+Line").tag(EngravingMode.fillAndLine)
                                    Text("Offset Fill").tag(EngravingMode.offset)
                                }
                                .pickerStyle(.segmented)
                            } else {
                                HStack {
                                    Text("Mode").font(.system(size: 11, weight: .semibold))
                                    Spacer()
                                    Text("Image").font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(.orange)
                                }
                            }

                            sliderRow("Speed (mm/min)", value: $object.speed, range: 60...maxFeedRate, step: 20, valueText: "\(Int(object.speed)) mm/min")
                            sliderRow("Max Power (%)", value: $object.power, range: 0...100, step: 1, valueText: "\(Int(object.power))%")
                            sliderRow("Min Power (%)", value: $object.minPower, range: 0...100, step: 1, valueText: "\(Int(object.minPower))%")

                            HStack {
                                Text("Number of Passes").font(.system(size: 11, weight: .medium))
                                Spacer()
                                Stepper("\(object.passCount)", value: $object.passCount, in: 1...30)
                                    .font(.system(size: 11, design: .monospaced))
                            }

                            HStack(spacing: 14) {
                                Toggle("Air Assist (M8)", isOn: $object.airAssist)
                                    .toggleStyle(.checkbox)
                                Toggle("Constant Power (M3)", isOn: $object.constantPower)
                                    .toggleStyle(.checkbox)
                            }
                            .font(.system(size: 11))
                        }
                        .padding(6)
                    }

                    GroupBox("Z Axis & Kerf") {
                        VStack(alignment: .leading, spacing: 8) {
                            sliderRow("Z Offset (mm)", value: $object.zOffset, range: -20...20, step: 0.1, valueText: String(format: "%.2f mm", object.zOffset))
                            sliderRow("Z Step per Pass (mm)", value: $object.zPerPass, range: -5...5, step: 0.05, valueText: String(format: "%.2f mm", object.zPerPass))
                            if object.kind != .image {
                                sliderRow("Kerf Offset (mm)", value: $object.kerfOffset, range: -2.0...2.0, step: 0.02, valueText: String(format: "%+.2f mm", object.kerfOffset))
                            }
                        }
                        .padding(6)
                    }
                }
                .frame(maxWidth: .infinity)

                // Right Column: Mode-Specific Settings (Line / Fill / Image)
                VStack(alignment: .leading, spacing: 12) {
                    if object.kind == .image {
                        imageModeSettings
                    } else {
                        if object.layerMode == .fill || object.layerMode == .fillAndLine || object.layerMode == .offset {
                            fillModeSettings
                        }
                        if object.layerMode == .line || object.layerMode == .fillAndLine {
                            lineModeSettings
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }

            Divider()

            HStack {
                if onApplyToSameColorLayers != nil {
                    Toggle("Apply cut settings to all shapes on Layer \(swatch.code)", isOn: $applyToMatchingLayerColor)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 11))
                }
                Spacer()
                Button("Reset Defaults") {
                    object.power = 20
                    object.minPower = 10
                    object.speed = 1200
                    object.passCount = 1
                    object.zOffset = 0
                    object.zPerPass = 0
                    object.kerfOffset = 0
                    object.useCustomInterval = false
                    object.lineInterval = 0.10
                    object.scanAngle = 0
                    object.crossHatch = false
                    object.bidirectionalFill = true
                    object.overscanEnabled = true
                    object.overscanPercent = 2.5
                    object.perforationEnabled = false
                    object.tabsEnabled = false
                    object.overcut = 0
                }
                .controlSize(.small)
                Button("OK") {
                    if applyToMatchingLayerColor {
                        onApplyToSameColorLayers?(object)
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 720)
    }

    private var fillModeSettings: some View {
        GroupBox("Fill / Scan Settings") {
            VStack(alignment: .leading, spacing: 9) {
                Toggle("Use Custom Line Interval", isOn: $object.useCustomInterval)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11, weight: .medium))
                if object.useCustomInterval {
                    sliderRow(
                        "Line Interval (mm)",
                        value: $object.lineInterval,
                        range: 0.02...2.0,
                        step: 0.01,
                        valueText: String(format: "%.2f mm (%.0f DPI)", object.lineInterval, 25.4 / max(0.02, object.lineInterval))
                    )
                }
                sliderRow("Scan Angle (°)", value: $object.scanAngle, range: -90...90, step: 1, valueText: "\(Int(object.scanAngle))°")
                HStack(spacing: 14) {
                    Toggle("Bi-directional Fill", isOn: $object.bidirectionalFill)
                    Toggle("Cross-Hatch", isOn: $object.crossHatch)
                    Toggle("Flood Fill", isOn: $object.floodFill)
                }
                .toggleStyle(.checkbox)
                .font(.system(size: 11))

                Toggle("Overscanning", isOn: $object.overscanEnabled)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))
                if object.overscanEnabled {
                    sliderRow("Overscan (%)", value: $object.overscanPercent, range: 0.5...10.0, step: 0.25, valueText: String(format: "%.2f%%", object.overscanPercent))
                }
            }
            .padding(6)
        }
    }

    private var lineModeSettings: some View {
        GroupBox("Line / Cut Modifiers") {
            VStack(alignment: .leading, spacing: 9) {
                sliderRow("Overcut (mm)", value: $object.overcut, range: 0...5.0, step: 0.1, valueText: String(format: "%.1f mm", object.overcut))

                Toggle("Perforation Mode", isOn: $object.perforationEnabled)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11, weight: .medium))
                if object.perforationEnabled {
                    sliderRow("Cut Length (mm)", value: $object.perforationCutLength, range: 0.2...20.0, step: 0.2, valueText: String(format: "%.1f mm", object.perforationCutLength))
                    sliderRow("Skip Length (mm)", value: $object.perforationSkipLength, range: 0.2...20.0, step: 0.2, valueText: String(format: "%.1f mm", object.perforationSkipLength))
                }

                Toggle("Tabs / Bridges", isOn: $object.tabsEnabled)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11, weight: .medium))
                if object.tabsEnabled {
                    HStack {
                        Text("Tabs per Shape").font(.system(size: 11))
                        Spacer()
                        Stepper("\(object.tabCount)", value: $object.tabCount, in: 1...16)
                            .font(.system(size: 11, design: .monospaced))
                    }
                    sliderRow("Tab Size (mm)", value: $object.tabSize, range: 0.2...5.0, step: 0.1, valueText: String(format: "%.1f mm", object.tabSize))
                }
            }
            .padding(6)
        }
    }

    private var imageModeSettings: some View {
        GroupBox("Image Engraving Settings") {
            VStack(alignment: .leading, spacing: 9) {
                Picker("Image Mode", selection: $object.imageDitherMode) {
                    ForEach(ImageDitherMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .disabled(object.imagePassThrough)

                HStack(spacing: 14) {
                    Toggle("Pass-Through", isOn: $object.imagePassThrough)
                    Toggle("Negative Image", isOn: $object.imageInverted)
                    Toggle("Bi-directional", isOn: $object.bidirectionalFill)
                }
                .toggleStyle(.checkbox)
                .font(.system(size: 11))

                Toggle("Use Custom DPI / Interval", isOn: $object.useCustomInterval)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))
                if object.useCustomInterval {
                    sliderRow(
                        "DPI",
                        value: $object.imageDPI,
                        range: 72...600,
                        step: 2,
                        valueText: String(format: "%.0f DPI (%.3f mm)", object.imageDPI, 25.4 / max(1, object.imageDPI))
                    )
                }

                sliderRow("Min Grayscale Speed", value: $object.minimumSpeed, range: 60...maxFeedRate, step: 20, valueText: "\(Int(object.minimumSpeed)) mm/min")
                sliderRow("Max Grayscale Speed", value: $object.maximumSpeed, range: 60...maxFeedRate, step: 20, valueText: "\(Int(object.maximumSpeed)) mm/min")
            }
            .padding(6)
        }
    }

    private func sliderRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, valueText: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.system(size: 11, weight: .medium))
                Spacer()
                Text(valueText).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step).tint(.orange)
        }
    }
}

// MARK: - LightBurn Adjust Image Dialog

struct AdjustImageEditorSheet: View {
    @Binding var object: DesignObject
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Adjust Image · \(object.label)").font(.headline)
                    Text("LightBurn-compatible tone curve, unsharp mask edge enhancement, and dithering preview.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(object.imagePixelWidth) × \(object.imagePixelHeight) px · \(String(format: "%.1f × %.1f mm", object.width, object.height))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 14) {
                // Original Image Preview
                VStack(spacing: 4) {
                    Text("Source Image").font(.caption).foregroundStyle(.secondary)
                    ZStack {
                        RoundedRectangle(cornerRadius: 8).fill(Color(red: 0.1, green: 0.11, blue: 0.13))
                        if let data = object.imageData, let nsImage = NSImage(data: data) {
                            Image(nsImage: nsImage)
                                .resizable()
                                .scaledToFit()
                                .padding(8)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Processed / Dithered Output Preview
                VStack(spacing: 4) {
                    Text("Laser Output Preview (\(object.imagePassThrough ? "Pass-Through" : object.imageDitherMode.rawValue))")
                        .font(.caption).foregroundStyle(.orange)
                    ZStack {
                        RoundedRectangle(cornerRadius: 8).fill(Color(red: 0.1, green: 0.11, blue: 0.13))
                        if let processed = ImageImporter.processedNSImage(for: object) {
                            Image(nsImage: processed)
                                .resizable()
                                .interpolation(.none)
                                .scaledToFit()
                                .padding(8)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Controls Column
                VStack(alignment: .leading, spacing: 10) {
                    GroupBox("Dithering & Resolution") {
                        VStack(alignment: .leading, spacing: 8) {
                            Picker("Image Mode", selection: $object.imageDitherMode) {
                                ForEach(ImageDitherMode.allCases) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            .disabled(object.imagePassThrough)

                            HStack {
                                Toggle("Pass-Through", isOn: $object.imagePassThrough)
                                Toggle("Negative Image", isOn: $object.imageInverted)
                            }
                            .toggleStyle(.checkbox)
                            .font(.system(size: 11))

                            sliderRow("DPI", value: $object.imageDPI, range: 72...600, text: "\(Int(object.imageDPI)) DPI")
                        }
                        .padding(6)
                    }

                    GroupBox("Tone & Edge Enhancement") {
                        VStack(alignment: .leading, spacing: 8) {
                            sliderRow("Contrast", value: $object.imageContrast, range: -100...100, text: "\(Int(object.imageContrast))")
                            sliderRow("Brightness", value: $object.imageBrightness, range: -100...100, text: "\(Int(object.imageBrightness))")
                            sliderRow("Gamma", value: $object.imageGamma, range: 0.2...3.0, text: String(format: "%.2f", object.imageGamma))
                            sliderRow("Enhance Radius", value: $object.imageEnhanceRadius, range: 0...8, text: "\(Int(object.imageEnhanceRadius)) px")
                            sliderRow("Enhance Amount", value: $object.imageEnhanceAmount, range: 0...400, text: "\(Int(object.imageEnhanceAmount))%")
                        }
                        .padding(6)
                    }

                    HStack(spacing: 6) {
                        Button("Photo Preset (Stucki)") {
                            object.imageDitherMode = .stucki
                            object.imageContrast = 12
                            object.imageBrightness = 4
                            object.imageGamma = 1.15
                            object.imageEnhanceRadius = 2
                            object.imageEnhanceAmount = 140
                        }
                        .controlSize(.small)

                        Button("Reset") {
                            object.imageDitherMode = .grayscale
                            object.imagePassThrough = false
                            object.imageInverted = false
                            object.imageContrast = 0
                            object.imageBrightness = 0
                            object.imageGamma = 1.0
                            object.imageEnhanceRadius = 0
                            object.imageEnhanceAmount = 100
                        }
                        .controlSize(.small)
                    }

                    Spacer()
                }
                .frame(width: 265)
            }

            HStack {
                Spacer()
                Button("OK") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 820, height: 500)
    }

    private func sliderRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.system(size: 11, weight: .medium))
                Spacer()
                Text(text).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
            }
            Slider(value: value, in: range).tint(.orange)
        }
    }
}

// MARK: - LightBurn Offset Shapes, Grid Array, and Circular Array Sheets

struct OffsetShapesSheet: View {
    let sourceObjects: [DesignObject]
    let workspace: CGSize
    let onApply: (DesignObject, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var distance: Double = 2.0
    @State private var direction: OffsetDirection = .outward
    @State private var cornerStyle: OffsetCornerStyle = .round
    @State private var deleteOriginal: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Offset Shapes").font(.headline)
            Text("Create inward, outward, or双-sided offset outlines like LightBurn.")
                .font(.caption).foregroundStyle(.secondary)

            Picker("Direction", selection: $direction) {
                ForEach(OffsetDirection.allCases) { dir in
                    Text(dir.rawValue).tag(dir)
                }
            }
            .pickerStyle(.segmented)

            Picker("Corner Style", selection: $cornerStyle) {
                ForEach(OffsetCornerStyle.allCases) { style in
                    Text(style.rawValue).tag(style)
                }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Offset Distance (mm)").font(.system(size: 11, weight: .medium))
                    Spacer()
                    Text(String(format: "%.2f mm", distance)).font(.system(size: 11, design: .monospaced))
                }
                Slider(value: $distance, in: 0.2...30.0, step: 0.2).tint(.orange)
            }

            Toggle("Delete original objects", isOn: $deleteOriginal)
                .toggleStyle(.checkbox)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("OK") {
                    if let result = ShapeGeometry.offsetObject(
                        from: sourceObjects,
                        distance: distance,
                        direction: direction,
                        cornerStyle: cornerStyle,
                        workspace: workspace
                    ) {
                        onApply(result, deleteOriginal)
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 360)
    }
}

struct GridArraySheet: View {
    let sourceObjects: [DesignObject]
    let workspace: CGSize
    let onApply: ([DesignObject]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var columns: Int = 3
    @State private var rows: Int = 2
    @State private var xSpacing: Double = 5.0
    @State private var ySpacing: Double = 5.0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Grid Array").font(.headline)
            Text("Duplicate selected shapes into a rectangular grid array.")
                .font(.caption).foregroundStyle(.secondary)

            HStack {
                Text("X Columns")
                Spacer()
                Stepper("\(columns)", value: $columns, in: 1...25)
            }
            HStack {
                Text("Y Rows")
                Spacer()
                Stepper("\(rows)", value: $rows, in: 1...25)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("X Spacing Between Shapes (mm)")
                    Spacer()
                    Text(String(format: "%.1f mm", xSpacing)).font(.system(size: 11, design: .monospaced))
                }
                Slider(value: $xSpacing, in: -20...60, step: 0.5).tint(.orange)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("Y Spacing Between Shapes (mm)")
                    Spacer()
                    Text(String(format: "%.1f mm", ySpacing)).font(.system(size: 11, design: .monospaced))
                }
                Slider(value: $ySpacing, in: -20...60, step: 0.5).tint(.orange)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Create \(columns * rows - 1) Copies") {
                    var created: [DesignObject] = []
                    guard let minX = sourceObjects.map(\.x).min(),
                          let maxX = sourceObjects.map({ $0.x + $0.width }).max(),
                          let minY = sourceObjects.map(\.y).min(),
                          let maxY = sourceObjects.map({ $0.y + $0.height }).max() else {
                        dismiss()
                        return
                    }
                    let stepW = (maxX - minX) + xSpacing
                    let stepH = (maxY - minY) + ySpacing
                    for r in 0..<rows {
                        for c in 0..<columns where !(r == 0 && c == 0) {
                            let groupID = sourceObjects.count > 1 ? UUID() : nil
                            for obj in sourceObjects {
                                var copy = obj
                                copy.id = UUID()
                                copy.x = min(workspace.width - copy.width, max(0, obj.x + Double(c) * stepW))
                                copy.y = min(workspace.height - copy.height, max(0, obj.y + Double(r) * stepH))
                                copy.label = "\(obj.label) [\(c + 1),\(r + 1)]"
                                if let groupID { copy.groupID = groupID }
                                created.append(copy)
                            }
                        }
                    }
                    onApply(created)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 360)
    }
}

struct CircularArraySheet: View {
    let sourceObjects: [DesignObject]
    let workspace: CGSize
    let onApply: ([DesignObject]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var copies: Int = 6
    @State private var radius: Double = 45.0
    @State private var totalAngle: Double = 360.0
    @State private var rotateCopies: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Circular Array").font(.headline)
            Text("Arrange copies of the selected shape around a circle.")
                .font(.caption).foregroundStyle(.secondary)

            HStack {
                Text("Total Copies")
                Spacer()
                Stepper("\(copies)", value: $copies, in: 2...36)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("Circle Radius (mm)")
                    Spacer()
                    Text(String(format: "%.1f mm", radius)).font(.system(size: 11, design: .monospaced))
                }
                Slider(value: $radius, in: 5...150, step: 1).tint(.orange)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("Sweep Angle (°)")
                    Spacer()
                    Text("\(Int(totalAngle))°").font(.system(size: 11, design: .monospaced))
                }
                Slider(value: $totalAngle, in: 30...360, step: 5).tint(.orange)
            }
            Toggle("Rotate object copies", isOn: $rotateCopies)
                .toggleStyle(.checkbox)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Create Array") {
                    guard let first = sourceObjects.first else { dismiss(); return }
                    let baseCenterX = first.x + first.width / 2
                    let baseCenterY = first.y + first.height / 2
                    let pivotX = baseCenterX
                    let pivotY = baseCenterY + radius
                    var created: [DesignObject] = []
                    let stepAngle = totalAngle / Double(max(1, copies))
                    for i in 1..<copies {
                        let deg = Double(i) * stepAngle
                        let rad = deg * .pi / 180.0
                        for obj in sourceObjects {
                            let cx = obj.x + obj.width / 2
                            let cy = obj.y + obj.height / 2
                            let dx = cx - pivotX
                            let dy = cy - pivotY
                            let ncx = pivotX + dx * cos(rad) - dy * sin(rad)
                            let ncy = pivotY + dx * sin(rad) + dy * cos(rad)
                            var copy = obj
                            copy.id = UUID()
                            copy.x = min(workspace.width - copy.width, max(0, ncx - copy.width / 2))
                            copy.y = min(workspace.height - copy.height, max(0, ncy - copy.height / 2))
                            if rotateCopies {
                                copy.rotation = (obj.rotation + deg).truncatingRemainder(dividingBy: 360)
                            }
                            copy.label = "\(obj.label) #\(i + 1)"
                            created.append(copy)
                        }
                    }
                    onApply(created)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 360)
    }
}
