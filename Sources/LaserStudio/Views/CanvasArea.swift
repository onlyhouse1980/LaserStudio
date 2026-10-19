import SwiftUI
import AppKit

struct CanvasArea: View {
    @Binding var objects: [DesignObject]
    @Binding var selection: UUID?
    @Binding var selectedIDs: Set<UUID>
    var showGrid: Bool
    var zoom: Double
    @Binding var activeTool: String
    @Binding var status: String

    @State private var dragStart: CGPoint?
    @State private var draftPoints: [CGPoint] = []
    @State private var interaction: Interaction?
    @State private var initialFrame: CGRect?
    @State private var initialPathPoints: [CGPoint] = []
    @State private var initialTransforms: [UUID: LayerTransform] = [:]
    @State private var pointerStart: CGPoint?
    @State private var hoverLocation: CGPoint?
    @State private var initialPointerAngle: Double?
    @State private var initialGroupCenter: CGPoint?
    @State private var initialGroupBounds: CGRect?
    @State private var marqueeStart: CGPoint?
    @State private var marqueeEnd: CGPoint?
    @State private var rightClickTargetID: UUID?
    @State private var contextMenuImageID: UUID?
    @State private var contextMenuLocation = CGPoint.zero
    @State private var showingImageContextMenu = false
    @State private var traceEditorImage: DesignObject?

    private enum ResizeHandle: CaseIterable {
        case topLeft, topRight, bottomLeft, bottomRight
        var u: Double { self == .topLeft || self == .bottomLeft ? 0 : 1 }
        var v: Double { self == .topLeft || self == .topRight ? 0 : 1 }
    }
    private enum Interaction {
        case move(Set<UUID>)
        case resize(UUID, ResizeHandle)
        case resizeGroup(Set<UUID>, ResizeHandle)
        case rotate(Set<UUID>)
        case marquee(fullyContained: Bool)
        case contextClick
        case draw
        case measure
        case none
    }
    private struct LayerTransform {
        var x: Double
        var y: Double
        var width: Double
        var height: Double
        var rotation: Double
        var pathPoints: [CGPoint]
    }

    var body: some View {
        GeometryReader { proxy in
            let scale = min(proxy.size.width / 520, proxy.size.height / 480) * zoom
            let origin = CGPoint(x: (proxy.size.width - 400 * scale) / 2, y: (proxy.size.height - 400 * scale) / 2)
            let activeSelection = selectedIDs.isEmpty ? Set(selection.map { [$0] } ?? []) : selectedIDs
            let selectedObjects = objects.filter { activeSelection.contains($0.id) }
            let selectedObject = selectedObjects.count == 1 ? selectedObjects.first : nil
            let groupBounds = bounds(for: selectedObjects)
            let hoveredRotationCorner = groupBounds.flatMap { bounds in
                ResizeHandle.allCases.first { handle in
                    guard let hoverLocation else { return false }
                    let corner = selectionCorner(bounds, handle: handle, scale: scale, origin: origin)
                    let rotatePoint = rotationHandlePosition(bounds, handle: handle, scale: scale, origin: origin)
                    return distance(hoverLocation, corner) <= 26 || distance(hoverLocation, rotatePoint) <= 12
                }
            }
            ZStack(alignment: .topLeading) {
                if showGrid { grid(origin: origin, scale: scale).allowsHitTesting(false) }
                Rectangle().stroke(Color.white.opacity(0.23), lineWidth: 1)
                    .frame(width: 400 * scale, height: 400 * scale)
                    .position(x: origin.x + 200 * scale, y: origin.y + 200 * scale)
                    .allowsHitTesting(false)
                Text("400 × 400 mm").font(.system(size: 9, design: .monospaced)).foregroundStyle(.white.opacity(0.35))
                    .position(x: origin.x + 200 * scale, y: origin.y + 400 * scale + 14).allowsHitTesting(false)
                ForEach(objects) { object in
                    if object.isVisible {
                        shape(object, scale: scale)
                            .frame(width: max(12, object.width * scale), height: max(12, object.height * scale))
                            .rotationEffect(.degrees(object.rotation))
                            .position(x: origin.x + (object.x + object.width / 2) * scale,
                                      y: origin.y + (object.y + object.height / 2) * scale)
                            .allowsHitTesting(false)
                    }
                }
                if selectedObjects.count > 1, let bounds = groupBounds {
                    Rectangle().stroke(Color.orange.opacity(0.8), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .frame(width: bounds.width * scale, height: bounds.height * scale)
                        .position(x: origin.x + bounds.midX * scale, y: origin.y + bounds.midY * scale)
                        .allowsHitTesting(false)
                    ForEach(ResizeHandle.allCases, id: \.self) { handle in
                        Rectangle().fill(.white).frame(width: 14, height: 14)
                            .overlay(Rectangle().stroke(Color.orange, lineWidth: 1.5))
                            .position(selectionCorner(bounds, handle: handle, scale: scale, origin: origin))
                            .allowsHitTesting(false)
                    }
                }
                if let object = selectedObject, object.isVisible {
                    ForEach(ResizeHandle.allCases, id: \.self) { handle in
                        Rectangle().fill(.white).frame(width: 14, height: 14)
                            .overlay(Rectangle().stroke(Color.orange, lineWidth: 1.5))
                            .position(cornerPosition(object, handle: handle, scale: scale, origin: origin))
                            .allowsHitTesting(false)
                    }
                }
                if let bounds = groupBounds, let handle = hoveredRotationCorner {
                    Circle().fill(Color.black.opacity(0.9)).frame(width: 24, height: 24)
                        .overlay(Circle().stroke(Color.orange, lineWidth: 1.5))
                        .overlay(Image(systemName: "rotate.right").font(.system(size: 12, weight: .bold)).foregroundStyle(.orange))
                        .position(rotationHandlePosition(bounds, handle: handle, scale: scale, origin: origin))
                        .allowsHitTesting(false)
                }
                if draftPoints.count > 1 {
                    Path { path in
                        path.move(to: CGPoint(x: origin.x + draftPoints[0].x * scale, y: origin.y + draftPoints[0].y * scale))
                        for point in draftPoints.dropFirst() {
                            path.addLine(to: CGPoint(x: origin.x + point.x * scale, y: origin.y + point.y * scale))
                        }
                    }.stroke(.orange, style: StrokeStyle(lineWidth: 1.5, dash: activeTool == "Measure" ? [4, 3] : []))
                        .allowsHitTesting(false)
                }
                if case .marquee(let fullyContained) = interaction,
                   let start = marqueeStart, let end = marqueeEnd {
                    let box = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                                     width: abs(end.x - start.x), height: abs(end.y - start.y))
                    let color: Color = fullyContained ? .cyan : .orange
                    Rectangle().fill(color.opacity(0.12))
                        .overlay(Rectangle().stroke(color, style: StrokeStyle(lineWidth: 1.2, dash: [5, 3])))
                        .frame(width: max(1, box.width * scale), height: max(1, box.height * scale))
                        .position(x: origin.x + box.midX * scale, y: origin.y + box.midY * scale)
                        .allowsHitTesting(false)
                }
                CanvasMouseInput(
                    onMove: { hoverLocation = $0 },
                    onDown: { location, button in
                        pointerStart = location
                        beginInteraction(at: location, button: button, scale: scale, origin: origin)
                    },
                    onDrag: { current in
                        guard let start = pointerStart else { return }
                        updateInteraction(translation: CGSize(width: current.x - start.x, height: current.y - start.y),
                                          location: current, scale: scale, origin: origin)
                    },
                    onUp: { current in
                        guard let start = pointerStart else { return }
                        let translation = CGSize(width: current.x - start.x, height: current.y - start.y)
                        updateInteraction(translation: translation, location: current, scale: scale, origin: origin)
                        finishInteraction(at: current, scale: scale, origin: origin)
                        pointerStart = nil
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                if showingImageContextMenu {
                    VStack(alignment: .leading, spacing: 0) {
                        let ids = selectedLayerIDs()
                        if ids.count > 1 {
                            Button(action: groupSelectedLayers) {
                                Label("Group Layers", systemImage: "square.3.layers.3d")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 10).padding(.vertical, 8)
                            if objects.contains(where: { ids.contains($0.id) && $0.groupID != nil }) {
                                Button(action: ungroupSelectedLayers) {
                                    Label("Ungroup Layers", systemImage: "square.3.layers.3d.down.right")
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal, 10).padding(.vertical, 8)
                            }
                        }
                        if let image = objects.first(where: { $0.id == contextMenuImageID && $0.kind == .image }) {
                            Button {
                                traceEditorImage = image
                                showingImageContextMenu = false
                            } label: {
                                Label("Trace Image…", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 10).padding(.vertical, 8)
                        }
                    }
                    .frame(width: 165)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.16), lineWidth: 1))
                    .position(x: min(proxy.size.width - 78, max(78, contextMenuLocation.x + 76)),
                              y: min(proxy.size.height - 22, max(22, contextMenuLocation.y + 22)))
                    .zIndex(2)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .clipped()
        .sheet(item: $traceEditorImage) { image in
            ImageTraceEditor(image: image) { tracedLayers in
                guard !tracedLayers.isEmpty else { return }
                objects.append(contentsOf: tracedLayers)
                selectedIDs = Set(tracedLayers.map(\.id))
                selection = tracedLayers.first?.id
                status = "Traced image into \(tracedLayers.count) vector layer\(tracedLayers.count == 1 ? "" : "s")"
            }
            .frame(width: 900, height: 620)
        }
    }

    private func beginInteraction(at location: CGPoint, button: CanvasMouseButton, scale: Double, origin: CGPoint) {
        guard scale > 0 else { interaction = Interaction.none; return }
        showingImageContextMenu = false
        rightClickTargetID = nil
        let point = workspacePoint(location, scale: scale, origin: origin)
        if button == .right {
            let objectHit = objects.reversed().first { object in
                object.isVisible && contains(point, in: object)
            }
            rightClickTargetID = objectHit?.id
            if let objectHit, !selectedLayerIDs().contains(objectHit.id) { selectObject(objectHit) }
            if activeTool == "Select" {
                dragStart = point
                marqueeStart = point
                marqueeEnd = point
                interaction = .marquee(fullyContained: true)
            } else {
                interaction = objectHit == nil ? Interaction.none : .contextClick
            }
            return
        }
        guard button == .left else { interaction = Interaction.none; return }
        let currentSelection = selectedIDs.isEmpty ? Set(selection.map { [$0] } ?? []) : selectedIDs
        let currentObjects = objects.filter { currentSelection.contains($0.id) }
        if let bounds = bounds(for: currentObjects), !currentObjects.isEmpty {
            if ResizeHandle.allCases.contains(where: {
                distance(location, rotationHandlePosition(bounds, handle: $0, scale: scale, origin: origin)) <= 13
            }) {
                interaction = .rotate(currentSelection)
                initialTransforms = transforms(for: currentSelection)
                let center = CGPoint(x: origin.x + bounds.midX * scale, y: origin.y + bounds.midY * scale)
                initialGroupCenter = CGPoint(x: bounds.midX, y: bounds.midY)
                initialPointerAngle = atan2(location.y - center.y, location.x - center.x)
                return
            }
            if currentObjects.count > 1,
               let handle = ResizeHandle.allCases.first(where: {
                   distance(location, selectionCorner(bounds, handle: $0, scale: scale, origin: origin)) <= 11
               }) {
                interaction = .resizeGroup(currentSelection, handle)
                initialTransforms = transforms(for: currentSelection)
                initialGroupBounds = bounds
                return
            }
        }
        if currentObjects.count == 1, let selected = currentObjects.first?.id, let object = currentObjects.first {
            if let handle = ResizeHandle.allCases.first(where: { handle in
                distance(location, cornerPosition(object, handle: handle, scale: scale, origin: origin)) <= 11
            }) {
                interaction = .resize(selected, handle)
                initialFrame = CGRect(x: object.x, y: object.y, width: object.width, height: object.height)
                initialPathPoints = object.pathPoints
                return
            }
        }
        switch activeTool {
        case "Select", "Node edit":
            if let hit = objects.reversed().first(where: { object in
                guard object.isVisible else { return false }
                let rect = CGRect(x: object.x, y: object.y, width: max(object.width, 12 / scale), height: max(object.height, 12 / scale))
                return rect.insetBy(dx: -7 / scale, dy: -7 / scale).contains(unrotatedPoint(point, for: object))
            }) {
                selectObject(hit)
                let movingIDs = selectedIDs
                interaction = .move(movingIDs)
                initialFrame = CGRect(x: hit.x, y: hit.y, width: hit.width, height: hit.height)
                initialPathPoints = hit.pathPoints
                initialTransforms = transforms(for: movingIDs)
            } else {
                selection = nil
                selectedIDs = []
                if activeTool == "Select" {
                    dragStart = point
                    marqueeStart = point
                    marqueeEnd = point
                    interaction = .marquee(fullyContained: false)
                } else {
                    interaction = Interaction.none
                }
            }
        case "Measure":
            dragStart = point; draftPoints = [point]; interaction = .measure
        default:
            dragStart = point; draftPoints = [point]; interaction = .draw
        }
    }

    private func updateInteraction(translation: CGSize, location: CGPoint, scale: Double, origin: CGPoint) {
        guard scale > 0 else { return }
        let dx = Double(translation.width) / scale, dy = Double(translation.height) / scale
        switch interaction {
        case .move(let ids):
            guard let initialBounds = bounds(for: initialTransforms) else { return }
            let appliedDX = min(400 - initialBounds.maxX, max(-initialBounds.minX, dx))
            let appliedDY = min(400 - initialBounds.maxY, max(-initialBounds.minY, dy))
            var changed = objects
            for index in changed.indices where ids.contains(changed[index].id) {
                guard let original = initialTransforms[changed[index].id] else { continue }
                changed[index].x = original.x + appliedDX
                changed[index].y = original.y + appliedDY
            }
            objects = changed
            status = ids.count > 1 ? "Moving \(ids.count) layers" : "Moving layer"
        case .resize(let id, let handle):
            resize(id: id, handle: handle, dx: dx, dy: dy)
        case .resizeGroup(let ids, let handle):
            resizeGroup(ids: ids, handle: handle, dx: dx, dy: dy)
        case .rotate(let ids):
            guard let startAngle = initialPointerAngle, let groupCenter = initialGroupCenter else { return }
            let center = CGPoint(x: origin.x + groupCenter.x * scale, y: origin.y + groupCenter.y * scale)
            let currentAngle = atan2(location.y - center.y, location.x - center.x)
            let delta = atan2(sin(currentAngle - startAngle), cos(currentAngle - startAngle))
            let degrees = delta * 180 / .pi
            var changed = objects
            for index in changed.indices where ids.contains(changed[index].id) {
                guard let original = initialTransforms[changed[index].id] else { continue }
                let originalCenter = CGPoint(x: original.x + original.width / 2, y: original.y + original.height / 2)
                let rotatedCenter = rotatePoint(originalCenter, around: groupCenter, degrees: degrees)
                changed[index].x = rotatedCenter.x - original.width / 2
                changed[index].y = rotatedCenter.y - original.height / 2
                changed[index].rotation = original.rotation + degrees
            }
            if let rotatedBounds = bounds(for: transforms(for: ids, from: changed)) {
                let shiftX = rotatedBounds.width > 400 ? -rotatedBounds.minX : (rotatedBounds.minX < 0 ? -rotatedBounds.minX : (rotatedBounds.maxX > 400 ? 400 - rotatedBounds.maxX : 0))
                let shiftY = rotatedBounds.height > 400 ? -rotatedBounds.minY : (rotatedBounds.minY < 0 ? -rotatedBounds.minY : (rotatedBounds.maxY > 400 ? 400 - rotatedBounds.maxY : 0))
                for index in changed.indices where ids.contains(changed[index].id) {
                    changed[index].x += shiftX
                    changed[index].y += shiftY
                }
            }
            objects = changed
            status = ids.count > 1 ? String(format: "Rotating %d layers · %.0f°", ids.count, degrees) : String(format: "Rotating layer · %.0f°", degrees)
        case .marquee:
            let point = workspacePoint(location, scale: scale, origin: origin)
            marqueeEnd = point
        case .contextClick:
            break
        case .draw, .measure:
            guard let start = dragStart else { return }
            let point = workspacePoint(location, scale: scale, origin: origin)
            if activeTool == "Pen" {
                if let last = draftPoints.last, hypot(point.x - last.x, point.y - last.y) > 1 { draftPoints.append(point) }
            } else if activeTool == "Measure" { draftPoints = [start, point] }
            else if draftPoints.count == 1 { draftPoints.append(point) }
            else { draftPoints[1] = point }
        case nil, .some(.none): break
        }
    }

    private func finishInteraction(at location: CGPoint, scale: Double, origin: CGPoint) {
        defer { interaction = nil; initialFrame = nil; initialPathPoints = []; initialTransforms = [:]; initialPointerAngle = nil; initialGroupCenter = nil; initialGroupBounds = nil; dragStart = nil; draftPoints = []; marqueeStart = nil; marqueeEnd = nil; rightClickTargetID = nil }
        if case .contextClick = interaction {
            if let pointerStart, hypot(location.x - pointerStart.x, location.y - pointerStart.y) < 3,
               selectedLayerIDs().count > 1 ||
                rightClickTargetID.flatMap({ id in objects.first(where: { $0.id == id && $0.kind == .image }) }) != nil {
                contextMenuImageID = rightClickTargetID.flatMap { id in
                    objects.first(where: { $0.id == id && $0.kind == .image })?.id
                }
                contextMenuLocation = location
                showingImageContextMenu = true
            }
            return
        }
        if case .marquee(let fullyContained) = interaction, let start = dragStart {
            let end = workspacePoint(location, scale: scale, origin: origin)
            if let pointerStart, hypot(location.x - pointerStart.x, location.y - pointerStart.y) >= 3 {
                selectLayers(from: start, to: end, fullyContained: fullyContained)
            } else if fullyContained,
                      selectedLayerIDs().count > 1 ||
                        rightClickTargetID.flatMap({ id in objects.first(where: { $0.id == id && $0.kind == .image }) }) != nil {
                contextMenuImageID = rightClickTargetID.flatMap { id in
                    objects.first(where: { $0.id == id && $0.kind == .image })?.id
                }
                contextMenuLocation = location
                showingImageContextMenu = true
            } else if !fullyContained {
                selection = nil; selectedIDs = []
            }
            return
        }
        if case .move(let ids) = interaction {
            status = ids.count > 1 ? "Moved \(ids.count) layers" : "Moved layer"
            return
        }
        if case .resize(let id, _) = interaction, let item = objects.first(where: { $0.id == id }) {
            if let start = pointerStart, initialFrame != nil {
                resize(id: id, handle: interactionResizeHandle, dx: (location.x - start.x) / scale, dy: (location.y - start.y) / scale)
            }
            let resized = objects.first(where: { $0.id == id }) ?? item
            status = String(format: "Resized object to %.1f × %.1f mm", resized.width, resized.height)
            return
        }
        if case .resizeGroup(let ids, _) = interaction {
            status = "Resized \(ids.count) layers"
            return
        }
        if case .rotate(let ids) = interaction {
            status = ids.count > 1 ? "Rotated \(ids.count) layers" : "Rotated layer"
            return
        }
        guard case .draw = interaction, let start = dragStart else {
            if case .measure = interaction, let start = dragStart {
                let end = workspacePoint(location, scale: scale, origin: origin)
                status = String(format: "Measured %.1f mm", hypot(end.x - start.x, end.y - start.y))
            }
            return
        }
        let end = workspacePoint(location, scale: scale, origin: origin)
        let left = min(start.x, end.x), top = min(start.y, end.y)
        let width = max(1, abs(end.x - start.x)), height = max(1, abs(end.y - start.y))
        switch activeTool {
        case "Text":
            let item = DesignObject(kind: .text, x: min(398, max(0, start.x)), y: min(398, max(0, start.y)), width: 100, height: 24, label: "New text", color: .green)
            objects.append(item); selection = item.id; activeTool = "Select"; status = "Placed text · Select tool active"
        case "Rectangle", "Circle":
            let kind: DesignObject.Kind = activeTool == "Rectangle" ? .rectangle : .circle
            let item = DesignObject(kind: kind, x: left, y: top, width: width, height: height,
                                    label: "\(kind.rawValue) \(objects.count + 1)", color: kind == .rectangle ? .red : .blue)
            objects.append(item); selection = item.id; activeTool = "Select"; status = "Added \(kind.rawValue.lowercased()) · Select tool active"
        case "Line":
            let points = [start, end].map { CGPoint(x: $0.x - left, y: $0.y - top) }
            let item = DesignObject(kind: .path, x: left, y: top, width: width, height: height,
                                    label: "Line \(objects.count + 1)", pathPoints: points)
            objects.append(item); selection = item.id; activeTool = "Select"; status = "Added line · Select tool active"
        case "Pen":
            let points = (draftPoints + [end]).map { CGPoint(x: $0.x - left, y: $0.y - top) }
            let item = DesignObject(kind: .path, x: left, y: top, width: width, height: height,
                                    label: "Pen path \(objects.count + 1)", pathPoints: points)
            objects.append(item); selection = item.id; activeTool = "Select"; status = "Added pen path · Select tool active"
        default: break
        }
    }

    private func resize(id: UUID, handle: ResizeHandle, dx: Double, dy: Double) {
        guard let frame = initialFrame, let index = objects.firstIndex(where: { $0.id == id }) else { return }
        let minSize = 2.0
        let left: Double, right: Double, top: Double, bottom: Double
        if handle.u == 0 { right = frame.maxX; left = min(right - minSize, max(0, frame.minX + dx)) }
        else { left = frame.minX; right = max(left + minSize, min(400, frame.maxX + dx)) }
        if handle.v == 0 { bottom = frame.maxY; top = min(bottom - minSize, max(0, frame.minY + dy)) }
        else { top = frame.minY; bottom = max(top + minSize, min(400, frame.maxY + dy)) }
        let width = right - left, height = bottom - top
        var changed = objects
        changed[index].x = left; changed[index].y = top; changed[index].width = width; changed[index].height = height
        if !initialPathPoints.isEmpty, frame.width > 0, frame.height > 0 {
            changed[index].pathPoints = initialPathPoints.map { CGPoint(x: $0.x * width / frame.width, y: $0.y * height / frame.height) }
        }
        objects = changed
    }

    private func resizeGroup(ids: Set<UUID>, handle: ResizeHandle, dx: Double, dy: Double) {
        guard let bounds = initialGroupBounds, bounds.width > 0, bounds.height > 0 else { return }
        let movingX = handle.u == 0
            ? min(Double(bounds.maxX) - 2, max(0, Double(bounds.minX) + dx))
            : max(Double(bounds.minX) + 2, min(400, Double(bounds.maxX) + dx))
        let movingY = handle.v == 0
            ? min(Double(bounds.maxY) - 2, max(0, Double(bounds.minY) + dy))
            : max(Double(bounds.minY) + 2, min(400, Double(bounds.maxY) + dy))
        let fixedX = handle.u == 0 ? Double(bounds.maxX) : Double(bounds.minX)
        let fixedY = handle.v == 0 ? Double(bounds.maxY) : Double(bounds.minY)
        var scaleX = handle.u == 0 ? (fixedX - movingX) / Double(bounds.width) : (movingX - fixedX) / Double(bounds.width)
        var scaleY = handle.v == 0 ? (fixedY - movingY) / Double(bounds.height) : (movingY - fixedY) / Double(bounds.height)
        let minimumScaleX = initialTransforms.values.map { 2 / max(2, $0.width) }.max() ?? 0.01
        let minimumScaleY = initialTransforms.values.map { 2 / max(2, $0.height) }.max() ?? 0.01
        scaleX = max(minimumScaleX, scaleX)
        scaleY = max(minimumScaleY, scaleY)

        var changed = objects
        for index in changed.indices where ids.contains(changed[index].id) {
            guard let original = initialTransforms[changed[index].id] else { continue }
            let pivotX = handle.u == 0 ? Double(bounds.maxX) : Double(bounds.minX)
            let pivotY = handle.v == 0 ? Double(bounds.maxY) : Double(bounds.minY)
            let originalCenterX = original.x + original.width / 2
            let originalCenterY = original.y + original.height / 2
            let width = max(2, original.width * scaleX)
            let height = max(2, original.height * scaleY)
            let centerX = pivotX + (originalCenterX - pivotX) * scaleX
            let centerY = pivotY + (originalCenterY - pivotY) * scaleY
            changed[index].x = centerX - width / 2
            changed[index].y = centerY - height / 2
            changed[index].width = width
            changed[index].height = height
            changed[index].pathPoints = original.pathPoints.map { CGPoint(x: $0.x * scaleX, y: $0.y * scaleY) }
        }
        objects = changed
    }

    private var interactionResizeHandle: ResizeHandle {
        if case .resize(_, let handle) = interaction { return handle }
        return .bottomRight
    }

    private func cornerPosition(_ object: DesignObject, handle: ResizeHandle, scale: Double, origin: CGPoint) -> CGPoint {
        let center = CGPoint(x: object.x + object.width / 2, y: object.y + object.height / 2)
        let unrotated = CGPoint(x: object.x + object.width * handle.u,
                                y: object.y + object.height * handle.v)
        let radians = object.rotation * .pi / 180
        let dx = unrotated.x - center.x, dy = unrotated.y - center.y
        let rotated = CGPoint(x: center.x + dx * cos(radians) - dy * sin(radians),
                              y: center.y + dx * sin(radians) + dy * cos(radians))
        return CGPoint(x: origin.x + rotated.x * scale, y: origin.y + rotated.y * scale)
    }

    private func selectionCorner(_ bounds: CGRect, handle: ResizeHandle, scale: Double, origin: CGPoint) -> CGPoint {
        CGPoint(x: origin.x + (Double(bounds.minX) + Double(bounds.width) * handle.u) * scale,
                y: origin.y + (Double(bounds.minY) + Double(bounds.height) * handle.v) * scale)
    }

    private func rotationHandlePosition(_ bounds: CGRect, handle: ResizeHandle, scale: Double, origin: CGPoint) -> CGPoint {
        let corner = selectionCorner(bounds, handle: handle, scale: scale, origin: origin)
        let center = CGPoint(x: origin.x + Double(bounds.midX) * scale,
                             y: origin.y + Double(bounds.midY) * scale)
        let dx = corner.x - center.x, dy = corner.y - center.y
        let length = max(1, hypot(dx, dy))
        return CGPoint(x: corner.x + dx / length * 23, y: corner.y + dy / length * 23)
    }

    private func transforms(for ids: Set<UUID>, from source: [DesignObject]? = nil) -> [UUID: LayerTransform] {
        Dictionary(uniqueKeysWithValues: (source ?? objects).filter { ids.contains($0.id) }.map { object in
            (object.id, LayerTransform(x: object.x, y: object.y, width: object.width,
                                       height: object.height, rotation: object.rotation,
                                       pathPoints: object.pathPoints))
        })
    }

    private func bounds(for objects: [DesignObject]) -> CGRect? {
        let rects = objects.map { object in
            rotatedBounds(for: LayerTransform(x: object.x, y: object.y, width: object.width,
                                              height: object.height, rotation: object.rotation,
                                              pathPoints: object.pathPoints))
        }
        guard var result = rects.first else { return nil }
        for rect in rects.dropFirst() { result = result.union(rect) }
        return result
    }

    private func bounds(for transforms: [UUID: LayerTransform]) -> CGRect? {
        let rects = transforms.values.map { rotatedBounds(for: $0) }
        guard var result = rects.first else { return nil }
        for rect in rects.dropFirst() { result = result.union(rect) }
        return result
    }

    private func rotatedBounds(for transform: LayerTransform) -> CGRect {
        let center = CGPoint(x: transform.x + transform.width / 2, y: transform.y + transform.height / 2)
        let corners = [CGPoint(x: transform.x, y: transform.y),
                       CGPoint(x: transform.x + transform.width, y: transform.y),
                       CGPoint(x: transform.x + transform.width, y: transform.y + transform.height),
                       CGPoint(x: transform.x, y: transform.y + transform.height)]
            .map { rotatePoint($0, around: center, degrees: transform.rotation) }
        let minX = corners.map(\.x).min() ?? center.x
        let maxX = corners.map(\.x).max() ?? center.x
        let minY = corners.map(\.y).min() ?? center.y
        let maxY = corners.map(\.y).max() ?? center.y
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func rotatePoint(_ point: CGPoint, around center: CGPoint, degrees: Double) -> CGPoint {
        let radians = degrees * .pi / 180
        let dx = point.x - center.x, dy = point.y - center.y
        return CGPoint(x: center.x + dx * cos(radians) - dy * sin(radians),
                       y: center.y + dx * sin(radians) + dy * cos(radians))
    }

    private func distance(_ first: CGPoint, _ second: CGPoint) -> CGFloat {
        hypot(first.x - second.x, first.y - second.y)
    }

    private func unrotatedPoint(_ point: CGPoint, for object: DesignObject) -> CGPoint {
        let center = CGPoint(x: object.x + object.width / 2, y: object.y + object.height / 2)
        let radians = -object.rotation * .pi / 180
        let dx = point.x - center.x, dy = point.y - center.y
        return CGPoint(x: center.x + dx * cos(radians) - dy * sin(radians),
                       y: center.y + dx * sin(radians) + dy * cos(radians))
    }

    private func contains(_ point: CGPoint, in object: DesignObject) -> Bool {
        CGRect(x: object.x, y: object.y, width: object.width, height: object.height)
            .contains(unrotatedPoint(point, for: object))
    }

    private func selectedLayerIDs() -> Set<UUID> {
        selectedIDs.isEmpty ? Set(selection.map { [$0] } ?? []) : selectedIDs
    }

    private func selectObject(_ object: DesignObject) {
        let currentSelection = selectedLayerIDs()
        selection = object.id
        if currentSelection.contains(object.id) { return }
        if let groupID = object.groupID {
            selectedIDs = Set(objects.filter { $0.groupID == groupID }.map(\.id))
        } else {
            selectedIDs = [object.id]
        }
    }

    private func groupSelectedLayers() {
        let ids = selectedLayerIDs()
        guard ids.count > 1 else { return }
        let groupID = UUID()
        for index in objects.indices where ids.contains(objects[index].id) {
            objects[index].groupID = groupID
        }
        selectedIDs = ids
        showingImageContextMenu = false
        status = "Grouped \(ids.count) layers"
    }

    private func ungroupSelectedLayers() {
        let ids = selectedLayerIDs()
        let groupIDs = Set(objects.filter { ids.contains($0.id) }.compactMap(\.groupID))
        guard !groupIDs.isEmpty else { return }
        for index in objects.indices where objects[index].groupID.map(groupIDs.contains) == true {
            objects[index].groupID = nil
        }
        showingImageContextMenu = false
        status = "Ungrouped layers"
    }

    private func selectLayers(from start: CGPoint, to end: CGPoint, fullyContained: Bool) {
        let box = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                         width: abs(end.x - start.x), height: abs(end.y - start.y))
        let matches = objects.filter { object in
            guard object.isVisible else { return false }
            let frame = CGRect(x: object.x, y: object.y, width: object.width, height: object.height)
            if fullyContained {
                return frame.minX >= box.minX && frame.maxX <= box.maxX &&
                    frame.minY >= box.minY && frame.maxY <= box.maxY
            }
            return frame.maxX >= box.minX && frame.minX <= box.maxX &&
                frame.maxY >= box.minY && frame.minY <= box.maxY
        }
        let selectedGroupIDs = Set(matches.compactMap(\.groupID))
        let expanded = objects.filter { object in
            matches.contains(where: { $0.id == object.id }) ||
                (object.groupID.map(selectedGroupIDs.contains) == true)
        }
        selectedIDs = Set(expanded.map(\.id))
        selection = matches.first?.id
        status = fullyContained
            ? "Selected \(matches.count) fully enclosed layer\(matches.count == 1 ? "" : "s")"
            : "Selected \(matches.count) touched layer\(matches.count == 1 ? "" : "s")"
    }

    @ViewBuilder private func shape(_ object: DesignObject, scale: Double) -> some View {
        let selected = selection == object.id || selectedIDs.contains(object.id)
        let w = object.width * scale, h = object.height * scale
        ZStack {
            Rectangle().fill(Color.black.opacity(0.001)).frame(width: w, height: h)
            switch object.kind {
            case .rectangle: Rectangle().stroke(object.color, lineWidth: selected ? 2 : 1.4).frame(width: w, height: h)
            case .circle: Ellipse().stroke(object.color, lineWidth: selected ? 2 : 1.4).frame(width: w, height: h)
            case .text:
                Text(object.label)
                    .font(.custom(SystemFontCatalog.font(family: object.fontFamily, size: 100,
                                                         bold: object.fontBold, italic: object.fontItalic).fontName,
                                  size: SystemFontCatalog.fittedTextMetrics(label: object.label, family: object.fontFamily,
                                                                           width: object.width, height: object.height,
                                                                           bold: object.fontBold, italic: object.fontItalic).fittedFontSize * CGFloat(scale)))
                    .lineLimit(1).minimumScaleFactor(1)
                    .foregroundStyle(object.color).frame(width: w, height: h)
            case .line:
                Path { path in path.move(to: .zero); path.addLine(to: CGPoint(x: w, y: h)) }
                    .stroke(object.color, lineWidth: selected ? 2 : 1.4).frame(width: w, height: h)
            case .path:
                Path { path in
                    guard let first = object.pathPoints.first else { return }
                    path.move(to: CGPoint(x: first.x * scale, y: first.y * scale))
                    for point in object.pathPoints.dropFirst() { path.addLine(to: CGPoint(x: point.x * scale, y: point.y * scale)) }
                    if object.pathIsClosed { path.closeSubpath() }
                }.stroke(object.color, lineWidth: selected ? 2 : 1.4).frame(width: w, height: h)
            case .image:
                if let data = object.imageData, let image = NSImage(data: data) {
                    if object.imageInverted {
                        Image(nsImage: image).resizable().interpolation(.high)
                            .saturation(0).colorInvert()
                            .frame(width: w, height: h).clipped()
                            .overlay(Rectangle().stroke(object.color, lineWidth: selected ? 2 : 1.2))
                    } else {
                        Image(nsImage: image).resizable().interpolation(.high)
                            .frame(width: w, height: h).clipped()
                            .overlay(Rectangle().stroke(object.color, lineWidth: selected ? 2 : 1.2))
                    }
                } else {
                    Rectangle().fill(Color.white.opacity(0.08))
                        .overlay(Image(systemName: "photo").foregroundStyle(object.color))
                        .frame(width: w, height: h)
                }
            }
            if selected {
                Rectangle().strokeBorder(Color.white.opacity(0.7), style: StrokeStyle(lineWidth: 0.8, dash: [3, 3]))
                    .frame(width: w + 8, height: h + 8).allowsHitTesting(false)
            }
        }
    }

    private func workspacePoint(_ location: CGPoint, scale: Double, origin: CGPoint) -> CGPoint {
        CGPoint(x: min(400, max(0, (location.x - origin.x) / scale)), y: min(400, max(0, (location.y - origin.y) / scale)))
    }

    private func grid(origin: CGPoint, scale: Double) -> some View {
        Canvas { context, _ in
            let spacing = 10 * scale
            guard spacing > 2 else { return }
            var path = Path()
            for step in 0...40 {
                let p = CGFloat(step) * spacing
                path.move(to: CGPoint(x: origin.x + p, y: origin.y)); path.addLine(to: CGPoint(x: origin.x + p, y: origin.y + 400 * scale))
                path.move(to: CGPoint(x: origin.x, y: origin.y + p)); path.addLine(to: CGPoint(x: origin.x + 400 * scale, y: origin.y + p))
            }
            context.stroke(path, with: .color(.white.opacity(0.055)), lineWidth: 0.5)
            var major = Path()
            for step in stride(from: 0, through: 40, by: 5) {
                let p = CGFloat(step) * spacing
                major.move(to: CGPoint(x: origin.x + p, y: origin.y)); major.addLine(to: CGPoint(x: origin.x + p, y: origin.y + 400 * scale))
                major.move(to: CGPoint(x: origin.x, y: origin.y + p)); major.addLine(to: CGPoint(x: origin.x + 400 * scale, y: origin.y + p))
            }
            context.stroke(major, with: .color(.white.opacity(0.1)), lineWidth: 0.65)
        }
    }
}

private enum CanvasMouseButton: Equatable { case left, right }

private struct CanvasMouseInput: NSViewRepresentable {
    var onMove: (CGPoint?) -> Void
    var onDown: (CGPoint, CanvasMouseButton) -> Void
    var onDrag: (CGPoint) -> Void
    var onUp: (CGPoint) -> Void

    func makeNSView(context: Context) -> MouseView {
        let view = MouseView()
        update(view)
        return view
    }

    func updateNSView(_ nsView: MouseView, context: Context) { update(nsView) }

    private func update(_ view: MouseView) {
        view.onMove = onMove
        view.onDown = onDown
        view.onDrag = onDrag
        view.onUp = onUp
    }

    final class MouseView: NSView {
        var onMove: ((CGPoint?) -> Void)?
        var onDown: ((CGPoint, CanvasMouseButton) -> Void)?
        var onDrag: ((CGPoint) -> Void)?
        var onUp: ((CGPoint) -> Void)?

        override var isOpaque: Bool { false }
        override var acceptsFirstResponder: Bool { true }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            for area in trackingAreas { removeTrackingArea(area) }
            addTrackingArea(NSTrackingArea(rect: bounds,
                                          options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                          owner: self, userInfo: nil))
        }

        private func canvasPoint(for event: NSEvent) -> CGPoint {
            let point = convert(event.locationInWindow, from: nil)
            return CGPoint(x: point.x, y: bounds.height - point.y)
        }

        private func handleDown(_ event: NSEvent, button: CanvasMouseButton) {
            let point = canvasPoint(for: event)
            window?.makeFirstResponder(self)
            onDown?(point, button)
        }

        override func mouseDown(with event: NSEvent) { handleDown(event, button: .left) }
        override func rightMouseDown(with event: NSEvent) { handleDown(event, button: .right) }
        override func mouseMoved(with event: NSEvent) { onMove?(canvasPoint(for: event)) }
        override func mouseExited(with event: NSEvent) { onMove?(nil) }
        override func mouseDragged(with event: NSEvent) {
            onDrag?(canvasPoint(for: event))
        }
        override func rightMouseDragged(with event: NSEvent) {
            onDrag?(canvasPoint(for: event))
        }

        override func mouseUp(with event: NSEvent) {
            onUp?(canvasPoint(for: event))
        }
        override func rightMouseUp(with event: NSEvent) {
            onUp?(canvasPoint(for: event))
        }
    }
}
