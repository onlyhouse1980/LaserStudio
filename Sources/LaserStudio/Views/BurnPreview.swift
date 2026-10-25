import SwiftUI
import Combine

/// One straight machine move parsed from the generated G-code.
struct PreviewSegment {
    var x0: Double, y0: Double   // design space (mm, origin top-left)
    var x1: Double, y1: Double
    var burn: Bool               // laser on while moving
    var feed: Double             // mm/min
    var power: Double            // 0...1
}

/// Parses the exact G-code that would be sent to the machine so the preview matches the real job.
final class BurnPreviewModel {
    static let chunkSize = 256

    private(set) var segments: [PreviewSegment] = []
    private(set) var cumulativeEnd: [Double] = []   // seconds at the end of each segment
    private(set) var plannedBurn = Path()
    private(set) var travel = Path()
    private(set) var burnChunks: [Path] = []
    private(set) var burnLength = 0.0
    private(set) var travelLength = 0.0
    var totalTime: Double { cumulativeEnd.last ?? 0 }

    init(lines: [String], sMax: Int, machine: LaserProfile) {
        let workspace = machine.workspaceHeight
        var x = 0.0, y = 0.0, feed = machine.maxFeedRate, s = 0.0
        var rapid = true, laserOn = false
        var chunk = Path()
        var time = 0.0

        for raw in lines {
            let line = raw.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
            var newX = x, newY = y, moved = false
            for word in line.split(whereSeparator: { $0 == " " || $0 == "\t" }) {
                guard let letter = word.first, let value = Double(word.dropFirst()) else { continue }
                switch letter {
                case "G": if value == 0 { rapid = true } else if value == 1 { rapid = false }
                case "M": if value == 3 || value == 4 { laserOn = true } else if value == 5 { laserOn = false; s = 0 }
                case "X": newX = value; moved = true
                case "Y": newY = value; moved = true
                case "F": feed = value
                case "S": s = value
                default: break
                }
            }
            guard moved, newX != x || newY != y else { x = newX; y = newY; continue }
            let burn = !rapid && laserOn && s > 0
            let speed = rapid ? machine.maxFeedRate : max(1, feed)
            let segment = PreviewSegment(x0: x, y0: workspace - y, x1: newX, y1: workspace - newY,
                                         burn: burn, feed: speed, power: min(1, s / Double(max(1, sMax))))
            let length = hypot(newX - x, newY - y)
            time += length / speed * 60
            segments.append(segment)
            cumulativeEnd.append(time)

            let from = CGPoint(x: segment.x0, y: segment.y0), to = CGPoint(x: segment.x1, y: segment.y1)
            if burn {
                burnLength += length
                plannedBurn.move(to: from); plannedBurn.addLine(to: to)
                chunk.move(to: from); chunk.addLine(to: to)
            } else {
                travelLength += length
                travel.move(to: from); travel.addLine(to: to)
            }
            if segments.count % Self.chunkSize == 0 { burnChunks.append(chunk); chunk = Path() }
            x = newX; y = newY
        }
    }

    /// Index of the segment being executed at `time` (or segments.count when finished).
    func index(at time: Double) -> Int {
        var low = 0, high = cumulativeEnd.count
        while low < high {
            let mid = (low + high) / 2
            if cumulativeEnd[mid] > time { high = mid } else { low = mid + 1 }
        }
        return low
    }

    func segmentStart(_ index: Int) -> Double { index == 0 ? 0 : cumulativeEnd[index - 1] }
}

struct BurnPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    private let model: BurnPreviewModel
    private let machine: LaserProfile
    private let timer = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()

    @State private var time = 0.0
    @State private var playing = true
    @State private var previewSeconds = 20.0
    @State private var showTravel = true
    @State private var showPlanned = true

    init(lines: [String], sMax: Int, machine: LaserProfile) {
        self.machine = machine
        model = BurnPreviewModel(lines: lines, sMax: sMax, machine: machine)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            preview
            Divider().opacity(0.4)
            controls
        }
        .frame(minWidth: 820, minHeight: 760)
        .preferredColorScheme(.dark)
        .onReceive(timer) { _ in
            guard playing, model.totalTime > 0 else { return }
            time += model.totalTime / previewSeconds / 30.0
            if time >= model.totalTime { time = model.totalTime; playing = false }
        }
    }

    private var header: some View {
        HStack(spacing: 18) {
            Label("BURN PREVIEW", systemImage: "flame.fill")
                .font(.system(size: 12, weight: .bold, design: .rounded)).tracking(1.2).foregroundStyle(.orange)
            Spacer()
            stat("Est. time", Self.format(model.totalTime))
            stat("Burn", String(format: "%.0f mm", model.burnLength))
            stat("Travel", String(format: "%.0f mm", model.travelLength))
            stat("Moves", "\(model.segments.count)")
            Button("Close") { dismiss() }.keyboardShortcut(.escape)
        }
        .padding(.horizontal, 18).frame(height: 48)
    }

    private var preview: some View {
        Canvas { context, size in
            let scale = min((size.width - 24) / machine.workspaceWidth, (size.height - 24) / machine.workspaceHeight)
            let boardSize = CGSize(width: machine.workspaceWidth * scale, height: machine.workspaceHeight * scale)
            let origin = CGPoint(x: (size.width - boardSize.width) / 2, y: (size.height - boardSize.height) / 2)
            let board = CGRect(origin: origin, size: boardSize)

            context.fill(Path(roundedRect: board, cornerRadius: 4), with: .color(Color(red: 0.09, green: 0.1, blue: 0.12)))
            // 50 mm grid
            var grid = Path()
            for step in stride(from: 0.0, through: machine.workspaceWidth, by: 50) {
                grid.move(to: CGPoint(x: origin.x + step * scale, y: origin.y))
                grid.addLine(to: CGPoint(x: origin.x + step * scale, y: origin.y + boardSize.height))
            }
            for step in stride(from: 0.0, through: machine.workspaceHeight, by: 50) {
                grid.move(to: CGPoint(x: origin.x, y: origin.y + step * scale))
                grid.addLine(to: CGPoint(x: origin.x + boardSize.width, y: origin.y + step * scale))
            }
            context.stroke(grid, with: .color(.white.opacity(0.07)), lineWidth: 1)
            context.stroke(Path(roundedRect: board, cornerRadius: 4), with: .color(.white.opacity(0.25)), lineWidth: 1)

            var layer = context
            layer.translateBy(x: origin.x, y: origin.y)
            layer.scaleBy(x: scale, y: scale)
            let hairline = max(0.3, 1.2 / scale)

            if showTravel {
                layer.stroke(model.travel, with: .color(.cyan.opacity(0.25)),
                             style: StrokeStyle(lineWidth: hairline, dash: [3 / scale, 3 / scale]))
            }
            if showPlanned {
                layer.stroke(model.plannedBurn, with: .color(.white.opacity(0.18)), lineWidth: hairline)
            }

            // Already burned portion.
            let index = model.index(at: time)
            var burned = Path()
            let fullChunks = min(model.burnChunks.count, index / BurnPreviewModel.chunkSize)
            for chunk in 0..<fullChunks { burned.addPath(model.burnChunks[chunk]) }
            var head = CGPoint(x: model.segments.first?.x0 ?? 0, y: model.segments.first?.y0 ?? 0)
            var laserOn = false
            if index > fullChunks * BurnPreviewModel.chunkSize {
                for i in (fullChunks * BurnPreviewModel.chunkSize)..<min(index, model.segments.count) where model.segments[i].burn {
                    burned.move(to: CGPoint(x: model.segments[i].x0, y: model.segments[i].y0))
                    burned.addLine(to: CGPoint(x: model.segments[i].x1, y: model.segments[i].y1))
                }
            }
            if index < model.segments.count {
                let seg = model.segments[index]
                let start = model.segmentStart(index)
                let span = model.cumulativeEnd[index] - start
                let f = span > 0 ? min(1, max(0, (time - start) / span)) : 1
                head = CGPoint(x: seg.x0 + (seg.x1 - seg.x0) * f, y: seg.y0 + (seg.y1 - seg.y0) * f)
                laserOn = seg.burn
                if seg.burn {
                    burned.move(to: CGPoint(x: seg.x0, y: seg.y0)); burned.addLine(to: head)
                }
            } else if let last = model.segments.last {
                head = CGPoint(x: last.x1, y: last.y1)
            }
            layer.stroke(burned, with: .color(.orange.opacity(0.35)), style: StrokeStyle(lineWidth: hairline * 4, lineCap: .round, lineJoin: .round))
            layer.stroke(burned, with: .color(Color(red: 1, green: 0.55, blue: 0.15)), style: StrokeStyle(lineWidth: hairline * 1.4, lineCap: .round, lineJoin: .round))

            // Laser head.
            let glow = laserOn ? Color.red : Color.green
            let radius = 5 / scale
            layer.fill(Path(ellipseIn: CGRect(x: head.x - radius * 2, y: head.y - radius * 2, width: radius * 4, height: radius * 4)),
                       with: .color(glow.opacity(0.25)))
            layer.fill(Path(ellipseIn: CGRect(x: head.x - radius * 0.6, y: head.y - radius * 0.6, width: radius * 1.2, height: radius * 1.2)),
                       with: .color(laserOn ? .white : glow))
            var cross = Path()
            cross.move(to: CGPoint(x: head.x - radius * 1.8, y: head.y)); cross.addLine(to: CGPoint(x: head.x + radius * 1.8, y: head.y))
            cross.move(to: CGPoint(x: head.x, y: head.y - radius * 1.8)); cross.addLine(to: CGPoint(x: head.x, y: head.y + radius * 1.8))
            layer.stroke(cross, with: .color(glow), lineWidth: hairline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.06, green: 0.07, blue: 0.08))
        .overlay(alignment: .topLeading) { legend.padding(14) }
        .overlay(alignment: .bottomTrailing) { readout.padding(14) }
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 5) {
            legendRow(.orange, "Laser ON (burning)")
            legendRow(.cyan, "Laser OFF (travel move)")
            legendRow(.white.opacity(0.5), "Still to burn")
        }
        .font(.system(size: 10)).padding(9)
        .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 7))
    }

    private var readout: some View {
        let index = model.index(at: time)
        let seg = index < model.segments.count ? model.segments[index] : model.segments.last
        return VStack(alignment: .trailing, spacing: 3) {
            Text(seg.map { $0.burn ? "BURNING" : "TRAVEL" } ?? "—")
                .font(.system(size: 11, weight: .bold)).foregroundStyle(seg?.burn == true ? Color.orange : Color.cyan)
            Text(seg.map { String(format: "Feed %.0f mm/min · Power %.0f%%", $0.feed, $0.burn ? $0.power * 100 : 0) } ?? "")
            Text(String(format: "Move %d / %d", min(index + 1, model.segments.count), model.segments.count))
        }
        .font(.system(size: 10, design: .monospaced)).padding(9)
        .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 7))
    }

    private var controls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Button {
                    if time >= model.totalTime { time = 0 }
                    playing.toggle()
                } label: { Image(systemName: playing ? "pause.fill" : "play.fill").frame(width: 22) }
                    .keyboardShortcut(.space, modifiers: [])
                Button { time = 0; playing = true } label: { Image(systemName: "backward.end.fill") }
                    .help("Restart")
                Slider(value: $time, in: 0...max(0.001, model.totalTime)) { editing in
                    if editing { playing = false }
                }.tint(.orange)
                Text("\(Self.format(time)) / \(Self.format(model.totalTime))")
                    .font(.system(size: 11, design: .monospaced)).frame(width: 130, alignment: .trailing)
            }
            HStack(spacing: 18) {
                Picker("Playback", selection: $previewSeconds) {
                    Text("Slow · 60 s").tag(60.0)
                    Text("Normal · 20 s").tag(20.0)
                    Text("Fast · 8 s").tag(8.0)
                    Text("Very fast · 3 s").tag(3.0)
                }.pickerStyle(.menu).frame(width: 190)
                Toggle("Show travel moves", isOn: $showTravel).toggleStyle(.checkbox)
                Toggle("Show planned burn", isOn: $showPlanned).toggleStyle(.checkbox)
                Spacer()
                Text("Preview of the exact G-code. Time is an estimate; it ignores acceleration.")
                    .font(.system(size: 9)).foregroundStyle(.secondary)
            }.font(.system(size: 11))
        }
        .buttonStyle(.borderless).padding(14)
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(title.uppercased()).font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 11, design: .monospaced))
        }
    }

    private func legendRow(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 1).fill(color).frame(width: 16, height: 3)
            Text(text)
        }
    }

    private static func format(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
