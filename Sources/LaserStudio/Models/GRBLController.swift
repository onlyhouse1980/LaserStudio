import Foundation
import Combine
import Darwin

@MainActor
final class GRBLController: ObservableObject {
    @Published private(set) var ports: [String] = []
    @Published private(set) var connectedPort: String?
    @Published private(set) var isConnecting = false
    @Published private(set) var isSendingJob = false
    @Published private(set) var isJobPaused = false
    @Published private(set) var isSendingManualCommand = false
    @Published private(set) var lastError: String?
    // Fixed to the Longer Ray5's standard GRBL laser settings. Some Ray5
    // firmware responds to realtime status but does not return the $$ dump.
    @Published private(set) var sMax = 1000
    @Published private(set) var laserModeEnabled: Bool? = true
    @Published private(set) var settingsLoaded = true
    // Hard coded for the Ray5 configuration requested by the user ($22=1).
    @Published private(set) var homingEnabled: Bool? = true
    @Published private(set) var homingSettingLoaded = true
    @Published private(set) var workspacePosition: (x: Double, y: Double)?
    @Published private(set) var controllerState: String?

    private var fileDescriptor: Int32 = -1
    private var readSource: DispatchSourceRead?
    private var statusPollTimer: DispatchSourceTimer?
    private var readBuffer = Data()
    private var pendingLines: [String] = []
    private var jobLines: [String] = []
    private var manualLines: [String] = []
    private var responseTimer: DispatchWorkItem?
    private var manualResponseTimer: DispatchWorkItem?
    private let ioQueue = DispatchQueue(label: "studio.laserstudio.grbl-serial")
    private var onConnect: ((Result<Void, Error>) -> Void)?
    private var connectingPath: String?

    var isConnected: Bool { connectedPort != nil }
    var hasActiveJob: Bool { isSendingJob || isJobPaused }

    func refreshPorts() {
        let paths = (try? FileManager.default.contentsOfDirectory(atPath: "/dev")) ?? []
        ports = paths
            .filter { $0.hasPrefix("cu.") && ($0.contains("usb") || $0.contains("serial") || $0.contains("wch") || $0.contains("SLAB")) }
            .map { "/dev/\($0)" }
            .sorted()
    }

    func connect(to path: String, completion: @escaping (Result<Void, Error>) -> Void) {
        disconnect()
        lastError = nil
        laserModeEnabled = true
        homingEnabled = true
        homingSettingLoaded = true
        workspacePosition = nil
        controllerState = nil
        settingsLoaded = true
        isConnecting = true
        onConnect = completion
        connectingPath = path

        let fd = open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard fd >= 0 else {
            finishConnect(.failure(serialError("Could not open \(path)")))
            return
        }
        fileDescriptor = fd

        var settings = termios()
        guard tcgetattr(fd, &settings) == 0 else {
            finishConnect(.failure(serialError("Could not read serial settings")))
            return
        }
        cfmakeraw(&settings)
        settings.c_cflag |= tcflag_t(CLOCAL | CREAD)
        settings.c_cflag &= ~tcflag_t(CSTOPB | PARENB | CSIZE)
        settings.c_cflag |= tcflag_t(CS8)
        settings.c_cc.0 = 0
        settings.c_cc.1 = 1
        guard cfsetspeed(&settings, speed_t(B115200)) == 0, tcsetattr(fd, TCSANOW, &settings) == 0 else {
            finishConnect(.failure(serialError("Could not configure the port at 115200 baud")))
            return
        }
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: ioQueue)
        source.setEventHandler { [weak self] in self?.readAvailable() }
        source.setCancelHandler { close(fd) }
        readSource = source
        source.resume()

        // Opening a serial port can reset some GRBL boards. Poll until one status
        // response arrives instead of relying on a single request during startup.
        let pollTimer = DispatchSource.makeTimerSource(queue: ioQueue)
        pollTimer.schedule(deadline: .now() + 0.4, repeating: 0.5)
        pollTimer.setEventHandler { Self.writeRaw(fd: fd, data: Data([63])) }
        statusPollTimer = pollTimer
        pollTimer.resume()
        responseTimer = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self, self.isConnecting else { return }
                self.finishConnect(.failure(self.serialError("No GRBL status response. Check the cable and controller.")))
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: responseTimer!)
    }

    func disconnect() {
        responseTimer?.cancel()
        responseTimer = nil
        manualResponseTimer?.cancel()
        manualResponseTimer = nil
        statusPollTimer?.cancel()
        statusPollTimer = nil
        isConnecting = false
        isSendingJob = false
        isJobPaused = false
        isSendingManualCommand = false
        jobLines.removeAll()
        manualLines.removeAll()
        pendingLines.removeAll()
        onConnect = nil
        connectedPort = nil
        if let source = readSource {
            source.cancel()
            readSource = nil
        } else if fileDescriptor >= 0 {
            close(fileDescriptor)
        }
        fileDescriptor = -1
    }

    func sendJob(_ gcode: [String]) {
        guard isConnected, !isSendingManualCommand, !isJobPaused else { return }
        jobLines = gcode.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        pendingLines.removeAll()
        lastError = nil
        isJobPaused = false
        isSendingJob = true
        sendNextLine()
    }

    func pauseJob() {
        guard isSendingJob else { return }
        isSendingJob = false
        isJobPaused = true
        let fd = fileDescriptor
        ioQueue.async { Self.writeRaw(fd: fd, data: Data([33])) } // GRBL feed hold
    }

    func resumeJob() {
        guard isConnected, isJobPaused, !isSendingManualCommand else { return }
        isJobPaused = false
        isSendingJob = true
        let fd = fileDescriptor
        ioQueue.async { Self.writeRaw(fd: fd, data: Data([126])) } // GRBL cycle start
        if pendingLines.isEmpty { sendNextLine() }
    }

    func stopJob() {
        guard hasActiveJob else { return }
        isSendingJob = false
        isJobPaused = false
        jobLines.removeAll()
        pendingLines.removeAll()
        let fd = fileDescriptor
        ioQueue.async { Self.writeRaw(fd: fd, data: Data([24])) } // GRBL soft reset clears the queued job
    }

    @discardableResult
    func moveToWorkspaceOrigin() -> Bool {
        guard isConnected, !hasActiveJob, !isSendingManualCommand, homingSettingLoaded,
              let homingEnabled else { return false }
        lastError = nil
        // Ensure the controller's homing setting matches the Ray5 profile.
        // GRBL reports error:5 for $H when $22 is disabled. Run $H before
        // ordinary G-code so a startup homing alarm can be cleared safely.
        // Then define the front-left pull-off position as the app's G54 0,0.
        manualLines = Self.workspaceOriginCommands(homingEnabled: homingEnabled)
        isSendingManualCommand = true
        sendNextManualLine()
        return true
    }

    static func workspaceOriginCommands(homingEnabled: Bool) -> [String] {
        homingEnabled ? ["$22=1", "$H", "M5", "G10 L20 P1 X0 Y0", "G90 G54 G0 X0 Y0"] : ["M5"]
    }

    private func readAvailable() {
        guard fileDescriptor >= 0 else { return }
        var bytes = [UInt8](repeating: 0, count: 2048)
        let count = Darwin.read(fileDescriptor, &bytes, bytes.count)
        guard count > 0 else { return }
        readBuffer.append(contentsOf: bytes.prefix(count))

        var lines: [String] = []
        while let delimiter = readBuffer.firstIndex(where: { $0 == 10 || $0 == 13 }) {
            let lineData = readBuffer[..<delimiter]
            readBuffer.removeSubrange(...delimiter)
            guard let line = String(data: lineData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !line.isEmpty else { continue }
            lines.append(line)
        }
        if !lines.isEmpty {
            Task { @MainActor in
                for line in lines { self.handleResponse(line) }
            }
        }
    }

    func handleResponse(_ line: String) {
        if line.hasPrefix("<") { updatePosition(from: line) }
        if isConnecting && line.hasPrefix("<") {
            finishConnect(.success(()))
            return
        }
        if line.hasPrefix("error:") || line.hasPrefix("ALARM:") {
            if isConnecting { finishConnect(.failure(serialError("GRBL replied: \(line)"))) }
            else if hasActiveJob { lastError = line; stopJob() }
            else if isSendingManualCommand {
                manualResponseTimer?.cancel()
                manualResponseTimer = nil
                lastError = line
                manualLines.removeAll()
                pendingLines.removeAll()
                isSendingManualCommand = false
            }
            return
        }
        guard line == "ok" else { return }
        guard !pendingLines.isEmpty else { return }
        if isSendingManualCommand {
            manualResponseTimer?.cancel()
            manualResponseTimer = nil
        }
        pendingLines.removeFirst()
        if isSendingJob { sendNextLine() }
        else if isSendingManualCommand { sendNextManualLine() }
    }

    private func sendNextLine() {
        guard isSendingJob else { return }
        guard !jobLines.isEmpty else { isSendingJob = false; isJobPaused = false; return }
        let line = jobLines.removeFirst()
        pendingLines.append(line)
        let fd = fileDescriptor
        ioQueue.async { Self.writeRaw(fd: fd, data: Data((line + "\n").utf8)) }
    }

    private func sendNextManualLine() {
        guard isSendingManualCommand else { return }
        guard !manualLines.isEmpty else {
            manualResponseTimer?.cancel()
            manualResponseTimer = nil
            isSendingManualCommand = false
            return
        }
        let line = manualLines.removeFirst()
        pendingLines.append(line)
        let fd = fileDescriptor
        ioQueue.async { Self.writeRaw(fd: fd, data: Data((line + "\n").utf8)) }
        let timeout: TimeInterval = line == "$H" ? 180 : 15
        manualResponseTimer = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self, self.isSendingManualCommand else { return }
                self.lastError = "No GRBL acknowledgement for \(line) within \(Int(timeout)) seconds"
                self.manualLines.removeAll()
                self.pendingLines.removeAll()
                self.isSendingManualCommand = false
                self.manualResponseTimer = nil
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: manualResponseTimer!)
    }

    nonisolated private static func writeRaw(fd: Int32, data: Data) {
        guard fd >= 0 else { return }
        data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return }
            _ = Darwin.write(fd, base, data.count)
        }
    }

    private func finishConnect(_ result: Result<Void, Error>) {
        responseTimer?.cancel()
        responseTimer = nil
        manualResponseTimer?.cancel()
        manualResponseTimer = nil
        statusPollTimer?.cancel()
        statusPollTimer = nil
        isConnecting = false
        let completion = onConnect
        onConnect = nil
        switch result {
        case .success:
            connectedPort = connectingPath ?? "USB serial"
            lastError = nil
            let fd = fileDescriptor
            let pollTimer = DispatchSource.makeTimerSource(queue: ioQueue)
            pollTimer.schedule(deadline: .now() + 1, repeating: 1)
            pollTimer.setEventHandler { Self.writeRaw(fd: fd, data: Data([63])) }
            statusPollTimer = pollTimer
            pollTimer.resume()
        case .failure(let error):
            lastError = error.localizedDescription
            if let source = readSource { source.cancel(); readSource = nil }
            else if fileDescriptor >= 0 { close(fileDescriptor) }
            fileDescriptor = -1
            connectingPath = nil
        }
        completion?(result)
        if case .failure = result { connectingPath = nil }
    }

    private func serialError(_ message: String) -> NSError {
        let detail = String(cString: strerror(errno))
        return NSError(domain: "LaserStudio.GRBL", code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "\(message) (\(detail))"])
    }

    private func updatePosition(from status: String) {
        guard let body = status.dropFirst().split(separator: ">", maxSplits: 1).first else { return }
        controllerState = body.split(separator: "|").first.map(String.init)
        var fields: [String: [Double]] = [:]
        for field in body.split(separator: "|") {
            let pair = field.split(separator: ":", maxSplits: 1)
            guard pair.count == 2 else { continue }
            let values = pair[1].split(separator: ",").compactMap { Double($0) }
            fields[String(pair[0])] = values
        }
        if let work = fields["WPos"], work.count >= 2 {
            workspacePosition = (work[0], work[1])
        } else if let machine = fields["MPos"], machine.count >= 2,
                  let offset = fields["WCO"], offset.count >= 2 {
            workspacePosition = (machine[0] - offset[0], machine[1] - offset[1])
        } else if let machine = fields["MPos"], machine.count >= 2 {
            workspacePosition = (machine[0], machine[1])
        }
    }
}
