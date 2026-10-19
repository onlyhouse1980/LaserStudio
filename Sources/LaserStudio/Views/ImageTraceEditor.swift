import SwiftUI
import AppKit

struct ImageTraceEditor: View {
    @Environment(\.dismiss) private var dismiss
    let image: DesignObject
    let onApply: ([DesignObject]) -> Void

    @State private var options: ImageTraceOptions
    @State private var contours: [[CGPoint]] = []

    init(image: DesignObject, onApply: @escaping ([DesignObject]) -> Void) {
        self.image = image
        self.onApply = onApply
        _options = State(initialValue: ImageTraceOptions(inverted: image.imageInverted))
    }

    private var tracedLayers: [DesignObject] {
        ImageTracer.makePathLayers(from: image, contours: contours)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("IMAGE TRACE").font(.system(size: 11, weight: .bold)).tracking(1)
                    Text(image.label).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("\(contours.count) contours · \(tracedLayers.count) vector layers")
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                    if contours.count == ImageTracer.maximumContourCount {
                        Text("Contour limit reached; raise Minimum region to simplify")
                            .font(.system(size: 9)).foregroundStyle(.orange)
                    }
                }
            }
            .padding(.horizontal, 18).padding(.vertical, 13)
            Divider().opacity(0.35)

            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 17) {
                    Text("TRACE PARAMETERS").font(.system(size: 9, weight: .bold)).tracking(0.7).foregroundStyle(.secondary)
                    parameterRow("Threshold", value: $options.threshold, range: 0...255, step: 1, suffix: "")
                    Toggle("Invert selection", isOn: $options.inverted).toggleStyle(.checkbox)
                    parameterRow("Minimum region", value: $options.minimumRegion, range: 1...200, step: 1, suffix: " px")
                    parameterRow("Simplify", value: $options.simplifyTolerance, range: 0...3, step: 0.1, suffix: " px")
                    Text("Dark regions become vector outlines. Raise the threshold to include lighter pixels; increase Minimum region to remove specks.")
                        .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(16)
                .frame(width: 245)
                .frame(maxHeight: .infinity, alignment: .topLeading)

                Divider().opacity(0.35)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("PREVIEW").font(.system(size: 9, weight: .bold)).tracking(0.7).foregroundStyle(.secondary)
                        Spacer()
                        Text("Orange shows traced outlines").font(.system(size: 9)).foregroundStyle(.tertiary)
                    }
                    preview
                        .background(Color.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.1), lineWidth: 1))
                }
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider().opacity(0.35)
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add as Vector Layers") {
                    onApply(tracedLayers)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(tracedLayers.isEmpty)
            }
            .padding(.horizontal, 18).padding(.vertical, 12)
        }
        .frame(minWidth: 760, minHeight: 520)
        .onAppear(perform: updateTrace)
        .onChange(of: options) { _, _ in updateTrace() }
    }

    private var preview: some View {
        GeometryReader { proxy in
            let sourceWidth = CGFloat(max(1, image.imagePixelWidth))
            let sourceHeight = CGFloat(max(1, image.imagePixelHeight))
            let fit = min(proxy.size.width / sourceWidth, proxy.size.height / sourceHeight)
            let drawWidth = sourceWidth * fit
            let drawHeight = sourceHeight * fit
            let origin = CGPoint(x: (proxy.size.width - drawWidth) / 2, y: (proxy.size.height - drawHeight) / 2)
            ZStack {
                if let data = image.imageData, let sourceImage = NSImage(data: data) {
                    Image(nsImage: sourceImage).resizable().interpolation(.high)
                        .frame(width: drawWidth, height: drawHeight)
                        .position(x: origin.x + drawWidth / 2, y: origin.y + drawHeight / 2)
                }
                Canvas { context, _ in
                    for contour in contours {
                        guard let first = contour.first else { continue }
                        var path = Path()
                        path.move(to: CGPoint(x: origin.x + first.x * fit, y: origin.y + first.y * fit))
                        for point in contour.dropFirst() {
                            path.addLine(to: CGPoint(x: origin.x + point.x * fit, y: origin.y + point.y * fit))
                        }
                        path.closeSubpath()
                        context.stroke(path, with: .color(.orange), lineWidth: 1.2)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .clipped()
    }

    private func parameterRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, suffix: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
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
        contours = ImageTracer.trace(image: image, options: options)
    }
}
