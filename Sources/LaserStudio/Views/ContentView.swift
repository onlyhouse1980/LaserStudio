import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var objects: [DesignObject] = [
        DesignObject(kind: .rectangle, x: 105, y: 78, width: 135, height: 102, label: "Outer frame", color: .red),
        DesignObject(kind: .circle, x: 149, y: 111, width: 48, height: 48, label: "Mount hole", color: .blue),
        DesignObject(kind: .circle, x: 215, y: 111, width: 48, height: 48, label: "Mount hole", color: .blue),
        DesignObject(kind: .text, x: 133, y: 210, width: 120, height: 28, label: "LASER STUDIO", color: .green)
    ]
    @State private var selection: UUID?
    @State private var selectedIDs: Set<UUID> = []
    @State private var undoStack: [[DesignObject]] = []
    @State private var redoStack: [[DesignObject]] = []
    @State private var pendingUndoSnapshot: [DesignObject]?
    @State private var historyWorkItem: DispatchWorkItem?
    @State private var applyingHistory = false
    @State private var activeTool = "Select"
    @State private var showGrid = true
    @State private var zoom = 1.0
    @State private var panOffset: CGSize = .zero
    @StateObject private var grbl = GRBLController()
    @State private var showDevicePicker = false
    @State private var showCameraPreview = false
    @State private var showBurnPreview = false
    @State private var showAddDevice = false
    @StateObject private var profiles = LaserProfileStore()
    @State private var activeMachine = LaserProfile.ray5
    @State private var showSavePreset = false
    @State private var presetName = ""
    @State private var previewGCode: [String] = []
    @State private var material = "3 mm birch plywood"
    @State private var hatchSpacing = 0.4
    @State private var projectName = "Untitled project"
    @State private var status = "Ready"
    @State private var activeLayerIndex: Int = 0
    @State private var activeIsToolLayer: Bool = false
    @State private var cutSettingsLayerID: UUID?
    @State private var adjustImageLayerID: UUID?
    @State private var traceImageObject: DesignObject?
    @State private var showOffsetSheet = false
    @State private var showGridArraySheet = false
    @State private var showCircularArraySheet = false
    @State private var hoveredToolLabel: String?
    @FocusState private var textInputFocused: Bool

    private var selectedIndex: Int? { objects.firstIndex { $0.id == selection } }
    private var selectedObject: DesignObject? { selectedIndex.map { objects[$0] } }
    private var activeSwatch: LightBurnLayerSwatch {
        if activeIsToolLayer {
            return LightBurnPalette.toolLayers.first(where: { $0.index == activeLayerIndex }) ?? LightBurnPalette.toolLayers[0]
        }
        return LightBurnPalette.layers[min(max(0, activeLayerIndex), LightBurnPalette.layers.count - 1)]
    }
    private var usedLayerIndices: Set<Int> {
        Set(objects.map { LightBurnPalette.closestSwatch(for: $0.color, isToolLayer: $0.isToolLayer).index })
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            HStack(spacing: 0) {
                toolRail
                workspace
                inspector
            }
            footer
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(.dark)
        .onAppear {
            activeMachine = profiles.selected
            grbl.configure(with: activeMachine)
            if selection == nil { selection = objects.first?.id }
            if let selection, selectedIDs.isEmpty { selectedIDs = [selection] }
        }
        .onChange(of: objects) { oldValue, _ in
            if applyingHistory {
                applyingHistory = false
                pendingUndoSnapshot = nil
                historyWorkItem?.cancel()
                return
            }
            if pendingUndoSnapshot == nil { pendingUndoSnapshot = oldValue }
            historyWorkItem?.cancel()
            let work = DispatchWorkItem { commitPendingHistory() }
            historyWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
        }
        .onChange(of: selection) { _, newSelection in
            if let newSelection {
                if let groupID = objects.first(where: { $0.id == newSelection })?.groupID {
                    selectedIDs = Set(objects.filter { $0.groupID == groupID }.map(\.id))
                } else if !selectedIDs.contains(newSelection) {
                    selectedIDs = [newSelection]
                }
            } else {
                selectedIDs = []
            }
            guard let newSelection, objects.first(where: { $0.id == newSelection })?.kind == .text else {
                textInputFocused = false
                return
            }
            textInputFocused = false
            DispatchQueue.main.async {
                textInputFocused = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .newProject)) { _ in newProject() }
        .onReceive(NotificationCenter.default.publisher(for: .exportJob)) { _ in exportJob() }
        .sheet(isPresented: $showDevicePicker) { devicePicker }
        .sheet(isPresented: $showCameraPreview) { CameraPreviewSheet() }
        .sheet(isPresented: $showBurnPreview) { BurnPreviewSheet(lines: previewGCode, sMax: grbl.sMax, machine: activeMachine) }
        .sheet(isPresented: Binding(
            get: { cutSettingsLayerID != nil && objects.contains(where: { $0.id == cutSettingsLayerID }) },
            set: { if !$0 { cutSettingsLayerID = nil } }
        )) {
            if let id = cutSettingsLayerID, let idx = objects.firstIndex(where: { $0.id == id }) {
                CutSettingsEditorSheet(
                    object: $objects[idx],
                    maxFeedRate: activeMachine.maxFeedRate,
                    onApplyToSameColorLayers: { updated in
                        let targetCode = LightBurnPalette.closestSwatch(for: updated.color, isToolLayer: updated.isToolLayer).code
                        for i in objects.indices where objects[i].id != updated.id {
                            let code = LightBurnPalette.closestSwatch(for: objects[i].color, isToolLayer: objects[i].isToolLayer).code
                            if code == targetCode {
                                objects[i].layerMode = updated.layerMode
                                objects[i].speed = updated.speed
                                objects[i].power = updated.power
                                objects[i].minPower = updated.minPower
                                objects[i].passCount = updated.passCount
                                objects[i].zOffset = updated.zOffset
                                objects[i].zPerPass = updated.zPerPass
                                objects[i].kerfOffset = updated.kerfOffset
                                objects[i].useCustomInterval = updated.useCustomInterval
                                objects[i].lineInterval = updated.lineInterval
                                objects[i].scanAngle = updated.scanAngle
                                objects[i].crossHatch = updated.crossHatch
                                objects[i].bidirectionalFill = updated.bidirectionalFill
                                objects[i].overscanEnabled = updated.overscanEnabled
                                objects[i].overscanPercent = updated.overscanPercent
                                objects[i].floodFill = updated.floodFill
                                objects[i].constantPower = updated.constantPower
                                objects[i].airAssist = updated.airAssist
                                objects[i].perforationEnabled = updated.perforationEnabled
                                objects[i].perforationCutLength = updated.perforationCutLength
                                objects[i].perforationSkipLength = updated.perforationSkipLength
                                objects[i].tabsEnabled = updated.tabsEnabled
                                objects[i].tabSize = updated.tabSize
                                objects[i].tabCount = updated.tabCount
                                objects[i].overcut = updated.overcut
                                objects[i].isToolLayer = updated.isToolLayer
                            }
                        }
                    }
                )
            }
        }
        .sheet(isPresented: Binding(
            get: { adjustImageLayerID != nil && objects.contains(where: { $0.id == adjustImageLayerID }) },
            set: { if !$0 { adjustImageLayerID = nil } }
        )) {
            if let id = adjustImageLayerID, let idx = objects.firstIndex(where: { $0.id == id }) {
                AdjustImageEditorSheet(object: $objects[idx])
            }
        }
        .sheet(item: $traceImageObject) { image in
            ImageTraceEditor(image: image) { tracedLayers, deleteOriginal in
                guard !tracedLayers.isEmpty else { return }
                if deleteOriginal {
                    objects.removeAll { $0.id == image.id }
                }
                objects.append(contentsOf: tracedLayers)
                selectedIDs = Set(tracedLayers.map(\.id))
                selection = tracedLayers.first?.id
                status = "Traced image into \(tracedLayers.count) vector layer\(tracedLayers.count == 1 ? "" : "s")"
            }
            .frame(width: 920, height: 640)
        }
        .sheet(isPresented: $showOffsetSheet) {
            let ids = selectedIDs.isEmpty ? Set(selection.map { [$0] } ?? []) : selectedIDs
            let sources = objects.filter { ids.contains($0.id) && $0.kind != .image }
            OffsetShapesSheet(sourceObjects: sources, workspace: activeMachine.workspace) { offsetObj, deleteOrig in
                if deleteOrig {
                    let removeIDs = Set(sources.map(\.id))
                    objects.removeAll { removeIDs.contains($0.id) }
                }
                objects.append(offsetObj)
                selection = offsetObj.id
                selectedIDs = [offsetObj.id]
                status = "Created offset shape (\(offsetObj.label))"
            }
        }
        .sheet(isPresented: $showGridArraySheet) {
            let ids = selectedIDs.isEmpty ? Set(selection.map { [$0] } ?? []) : selectedIDs
            let sources = objects.filter { ids.contains($0.id) }
            GridArraySheet(sourceObjects: sources, workspace: activeMachine.workspace) { copies in
                objects.append(contentsOf: copies)
                selectedIDs.formUnion(copies.map(\.id))
                status = "Created Grid Array (\(copies.count) copies)"
            }
        }
        .sheet(isPresented: $showCircularArraySheet) {
            let ids = selectedIDs.isEmpty ? Set(selection.map { [$0] } ?? []) : selectedIDs
            let sources = objects.filter { ids.contains($0.id) }
            CircularArraySheet(sourceObjects: sources, workspace: activeMachine.workspace) { copies in
                objects.append(contentsOf: copies)
                selectedIDs.formUnion(copies.map(\.id))
                status = "Created Circular Array (\(copies.count) copies)"
            }
        }
        .sheet(isPresented: $showAddDevice) {
            AddDeviceSheet(grbl: grbl, onSave: { profile in
                let saved = profiles.save(profile, named: profile.name)
                activeMachine = saved
                grbl.configure(with: saved)
                status = "Added device \(saved.name)"
                showAddDevice = false
            }, onCancel: {
                if !grbl.isConnected { grbl.configure(with: activeMachine) }
                showAddDevice = false
            })
        }
        .onReceive(NotificationCenter.default.publisher(for: .addDevice)) { _ in showAddDevice = true }
        .onChange(of: profiles.selectedID) { _, newID in
            guard newID != activeMachine.id else { return }
            if grbl.isConnected { grbl.disconnect() }
            activeMachine = profiles.selected
            grbl.configure(with: activeMachine)
            status = activeMachine.autoDetect
                ? "Preset: \(activeMachine.name) · connect to detect settings"
                : "Preset: \(activeMachine.name)"
        }
        .onChange(of: grbl.detected) { _, detected in
            guard let detected else { return }
            activeMachine = detected.applied(to: profiles.selected)
            let size = "\(Int(activeMachine.workspaceWidth)) × \(Int(activeMachine.workspaceHeight)) mm"
            status = "Detected \(detected.firmware ?? "GRBL controller") · \(size) · S max \(activeMachine.sMax)"
        }
        .alert("Save machine preset", isPresented: $showSavePreset) {
            TextField("Preset name", text: $presetName)
            Button("Save") {
                let saved = profiles.save(activeMachine, named: presetName)
                activeMachine = saved
                status = "Saved preset \(saved.name)"
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Stores the current work area, speed limit, S max, laser mode and homing settings.")
        }
        .onReceive(NotificationCenter.default.publisher(for: .burnPreview)) { _ in openBurnPreview() }
        .onChange(of: grbl.isSendingJob) { _, sending in
            if !sending && !grbl.isJobPaused &&
                (status.hasPrefix("Sending job") || status.hasPrefix("Resuming job")) && grbl.lastError == nil {
                status = "Job complete"
            }
        }
        .onChange(of: grbl.isSendingManualCommand) { wasSending, isSending in
            if wasSending && !isSending {
                status = grbl.lastError == nil ? "Homing complete · workspace X0 Y0" : "Homing failed"
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "scope").font(.system(size: 19, weight: .semibold)).foregroundStyle(.orange)
                Text("LASERSTUDIO").font(.system(size: 12, weight: .bold, design: .rounded)).tracking(1.2)
            }
            Rectangle().fill(.white.opacity(0.12)).frame(width: 1, height: 23)
            Button(action: newProject) { Label("New", systemImage: "doc.badge.plus") }
                .keyboardShortcut("n", modifiers: .command)
                .hoverToolName("New Project (⌘N)", edge: .bottom) { hoveredToolLabel = $0 ? "New Project (⌘N)" : nil }
            Button(action: undo) { Label("Undo", systemImage: "arrow.uturn.backward") }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(undoStack.isEmpty && pendingUndoSnapshot == nil)
                .hoverToolName("Undo (⌘Z)", edge: .bottom) { hoveredToolLabel = $0 ? "Undo (⌘Z)" : nil }
            Button(action: redo) { Label("Redo", systemImage: "arrow.uturn.forward") }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(redoStack.isEmpty || pendingUndoSnapshot != nil)
                .hoverToolName("Redo (⇧⌘Z)", edge: .bottom) { hoveredToolLabel = $0 ? "Redo (⇧⌘Z)" : nil }
            Button {
                if grbl.moveToWorkspaceOrigin() { status = "Homing to workspace X0 Y0…" }
                else if !grbl.homingSettingLoaded { status = "Waiting for homing settings" }
                else { status = "Connect the laser and stop the current job before homing" }
            } label: { Label("Home", systemImage: "house") }
                .disabled(!grbl.isConnected || !grbl.homingSettingLoaded || grbl.hasActiveJob || grbl.isSendingManualCommand)
                .hoverToolName("Home Laser (X0 Y0)", edge: .bottom) { hoveredToolLabel = $0 ? "Home Laser (X0 Y0)" : nil }
            Button { addShape() } label: { Label("Shape", systemImage: "square.on.circle") }
                .hoverToolName("Add Shape to Workspace", edge: .bottom) { hoveredToolLabel = $0 ? "Add Shape to Workspace" : nil }
            Button(action: importArtwork) { Label("Import", systemImage: "square.and.arrow.down") }
                .hoverToolName("Import Artwork (SVG / PNG / JPG / BMP)", edge: .bottom) { hoveredToolLabel = $0 ? "Import Artwork (SVG / PNG / JPG / BMP)" : nil }
            Button(action: exportJob) { Label("Export", systemImage: "square.and.arrow.up") }
                .keyboardShortcut("e", modifiers: .command)
                .hoverToolName("Export G-code (⌘E)", edge: .bottom) { hoveredToolLabel = $0 ? "Export G-code (⌘E)" : nil }
            Button(action: openBurnPreview) { Label("Preview", systemImage: "flame") }
                .keyboardShortcut("b", modifiers: .command)
                .hoverToolName("Burn Preview (⌘B)", edge: .bottom) { hoveredToolLabel = $0 ? "Burn Preview (⌘B)" : nil }
            Spacer()
            HStack(spacing: 7) {
                Circle().fill(grbl.isConnected ? Color.green : Color.gray).frame(width: 7, height: 7)
                Text(grbl.isConnected ? "Machine connected" : "No machine connected").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                Button(grbl.isConnected ? "Disconnect" : grbl.isConnecting ? "Connecting…" : "Connect") {
                    if grbl.isConnected { grbl.disconnect(); status = "Machine disconnected" }
                    else { grbl.refreshPorts(); showDevicePicker = true }
                }
                    .disabled(grbl.isConnecting)
                    .buttonStyle(.bordered).controlSize(.small)
            }
        }
        .buttonStyle(.borderless).padding(.horizontal, 16).frame(height: 52)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .bottom) { Divider().opacity(0.35) }
    }

    private var toolRail: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 4) {
                toolButton("Select", help: "Select — Select, move, scale, and rotate objects (Left-drag: touched, Right-drag: enclosed)")
                toolButton("Position Laser", help: "Position Laser — Click anywhere on the workspace to jog the laser to that coordinate")
                Divider().padding(.vertical, 3).opacity(0.3)

                toolButton("Line", help: "Draw Lines — Click and drag to create vector lines")
                toolButton("Pen", help: "Draw Freehand / Spline — Sketch freehand vector paths")
                toolButton("Rectangle", help: "Draw Rectangle — Drag to create rectangles or squares")
                toolButton("Circle", help: "Draw Ellipse / Circle — Drag to create ellipses or circles")
                toolButton("Polygon", help: "Draw Regular Polygon — Drag to create multi-sided polygons (3–24 sides)")
                toolButton("Text", help: "Create / Edit Text — Click on the workspace to place vector text")
                Divider().padding(.vertical, 3).opacity(0.3)

                toolButton("Node edit", help: "Edit Nodes — Drag path vertices directly or click a shape to convert it to editable nodes")
                toolButton("Add Tabs", help: "Add Tabs / Bridges — Click a vector shape to add holding tabs along its cut path")
                toolButton("Measure", help: "Measure — Drag between two points to measure distance and ΔX / ΔY")
                toolButton("Radius", help: "Corner Radius / Fillet — Click a rectangle, polygon, or path to round its corners")
                Divider().padding(.vertical, 3).opacity(0.3)

                actionToolButton("Offset Shapes", help: "Offset Shapes — Create inward, outward, or dual offsets around selected shapes") {
                    let ids = selectedIDs.isEmpty ? Set(selection.map { [$0] } ?? []) : selectedIDs
                    guard objects.contains(where: { ids.contains($0.id) && $0.kind != .image }) else {
                        status = "Select at least one vector shape to offset"
                        return
                    }
                    showOffsetSheet = true
                }
                actionToolButton("Weld", help: "Boolean Weld — Fuse all selected overlapping shapes into their outer silhouette") {
                    triggerSidebarBoolean(.weld)
                }
                actionToolButton("Union", help: "Boolean Union — Combine two selected shapes into one") {
                    triggerSidebarBoolean(.union)
                }
                actionToolButton("Subtract", help: "Boolean Subtract (A - B) — Cut the second selected shape out of the first") {
                    triggerSidebarBoolean(.subtract)
                }
                actionToolButton("Intersect", help: "Boolean Intersection — Keep only the overlapping region of selected shapes") {
                    triggerSidebarBoolean(.intersect)
                }
                Divider().padding(.vertical, 3).opacity(0.3)

                actionToolButton("Grid Array", help: "Grid Array — Duplicate selected objects in a 2D row/column grid") {
                    guard selection != nil || !selectedIDs.isEmpty else {
                        status = "Select an object first to create a Grid Array"
                        return
                    }
                    showGridArraySheet = true
                }
                actionToolButton("Circular Array", help: "Circular Array — Duplicate selected objects radially around a center point") {
                    guard selection != nil || !selectedIDs.isEmpty else {
                        status = "Select an object first to create a Circular Array"
                        return
                    }
                    showCircularArraySheet = true
                }
                Divider().padding(.vertical, 3).opacity(0.3)

                toolButton("Camera", help: "Camera Alignment — Open overhead camera overlay")
            }
            .padding(.vertical, 8)
        }
        .frame(width: 50)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .trailing) { Divider().opacity(0.35) }
    }

    private func toolButton(_ name: String, help: String) -> some View {
        let shortLabel = help.components(separatedBy: " — ").first ?? name
        return Button {
            if name == "Camera" {
                showCameraPreview = true
                return
            }
            activeTool = name
            status = "\(name) tool active"
        } label: {
            LightBurnToolIcon(toolName: name, isSelected: activeTool == name)
                .frame(width: 34, height: 28)
                .background(activeTool == name ? Color.orange.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(activeTool == name ? Color.orange.opacity(0.75) : .clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .hoverToolName(shortLabel, edge: .trailing) { hovering in
            hoveredToolLabel = hovering ? help : nil
        }
    }

    private func actionToolButton(_ name: String, help: String, action: @escaping () -> Void) -> some View {
        let shortLabel = help.components(separatedBy: " — ").first ?? name
        return Button(action: action) {
            LightBurnToolIcon(toolName: name, isSelected: false)
                .frame(width: 34, height: 28)
                .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .hoverToolName(shortLabel, edge: .trailing) { hovering in
            hoveredToolLabel = hovering ? help : nil
        }
    }

    private func triggerSidebarBoolean(_ op: BooleanOperationKind) {
        let ids = selectedIDs.isEmpty ? Set(selection.map { [$0] } ?? []) : selectedIDs
        let selected = objects.filter { ids.contains($0.id) && $0.kind != .image }
        guard selected.count >= 2,
              let result = ShapeGeometry.booleanOperation(op, objects: selected, workspace: activeMachine.workspace) else {
            status = "Select at least 2 overlapping vector shapes for Boolean \(op.rawValue)"
            return
        }
        let removeIDs = Set(selected.map(\.id))
        objects.removeAll { removeIDs.contains($0.id) }
        objects.append(result)
        selection = result.id
        selectedIDs = [result.id]
        status = "Applied Boolean \(op.rawValue)"
    }

    private var workspace: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Label(projectName, systemImage: "square.dashed").font(.system(size: 11, weight: .medium))
                Text("·  \(hoveredToolLabel ?? "Tool: \(activeTool)")")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                Spacer()
                Button { showGrid.toggle() } label: { Image(systemName: showGrid ? "grid" : "grid.circle") }
                    .hoverToolName(showGrid ? "Hide Grid" : "Show Grid", edge: .bottom) { hoveredToolLabel = $0 ? (showGrid ? "Hide Grid" : "Show Grid") : nil }
                Button { zoom = max(0.05, zoom / 1.25) } label: { Image(systemName: "minus.magnifyingglass") }
                    .keyboardShortcut("-", modifiers: .command)
                    .hoverToolName("Zoom Out (⌘-)", edge: .bottom) { hoveredToolLabel = $0 ? "Zoom Out (⌘-)" : nil }
                Text("\((zoom * 100).formatted(.number.precision(.fractionLength(0))))%")
                    .font(.system(size: 10, design: .monospaced))
                    .frame(minWidth: 48)
                Button { zoom = zoom * 1.25 } label: { Image(systemName: "plus.magnifyingglass") }
                    .keyboardShortcut("=", modifiers: .command)
                    .hoverToolName("Zoom In (⌘+)", edge: .bottom) { hoveredToolLabel = $0 ? "Zoom In (⌘+)" : nil }
                Button {
                    zoom = 1
                    panOffset = .zero
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .keyboardShortcut("0", modifiers: .command)
                .hoverToolName("Zoom to Page (⌘0)", edge: .bottom) { hoveredToolLabel = $0 ? "Zoom to Page (⌘0)" : nil }
            }
            .buttonStyle(.plain).foregroundStyle(.secondary).padding(.horizontal, 15).frame(height: 39)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.7))

            if let textObj = selectedObject, textObj.kind == .text {
                textFormattingToolbar(for: textObj)
            }

            CanvasArea(
                objects: $objects,
                selection: $selection,
                selectedIDs: $selectedIDs,
                showGrid: showGrid,
                workspace: activeMachine.workspace,
                zoom: $zoom,
                panOffset: $panOffset,
                activeTool: $activeTool,
                status: $status,
                activeLayerColor: activeSwatch.color,
                activeIsToolLayer: activeIsToolLayer,
                onUndo: undo,
                onRedo: redo,
                onOpenCutSettings: { id in cutSettingsLayerID = id },
                onPositionLaser: { pt in
                    let grblY = max(0, activeMachine.workspaceHeight - pt.y)
                    if grbl.isConnected && !grbl.hasActiveJob {
                        grbl.sendJob([String(format: "G0 X%.2f Y%.2f", pt.x, grblY)])
                    }
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(red: 0.105, green: 0.12, blue: 0.14))

            LightBurnColorPaletteBar(
                activeLayerIndex: activeLayerIndex,
                activeIsTool: activeIsToolLayer,
                usedLayerIndices: usedLayerIndices,
                onSelectSwatch: { swatch in
                    activeLayerIndex = swatch.index
                    activeIsToolLayer = swatch.isToolLayer
                    let ids = selectedIDs.isEmpty ? Set(selection.map { [$0] } ?? []) : selectedIDs
                    if !ids.isEmpty {
                        for idx in objects.indices where ids.contains(objects[idx].id) {
                            objects[idx].color = swatch.color
                            objects[idx].isToolLayer = swatch.isToolLayer
                        }
                        status = "Assigned selection to layer \(swatch.code) (\(swatch.name))"
                    } else {
                        status = "Active layer set to \(swatch.code) (\(swatch.name))"
                    }
                }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func textFormattingToolbar(for textObj: DesignObject) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "textformat")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.orange)
            TextField("Text", text: selectedTextBinding)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))
                .frame(minWidth: 120, maxWidth: 210)
                .focused($textInputFocused)
                .onSubmit { textInputFocused = false }
            Divider().frame(height: 18).opacity(0.35)
            Picker("Font", selection: fontFamilyBinding(for: textObj.id)) {
                ForEach(SystemFontCatalog.families, id: \.self) { family in
                    Text(family).tag(family)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
            .frame(width: 150)
            .hoverToolName("Font Family", edge: .bottom) { hoveredToolLabel = $0 ? "Font Family" : nil }

            Divider().frame(height: 18).opacity(0.35)

            HStack(spacing: 5) {
                fontModifierButton(
                    icon: "bold",
                    title: "Bold (⌘B)",
                    isActive: textObj.fontBold
                ) {
                    if let idx = objects.firstIndex(where: { $0.id == textObj.id }) {
                        objects[idx].fontBold.toggle()
                        status = objects[idx].fontBold ? "Enabled Bold" : "Disabled Bold"
                    }
                }
                fontModifierButton(
                    icon: "italic",
                    title: "Italic (⌘I)",
                    isActive: textObj.fontItalic
                ) {
                    if let idx = objects.firstIndex(where: { $0.id == textObj.id }) {
                        objects[idx].fontItalic.toggle()
                        status = objects[idx].fontItalic ? "Enabled Italic" : "Disabled Italic"
                    }
                }
                fontModifierButton(
                    icon: "underline",
                    title: "Underline (⌘U)",
                    isActive: textObj.fontUnderline
                ) {
                    if let idx = objects.firstIndex(where: { $0.id == textObj.id }) {
                        objects[idx].fontUnderline.toggle()
                        status = objects[idx].fontUnderline ? "Enabled Underline" : "Disabled Underline"
                    }
                }
                fontModifierButton(
                    icon: "strikethrough",
                    title: "Strikethrough",
                    isActive: textObj.fontStrikethrough
                ) {
                    if let idx = objects.firstIndex(where: { $0.id == textObj.id }) {
                        objects[idx].fontStrikethrough.toggle()
                        status = objects[idx].fontStrikethrough ? "Enabled Strikethrough" : "Disabled Strikethrough"
                    }
                }
                fontModifierButton(
                    icon: "textformat.abc",
                    title: "All Caps (Uppercase)",
                    isActive: textObj.fontUppercase
                ) {
                    if let idx = objects.firstIndex(where: { $0.id == textObj.id }) {
                        objects[idx].fontUppercase.toggle()
                        status = objects[idx].fontUppercase ? "Enabled All Caps" : "Disabled All Caps"
                    }
                }
            }

            Divider().frame(height: 18).opacity(0.35)

            HStack(spacing: 4) {
                Text("H")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                TextField("", value: selectedBinding(\DesignObject.height, fallback: 28), format: .number.precision(.fractionLength(1)))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 10, design: .monospaced))
                    .frame(width: 48)
                Text("mm")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            .hoverToolName("Text Height (mm)", edge: .bottom) { hoveredToolLabel = $0 ? "Text Height (mm)" : nil }

            Spacer()

            Button {
                if let idx = objects.firstIndex(where: { $0.id == textObj.id }) {
                    objects[idx] = ShapeGeometry.convertToPath(objects[idx])
                    status = "Converted text to editable vector path"
                }
            } label: {
                Label("Convert to Path", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                    .font(.system(size: 10, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .hoverToolName("Convert Text to Vector Path (⌘P)", edge: .bottom) { hoveredToolLabel = $0 ? "Convert Text to Vector Path (⌘P)" : nil }
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.92))
        .overlay(alignment: .top) { Divider().opacity(0.25) }
        .overlay(alignment: .bottom) { Divider().opacity(0.35) }
    }

    private func fontModifierButton(icon: String, title: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isActive ? Color.orange : Color.primary.opacity(0.85))
                .frame(width: 26, height: 24)
                .background(isActive ? Color.orange.opacity(0.22) : Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 5))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(isActive ? Color.orange : Color.white.opacity(0.15), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .hoverToolName(title, edge: .bottom) { hoveredToolLabel = $0 ? title : nil }
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("JOB SETUP").font(.system(size: 10, weight: .bold)).tracking(1).foregroundStyle(.secondary)
                Spacer(); Image(systemName: "slider.horizontal.3").foregroundStyle(.secondary)
            }.padding(.horizontal, 16).frame(height: 42)
            Divider().opacity(0.3)
            ScrollView {
                VStack(alignment: .leading, spacing: 19) {
                    group("DEVICE") {
                        Picker("Machine preset", selection: $profiles.selectedID) {
                            ForEach(profiles.all) { profile in Text(profile.name).tag(profile.id) }
                        }.labelsHidden().pickerStyle(.menu).font(.system(size: 11))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(grbl.connectedPort ?? "GRBL · USB · Not connected").font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                            if grbl.isDetecting {
                                Text("Detecting controller settings…").font(.system(size: 9)).foregroundStyle(.orange)
                            } else if grbl.isConnected {
                                Text("S max \(grbl.sMax) · Laser mode \(grbl.laserModeEnabled == true ? "on" : grbl.laserModeEnabled == false ? "off" : "checking…")")
                                    .font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                            }
                            if let firmware = grbl.detected?.firmware {
                                Text(firmware).font(.system(size: 9)).foregroundStyle(.tertiary).lineLimit(1)
                            }
                        }
                        HStack { Text("Workspace").foregroundStyle(.secondary); Spacer(); Text("\(Int(activeMachine.workspaceWidth)) × \(Int(activeMachine.workspaceHeight)) mm") }
                        HStack { Text("Max speed").foregroundStyle(.secondary); Spacer(); Text("\(Int(activeMachine.maxFeedRate)) mm/min") }
                        Button { showAddDevice = true } label: { Label("Add Device…", systemImage: "plus.circle").font(.system(size: 10)) }
                            .buttonStyle(.borderless).foregroundStyle(.orange)
                            .help("Detect a connected GRBL laser and edit its controller settings")
                        HStack {
                            Button {
                                presetName = activeMachine.isBuiltIn ? "" : activeMachine.name
                                showSavePreset = true
                            } label: { Label("Save as preset…", systemImage: "square.and.arrow.down.on.square").font(.system(size: 10)) }
                                .help("Save the current machine settings as a reusable preset")
                            Spacer()
                            if !profiles.selected.isBuiltIn {
                                Button { profiles.delete(profiles.selected) } label: { Image(systemName: "trash").font(.system(size: 10)) }
                                    .help("Delete this preset")
                            }
                        }.buttonStyle(.borderless).foregroundStyle(.secondary)
                    }
                    group("MATERIAL") {
                        Picker("Preset", selection: $material) { Text("3 mm birch plywood").tag("3 mm birch plywood"); Text("3 mm acrylic").tag("3 mm acrylic"); Text("6 mm MDF").tag("6 mm MDF"); Text("Custom material").tag("Custom material") }.labelsHidden().pickerStyle(.menu).font(.system(size: 11))
                        HStack { Label("Hatch spacing", systemImage: "arrow.left.and.right").font(.system(size: 10)).foregroundStyle(.secondary); Spacer(); TextField("", value: $hatchSpacing, format: .number.precision(.fractionLength(2))).frame(width: 52).textFieldStyle(.roundedBorder); Text("mm").font(.system(size: 9)).foregroundStyle(.tertiary) }
                    }
                    group("LAYERS · \(objects.count)") {
                        ForEach(objects) { object in
                            objectRow(object)
                        }
                        HStack {
                            Button { addShape() } label: { Label("Add", systemImage: "plus").font(.system(size: 10)) }
                                .hoverToolName("Add Shape Layer", edge: .leading)
                            Spacer()
                            Button {
                                let ids = selectedIDs.isEmpty ? (selection.map { Set([$0]) } ?? []) : selectedIDs
                                objects.removeAll { ids.contains($0.id) }
                                selection = objects.first?.id
                                selectedIDs = selection.map { Set([$0]) } ?? []
                            } label: { Image(systemName: "trash").font(.system(size: 10)) }
                                .disabled(selection == nil && selectedIDs.isEmpty)
                                .hoverToolName(selectedIDs.count > 1 ? "Delete Selected Layers" : "Delete Selected Layer", edge: .leading)
                        }.buttonStyle(.borderless).foregroundStyle(.secondary)
                    }
                    if let sel = selectedObject {
                        group("SHAPE & LAYER PROPERTIES") {
                            if sel.kind == .text {
                                TextField("Text", text: selectedTextBinding)
                                    .textFieldStyle(.roundedBorder)
                                    .focused($textInputFocused)
                                    .onSubmit { textInputFocused = false }
                            }
                            coordinateRow("X", value: \DesignObject.x, unit: "mm")
                            coordinateRow("Y", value: \DesignObject.y, unit: "mm")
                            coordinateRow("W", value: \DesignObject.width, unit: "mm")
                            coordinateRow("H", value: \DesignObject.height, unit: "mm")
                            coordinateRow("Rot", value: \DesignObject.rotation, unit: "°")

                            if sel.kind == .rectangle || sel.kind == .polygon {
                                HStack(spacing: 7) {
                                    Text("Corner R").font(.system(size: 10)).foregroundStyle(.secondary)
                                    Spacer()
                                    TextField("", value: selectedBinding(\DesignObject.cornerRadius, fallback: 0), format: .number.precision(.fractionLength(1)))
                                        .textFieldStyle(.roundedBorder).frame(width: 58).font(.system(size: 10, design: .monospaced))
                                    Text("mm").font(.system(size: 9)).foregroundStyle(.tertiary)
                                }
                            }
                            if sel.kind == .polygon {
                                HStack(spacing: 7) {
                                    Text("Sides").font(.system(size: 10)).foregroundStyle(.secondary)
                                    Spacer()
                                    Stepper("\(sel.polygonSides)", value: Binding(
                                        get: { selectedObject?.polygonSides ?? 6 },
                                        set: { v in if let idx = selectedIndex { objects[idx].polygonSides = max(3, min(24, v)) } }
                                    ), in: 3...24)
                                    .font(.system(size: 10, design: .monospaced))
                                }
                            }

                            Toggle("Lock Shape Position & Size", isOn: Binding(
                                get: { selectedObject?.isLocked ?? false },
                                set: { v in if let idx = selectedIndex { objects[idx].isLocked = v } }
                            ))
                            .toggleStyle(.checkbox)

                            Divider().opacity(0.3)

                            HStack(spacing: 6) {
                                Button("Cut Settings…") {
                                    cutSettingsLayerID = sel.id
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                Spacer()
                                if sel.kind == .image {
                                    Button("Trace…") {
                                        traceImageObject = sel
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    Button("Adjust…") {
                                        adjustImageLayerID = sel.id
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.orange)
                                    .controlSize(.small)
                                } else {
                                    Button("To Path") {
                                        if let idx = selectedIndex {
                                            objects[idx] = ShapeGeometry.convertToPath(objects[idx])
                                            status = "Converted \(objects[idx].label) to editable path"
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                        }
                    }
                }.padding(14)
            }
            Divider().opacity(0.3)
            HStack(spacing: 7) {
                Button(action: toggleJob) {
                    HStack { Image(systemName: grbl.isSendingJob ? "pause.fill" : "play.fill"); Text(jobButtonTitle).fontWeight(.semibold); Spacer(); Text("⇧⌘↩").font(.system(size: 9, design: .monospaced)).opacity(0.7) }
                        .font(.system(size: 11)).foregroundStyle(.white).padding(.horizontal, 13).frame(height: 38)
                        .background(grbl.isSendingJob ? Color.orange : Color.green, in: RoundedRectangle(cornerRadius: 7))
                }.buttonStyle(.plain).keyboardShortcut(.return, modifiers: [.command, .shift])
                if grbl.hasActiveJob {
                    Button(action: cancelJob) {
                        Image(systemName: "stop.fill").font(.system(size: 11)).foregroundStyle(.white)
                            .frame(width: 36, height: 38).background(Color.red, in: RoundedRectangle(cornerRadius: 7))
                    }.buttonStyle(.plain).help("Cancel job and clear the queued moves")
                }
            }.padding(12)
        }
        .frame(width: 280).background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        .overlay(alignment: .leading) { Divider().opacity(0.35) }
    }

    private var footer: some View {
        HStack(spacing: 13) {
            Circle().fill(status == "Ready" ? Color.green : Color.orange).frame(width: 6, height: 6)
            Text(grbl.lastError.map { "\(status) · \($0)" } ?? status).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            if let position = grbl.workspacePosition {
                Text(String(format: "X  %.1f mm", position.x)).foregroundStyle(.tertiary)
                Text(String(format: "Y  %.1f mm", position.y)).foregroundStyle(.tertiary)
            } else {
                Text("X  -- mm").foregroundStyle(.tertiary)
                Text("Y  -- mm").foregroundStyle(.tertiary)
            }
            Divider().frame(height: 12)
            Text("\(objects.filter(\.burnEnabled).count) burn / \(objects.count) layers").foregroundStyle(.secondary)
        }.font(.system(size: 9, design: .monospaced)).padding(.horizontal, 15).frame(height: 26)
            .background(Color(nsColor: .controlBackgroundColor)).overlay(alignment: .top) { Divider().opacity(0.35) }
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.system(size: 9, weight: .bold)).tracking(0.8).foregroundStyle(.secondary)
            content().font(.system(size: 10))
        }
    }
    private func objectRow(_ object: DesignObject) -> some View {
        let isSelected = selectedIDs.contains(object.id) || selection == object.id
        let swatch = LightBurnPalette.closestSwatch(for: object.color, isToolLayer: object.isToolLayer)
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Button { selectLayer(object.id) } label: {
                    HStack(spacing: 6) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 3).fill(object.color).frame(width: 19, height: 19)
                            Text(swatch.code)
                                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.85), radius: 1, x: 0, y: 0.5)
                        }
                        Image(systemName: icon(for: object.kind)).frame(width: 14).foregroundStyle(Color.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(object.label).font(.system(size: 10, weight: .medium)).lineLimit(1)
                            Text(object.isToolLayer
                                 ? "Tool Layer · Frame Only"
                                 : (object.kind == .image
                                    ? "Image · \(object.imageDitherMode.rawValue) · \(Int(object.imageDPI)) DPI"
                                    : "\(object.layerMode.rawValue) · \(Int(object.speed)) mm/m · \(Int(object.power))% · \(object.passCount)P"))
                                .font(.system(size: 8.5, design: .monospaced)).foregroundStyle(Color.secondary).lineLimit(1)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer(minLength: 2)
                Button { cutSettingsLayerID = object.id } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.orange)
                        .frame(width: 18, height: 20)
                }
                .buttonStyle(.plain)
                .hoverToolName("Cut Settings Editor", edge: .leading)
                Button { toggleLayerVisibility(object.id) } label: {
                    Image(systemName: object.isVisible ? "eye" : "eye.slash")
                        .font(.system(size: 10.5))
                        .foregroundStyle(object.isVisible ? Color.secondary : Color.orange)
                        .frame(width: 18, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverToolName(object.isVisible ? "Hide Layer" : "Show Layer", edge: .leading)
                Toggle("Output", isOn: burnBinding(for: object.id))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .disabled(object.isToolLayer)
                    .help(object.isToolLayer ? "Tool layers are not output to laser" : (object.burnEnabled ? "Output enabled" : "Output disabled"))
            }
            if object.kind == .text {
                HStack(spacing: 4) {
                    Text("Font").frame(width: 28, alignment: .leading)
                    Picker("Text font", selection: fontFamilyBinding(for: object.id)) {
                        ForEach(SystemFontCatalog.families, id: \.self) { family in
                            Text(family).tag(family)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    .help("Choose an installed font family for this text layer")
                    Button { if let index = objects.firstIndex(where: { $0.id == object.id }) { objects[index].fontBold.toggle() } } label: {
                        Image(systemName: "bold").font(.system(size: 10, weight: .bold)).frame(width: 20, height: 20)
                            .background(object.fontBold ? Color.orange.opacity(0.24) : Color.clear, in: RoundedRectangle(cornerRadius: 4))
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(object.fontBold ? Color.orange : Color.white.opacity(0.15), lineWidth: 1))
                    }
                    .buttonStyle(.plain).foregroundStyle(object.fontBold ? Color.orange : Color.secondary)
                    .hoverToolName(object.fontBold ? "Disable Bold" : "Enable Bold", edge: .leading)
                    Button { if let index = objects.firstIndex(where: { $0.id == object.id }) { objects[index].fontItalic.toggle() } } label: {
                        Image(systemName: "italic").font(.system(size: 10, weight: .bold)).frame(width: 20, height: 20)
                            .background(object.fontItalic ? Color.orange.opacity(0.24) : Color.clear, in: RoundedRectangle(cornerRadius: 4))
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(object.fontItalic ? Color.orange : Color.white.opacity(0.15), lineWidth: 1))
                    }
                    .buttonStyle(.plain).foregroundStyle(object.fontItalic ? Color.orange : Color.secondary)
                    .hoverToolName(object.fontItalic ? "Disable Italic" : "Enable Italic", edge: .leading)
                    Button { if let index = objects.firstIndex(where: { $0.id == object.id }) { objects[index].fontUnderline.toggle() } } label: {
                        Image(systemName: "underline").font(.system(size: 10, weight: .bold)).frame(width: 20, height: 20)
                            .background(object.fontUnderline ? Color.orange.opacity(0.24) : Color.clear, in: RoundedRectangle(cornerRadius: 4))
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(object.fontUnderline ? Color.orange : Color.white.opacity(0.15), lineWidth: 1))
                    }
                    .buttonStyle(.plain).foregroundStyle(object.fontUnderline ? Color.orange : Color.secondary)
                    .hoverToolName(object.fontUnderline ? "Disable Underline" : "Enable Underline", edge: .leading)
                    Button { if let index = objects.firstIndex(where: { $0.id == object.id }) { objects[index].fontStrikethrough.toggle() } } label: {
                        Image(systemName: "strikethrough").font(.system(size: 10, weight: .bold)).frame(width: 20, height: 20)
                            .background(object.fontStrikethrough ? Color.orange.opacity(0.24) : Color.clear, in: RoundedRectangle(cornerRadius: 4))
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(object.fontStrikethrough ? Color.orange : Color.white.opacity(0.15), lineWidth: 1))
                    }
                    .buttonStyle(.plain).foregroundStyle(object.fontStrikethrough ? Color.orange : Color.secondary)
                    .hoverToolName(object.fontStrikethrough ? "Disable Strikethrough" : "Enable Strikethrough", edge: .leading)
                }
            }
            if object.kind != .image && !object.isToolLayer {
                Picker("Layer cut mode", selection: layerModeBinding(for: object.id)) {
                    ForEach(EngravingMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.small)
            }
            if !object.isToolLayer {
                HStack(spacing: 5) {
                    Text("Max P").frame(width: 36, alignment: .leading)
                    Slider(value: layerPowerBinding(for: object.id), in: 1...100).tint(.orange)
                    Text("\(Int(object.power))%").font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary).frame(width: 32, alignment: .trailing)
                }
            }
            if object.kind == .image {
                HStack(spacing: 5) {
                    Text("Mode").frame(width: 36, alignment: .leading)
                    Picker("", selection: Binding(
                        get: { objects.first(where: { $0.id == object.id })?.imageDitherMode ?? .jarvis },
                        set: { v in if let idx = objects.firstIndex(where: { $0.id == object.id }) { objects[idx].imageDitherMode = v } }
                    )) {
                        ForEach(ImageDitherMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .controlSize(.small)
                    Text("DPI")
                    TextField("", value: Binding(
                        get: { objects.first(where: { $0.id == object.id })?.imageDPI ?? 254 },
                        set: { v in if let idx = objects.firstIndex(where: { $0.id == object.id }) { objects[idx].imageDPI = max(25.4, min(1270, v)) } }
                    ), format: .number.precision(.fractionLength(0)))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 44)
                }
                HStack(spacing: 8) {
                    Toggle("Negative", isOn: imageInvertedBinding(for: object.id))
                        .toggleStyle(.checkbox)
                        .font(.system(size: 9))
                    Toggle("Pass-Through", isOn: Binding(
                        get: { objects.first(where: { $0.id == object.id })?.imagePassThrough ?? false },
                        set: { v in if let idx = objects.firstIndex(where: { $0.id == object.id }) { objects[idx].imagePassThrough = v } }
                    ))
                    .toggleStyle(.checkbox)
                    .font(.system(size: 9))
                }
                HStack(spacing: 5) {
                    Text("Min").frame(width: 34, alignment: .leading)
                    Slider(value: imageMinimumSpeedBinding(for: object.id), in: 40...activeMachine.maxFeedRate).tint(.orange)
                    Text("\(Int(object.minimumSpeed))").font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(.secondary).frame(width: 40, alignment: .trailing)
                }
                HStack(spacing: 5) {
                    Text("Max").frame(width: 34, alignment: .leading)
                    Slider(value: imageMaximumSpeedBinding(for: object.id), in: 40...activeMachine.maxFeedRate).tint(.orange)
                    Text("\(Int(object.maximumSpeed))").font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(.secondary).frame(width: 40, alignment: .trailing)
                }
                HStack(spacing: 6) {
                    Toggle("Var. Power", isOn: imageVariablePowerBinding(for: object.id))
                        .toggleStyle(.checkbox)
                        .font(.system(size: 9))
                    Spacer()
                    Button("Trace…") { traceImageObject = object }
                        .buttonStyle(.bordered).controlSize(.mini)
                    Button("Adjust…") { adjustImageLayerID = object.id }
                        .buttonStyle(.bordered).controlSize(.mini)
                }
            } else if !object.isToolLayer {
                HStack(spacing: 5) {
                    Text("Speed").frame(width: 36, alignment: .leading)
                    Slider(value: layerSpeedBinding(for: object.id), in: 40...activeMachine.maxFeedRate).tint(.orange)
                    Text("\(Int(object.speed)) mm/m").font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(.secondary).frame(width: 55, alignment: .trailing)
                }
                HStack(spacing: 8) {
                    Stepper("Passes: \(object.passCount)", value: Binding(
                        get: { objects.first(where: { $0.id == object.id })?.passCount ?? 1 },
                        set: { v in if let idx = objects.firstIndex(where: { $0.id == object.id }) { objects[idx].passCount = max(1, min(50, v)) } }
                    ), in: 1...50)
                    .font(.system(size: 9))
                    Spacer()
                    Toggle("Air", isOn: Binding(
                        get: { objects.first(where: { $0.id == object.id })?.airAssist ?? true },
                        set: { v in if let idx = objects.firstIndex(where: { $0.id == object.id }) { objects[idx].airAssist = v } }
                    ))
                    .toggleStyle(.checkbox)
                    .font(.system(size: 9))
                    .help("Enable Air Assist (M8)")
                }
            }
        }
        .padding(7)
        .background(isSelected ? Color.white.opacity(0.06) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
    }
    private func burnBinding(for id: UUID) -> Binding<Bool> {
        Binding(get: { objects.first(where: { $0.id == id })?.burnEnabled ?? false }, set: { value in
            if let index = objects.firstIndex(where: { $0.id == id }) { objects[index].burnEnabled = value }
        })
    }
    private func selectLayer(_ id: UUID) {
        selection = id
        if let groupID = objects.first(where: { $0.id == id })?.groupID {
            selectedIDs = Set(objects.filter { $0.groupID == groupID }.map(\.id))
        } else {
            selectedIDs = [id]
        }
    }
    private func toggleLayerVisibility(_ id: UUID) {
        guard let index = objects.firstIndex(where: { $0.id == id }) else { return }
        objects[index].isVisible.toggle()
        status = objects[index].isVisible ? "Layer shown on canvas" : "Layer hidden on canvas"
    }
    private func layerModeBinding(for id: UUID) -> Binding<EngravingMode> {
        Binding(get: { objects.first(where: { $0.id == id })?.layerMode ?? .line }, set: { value in
            if let index = objects.firstIndex(where: { $0.id == id }) { objects[index].layerMode = value }
        })
    }
    private func fontFamilyBinding(for id: UUID) -> Binding<String> {
        Binding(get: { objects.first(where: { $0.id == id })?.fontFamily ?? "Helvetica" }, set: { value in
            if let index = objects.firstIndex(where: { $0.id == id }) { objects[index].fontFamily = value }
        })
    }
    private func layerPowerBinding(for id: UUID) -> Binding<Double> {
        Binding(get: { objects.first(where: { $0.id == id })?.power ?? 1 }, set: { value in
            if let index = objects.firstIndex(where: { $0.id == id }) { objects[index].power = min(100, max(1, value)) }
        })
    }
    private func layerSpeedBinding(for id: UUID) -> Binding<Double> {
        Binding(get: { objects.first(where: { $0.id == id })?.speed ?? 40 }, set: { value in
            if let index = objects.firstIndex(where: { $0.id == id }) {
                objects[index].speed = min(activeMachine.maxFeedRate, max(40, value))
            }
        })
    }
    private func imageMinimumSpeedBinding(for id: UUID) -> Binding<Double> {
        Binding(get: { objects.first(where: { $0.id == id })?.minimumSpeed ?? 40 }, set: { value in
            guard let index = objects.firstIndex(where: { $0.id == id }) else { return }
            objects[index].minimumSpeed = min(objects[index].maximumSpeed, max(40, value))
        })
    }
    private func imageMaximumSpeedBinding(for id: UUID) -> Binding<Double> {
        Binding(get: { objects.first(where: { $0.id == id })?.maximumSpeed ?? 40 }, set: { value in
            guard let index = objects.firstIndex(where: { $0.id == id }) else { return }
            objects[index].maximumSpeed = min(activeMachine.maxFeedRate, max(objects[index].minimumSpeed, value))
        })
    }
    private func imageVariablePowerBinding(for id: UUID) -> Binding<Bool> {
        Binding(get: { objects.first(where: { $0.id == id })?.variablePower ?? true }, set: { value in
            if let index = objects.firstIndex(where: { $0.id == id }) { objects[index].variablePower = value }
        })
    }
    private func imageInvertedBinding(for id: UUID) -> Binding<Bool> {
        Binding(get: { objects.first(where: { $0.id == id })?.imageInverted ?? false }, set: { value in
            if let index = objects.firstIndex(where: { $0.id == id }) { objects[index].imageInverted = value }
        })
    }
    private func coordinateRow(_ title: String, value: WritableKeyPath<DesignObject, Double>, unit: String) -> some View {
        HStack(spacing: 7) {
            Text(title).font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(.secondary).frame(width: 18, alignment: .leading)
            TextField("", value: selectedBinding(value, fallback: 0), format: .number.precision(.fractionLength(1))).textFieldStyle(.roundedBorder).font(.system(size: 10, design: .monospaced))
            Text(unit).font(.system(size: 9)).foregroundStyle(.tertiary).frame(width: 18, alignment: .leading)
        }
    }
    private func selectedBinding(_ keyPath: WritableKeyPath<DesignObject, Double>, fallback: Double) -> Binding<Double> {
        Binding(get: { selectedObject?[keyPath: keyPath] ?? fallback }, set: { value in if let index = selectedIndex { objects[index][keyPath: keyPath] = value } })
    }
    private var selectedTextBinding: Binding<String> {
        Binding(get: { selectedObject?.label ?? "" }, set: { value in
            if let index = selectedIndex { objects[index].label = value }
        })
    }
    private func colorSwatch(_ color: Color) -> some View {
        Button { if let index = selectedIndex { objects[index].color = color } } label: { Circle().fill(color).frame(width: 12, height: 12).overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1)) }.buttonStyle(.plain)
    }
    private func icon(for kind: DesignObject.Kind) -> String {
        switch kind {
        case .rectangle: "rectangle"
        case .circle: "circle"
        case .polygon: "hexagon"
        case .text: "textformat"
        case .line: "line.diagonal"
        case .path: "scribble"
        case .image: "photo"
        }
    }
    private var devicePicker: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Connect Laser").font(.headline)
                    Text("Select the USB serial port running GRBL at 115200 baud.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { grbl.refreshPorts() } label: { Image(systemName: "arrow.clockwise") }.help("Refresh ports")
            }
            if grbl.ports.isEmpty {
                ContentUnavailableView("No USB serial ports found", systemImage: "cable.connector.horizontal", description: Text("Connect and power on your Ray5, then refresh the port list."))
                    .frame(height: 170)
            } else {
                List(grbl.ports, id: \.self) { port in
                    HStack {
                        Image(systemName: "cable.connector.horizontal").foregroundStyle(.orange)
                        Text(port).font(.system(.body, design: .monospaced))
                        Spacer()
                        Button("Connect") {
                            grbl.connect(to: port) { result in
                                switch result {
                                case .success: status = "Connected to GRBL · \(port)"; showDevicePicker = false
                                case .failure: status = "Connection failed"
                                }
                            }
                            status = "Checking GRBL controller…"
                        }.disabled(grbl.isConnecting)
                    }.padding(.vertical, 3)
                }.listStyle(.inset)
            }
            HStack { Spacer(); Button("Cancel") { showDevicePicker = false }.keyboardShortcut(.escape) }
        }
        .padding(20).frame(width: 460, height: 330)
        .onAppear { grbl.refreshPorts() }
    }
    private func addShape() {
        activeTool = "Rectangle"
        status = "Drag on the workspace to draw a rectangle"
    }
    private func commitPendingHistory() {
        guard let snapshot = pendingUndoSnapshot else { return }
        undoStack.append(snapshot)
        if undoStack.count > 100 { undoStack.removeFirst(undoStack.count - 100) }
        pendingUndoSnapshot = nil
        redoStack.removeAll()
        historyWorkItem = nil
    }
    private func undo() {
        historyWorkItem?.cancel()
        commitPendingHistory()
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(objects)
        applyingHistory = true
        objects = previous
        let valid = Set(previous.map(\.id))
        selectedIDs.formIntersection(valid)
        if let selection, !valid.contains(selection) { self.selection = selectedIDs.first ?? previous.first?.id }
        status = "Undo"
    }
    private func redo() {
        guard pendingUndoSnapshot == nil, let next = redoStack.popLast() else { return }
        undoStack.append(objects)
        applyingHistory = true
        objects = next
        let valid = Set(next.map(\.id))
        selectedIDs.formIntersection(valid)
        if let selection, !valid.contains(selection) { self.selection = selectedIDs.first ?? next.first?.id }
        status = "Redo"
    }
    private func newProject() { objects.removeAll(); selection = nil; selectedIDs = []; projectName = "Untitled project"; status = "New project created" }
    private func importArtwork() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.svg, .png, .jpeg, .bmp, .tiff, .gif, .webP]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let imported: [DesignObject]
                if url.pathExtension.lowercased() == "svg" {
                    imported = try SVGImporter.load(url, workspace: activeMachine.workspace)
                } else {
                    let imgObj = try ImageImporter.load(url, workspace: activeMachine.workspace)
                    imported = [imgObj]
                }
                objects.append(contentsOf: imported)
                selection = imported.first?.id
                selectedIDs = Set(imported.map(\.id))
                if let first = imported.first, first.kind == .image {
                    status = String(format: "Imported image %@ (%.1f × %.1f mm @ %.0f DPI · %@)",
                                    url.lastPathComponent, first.width, first.height, first.imageDPI, first.imageDitherMode.rawValue)
                } else {
                    status = "Imported \(imported.count) vector path\(imported.count == 1 ? "" : "s") from \(url.lastPathComponent)"
                }
            } catch { status = "Import failed: \(error.localizedDescription)" }
        }
    }
    private func openBurnPreview() {
        do {
            previewGCode = try makeGCode(requireLaserMode: false)
            showBurnPreview = true
        } catch { status = "Cannot preview: \(error.localizedDescription)" }
    }
    private func exportJob() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "laser-job.gcode"; panel.allowedContentTypes = [.plainText]
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let lines = try makeGCode(requireLaserMode: false)
                try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
                status = "Exported \(url.lastPathComponent)"
            } catch { status = "Export failed: \(error.localizedDescription)" }
        }
    }
    private var jobButtonTitle: String {
        if grbl.isSendingJob { return "Pause job" }
        if grbl.isJobPaused { return "Resume job" }
        return "Start job"
    }
    private func toggleJob() {
        if grbl.isSendingJob { grbl.pauseJob(); status = "Job paused · click Resume job to continue"; return }
        if grbl.isJobPaused { grbl.resumeJob(); status = "Resuming job"; return }
        guard grbl.isConnected else { status = "Connect the laser before starting a job"; return }
        guard !objects.isEmpty else { status = "Add at least one object before starting a job"; return }
        do { grbl.sendJob(try makeGCode(requireLaserMode: true)) }
        catch { status = "Cannot start: \(error.localizedDescription)"; return }
        status = "Sending job · \(objects.filter(\.burnEnabled).count) layers"
    }
    private func cancelJob() {
        grbl.stopJob()
        status = "Job cancelled · queued moves cleared"
    }

    private func makeGCode(requireLaserMode: Bool) throws -> [String] {
        if requireLaserMode && !grbl.settingsLoaded {
            let detail = grbl.lastError ?? "The app is retrying the read-only GRBL settings request."
            throw NSError(domain: "LaserStudio", code: 2, userInfo: [NSLocalizedDescriptionKey: "Laser settings ($30 and $32) are unavailable. \(detail)"])
        }
        guard !requireLaserMode || grbl.laserModeEnabled == true else {
            throw NSError(domain: "LaserStudio", code: 1, userInfo: [NSLocalizedDescriptionKey: "GRBL laser mode ($32=1) is required for dynamic M4 power. Connect and confirm the controller settings first."])
        }
        return try GCodeGenerator.make(objects: objects, material: material, sMax: grbl.sMax, kerf: max(0.1, hatchSpacing), machine: activeMachine)
    }
}
