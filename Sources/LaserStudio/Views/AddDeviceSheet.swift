import SwiftUI

/// "Add Device" — detects a connected GRBL controller and lets the user review and edit its settings
/// before saving them as a reusable machine preset.
struct AddDeviceSheet: View {
    @ObservedObject var grbl: GRBLController
    var onSave: (LaserProfile) -> Void
    var onCancel: () -> Void

    @State private var port = ""
    @State private var draft: LaserProfile = {
        var profile = LaserProfile.autoDetected
        profile.name = "My GRBL laser"
        return profile
    }()
    @State private var nameEdited = false
    @State private var startedConnection = false
    @State private var showWriteConfirm = false
    @State private var message: String?

    private var detected: DetectedMachine? { grbl.detected }
    private var isBusy: Bool { grbl.isConnecting || grbl.isDetecting }
    private var isValid: Bool {
        draft.workspaceWidth >= 10 && draft.workspaceHeight >= 10 && draft.maxFeedRate >= 1
            && (1...10000).contains(draft.sMax) && !draft.name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.4)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    portSection
                    settingsSection
                    advancedSection
                }.padding(22)
            }
            Divider().opacity(0.4)
            footer
        }
        .frame(width: 560, height: 700)
        .preferredColorScheme(.dark)
        .onAppear {
            grbl.refreshPorts()
            if port.isEmpty { port = grbl.ports.first ?? "" }
        }
        .onChange(of: grbl.detected) { _, result in
            guard let result else { return }
            let name = draft.name
            draft = result.applied(to: draft)
            draft.name = name
            if !nameEdited, let model = Self.modelName(from: result.firmware) { draft.name = model }
            message = "Detected \(result.firmware ?? "GRBL controller"). Review the values below and edit anything that is wrong."
        }
        .onChange(of: grbl.lastError) { _, error in
            if let error, !grbl.isConnected { message = error }
        }
        .confirmationDialog("Write settings to the controller?", isPresented: $showWriteConfirm, titleVisibility: .visible) {
            Button("Write Settings", role: .destructive) { writeToController() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This overwrites $30, $32, $22, $110, $111, $130 and $131 in the controller's memory. Only do this if you know the correct values for your machine.")
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "cable.connector.horizontal").foregroundStyle(.orange)
            Text("ADD DEVICE").font(.system(size: 12, weight: .bold, design: .rounded)).tracking(1.2)
            Spacer()
        }.padding(.horizontal, 22).frame(height: 48)
    }

    private var portSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("1 · CONNECT & DETECT")
            if grbl.ports.isEmpty {
                ContentUnavailableView("No USB serial ports found", systemImage: "cable.connector.horizontal",
                                       description: Text("Plug in and power on your laser, then refresh."))
                    .frame(height: 130)
            } else {
                Picker("Port", selection: $port) {
                    ForEach(grbl.ports, id: \.self) { Text($0).tag($0) }
                }.pickerStyle(.menu)
            }
            HStack(spacing: 10) {
                Button { grbl.refreshPorts(); if port.isEmpty || !grbl.ports.contains(port) { port = grbl.ports.first ?? "" } } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                Button(action: detect) {
                    Label(grbl.isConnected ? "Detect Again" : "Detect Device", systemImage: "dot.radiowaves.left.and.right")
                }
                .buttonStyle(.borderedProminent).tint(.orange)
                .disabled(port.isEmpty || isBusy)
                if isBusy { ProgressView().controlSize(.small) }
                Spacer()
            }
            statusLine
        }
    }

    private var statusLine: some View {
        HStack(spacing: 7) {
            Circle().fill(statusColor).frame(width: 7, height: 7)
            Text(statusText).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var statusColor: Color {
        if isBusy { return .orange }
        if detected != nil { return .green }
        return grbl.isConnected ? .yellow : .gray
    }

    private var statusText: String {
        if grbl.isConnecting { return "Connecting to \(port)…" }
        if grbl.isDetecting { return "Reading controller settings ($I, $$)…" }
        if let message { return message }
        return "Select the port and click Detect Device. You can also skip detection and enter the settings by hand."
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("2 · DEVICE SETTINGS")
            field("Device name", detected: false) {
                TextField("Name", text: Binding(get: { draft.name }, set: { draft.name = $0; nameEdited = true }))
                    .textFieldStyle(.roundedBorder)
            }
            HStack(spacing: 12) {
                field("Work area width (mm) · $130", detected: detected?.workspaceWidth != nil) {
                    TextField("", value: $draft.workspaceWidth, format: .number.precision(.fractionLength(0...1)))
                        .textFieldStyle(.roundedBorder)
                }
                field("Work area height (mm) · $131", detected: detected?.workspaceHeight != nil) {
                    TextField("", value: $draft.workspaceHeight, format: .number.precision(.fractionLength(0...1)))
                        .textFieldStyle(.roundedBorder)
                }
            }
            HStack(spacing: 12) {
                field("Max speed (mm/min) · $110/$111", detected: detected?.maxFeedRate != nil) {
                    TextField("", value: $draft.maxFeedRate, format: .number.precision(.fractionLength(0...1)))
                        .textFieldStyle(.roundedBorder)
                }
                field("Laser S max · $30", detected: detected?.sMax != nil) {
                    TextField("", value: $draft.sMax, format: .number)
                        .textFieldStyle(.roundedBorder)
                }
            }
            Toggle(isOn: $draft.laserMode) {
                toggleLabel("Laser mode · $32", detected: detected?.laserMode != nil,
                            note: "Required for dynamic power (M4). Jobs are blocked when off.")
            }.toggleStyle(.switch)
            Toggle(isOn: $draft.homingEnabled) {
                toggleLabel("Homing switches · $22", detected: detected?.homingEnabled != nil,
                            note: "Enables the Home button ($H, then work origin X0 Y0 at the front-left).")
            }.toggleStyle(.switch)
            if !isValid {
                Label("Enter a name, a work area of at least 10 mm, a speed above 0 and an S max from 1 to 10000.",
                      systemImage: "exclamationmark.triangle.fill").font(.system(size: 10)).foregroundStyle(.yellow)
            }
        }
    }

    private var advancedSection: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                Text("Writes the values above to the connected controller. The app never does this unless you press the button.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                Button(role: .destructive) { showWriteConfirm = true } label: {
                    Label("Write Settings to Controller…", systemImage: "square.and.arrow.down.on.square")
                }
                .disabled(!grbl.isConnected || isBusy || grbl.hasActiveJob || grbl.isSendingManualCommand || !isValid)
                if !grbl.isConnected {
                    Text("Connect first (step 1).").font(.system(size: 10)).foregroundStyle(.tertiary)
                }
            }.padding(.top, 8)
        } label: {
            sectionTitle("ADVANCED · CONTROLLER MEMORY")
        }
    }

    private var footer: some View {
        HStack {
            Text(grbl.isConnected ? "Connected · \(grbl.connectedPort ?? "")" : "Not connected")
                .font(.system(size: 10)).foregroundStyle(.secondary)
            Spacer()
            Button("Cancel") { cancel() }.keyboardShortcut(.cancelAction)
            Button("Save Device") { onSave(finalProfile()) }
                .buttonStyle(.borderedProminent).tint(.orange)
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
        }.padding(.horizontal, 22).frame(height: 56)
    }

    // MARK: Actions

    private func detect() {
        message = nil
        grbl.configure(with: .autoDetected)
        startedConnection = true
        grbl.connect(to: port) { result in
            if case .failure(let error) = result { message = error.localizedDescription }
        }
    }

    private func cancel() {
        if startedConnection && grbl.isConnected { grbl.disconnect() }
        onCancel()
    }

    private func finalProfile() -> LaserProfile {
        var profile = draft
        profile.name = draft.name.trimmingCharacters(in: .whitespaces)
        profile.autoDetect = false
        profile.isBuiltIn = false
        return profile
    }

    private func writeToController() {
        func number(_ value: Double) -> String { value == value.rounded() ? String(Int(value)) : String(format: "%.3f", value) }
        let commands = [
            "$30=\(draft.sMax)", "$32=\(draft.laserMode ? 1 : 0)", "$22=\(draft.homingEnabled ? 1 : 0)",
            "$110=\(number(draft.maxFeedRate))", "$111=\(number(draft.maxFeedRate))",
            "$130=\(number(draft.workspaceWidth))", "$131=\(number(draft.workspaceHeight))"
        ]
        message = grbl.writeSettings(commands) ? "Writing settings to the controller…" : "Could not write: stop the current job and make sure the device is connected."
    }

    // MARK: Helpers

    /// Firmware strings look like "1.1h.20190825:Machine name"; use the trailing text as a suggested name.
    private static func modelName(from firmware: String?) -> String? {
        guard let firmware, let last = firmware.split(separator: ":", omittingEmptySubsequences: false).last else { return nil }
        let name = last.trimmingCharacters(in: .whitespaces)
        return name.isEmpty || firmware.split(separator: ":").count < 2 ? nil : name
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text).font(.system(size: 10, weight: .bold)).tracking(0.9).foregroundStyle(.secondary)
    }

    private func field<Content: View>(_ title: String, detected: Bool, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
                if detected { Image(systemName: "checkmark.seal.fill").font(.system(size: 9)).foregroundStyle(.green).help("Detected from the controller") }
            }
            content()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func toggleLabel(_ title: String, detected: Bool, note: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(title).font(.system(size: 11, weight: .medium))
                if detected { Image(systemName: "checkmark.seal.fill").font(.system(size: 9)).foregroundStyle(.green) }
            }
            Text(note).font(.system(size: 9)).foregroundStyle(.secondary)
        }
    }
}
