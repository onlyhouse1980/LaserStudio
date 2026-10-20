import SwiftUI

private struct HelpSection: Identifiable {
    let id = UUID()
    let title: String
    let body: [String]
}

private struct HelpDocument: View {
    let heading: String
    let subtitle: String
    let sections: [HelpSection]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(heading).font(.system(size: 26, weight: .bold, design: .rounded))
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(section.title).font(.title3.weight(.semibold)).foregroundStyle(.orange)
                        ForEach(section.body, id: \.self) { line in
                            Text(.init(line)).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
        }
        .frame(minWidth: 560, minHeight: 520)
    }
}

/// Quick reference shown from Help ▸ LaserStudio Help.
struct HelpInfoView: View {
    private let sections: [HelpSection] = [
        HelpSection(title: "About", body: [
            "LaserStudio is a macOS design and job sender for Longer Ray5 laser engravers using GRBL over USB. Workspace: 400 × 400 mm.",
            "Requires macOS 14 or later. Project home: https://github.com/onlyhouse1980/LaserStudio"
        ]),
        HelpSection(title: "Quick Start", body: [
            "1. Click **Connect** (top right) and choose your Ray5's USB serial port.",
            "2. Add artwork with **Import** (SVG, PNG, JPEG, BMP), **Shape**, or the tool rail on the left.",
            "3. Set Power, Speed and Line/Fill mode per layer in the **Job Setup** panel.",
            "4. Use **Home** and the **Camera** tool to position your material.",
            "5. Press **Start** (⇧⌘↩) to send the job, or **Export** (⌘E) to save G-code."
        ]),
        HelpSection(title: "Keyboard Shortcuts", body: [
            "⌘N — New project",
            "⌘Z / ⇧⌘Z — Undo / Redo",
            "⌘E — Export G-code",
            "⇧⌘↩ — Start / pause job",
            "Esc — Close dialogs"
        ]),
        HelpSection(title: "Tips", body: [
            "Left-drag with Select picks every layer the box touches; right-drag picks only fully enclosed layers.",
            "Always test power and speed on scrap material, and wear laser safety eyewear.",
            "If the app can't open the camera, allow access in System Settings ▸ Privacy & Security ▸ Camera.",
            "Open **Help ▸ Instruction Manual** for the full guide."
        ])
    ]

    var body: some View {
        HelpDocument(heading: "LaserStudio Help", subtitle: "Quick reference", sections: sections)
    }
}

/// Full manual shown from Help ▸ Instruction Manual.
struct ManualView: View {
    private let sections: [HelpSection] = [
        HelpSection(title: "1. Introduction", body: [
            "LaserStudio lets you design simple vector and raster artwork, convert it to GRBL G-code, and stream it directly to a Longer Ray5 laser engraver over USB.",
            "The window has a top toolbar, a tool rail (left), the workspace canvas (center), the Job Setup panel (right) and a status bar (bottom)."
        ]),
        HelpSection(title: "2. Connecting the Machine", body: [
            "Plug the Ray5 into your Mac with USB, power it on, then click **Connect**. Choose the serial device and confirm.",
            "When connected, the toolbar shows *Machine connected* and Job Setup shows the S-max value and whether GRBL laser mode is on.",
            "Click **Disconnect** to release the port. If the port is missing, reconnect the cable and click Connect again to refresh the list."
        ]),
        HelpSection(title: "3. Drawing Tools", body: [
            "**Select** — click to select, drag to move; left-drag selects touched layers, right-drag selects fully enclosed layers.",
            "**Node edit** — edit the points of a path.",
            "**Line, Rectangle, Circle** — drag on the canvas to draw.",
            "**Text** — click the workspace to place text; set font, bold and italic in the layer row.",
            "**Pen** — draw freehand paths.",
            "**Measure** — measure distances on the canvas.",
            "**Camera** — opens a live preview to help position designs on your material."
        ]),
        HelpSection(title: "4. Importing Artwork", body: [
            "Click **Import** and choose an SVG, PNG, JPEG or BMP file.",
            "Raster images open in the Image Trace editor, where **Add as Vector Layers** converts them to traced vector layers. Images can also be engraved as shaded rasters.",
            "Use the zoom controls above the canvas and the grid toggle to line things up."
        ]),
        HelpSection(title: "5. Layers", body: [
            "Every object is a layer listed in Job Setup. Use the eye icon to hide a layer, the **Burn/Skip** switch to include or exclude it from the job, and the trash button to delete selected layers.",
            "Select several layers to group or ungroup them from the canvas controls.",
            "With a layer selected, edit its X, Y, width and height (mm) and layer color under *Selected Object*."
        ]),
        HelpSection(title: "6. Power, Speed and Modes", body: [
            "**Line** traces outlines (cutting or scoring). **Fill** hatches the interior using the *Hatch spacing* value under Material.",
            "**Power** is 1–100%. **Speed** is in mm/min (40 up to the Ray5 maximum of 10000).",
            "Image layers use **Min/Max speed**, **Invert**, and **Variable power by image shade** for grayscale engraving.",
            "Material presets (birch plywood, acrylic, MDF, custom) are a starting reference; always test on scrap."
        ]),
        HelpSection(title: "7. Positioning and Homing", body: [
            "**Home** homes the Ray5, then moves to workspace X0 Y0 at the front-left corner. It is available once the machine is connected and its homing setting has loaded.",
            "The bottom bar shows the live laser position in mm. Use the Camera preview to place material under the design."
        ]),
        HelpSection(title: "8. Running a Job", body: [
            "Press **Start** (⇧⌘↩) to stream G-code. While running the button becomes **Pause**; the red stop button cancels the job and clears queued moves.",
            "Use **Export** (⌘E) to save a `.gcode` file instead of sending directly."
        ]),
        HelpSection(title: "9. Projects and Undo", body: [
            "**New** (⌘N) clears the workspace. **Undo** (⌘Z) and **Redo** (⇧⌘Z) step through changes."
        ]),
        HelpSection(title: "10. Safety", body: [
            "Never leave a running laser unattended. Wear certified eye protection, keep a fire extinguisher nearby, ventilate fumes, and never engrave PVC or other materials that release toxic gas.",
            "Keep the Ray5's emergency stop within reach."
        ]),
        HelpSection(title: "11. Troubleshooting", body: [
            "**Can't open the app (unsigned build):** Control-click LaserStudio.app, choose Open, then confirm.",
            "**Machine not listed:** try another cable/port and click Connect again.",
            "**Camera black or denied:** allow access in System Settings ▸ Privacy & Security ▸ Camera.",
            "**Home disabled:** wait for the homing setting to load, connect the machine, and stop any running job.",
            "Report issues at https://github.com/onlyhouse1980/LaserStudio/issues"
        ])
    ]

    var body: some View {
        HelpDocument(heading: "LaserStudio Instruction Manual", subtitle: "Version 1.0", sections: sections)
    }
}
