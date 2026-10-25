import SwiftUI
import AppKit

struct ImageTraceEditor: View {
    @Environment(\.dismiss) private var dismiss
    let image: DesignObject
    let onApplyWithDelete: ([DesignObject], Bool) -> Void

    @State private var options: ImageTraceOptions
    @State private var contours: [[CGPoint]] = []
    @State private var zoomScale: Double = 1.0
    @State private var cropDragStart: CGPoint?
    @State private var cropDragCurrent: CGPoint?

    init(image: DesignObject, onApply: @escaping ([DesignObject], Bool) -> Void) {
        self.image = image
        self.onApplyWithDelete = onApply
        _options = State(initialValue: ImageTraceOptions(inverted: image.imageInverted))
    }

    init(image: DesignObject, onApply: @escaping ([DesignObject]) -> Void) {
        self.image = image
        self.onApplyWithDelete = { layers, _ in onApply(layers) }
        _options = State(initialValue: ImageTraceOptions(inverted: image.imageInverted))
    }

    private var tracedLayers: [DesignObject] {
        ImageTracer.makePathLayers(
            from: image,
            contours: contours,
            combineIntoCompoundPath: options.combineIntoCompoundPath
        )
    }

    private var totalPointCount: Int {
        contours.reduce(0) { $0 + $1.count }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("TRACE IMAGE (LIGHTBURN TRACE)").font(.system(size: 11, weight: .bold)).tracking(1)
                    Text("\(image.label) · Drag on preview to trace a sub-region").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 8) {
                    Button { zoomScale = max(0.05, zoomScale / 1.25) } label: { Image(systemName: "minus.magnifyingglass") }
                    Text("\((zoomScale * 100).formatted(.number.precision(.fractionLength(0))))%")
                        .font(.system(size: 10, design: .monospaced))
                        .frame(minWidth: 48)
                    Button { zoomScale = zoomScale * 1.25 } label: { Image(systemName: "plus.magnifyingglass") }
                    Button("Fit") { zoomScale = 1.0 }
                    if options.cropNormalizedRect != nil {
                        Button("Clear Boundary") {
                            options.cropNormalizedRect = nil
                        }
                        .foregroundStyle(.orange)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("\(contours.count) contours · \(totalPointCount) points")
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                    if contours.count == ImageTracer.maximumContourCount {
                        Text("Contour limit reached; raise Ignore Less Than")
                            .font(.system(size: 9)).foregroundStyle(.orange)
                    }
                }
            }
            .padding(.horizontal, 18).padding(.vertical, 12)
            Divider().opacity(0.35)

            HStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("TRACE PARAMETERS").font(.system(size: 9, weight: .bold)).tracking(0.7).foregroundStyle(.secondary)

                        Toggle("Sketch Trace (Edge Detect)", isOn: $options.sketchTrace)
                            .toggleStyle(.checkbox)

                        if !options.sketchTrace {
                            parameterRow("Cutoff (Low)", value: $options.cutoff, range: 0...254, step: 1, suffix: "")
                        }
                        parameterRow("Threshold (High)", value: $options.threshold, range: 1...255, step: 1, suffix: "")

                        Divider().opacity(0.25)

                        parameterRow("Ignore Less Than", value: $options.minimumRegion, range: 0...200, step: 1, suffix: " px")
                        parameterRow("Smoothness", value: $options.smoothness, range: 0...2.0, step: 0.1, suffix: "")
                        parameterRow("Optimize", value: $options.simplifyTolerance, range: 0...3.0, step: 0.1, suffix: " px")

                        Divider().opacity(0.25)

                        Text("DISPLAY & OUTPUT").font(.system(size: 9, weight: .bold)).tracking(0.7).foregroundStyle(.secondary)
                        Toggle("Fade Image", isOn: $options.fadeImage).toggleStyle(.checkbox)
                        Toggle("Show Points (Nodes)", isOn: $options.showPoints).toggleStyle(.checkbox)
                        Toggle("Invert Selection", isOn: $options.inverted).toggleStyle(.checkbox)
                        Toggle("Compound Path (Keep Holes)", isOn: $options.combineIntoCompoundPath).toggleStyle(.checkbox)
                        Toggle("Delete image after trace", isOn: $options.deleteImageAfterTrace).toggleStyle(.checkbox)

                        Text("Purple lines show the traced vectors. Yellow squares show path nodes when Show Points is active. Drag a box over the image to restrict tracing to that region.")
                            .font(.system(size: 9.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16)
                }
                .frame(width: 265)
                .frame(maxHeight: .infinity, alignment: .topLeading)

                Divider().opacity(0.35)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("PREVIEW").font(.system(size: 9, weight: .bold)).tracking(0.7).foregroundStyle(.secondary)
                        Spacer()
                        Text("Purple = traced vectors · Drag to set outer boundary").font(.system(size: 9)).foregroundStyle(.tertiary)
                    }
                    preview
                        .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.1), lineWidth: 1))
                }
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider().opacity(0.35)
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("OK") {
                    onApplyWithDelete(tracedLayers, options.deleteImageAfterTrace)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(tracedLayers.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 18).padding(.vertical, 12)
        }
        .frame(minWidth: 820, minHeight: 560)
        .onAppear(perform: updateTrace)
        .onChange(of: options) { _, _ in updateTrace() }
    }

    private var preview: some View {
        GeometryReader { proxy in
            let sourceWidth = CGFloat(max(1, image.imagePixelWidth))
            let sourceHeight = CGFloat(max(1, image.imagePixelHeight))
            let fit = min(proxy.size.width / sourceWidth, proxy.size.height / sourceHeight) * CGFloat(zoomScale)
            let drawWidth = sourceWidth * fit
            let drawHeight = sourceHeight * fit
            let origin = CGPoint(x: (proxy.size.width - drawWidth) / 2, y: (proxy.size.height - drawHeight) / 2)
            ZStack {
                if let data = image.imageData, let sourceImage = NSImage(data: data) {
                    Image(nsImage: sourceImage).resizable().interpolation(.high)
                        .opacity(options.fadeImage ? 0.35 : 1.0)
                        .frame(width: drawWidth, height: drawHeight)
                        .position(x: origin.x + drawWidth / 2, y: origin.y + drawHeight / 2)
                }
                Canvas { context, _ in
                    if let crop = options.cropNormalizedRect {
                        let rect = CGRect(
                            x: origin.x + crop.minX * drawWidth,
                            y: origin.y + crop.minY * drawHeight,
                            width: crop.width * drawWidth,
                            height: crop.height * drawHeight
                        )
                        context.stroke(Path(rect), with: .color(.cyan), style: StrokeStyle(lineWidth: 1.2, dash: [5, 3]))
                    }
                    if let start = cropDragStart, let end = cropDragCurrent {
                        let rect = CGRect(
                            x: min(start.x, end.x),
                            y: min(start.y, end.y),
                            width: abs(end.x - start.x),
                            height: abs(end.y - start.y)
                        )
                        context.stroke(Path(rect), with: .color(.orange), style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                    }
                    let traceColor = Color(red: 0.88, green: 0.18, blue: 0.96)
                    for contour in contours {
                        guard let first = contour.first else { continue }
                        var path = Path()
                        path.move(to: CGPoint(x: origin.x + first.x * fit, y: origin.y + first.y * fit))
                        for point in contour.dropFirst() {
                            path.addLine(to: CGPoint(x: origin.x + point.x * fit, y: origin.y + point.y * fit))
                        }
                        path.closeSubpath()
                        context.stroke(path, with: .color(traceColor), lineWidth: 1.35)
                        if options.showPoints {
                            for point in contour {
                                let px = origin.x + point.x * fit
                                let py = origin.y + point.y * fit
                                let nodeRect = CGRect(x: px - 2.2, y: py - 2.2, width: 4.4, height: 4.4)
                                context.fill(Path(nodeRect), with: .color(.yellow))
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        cropDragStart = value.startLocation
                        cropDragCurrent = value.location
                    }
                    .onEnded { value in
                        defer {
                            cropDragStart = nil
                            cropDragCurrent = nil
                        }
                        guard drawWidth > 1, drawHeight > 1 else { return }
                        let x0 = max(0, min(1, (min(value.startLocation.x, value.location.x) - origin.x) / drawWidth))
                        let y0 = max(0, min(1, (min(value.startLocation.y, value.location.y) - origin.y) / drawHeight))
                        let x1 = max(0, min(1, (max(value.startLocation.x, value.location.x) - origin.x) / drawWidth))
                        let y1 = max(0, min(1, (max(value.startLocation.y, value.location.y) - origin.y) / drawHeight))
                        if x1 - x0 > 0.02 && y1 - y0 > 0.02 {
                            options.cropNormalizedRect = CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
                        }
                    }
            )
        }
        .clipped()
    }

    private func parameterRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, suffix: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.system(size: 10, weight: .medium))
                Spacer()
                Text("\(value.wrappedValue.formatted(.number.precision(.fractionLength(step < 1 ? 2 : 0))))\(suffix)")
                    .font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step).tint(.orange)
        }
    }

    private func updateTrace() {
        if options.cutoff >= options.threshold {
            options.cutoff = max(0, options.threshold - 1)
        }
        contours = ImageTracer.trace(image: image, options: options)
    }
}
