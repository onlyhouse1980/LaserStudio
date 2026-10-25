import Foundation
import Combine

/// Machine settings that LaserStudio needs to generate safe G-code for a GRBL laser.
struct LaserProfile: Identifiable, Codable, Equatable, Hashable {
    var id: String
    var name: String
    var workspaceWidth: Double      // mm  ($130)
    var workspaceHeight: Double     // mm  ($131)
    var maxFeedRate: Double         // mm/min ($110/$111)
    var sMax: Int                   // spindle/laser max S value ($30)
    var laserMode: Bool             // $32=1
    var homingEnabled: Bool         // $22=1
    /// Write `$22=1` before homing. Only the Ray5 preset does this; other machines are never reconfigured.
    var writeHomingSetting: Bool
    /// Read `$$` after connecting and fill in the values above from the controller.
    var autoDetect: Bool
    var isBuiltIn: Bool

    var workspace: CGSize { CGSize(width: workspaceWidth, height: workspaceHeight) }

    /// Longer Ray5 (GRBL, 400 × 400 mm). Some Ray5 firmware does not answer `$$`, so nothing is detected.
    static let ray5 = LaserProfile(
        id: "builtin.longer-ray5", name: "Longer Ray5",
        workspaceWidth: 400, workspaceHeight: 400, maxFeedRate: 10000, sMax: 1000,
        laserMode: true, homingEnabled: true, writeHomingSetting: true, autoDetect: false, isBuiltIn: true)

    /// Any other GRBL laser: values are read from the controller after connecting.
    static let autoDetected = LaserProfile(
        id: "builtin.grbl-auto", name: "Other GRBL laser (auto-detect)",
        workspaceWidth: 400, workspaceHeight: 400, maxFeedRate: 6000, sMax: 1000,
        laserMode: false, homingEnabled: false, writeHomingSetting: false, autoDetect: true, isBuiltIn: true)

    static let builtIn: [LaserProfile] = [.ray5, .autoDetected]
}

/// Values reported by a GRBL controller in response to `$$` / `$I`.
struct DetectedMachine: Equatable {
    var firmware: String?
    var sMax: Int?
    var laserMode: Bool?
    var homingEnabled: Bool?
    var maxFeedRate: Double?
    var workspaceWidth: Double?
    var workspaceHeight: Double?

    var isEmpty: Bool { sMax == nil && laserMode == nil && homingEnabled == nil && maxFeedRate == nil && workspaceWidth == nil }

    /// Parses a single `$N=value` setting line. Returns false when the line is not a setting.
    mutating func parse(setting line: String) -> Bool {
        guard line.hasPrefix("$"), let equals = line.firstIndex(of: "="),
              let number = Int(line[line.index(after: line.startIndex)..<equals]),
              let value = Double(line[line.index(after: equals)...].split(separator: " ").first ?? "") else { return false }
        switch number {
        case 22: homingEnabled = value != 0
        case 30: sMax = Int(value)
        case 32: laserMode = value != 0
        case 110, 111:
            maxFeedRate = min(maxFeedRate ?? value, value)
        case 130: workspaceWidth = value
        case 131: workspaceHeight = value
        default: break
        }
        return true
    }

    /// Applies detected values on top of a profile. Missing values keep the profile defaults.
    func applied(to profile: LaserProfile) -> LaserProfile {
        var result = profile
        if let sMax, sMax > 0 { result.sMax = min(10000, sMax) }
        if let laserMode { result.laserMode = laserMode }
        if let homingEnabled { result.homingEnabled = homingEnabled }
        if let maxFeedRate, maxFeedRate > 0 { result.maxFeedRate = maxFeedRate }
        if let workspaceWidth, workspaceWidth > 10 { result.workspaceWidth = workspaceWidth }
        if let workspaceHeight, workspaceHeight > 10 { result.workspaceHeight = workspaceHeight }
        return result
    }
}

/// Stores built-in and user-saved machine presets and remembers the selected one.
@MainActor
final class LaserProfileStore: ObservableObject {
    @Published private(set) var custom: [LaserProfile] = []
    @Published var selectedID: String {
        didSet { UserDefaults.standard.set(selectedID, forKey: Self.selectedKey) }
    }

    private static let customKey = "LaserStudio.customProfiles"
    private static let selectedKey = "LaserStudio.selectedProfile"

    var all: [LaserProfile] { LaserProfile.builtIn + custom }
    var selected: LaserProfile { all.first { $0.id == selectedID } ?? .ray5 }

    init() {
        selectedID = UserDefaults.standard.string(forKey: Self.selectedKey) ?? LaserProfile.ray5.id
        if let data = UserDefaults.standard.data(forKey: Self.customKey),
           let decoded = try? JSONDecoder().decode([LaserProfile].self, from: data) {
            custom = decoded
        }
    }

    /// Saves `profile` as a user preset (replacing a preset with the same name) and selects it.
    @discardableResult
    func save(_ profile: LaserProfile, named name: String) -> LaserProfile {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var saved = profile
        saved.name = trimmed.isEmpty ? "My laser" : trimmed
        saved.isBuiltIn = false
        saved.autoDetect = false
        saved.writeHomingSetting = false
        if let index = custom.firstIndex(where: { $0.name == saved.name }) {
            saved.id = custom[index].id
            custom[index] = saved
        } else {
            saved.id = "custom.\(UUID().uuidString)"
            custom.append(saved)
        }
        persist()
        selectedID = saved.id
        return saved
    }

    func delete(_ profile: LaserProfile) {
        guard !profile.isBuiltIn else { return }
        custom.removeAll { $0.id == profile.id }
        if selectedID == profile.id { selectedID = LaserProfile.ray5.id }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(custom) { UserDefaults.standard.set(data, forKey: Self.customKey) }
    }
}
