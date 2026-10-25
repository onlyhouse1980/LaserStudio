import SwiftUI

// MARK: - Rich Illustrated Help & Instruction Manual Components

private enum ManualDiagramKind {
    case workspaceOverview
    case sidebarToolsGrid
    case textFormattingBar
    case selectionAndNodeEdit
    case booleanAndOffsetDiagram
    case arraysDiagram
    case imageTraceAndDitherDiagram
    case layerPaletteAndCutSettingsDiagram
}

private struct HelpSection: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let body: [String]
    var diagram: ManualDiagramKind? = nil
    var shortcutRows: [(key: String, action: String)] = []
}

private struct HelpDocument: View {
    let heading: String
    let subtitle: String
    let sections: [HelpSection]
    @State private var searchQuery = ""

    private var filteredSections: [HelpSection] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return sections }
        return sections.filter { section in
            section.title.lowercased().contains(q)
                || section.body.contains(where: { $0.lowercased().contains(q) })
                || section.shortcutRows.contains(where: { $0.key.lowercased().contains(q) || $0.action.lowercased().contains(q) })
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "scope")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(heading)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    TextField("Search tools, shortcuts, or topics…", text: $searchQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .frame(width: 210)
                    if !searchQuery.isEmpty {
                        Button {
                            searchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.12), lineWidth: 1))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(Color(nsColor: .controlBackgroundColor))
            .overlay(alignment: .bottom) { Divider().opacity(0.35) }

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(filteredSections) { section in
                        VStack(alignment: .leading, spacing: 11) {
                            HStack(spacing: 8) {
                                Image(systemName: section.icon)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.orange)
                                Text(section.title)
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(.orange)
                            }

                            ForEach(section.body, id: \.self) { line in
                                Text(.init(line))
                                    .font(.system(size: 12.5))
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            if let diagram = section.diagram {
                                ManualDiagramView(kind: diagram)
                                    .padding(.top, 4)
                            }

                            if !section.shortcutRows.isEmpty {
                                ShortcutTableView(rows: section.shortcutRows)
                                    .padding(.top, 4)
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            }
        }
        .frame(minWidth: 760, minHeight: 620)
        .preferredColorScheme(.dark)
    }
}

private struct ShortcutTableView: View {
    let rows: [(key: String, action: String)]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                HStack(spacing: 12) {
                    Text(row.key)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 5))
                        .frame(width: 155, alignment: .leading)
                    Text(row.action)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.primary.opacity(0.9))
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(idx.isMultiple(of: 2) ? Color.white.opacity(0.025) : Color.clear)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1), lineWidth: 1))
    }
}

// MARK: - Illustrated Diagrams for Manual & Help

private struct ManualDiagramView: View {
    let kind: ManualDiagramKind

    var body: some View {
        switch kind {
        case .workspaceOverview:
            workspaceOverviewDiagram
        case .sidebarToolsGrid:
            sidebarToolsGridDiagram
        case .textFormattingBar:
            textFormattingBarDiagram
        case .selectionAndNodeEdit:
            selectionAndNodeEditDiagram
        case .booleanAndOffsetDiagram:
            booleanAndOffsetDiagram
        case .arraysDiagram:
            arraysDiagram
        case .imageTraceAndDitherDiagram:
            imageTraceAndDitherDiagram
        case .layerPaletteAndCutSettingsDiagram:
            layerPaletteAndCutSettingsDiagram
        }
    }

    private var workspaceOverviewDiagram: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ILLUSTRATION · LASERSTUDIO WORKSPACE LAYOUT")
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)

            VStack(spacing: 3) {
                HStack(spacing: 8) {
                    Label("1. Top Action Bar", systemImage: "menubar.rectangle")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.orange)
                    Text("New · Undo/Redo · Home · Shape · Import · Export · Preview · Connect")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(7)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))

                HStack(spacing: 6) {
                    Label("2. Text Modifier Bar (when Text selected)", systemImage: "textformat")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(.cyan)
                    Text("Font Family · [B] Bold · [I] Italic · [U] Underline · [S] Strikethrough · [ABC] All Caps · Height · Convert to Path")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(6)
                .background(Color.cyan.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))

                HStack(spacing: 4) {
                    VStack(spacing: 5) {
                        Text("3. Tool\nRail")
                            .font(.system(size: 9, weight: .bold))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.orange)
                        ForEach(["Select", "Line", "Rectangle", "Circle", "Polygon", "Text", "Node edit", "Weld"], id: \.self) { t in
                            LightBurnToolIcon(toolName: t, isSelected: t == "Select")
                                .frame(width: 24, height: 20)
                                .background(t == "Select" ? Color.orange.opacity(0.25) : Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 4))
                        }
                    }
                    .padding(6)
                    .frame(width: 58)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 5))

                    ZStack {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color(red: 0.09, green: 0.11, blue: 0.13))
                        Canvas { ctx, size in
                            let step: CGFloat = 22
                            var grid = Path()
                            for x in stride(from: 0, through: size.width, by: step) {
                                grid.move(to: CGPoint(x: x, y: 0))
                                grid.addLine(to: CGPoint(x: x, y: size.height))
                            }
                            for y in stride(from: 0, through: size.height, by: step) {
                                grid.move(to: CGPoint(x: 0, y: y))
                                grid.addLine(to: CGPoint(x: size.width, y: y))
                            }
                            ctx.stroke(grid, with: .color(.white.opacity(0.07)), lineWidth: 1)

                            let rect = CGRect(x: 34, y: 26, width: 110, height: 75)
                            ctx.stroke(Path(roundedRect: rect, cornerRadius: 8), with: .color(.red), lineWidth: 2)
                            let c1 = CGRect(x: 52, y: 46, width: 30, height: 30)
                            let c2 = CGRect(x: 96, y: 46, width: 30, height: 30)
                            ctx.stroke(Path(ellipseIn: c1), with: .color(.blue), lineWidth: 1.6)
                            ctx.stroke(Path(ellipseIn: c2), with: .color(.blue), lineWidth: 1.6)
                        }
                        VStack {
                            HStack {
                                Text("4. Infinite Zoom Canvas (mm Grid + Origin X0 Y0)")
                                    .font(.system(size: 9.5, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Color.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 4))
                                Spacer()
                            }
                            Spacer()
                            HStack {
                                Text("Right-Click Context Menu · Scroll/Pinch Infinite Zoom · Space+Drag Pan")
                                    .font(.system(size: 8.5))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Color.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 4))
                                Spacer()
                            }
                        }
                        .padding(8)
                    }
                    .frame(height: 185)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("5. Job Setup & Inspector")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(.orange)
                        Text("• Device & Auto-Detect\n• Material & Hatch\n• Layers List (Mode, Speed, Power, Passes, Visibility, Output)\n• X, Y, W, H, Rot, Corner R\n• Cut Settings / Trace / Adjust\n• Start / Pause / Stop Job")
                            .font(.system(size: 8.5))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(8)
                    .frame(width: 175, height: 185)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 5))
                }

                HStack(spacing: 4) {
                    Text("6. 30-Layer Color Bar:")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.orange)
                    ForEach(LightBurnPalette.layers.prefix(12)) { sw in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(sw.color)
                            .frame(width: 18, height: 14)
                            .overlay(
                                Text(sw.code)
                                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.white)
                            )
                    }
                    Text("… 29 + T1/T2")
                        .font(.system(size: 8.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(6)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
            }
        }
        .padding(12)
        .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1), lineWidth: 1))
    }

    private var sidebarToolsGridDiagram: some View {
        let tools: [(name: String, title: String, desc: String)] = [
            ("Select", "Select", "Pick, move, scale, rotate, or drag-box objects"),
            ("Position Laser", "Position Laser", "Click canvas to jog laser head to that point"),
            ("Line", "Draw Lines", "Click and drag straight vector lines"),
            ("Pen", "Freehand / Pen", "Sketch smooth freehand vector paths"),
            ("Rectangle", "Draw Rectangle", "Create rectangles or rounded-corner boxes"),
            ("Circle", "Draw Ellipse / Circle", "Create circles and ellipses"),
            ("Polygon", "Regular Polygon", "Create 3 to 24-sided polygons"),
            ("Text", "Create / Edit Text", "Add a Helvetica text layer with 'Text' and Bold/Italic/Underline/Strikethrough"),
            ("Node edit", "Edit Nodes", "Move vertices, delete nodes, or convert shapes to paths"),
            ("Add Tabs", "Add Tabs / Bridges", "Place holding tabs on cut paths so parts stay in place"),
            ("Measure", "Measure Distance", "Drag between two points to inspect distance, ΔX, and ΔY"),
            ("Radius", "Corner Radius / Fillet", "Click any rectangle, polygon, or path to round corners"),
            ("Offset Shapes", "Offset Shapes (⌥O)", "Generate inward, outward, or dual contour offsets"),
            ("Weld", "Boolean Weld (⌘W)", "Fuse all overlapping selected shapes into one outline"),
            ("Union", "Boolean Union (⌥U)", "Combine two overlapping vector shapes"),
            ("Subtract", "Boolean Subtract (⌥S)", "Cut the second selected shape out of the first (A − B)"),
            ("Intersect", "Boolean Intersect (⌥I)", "Keep only the overlapping area of two shapes"),
            ("Grid Array", "Grid Array", "Duplicate objects across rows and columns with spacing"),
            ("Circular Array", "Circular Array", "Duplicate objects radially around a center point"),
            ("Camera", "Camera Alignment", "Open live overhead USB camera overlay for positioning")
        ]
        return VStack(alignment: .leading, spacing: 8) {
            Text("ILLUSTRATED REFERENCE · LEFT SIDEBAR TOOLS (HOVER ANY ICON IN APP FOR TOOL NAME)")
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(tools, id: \.name) { item in
                    HStack(spacing: 10) {
                        LightBurnToolIcon(toolName: item.name, isSelected: true)
                            .frame(width: 32, height: 28)
                            .background(Color.orange.opacity(0.22), in: RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.orange.opacity(0.75), lineWidth: 1))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                            Text(item.desc)
                                .font(.system(size: 9.5))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(7)
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
                }
            }
        }
        .padding(12)
        .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1), lineWidth: 1))
    }

    private var textFormattingBarDiagram: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ILLUSTRATION · TOP TEXT FORMATTING BAR & VECTOR FONT MODIFIERS")
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Image(systemName: "textformat")
                    .foregroundStyle(.orange)
                Text("LASER STUDIO")
                    .font(.system(size: 10, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                Text("Helvetica ▾")
                    .font(.system(size: 10))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))

                ForEach([
                    ("bold", "Bold"),
                    ("italic", "Italic"),
                    ("underline", "Underline"),
                    ("strikethrough", "Strike"),
                    ("textformat.abc", "All Caps")
                ], id: \.0) { icon, label in
                    VStack(spacing: 2) {
                        Image(systemName: icon)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.orange)
                            .frame(width: 26, height: 22)
                            .background(Color.orange.opacity(0.22), in: RoundedRectangle(cornerRadius: 5))
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.orange, lineWidth: 1))
                        Text(label)
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
                Text("Convert to Path")
                    .font(.system(size: 9.5, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
            }
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))

            HStack(spacing: 12) {
                VStack(spacing: 4) {
                    Text("LASER")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.green)
                    Text("Bold")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(8)
                .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 6))

                VStack(spacing: 4) {
                    Text("LASER")
                        .font(.system(size: 15, weight: .regular).italic())
                        .foregroundStyle(.green)
                    Text("Italic")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(8)
                .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 6))

                VStack(spacing: 4) {
                    Text("LASER")
                        .font(.system(size: 15, weight: .semibold))
                        .underline(true, color: .green)
                        .foregroundStyle(.green)
                    Text("Underline (Engraved Bar)")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(8)
                .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 6))

                VStack(spacing: 4) {
                    Text("LASER")
                        .font(.system(size: 15, weight: .semibold))
                        .strikethrough(true, color: .green)
                        .foregroundStyle(.green)
                    Text("Strikethrough (Engraved Bar)")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(8)
                .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(12)
        .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1), lineWidth: 1))
    }

    private var selectionAndNodeEditDiagram: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("LEFT-DRAG (TOUCHED)")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(.green)
                Canvas { ctx, size in
                    let r1 = CGRect(x: 18, y: 18, width: 65, height: 42)
                    let r2 = CGRect(x: 92, y: 24, width: 55, height: 38)
                    ctx.stroke(Path(r1), with: .color(.orange), lineWidth: 2)
                    ctx.stroke(Path(ellipseIn: r2), with: .color(.orange), lineWidth: 2)
                    let sel = CGRect(x: 45, y: 12, width: 70, height: 52)
                    ctx.fill(Path(sel), with: .color(.green.opacity(0.15)))
                    ctx.stroke(Path(sel), with: .color(.green), style: StrokeStyle(lineWidth: 1.3, dash: [4, 3]))
                }
                .frame(height: 76)
                .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
                Text("Selects every object the green marquee box touches.")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 6) {
                Text("RIGHT-DRAG (ENCLOSED)")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(.cyan)
                Canvas { ctx, size in
                    let r1 = CGRect(x: 22, y: 22, width: 46, height: 34)
                    let r2 = CGRect(x: 92, y: 20, width: 55, height: 40)
                    ctx.stroke(Path(r1), with: .color(.orange), lineWidth: 2)
                    ctx.stroke(Path(ellipseIn: r2), with: .color(.gray), lineWidth: 1.5)
                    let sel = CGRect(x: 14, y: 14, width: 95, height: 50)
                    ctx.fill(Path(sel), with: .color(.cyan.opacity(0.15)))
                    ctx.stroke(Path(sel), with: .color(.cyan), style: StrokeStyle(lineWidth: 1.3, dash: [4, 3]))
                }
                .frame(height: 76)
                .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
                Text("Selects only objects 100% inside the blue marquee box.")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 6) {
                Text("UNGROUP / BREAK APART")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(.orange)
                Canvas { ctx, size in
                    let p1 = CGRect(x: 16, y: 20, width: 38, height: 38)
                    let p2 = CGRect(x: 68, y: 14, width: 38, height: 38)
                    let p3 = CGRect(x: 116, y: 26, width: 34, height: 34)
                    ctx.stroke(Path(p1), with: .color(.red), lineWidth: 1.8)
                    ctx.stroke(Path(ellipseIn: p2), with: .color(.green), lineWidth: 1.8)
                    ctx.stroke(Path(roundedRect: p3, cornerRadius: 5), with: .color(.cyan), lineWidth: 1.8)
                }
                .frame(height: 76)
                .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
                Text("⌘U splits compound SVGs/text into individual contours; ⌥B breaks into lines.")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(12)
        .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1), lineWidth: 1))
    }

    private var booleanAndOffsetDiagram: some View {
        HStack(spacing: 10) {
            ForEach([
                ("Offset (⌥O)", "Inward / Outward", 0),
                ("Weld / Union", "Combined Outline", 1),
                ("Subtract (A−B)", "Cut Front from Back", 2),
                ("Intersect (⌥I)", "Overlap Region Only", 3)
            ], id: \.0) { title, sub, mode in
                VStack(spacing: 5) {
                    Text(title)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.orange)
                    Canvas { ctx, size in
                        let w = size.width, h = size.height
                        let r1 = CGRect(x: w * 0.18, y: h * 0.18, width: w * 0.44, height: h * 0.56)
                        let r2 = CGRect(x: w * 0.38, y: h * 0.26, width: w * 0.44, height: h * 0.56)
                        if mode == 0 {
                            let outer = CGRect(x: w * 0.14, y: h * 0.14, width: w * 0.72, height: h * 0.72)
                            let inner = outer.insetBy(dx: 10, dy: 10)
                            ctx.stroke(Path(roundedRect: outer, cornerRadius: 8), with: .color(.orange), style: StrokeStyle(lineWidth: 1.6, dash: [3, 2]))
                            ctx.stroke(Path(roundedRect: inner, cornerRadius: 4), with: .color(.white), lineWidth: 1.8)
                        } else if mode == 1 {
                            ctx.fill(Path(ellipseIn: r1), with: .color(.orange.opacity(0.3)))
                            ctx.fill(Path(ellipseIn: r2), with: .color(.orange.opacity(0.3)))
                            ctx.stroke(Path(ellipseIn: r1), with: .color(.orange), lineWidth: 1.8)
                            ctx.stroke(Path(ellipseIn: r2), with: .color(.orange), lineWidth: 1.8)
                        } else if mode == 2 {
                            ctx.fill(Path(r1), with: .color(.orange.opacity(0.3)))
                            ctx.stroke(Path(r1), with: .color(.orange), lineWidth: 1.8)
                            ctx.stroke(Path(ellipseIn: r2), with: .color(.cyan), style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                        } else {
                            ctx.stroke(Path(ellipseIn: r1), with: .color(.white.opacity(0.35)), lineWidth: 1.2)
                            ctx.stroke(Path(ellipseIn: r2), with: .color(.white.opacity(0.35)), lineWidth: 1.2)
                            ctx.fill(Path(roundedRect: r1.intersection(r2), cornerRadius: 6), with: .color(.orange))
                        }
                    }
                    .frame(height: 64)
                    .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
                    Text(sub)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(12)
        .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1), lineWidth: 1))
    }

    private var arraysDiagram: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("GRID ARRAY (X COLUMNS × Y ROWS)")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(.orange)
                Canvas { ctx, size in
                    for r in 0..<2 {
                        for c in 0..<4 {
                            let rect = CGRect(x: 20 + c * 42, y: 14 + r * 30, width: 30, height: 20)
                            ctx.stroke(Path(roundedRect: rect, cornerRadius: 3), with: .color(r == 0 && c == 0 ? .orange : .cyan), lineWidth: 1.6)
                        }
                    }
                }
                .frame(height: 74)
                .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
                Text("Set X/Y counts, spacing or center-to-center distance, and alternating row shift.")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 6) {
                Text("CIRCULAR ARRAY (RADIAL COPIES)")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(.orange)
                Canvas { ctx, size in
                    let cx = size.width / 2, cy = size.height / 2, rad: CGFloat = 24
                    ctx.stroke(Path(ellipseIn: CGRect(x: cx - rad, y: cy - rad, width: rad * 2, height: rad * 2)), with: .color(.white.opacity(0.2)), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    for i in 0..<8 {
                        let a = Double(i) * .pi / 4
                        let px = cx + CGFloat(cos(a)) * rad
                        let py = cy + CGFloat(sin(a)) * rad
                        let dot = CGRect(x: px - 5, y: py - 5, width: 10, height: 10)
                        ctx.stroke(Path(ellipseIn: dot), with: .color(i == 0 ? .orange : .cyan), lineWidth: 1.6)
                    }
                }
                .frame(height: 74)
                .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
                Text("Set copy count, start/end angle, center X/Y, and optional object rotation.")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(12)
        .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1), lineWidth: 1))
    }

    private var imageTraceAndDitherDiagram: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("IMAGE TRACE (BITMAP → VECTOR)")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(.purple)
                Canvas { ctx, size in
                    let r = CGRect(x: 18, y: 12, width: size.width - 36, height: size.height - 24)
                    ctx.fill(Path(roundedRect: r, cornerRadius: 8), with: .color(.white.opacity(0.08)))
                    var contour = Path()
                    contour.move(to: CGPoint(x: 34, y: 56))
                    contour.addCurve(to: CGPoint(x: 150, y: 24), control1: CGPoint(x: 70, y: 10), control2: CGPoint(x: 110, y: 70))
                    contour.addLine(to: CGPoint(x: 150, y: 58))
                    contour.closeSubpath()
                    ctx.stroke(contour, with: .color(.purple), lineWidth: 2)
                }
                .frame(height: 72)
                .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
                Text("Purple preview contours with Cutoff, Threshold, Smoothness, Optimize, and Crop box.")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 6) {
                Text("ADJUST IMAGE & 11 DITHER MODES")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(.orange)
                Canvas { ctx, size in
                    for row in 0..<5 {
                        for col in 0..<18 {
                            if (row + col).isMultiple(of: 2) || col > 10 {
                                let dot = CGRect(x: 18 + col * 9, y: 14 + row * 10, width: 4, height: 4)
                                ctx.fill(Path(ellipseIn: dot), with: .color(.orange.opacity(Double(col) / 18.0 + 0.2)))
                            }
                        }
                    }
                }
                .frame(height: 72)
                .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
                Text("Jarvis, Stucki, Atkinson, Dither, Ordered, Halftone, Newsprint, Sketch, Grayscale, DPI & Unsharp Mask.")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(12)
        .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1), lineWidth: 1))
    }

    private var layerPaletteAndCutSettingsDiagram: some View {
        HStack(spacing: 10) {
            ForEach([
                ("Line Mode", "Vector Cut / Score Outline", 0),
                ("Fill Mode", "Bidirectional / Cross-Hatch Scan", 1),
                ("Fill + Line", "Raster Fill Then Clean Outline Cut", 2)
            ], id: \.0) { title, desc, mode in
                VStack(spacing: 5) {
                    Text(title)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.orange)
                    Canvas { ctx, size in
                        let rect = CGRect(x: 24, y: 12, width: size.width - 48, height: size.height - 24)
                        if mode == 1 || mode == 2 {
                            var hatch = Path()
                            var y = rect.minY + 4
                            while y < rect.maxY {
                                hatch.move(to: CGPoint(x: rect.minX + 2, y: y))
                                hatch.addLine(to: CGPoint(x: rect.maxX - 2, y: y))
                                y += 5
                            }
                            ctx.stroke(hatch, with: .color(.orange.opacity(0.65)), lineWidth: 1.2)
                        }
                        if mode == 0 || mode == 2 {
                            ctx.stroke(Path(roundedRect: rect, cornerRadius: 5), with: .color(mode == 2 ? .red : .cyan), lineWidth: 2)
                        }
                    }
                    .frame(height: 62)
                    .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
                    Text(desc)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(12)
        .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1), lineWidth: 1))
    }
}

// MARK: - Quick Help Window (Help ▸ LaserStudio Help)

struct HelpInfoView: View {
    private let sections: [HelpSection] = [
        HelpSection(
            title: "Welcome to LaserStudio",
            icon: "sparkles",
            body: [
                "**LaserStudio** is a full-featured macOS laser design, image tracing, and GRBL G-code sender built with a LightBurn-compatible workflow.",
                "Hover over **any icon** in the top bar, left tool rail, workspace bar, bottom 30-layer palette, or right inspector to immediately see the tool's name and shortcut."
            ],
            diagram: .workspaceOverview
        ),
        HelpSection(
            title: "Quick Start in 5 Steps",
            icon: "bolt.fill",
            body: [
                "1. **Connect Your Laser**: Click **Connect** (top right) or **Add Device…** in Job Setup to select your USB serial port and auto-detect GRBL settings (`$$`, workspace size, and `S max`).",
                "2. **Create or Import Artwork**: Draw with the left sidebar tools (**Line, Pen, Rectangle, Circle, Polygon, Text**) or click **Import** for SVG, PNG, JPG, or BMP files.",
                "3. **Style Text & Shapes**: Select any text object to reveal the **Top Text Formatting Bar** with **Bold, Italic, Underline, Strikethrough, All Caps**, Font Family picker, and **Convert to Path**.",
                "4. **Assign Layers & Cut Settings**: Click a swatch (`00`–`29`, `T1`, `T2`) on the bottom palette bar, then click the **Cut Settings** slider icon to configure **Line / Fill / Fill+Line**, Speed, Max/Min Power, Passes, Kerf, Tabs, Perforation, Cross-Hatch, and Air Assist.",
                "5. **Preview & Run**: Click **Preview (⌘B)** to simulate laser travel and burn time, **Home** to move to workspace `X0 Y0`, and **Start (⇧⌘↩)** to stream the job or **Export (⌘E)** to save `.gcode`."
            ]
        ),
        HelpSection(
            title: "All Left-Sidebar Tools",
            icon: "wrench.and.screwdriver.fill",
            body: [
                "Click any tool in the left sidebar to activate it, or hover over its icon to see its name:"
            ],
            diagram: .sidebarToolsGrid
        ),
        HelpSection(
            title: "Essential Keyboard Shortcuts",
            icon: "keyboard",
            body: [
                "LaserStudio supports LightBurn's single-key and modifier shortcuts directly on the canvas:"
            ],
            shortcutRows: [
                ("⌘N / ⌘E / ⌘B", "New Project / Export G-code / Open Burn Preview"),
                ("⌘Z / ⇧⌘Z (or ⌘Y)", "Undo / Redo workspace changes"),
                ("⌘C / ⌘X / ⌘V / ⌘D", "Copy / Cut / Paste / Duplicate selection"),
                ("⌘A / ⇧⌘I / ⌫", "Select All / Invert Selection / Delete selected objects"),
                ("⌘G / ⌘U (or ⇧⌘G)", "Group objects / Ungroup group or split compound SVG/Text vectors"),
                ("⌥B / ⌘P", "Break Apart vectors into individual segments / Convert to Path"),
                ("⌘W / ⌥U / ⌥S / ⌥I", "Boolean Weld / Union / Subtract (A−B) / Intersect"),
                ("⌥O / ⌥T", "Offset Shapes dialog / Trace Image dialog"),
                ("P", "Move selected object(s) to the center of the workspace page"),
                ("L / R / T / B / C / E", "Align Left / Right / Top / Bottom / Center Horizontally / Vertically"),
                ("⌘H / ⌘J / . / ,", "Flip Horizontal / Flip Vertical / Rotate 90° CW / 90° CCW"),
                ("Arrow Keys", "Nudge 1 mm (Hold ⇧ for 5 mm, Hold ⌘ for 0.1 mm)"),
                ("Scroll / Pinch / Space+Drag", "Cursor-centered zoom to infinity / Pan workspace canvas"),
                ("⌘+ / ⌘- / ⌘0 / ⇧⌘A", "Zoom In / Zoom Out / Reset Zoom to Page / Frame Selection")
            ]
        )
    ]

    var body: some View {
        HelpDocument(
            heading: "LaserStudio Quick Help",
            subtitle: "Visual overview of tools, text modifiers, layers, and LightBurn shortcuts",
            sections: sections
        )
    }
}

// MARK: - Complete Instruction Manual (Help ▸ Instruction Manual)

struct ManualView: View {
    private let sections: [HelpSection] = [
        HelpSection(
            title: "1. Workspace Layout & Hover Tooltips",
            icon: "macwindow",
            body: [
                "**LaserStudio** organizes your workflow into 6 areas: the **Top Toolbar**, the contextual **Text Formatting Bar** (shown automatically whenever a Text layer is selected), the **Left Tool Rail**, the **Infinite-Zoom Canvas**, the **Bottom 30-Layer Palette (`00`–`29`, `T1`, `T2`)**, and the **Right Job Setup & Shape Inspector**.",
                "**Hover Tool Names**: Hovering your pointer over any icon anywhere in the app displays an instant popover badge with the tool's name and shortcut, and updates the orange tool banner above the canvas."
            ],
            diagram: .workspaceOverview
        ),
        HelpSection(
            title: "2. Connecting & Configuring Your Laser",
            icon: "cable.connector",
            body: [
                "1. Connect your GRBL laser engraver (Longer Ray5, xTool D1, Sculpfun, Ortur, Atomstack, NEJE, or custom GRBL) via USB and power it on.",
                "2. Click **Connect** in the top-right corner or **Add Device…** under **DEVICE** in the right inspector.",
                "3. When **Auto-Detect** is enabled, LaserStudio queries GRBL (`$I` and `$$`) to automatically configure workspace dimensions (`$130`/`$131`), maximum feed rate (`$110`/`$111`), spindle/laser max `S` (`$30`), laser mode (`$32`), and homing (`$22`).",
                "4. Use **Save as preset…** to store custom machine profiles."
            ]
        ),
        HelpSection(
            title: "3. Left Sidebar Drawing & Editing Tools",
            icon: "paintbrush.pointed.fill",
            body: [
                "All LightBurn creation, modification, measurement, array, and camera tools are located on the left sidebar:"
            ],
            diagram: .sidebarToolsGrid
        ),
        HelpSection(
            title: "4. Text Tool & Top Font Modifiers Bar",
            icon: "textformat",
            body: [
                "Click the **Text** tool on the left rail and click anywhere on the canvas to place a vector text layer. Whenever a text layer is selected, the **Text Formatting Bar** appears at the top of the workspace:",
                "• **Text Content Field**: Edit the text string live on the canvas.",
                "• **Font Family Menu**: Choose any installed macOS system font.",
                "• **Bold (`B`)**: Applies bold font weight traits to both the canvas preview and generated G-code.",
                "• **Italic (`I`)**: Applies italic slant traits to both the canvas preview and generated G-code.",
                "• **Underline (`U`)**: Adds a true vector underline contour below the baseline that engraves/cuts in Line, Fill, and Fill+Line modes.",
                "• **Strikethrough (`S`)**: Adds a true vector strikethrough contour across the text midline that engraves/cuts in all modes.",
                "• **All Caps (`ABC`)**: Toggles uppercase transformation non-destructively.",
                "• **Convert to Path (`⌘P`)**: Converts the text and any active Underline/Strikethrough bars into editable vector subpaths for node editing, welding, or breaking apart."
            ],
            diagram: .textFormattingBar
        ),
        HelpSection(
            title: "5. Selection, Grouping, Ungrouping & Breaking Vectors Apart",
            icon: "lasso.and.sparkles",
            body: [
                "• **Left-Drag Marquee (Green Box)**: Dragging with the left mouse button selects every visible layer that the selection box touches.",
                "• **Right-Drag Marquee (Blue Box)**: Dragging with the right mouse button (or holding `⌥` while left-dragging) selects only layers that are **100% enclosed** inside the box.",
                "• **Group (`⌘G`)**: Combines multiple selected objects into a group that moves and scales together.",
                "• **Ungroup (`⌘U` / `⇧⌘G`)**: Ungroups a group—OR, when used on an ungrouped compound SVG path, traced image, or text object, **splits its subpaths apart into separate independent vector objects** (just like LightBurn).",
                "• **Break Apart Vectors (`⌥B`)**: Available in the right-click menu; splits a compound path into separate contours or explodes a single shape into individual straight line segments.",
                "• **Edit Nodes (`Node edit`)**: Click any shape to convert it to a path, drag blue vertex handles to reshape, or Option-click / right-click a vertex to delete it."
            ],
            diagram: .selectionAndNodeEdit
        ),
        HelpSection(
            title: "6. Offset Shapes & Boolean Operations (Weld, Union, Subtract, Intersect)",
            icon: "square.on.circle",
            body: [
                "• **Offset Shapes (`⌥O`)**: Select one or more vector shapes and click **Offset Shapes** on the left sidebar (or right-click menu). Choose **Outward**, **Inward**, or **Both**, set the distance in `mm`, choose **Round**, **Sharp**, or **Bevel** corners, and optionally delete the original shape.",
                "• **Boolean Weld (`⌘W`)**: Fuses all selected overlapping shapes into their outer silhouette.",
                "• **Boolean Union (`⌥U`)**: Combines two overlapping shapes into a single unified shape.",
                "• **Boolean Subtract (`⌥S`)**: Cuts the second selected shape out of the first selected shape (`A − B`).",
                "• **Boolean Intersect (`⌥I`)**: Keeps only the overlapping region shared by the selected shapes."
            ],
            diagram: .booleanAndOffsetDiagram
        ),
        HelpSection(
            title: "7. Grid Array & Circular Array",
            icon: "square.grid.3x3.fill",
            body: [
                "• **Grid Array**: Select any object(s) and click **Grid Array** in the left sidebar or right-click menu. Set X Columns, Y Rows, gap or center-to-center spacing, alternating row shift, and reverse direction with live preview.",
                "• **Circular Array**: Select any object(s) and click **Circular Array**. Set the number of copies, start/end angle (e.g. `360°` full ring), rotation center X/Y, and whether copies rotate to face the center."
            ],
            diagram: .arraysDiagram
        ),
        HelpSection(
            title: "8. SVG Import, Image Import, Adjust Image & Trace Image",
            icon: "photo.on.rectangle.angled",
            body: [
                "• **LightBurn-Accurate SVG Import**: Preserves physical units (`mm`, `cm`, `in`, `pt`, `pc`), nested transforms, `<use>` clones, inner holes, and maps stroke/fill colors onto the 30-layer LightBurn palette (`00`–`29`), grouping same-color paths into compound layers.",
                "• **Image Import & Adjust Image**: Honors embedded DPI metadata, centers oversized images in the workspace, and provides **11 dithering modes** (*Threshold, Ordered, Atkinson, Dither/Floyd-Steinberg, Stucki, Jarvis, Burkes, Newsprint, Halftone, Sketch, Grayscale*) plus **DPI, Brightness, Contrast, Gamma, Unsharp Mask (Enhance Radius/Amount), Negative**, and **Pass-Through**.",
                "• **Trace Image (`⌥T`)**: Right-click any image and choose **Trace Image…** (or click **Trace…** in the inspector). Adjust **Cutoff**, **Threshold**, **Sketch Trace**, **Ignore Less Than**, **Smoothness** (Chaikin corner smoothing), **Optimize**, and the interactive **Crop frame** while inspecting purple vector contours in real time."
            ],
            diagram: .imageTraceAndDitherDiagram
        ),
        HelpSection(
            title: "9. 30-Layer Palette & Cut Settings Editor",
            icon: "slider.horizontal.3",
            body: [
                "• **Bottom Palette (`00`–`29` + `T1`/`T2`)**: Click any color swatch at the bottom of the window to assign selected objects to that layer or set the active drawing layer. `T1` and `T2` are non-output **Tool Layers** used for framing, guides, and alignment.",
                "• **Cut Settings Editor**: Click the slider icon next to any layer (or **Cut Settings…** in the inspector) to configure:",
                "  – **Mode**: **Line** (vector cut/score), **Fill** (raster scan hatch), or **Fill + Line** (fill interior then cut outline).",
                "  – **Speed, Max Power, Min Power & Passes**: Plus **Z-Offset** and **Z Step per Pass**.",
                "  – **Cut Modifiers**: **Kerf Offset**, **Overcut**, **Perforation Mode** (Cut/Skip mm), and **Holding Tabs / Bridges** (manual or automatic).",
                "  – **Fill Modifiers**: **Bi-Directional Fill**, **Cross-Hatch**, **Scan Angle**, **Line Interval / LPI**, **Overscanning %**, and **Flood Fill**.",
                "  – **Hardware Controls**: **Constant Power (`M3` vs `M4`)** and **Air Assist (`M8` / `M9`)**."
            ],
            diagram: .layerPaletteAndCutSettingsDiagram
        ),
        HelpSection(
            title: "10. Infinite Zoom, Panning, Burn Preview & Running Jobs",
            icon: "flame.fill",
            body: [
                "• **Infinite Magnification**: Scroll the mouse wheel or pinch on the trackpad to zoom smoothly toward the cursor with **no upper zoom cap**. The millimeter grid automatically subdivides by powers of 10 (`10 mm` → `1 mm` → `0.1 mm` → `0.01 mm` → …) as you zoom in.",
                "• **Panning**: Hold **Space + Left-Drag**, use a two-finger trackpad scroll, or drag with the middle mouse button. Press `⌘0` to reset zoom to the page.",
                "• **Burn Preview (`⌘B`)**: Simulates rapid travel moves (`G0`) and laser burn moves (`G1`), showing estimated job duration and playback scrubbing.",
                "• **Start / Pause / Stop / Export**: Press **Start (`⇧⌘↩`)** to stream G-code over USB, or **Export (`⌘E`)** to save `.gcode`."
            ]
        ),
        HelpSection(
            title: "11. Complete Keyboard Shortcuts Reference",
            icon: "command",
            body: [
                "Use these keyboard shortcuts on the workspace canvas for rapid LightBurn-style editing:"
            ],
            shortcutRows: [
                ("⌘N / ⌘E / ⌘B", "New Project / Export G-code / Burn Preview"),
                ("⌘Z / ⇧⌘Z / ⌘Y", "Undo / Redo"),
                ("⌘X / ⌘C / ⌘V / ⌘D", "Cut / Copy / Paste / Duplicate"),
                ("⌘A / ⇧⌘I / ⌫", "Select All / Invert Selection / Delete"),
                ("⌘G / ⌘U / ⇧⌘G", "Group / Ungroup (splits compound SVG & Text subpaths)"),
                ("⌥B", "Break Apart vectors into individual contours or segments"),
                ("⌘P", "Convert selected shape or text to editable vector path"),
                ("⌘W / ⌥U / ⌥S / ⌥I", "Boolean Weld / Union / Subtract (A−B) / Intersect"),
                ("⌥O / ⌥T", "Offset Shapes / Trace Image"),
                ("⌘L", "Lock / Unlock selected shape position and size"),
                ("P", "Center selected object(s) in workspace page"),
                ("L / R / T / B / C / E", "Align Left / Right / Top / Bottom / Center H / Center V"),
                ("⌘H / ⌘J", "Flip Horizontal / Flip Vertical"),
                (". / ,", "Rotate 90° Clockwise / 90° Counter-Clockwise"),
                ("⌘] / ⌘[ (PgUp/PgDn)", "Bring to Front / Send to Back"),
                ("Arrow Keys", "Nudge 1 mm (⇧ = 5 mm, ⌘ = 0.1 mm)"),
                ("⌘+ / ⌘- / ⌘0 / ⇧⌘A", "Zoom In (to infinity) / Zoom Out / Fit Page / Frame Selection"),
                ("Space + Drag", "Pan workspace canvas")
            ]
        ),
        HelpSection(
            title: "12. Laser Safety & Troubleshooting",
            icon: "exclamationmark.triangle.fill",
            body: [
                "• **Safety First**: Never leave an operating laser unattended. Always wear certified OD6+ laser safety goggles matched to your laser wavelength, use fume extraction, keep a fire extinguisher within arm's reach, and never cut PVC, vinyl, or PTFE/Teflon.",
                "• **Unsigned macOS App Launch**: On first launch, Control-click `LaserStudio.app`, choose **Open**, and confirm.",
                "• **Serial Port Not Listed**: Check your USB cable/adapter, power on the laser, and click **Connect** to rescan `/dev/cu.*` ports.",
                "• **Camera Access**: Enable camera permission in **System Settings ▸ Privacy & Security ▸ Camera**."
            ]
        )
    ]

    var body: some View {
        HelpDocument(
            heading: "LaserStudio Instruction Manual",
            subtitle: "Complete Visual Guide to Tools, Text Modifiers, Layers, Image Tracing & GRBL Control",
            sections: sections
        )
    }
}
