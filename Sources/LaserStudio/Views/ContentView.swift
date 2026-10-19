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
    @StateObject private var grbl = GRBLController()
    @State private var showDevicePicker = false
    @State private var showCameraPreview = false
    @State private var material = "3 mm birch plywood"
    @State private var hatchSpacing = 0.4
    @State private var projectName = "Untitled project"
    @State private var status = "Ready"
    @FocusState private var textInputFocused: Bool

    private var selectedIndex: Int? { objects.firstIndex { $0.id == selection } }
    private var selectedObject: DesignObject? { selectedIndex.map { objects[$0] } }

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
            Button(action: newProject) { Label("New", systemImage: "doc.badge.plus") }.keyboardShortcut("n", modifiers: .command)
            Button(action: undo) { Label("Undo", systemImage: "arrow.uturn.backward") }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(undoStack.isEmpty && pendingUndoSnapshot == nil)
                .help("Undo the last workspace change")
            Button(action: redo) { Label("Redo", systemImage: "arrow.uturn.forward") }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(redoStack.isEmpty || pendingUndoSnapshot != nil)
                .help("Redo the last undone workspace change")
            Button {
                if grbl.moveToWorkspaceOrigin() { status = "Homing to workspace X0 Y0…" }
                else if !grbl.homingSettingLoaded { status = "Waiting for Ray5 homing settings" }
                else { status = "Connect the Ray5 and stop the current job before homing" }
            } label: { Label("Home", systemImage: "house") }
                .disabled(!grbl.isConnected || !grbl.homingSettingLoaded || grbl.hasActiveJob || grbl.isSendingManualCommand)
                .help(grbl.homingSettingLoaded ? "Home the Ray5, then move to workspace X0 Y0 at the front-left corner" : "Waiting for the Ray5 GRBL homing setting")
            Button { addShape() } label: { Label("Shape", systemImage: "square.on.circle") }
            Button(action: importArtwork) { Label("Import", systemImage: "square.and.arrow.down") }
            Button(action: exportJob) { Label("Export", systemImage: "square.and.arrow.up") }.keyboardShortcut("e", modifiers: .command)
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
        VStack(spacing: 5) {
            toolButton("Select", icon: "arrow.up.left")
            toolButton("Node edit", icon: "point.3.connected.trianglepath.dotted")
            Divider().padding(.vertical, 6).opacity(0.3)
            toolButton("Line", icon: "line.diagonal")
            toolButton("Rectangle", icon: "rectangle")
            toolButton("Circle", icon: "circle")
            toolButton("Text", icon: "textformat")
            toolButton("Pen", icon: "pencil.tip")
            Spacer()
            toolButton("Measure", icon: "ruler")
            toolButton("Camera", icon: "camera.viewfinder")
        }
        .padding(.vertical, 11).frame(width: 54)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .trailing) { Divider().opacity(0.35) }
    }

    private func toolButton(_ name: String, icon: String) -> some View {
            Button {
                activeTool = name
                if name == "Text" { status = "Click the workspace to place text" }
                if name == "Camera" { showCameraPreview = true }
            } label: {
            Image(systemName: icon).font(.system(size: 15)).frame(width: 36, height: 34)
                .background(activeTool == name ? Color.orange.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 7))
                .foregroundStyle(activeTool == name ? Color.orange : Color.secondary)
        }
        .buttonStyle(.plain)
        .help(name == "Select"
              ? "Select and move layers · Left-drag selects touched layers · Right-drag selects fully enclosed layers"
              : name)
    }

    private var workspace: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Label(projectName, systemImage: "square.dashed").font(.system(size: 11, weight: .medium))
                Spacer()
                Button { showGrid.toggle() } label: { Image(systemName: showGrid ? "grid" : "grid.circle") }.help("Toggle grid")
                Button { zoom = max(0.5, zoom - 0.1) } label: { Image(systemName: "minus.magnifyingglass") }
                Text("\(Int(zoom * 100))%").font(.system(size: 10, design: .monospaced)).frame(width: 42)
                Button { zoom = min(1.5, zoom + 0.1) } label: { Image(systemName: "plus.magnifyingglass") }
                Button { zoom = 1 } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }.help("Fit to workspace")
            }
            .buttonStyle(.plain).foregroundStyle(.secondary).padding(.horizontal, 15).frame(height: 39)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.7))
            CanvasArea(objects: $objects, selection: $selection, selectedIDs: $selectedIDs,
                       showGrid: showGrid, zoom: zoom, activeTool: $activeTool, status: $status)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(red: 0.105, green: 0.12, blue: 0.14))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                        HStack { VStack(alignment: .leading, spacing: 4) { Text("Longer Ray5").font(.system(size: 11, weight: .medium)); Text(grbl.connectedPort ?? "GRBL · USB · Not connected").font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1); if grbl.isConnected { Text("S max \(grbl.sMax) · Laser mode \(grbl.laserModeEnabled == true ? "on" : grbl.laserModeEnabled == false ? "off" : "checking…")").font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary) } }; Spacer(); Image(systemName: "cable.connector.horizontal").font(.system(size: 12)).foregroundStyle(.tertiary) }
                        HStack { Text("Workspace").foregroundStyle(.secondary); Spacer(); Text("400 × 400 mm") }
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
                            Spacer()
                            Button {
                                let ids = selectedIDs.isEmpty ? (selection.map { Set([$0]) } ?? []) : selectedIDs
                                objects.removeAll { ids.contains($0.id) }
                                selection = objects.first?.id
                                selectedIDs = selection.map { Set([$0]) } ?? []
                            } label: { Image(systemName: "trash").font(.system(size: 10)) }
                                .disabled(selection == nil && selectedIDs.isEmpty)
                                .help(selectedIDs.count > 1 ? "Delete selected layers" : "Delete selected layer")
                        }.buttonStyle(.borderless).foregroundStyle(.secondary)
                    }
                    if selectedObject != nil {
                        group("SELECTED OBJECT") {
                            if selectedObject?.kind == .text {
                                TextField("Text", text: selectedTextBinding)
                                    .textFieldStyle(.roundedBorder)
                                    .focused($textInputFocused)
                                    .onSubmit { textInputFocused = false }
                            }
                            coordinateRow("X", value: \DesignObject.x, unit: "mm")
                            coordinateRow("Y", value: \DesignObject.y, unit: "mm")
                            coordinateRow("W", value: \DesignObject.width, unit: "mm")
                            coordinateRow("H", value: \DesignObject.height, unit: "mm")
                            Divider().opacity(0.3)
                            HStack { Text("Layer color").font(.system(size: 10)).foregroundStyle(.secondary); Spacer(); colorSwatch(.red); colorSwatch(.blue); colorSwatch(.green); colorSwatch(.orange) }
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
        .frame(width: 255).background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
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
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Button { selectLayer(object.id) } label: {
                    HStack(spacing: 7) {
                        RoundedRectangle(cornerRadius: 2).fill(object.color).frame(width: 3, height: 23)
                        Image(systemName: icon(for: object.kind)).frame(width: 15).foregroundStyle(Color.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(object.label).font(.system(size: 10, weight: .medium)).lineLimit(1)
                            Text("\(Int(object.width)) × \(Int(object.height)) mm")
                                .font(.system(size: 9, design: .monospaced)).foregroundStyle(Color.secondary)
                        }
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 11))
                            .foregroundStyle(isSelected ? Color.orange : Color.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Button { toggleLayerVisibility(object.id) } label: {
                    Image(systemName: object.isVisible ? "eye" : "eye.slash")
                        .font(.system(size: 11))
                        .foregroundStyle(object.isVisible ? Color.secondary : Color.orange)
                        .frame(width: 20, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(object.isVisible ? "Hide layer on canvas" : "Show layer on canvas")
                Spacer(minLength: 2)
                Toggle("Burn", isOn: burnBinding(for: object.id))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .help(object.burnEnabled ? "Burn this layer" : "Skip this layer")
                Text(object.burnEnabled ? "Burn" : "Skip")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(object.burnEnabled ? Color.orange : Color.secondary)
                    .frame(width: 27, alignment: .leading)
            }
            if object.kind == .text {
                HStack(spacing: 5) {
                    Text("Font").frame(width: 34, alignment: .leading)
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
                        Text("B").font(.system(size: 11, weight: .bold)).frame(width: 22, height: 22)
                            .background(object.fontBold ? Color.orange.opacity(0.24) : Color.clear, in: RoundedRectangle(cornerRadius: 4))
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(object.fontBold ? Color.orange : Color.white.opacity(0.15), lineWidth: 1))
                    }
                    .buttonStyle(.plain).foregroundStyle(object.fontBold ? Color.orange : Color.secondary)
                    .help(object.fontBold ? "Disable bold" : "Enable bold")
                    Button { if let index = objects.firstIndex(where: { $0.id == object.id }) { objects[index].fontItalic.toggle() } } label: {
                        Text("I").italic().font(.system(size: 11, weight: .medium)).frame(width: 22, height: 22)
                            .background(object.fontItalic ? Color.orange.opacity(0.24) : Color.clear, in: RoundedRectangle(cornerRadius: 4))
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(object.fontItalic ? Color.orange : Color.white.opacity(0.15), lineWidth: 1))
                    }
                    .buttonStyle(.plain).foregroundStyle(object.fontItalic ? Color.orange : Color.secondary)
                    .help(object.fontItalic ? "Disable italic" : "Enable italic")
                }
            }
            if object.kind != .image {
                Picker("Layer cut mode", selection: layerModeBinding(for: object.id)) {
                    ForEach(EngravingMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.small)
            }
            HStack(spacing: 5) {
                Text("Power").frame(width: 34, alignment: .leading)
                Slider(value: layerPowerBinding(for: object.id), in: 1...100).tint(.orange)
                Text("\(Int(object.power))%").font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary).frame(width: 32, alignment: .trailing)
            }
            if object.kind == .image {
                Toggle("Invert", isOn: imageInvertedBinding(for: object.id))
                    .toggleStyle(.checkbox)
                    .font(.system(size: 9))
                HStack(spacing: 5) {
                    Text("Min").frame(width: 34, alignment: .leading)
                    Slider(value: imageMinimumSpeedBinding(for: object.id), in: 40...GCodeGenerator.ray5MaxFeedRate).tint(.orange)
                    Text("\(Int(object.minimumSpeed))").font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(.secondary).frame(width: 40, alignment: .trailing)
                }
                HStack(spacing: 5) {
                    Text("Max").frame(width: 34, alignment: .leading)
                    Slider(value: imageMaximumSpeedBinding(for: object.id), in: 40...GCodeGenerator.ray5MaxFeedRate).tint(.orange)
                    Text("\(Int(object.maximumSpeed))").font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(.secondary).frame(width: 40, alignment: .trailing)
                }
                Toggle("Variable power by image shade", isOn: imageVariablePowerBinding(for: object.id))
                    .toggleStyle(.checkbox)
                    .font(.system(size: 9))
            } else {
                HStack(spacing: 5) {
                    Text("Speed").frame(width: 34, alignment: .leading)
                    Slider(value: layerSpeedBinding(for: object.id), in: 40...GCodeGenerator.ray5MaxFeedRate).tint(.orange)
                    Text("\(Int(object.speed)) mm/min").font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(.secondary).frame(width: 55, alignment: .trailing)
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
                objects[index].speed = min(GCodeGenerator.ray5MaxFeedRate, max(40, value))
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
            objects[index].maximumSpeed = min(GCodeGenerator.ray5MaxFeedRate, max(objects[index].minimumSpeed, value))
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
    private func icon(for kind: DesignObject.Kind) -> String { switch kind { case .rectangle: "rectangle"; case .circle: "circle"; case .text: "textformat"; case .line: "line.diagonal"; case .path: "scribble"; case .image: "photo" } }
    private var devicePicker: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Connect Longer Ray5").font(.headline)
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
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.svg, .png, .jpeg, .bmp]; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let imported: [DesignObject]
                if url.pathExtension.lowercased() == "svg" {
                    imported = try SVGImporter.load(url)
                } else {
                    imported = [try ImageImporter.load(url)]
                }
                objects.append(contentsOf: imported)
                selection = imported.first?.id
                selectedIDs = Set(imported.map(\.id))
                status = imported.first?.kind == .image
                    ? "Imported image layer from \(url.lastPathComponent)"
                    : "Imported \(imported.count) vector paths from \(url.lastPathComponent)"
            } catch { status = "Import failed: \(error.localizedDescription)" }
        }
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
        guard grbl.isConnected else { status = "Connect the Ray5 before starting a job"; return }
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
            throw NSError(domain: "LaserStudio", code: 2, userInfo: [NSLocalizedDescriptionKey: "Ray5 laser settings ($30 and $32) are unavailable. \(detail)"])
        }
        guard !requireLaserMode || grbl.laserModeEnabled == true else {
            throw NSError(domain: "LaserStudio", code: 1, userInfo: [NSLocalizedDescriptionKey: "GRBL laser mode ($32=1) is required for dynamic M4 power. Connect and confirm the controller settings first."])
        }
        return try GCodeGenerator.make(objects: objects, material: material, sMax: grbl.sMax, kerf: max(0.1, hatchSpacing))
    }
}
