import SwiftUI
import AppKit

struct CanvasArea: View {
    @Binding var objects: [DesignObject]
    @Binding var selection: UUID?
    @Binding var selectedIDs: Set<UUID>
    var showGrid: Bool
    var workspace: CGSize = CGSize(width: 400, height: 400)
    @Binding var zoom: Double
    @Binding var panOffset: CGSize
    @Binding var activeTool: String
    @Binding var status: String
    var activeLayerColor: Color = LightBurnPalette.layers[0].color
    var activeIsToolLayer: Bool = false
    var onUndo: (() -> Void)? = nil
    var onRedo: (() -> Void)? = nil
    var onOpenCutSettings: ((UUID) -> Void)? = nil
    var onPositionLaser: ((CGPoint) -> Void)? = nil

    @State private var dragStart: CGPoint?
    @State private var draftPoints: [CGPoint] = []
    @State private var interaction: Interaction?
    @State private var initialFrame: CGRect?
    @State private var initialPathPoints: [CGPoint] = []
    @State private var initialPathSubpaths: [PathSubpath] = []
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
    @State private var showingContextMenu = false
    @State private var clipboardObjects: [DesignObject] = []
    @State private var traceEditorImage: DesignObject?
    @State private var adjustImageID: UUID?
    @State private var showingOffsetSheet = false
    @State private var showingGridArraySheet = false
    @State private var showingCircularArraySheet = false

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
        case moveNode(UUID, Int, Int) // objectID, subpathIndex, pointIndex
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
        var pathSubpaths: [PathSubpath]
    }

    var body: some View {
        GeometryReader { proxy in
            let baseScale = max(0.001, min(proxy.size.width / (workspace.width + 120), proxy.size.height / (workspace.height + 80)))
            let scale = baseScale * zoom
            let origin = CGPoint(
                x: (proxy.size.width - workspace.width * scale) / 2 + panOffset.width,
                y: (proxy.size.height - workspace.height * scale) / 2 + panOffset.height
            )
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
                if showGrid { grid(origin: origin, scale: scale, viewportSize: proxy.size).allowsHitTesting(false) }
                Rectangle().stroke(Color.white.opacity(0.23), lineWidth: 1)
                    .frame(width: workspace.width * scale, height: workspace.height * scale)
                    .position(x: origin.x + workspace.width / 2 * scale, y: origin.y + workspace.height / 2 * scale)
                    .allowsHitTesting(false)
                Text("\(Int(workspace.width)) × \(Int(workspace.height)) mm").font(.system(size: 9, design: .monospaced)).foregroundStyle(.white.opacity(0.35))
                    .position(x: origin.x + workspace.width / 2 * scale, y: origin.y + workspace.height * scale + 14).allowsHitTesting(false)
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
                    if activeTool == "Node edit" && object.kind == .path {
                        Canvas { ctx, _ in
                            let center = CGPoint(x: object.x + object.width / 2, y: object.y + object.height / 2)
                            for sub in object.resolvedSubpaths {
                                for pt in sub.points {
                                    let ws = rotatePoint(CGPoint(x: object.x + pt.x, y: object.y + pt.y), around: center, degrees: object.rotation)
                                    let sx = origin.x + ws.x * scale
                                    let sy = origin.y + ws.y * scale
                                    let rect = CGRect(x: sx - 3.5, y: sy - 3.5, width: 7, height: 7)
                                    ctx.fill(Path(rect), with: .color(.yellow))
                                    ctx.stroke(Path(rect), with: .color(.black), lineWidth: 1)
                                }
                            }
                        }
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
                    },
                    onZoom: { cursor, factor in
                        guard factor.isFinite, factor > 0 else { return }
                        let newZoom = max(0.05, zoom * factor)
                        let actualFactor = newZoom / zoom
                        let newScale = baseScale * newZoom
                        let newOriginX = cursor.x - (cursor.x - origin.x) * actualFactor
                        let newOriginY = cursor.y - (cursor.y - origin.y) * actualFactor
                        panOffset = CGSize(
                            width: newOriginX - (proxy.size.width - workspace.width * newScale) / 2,
                            height: newOriginY - (proxy.size.height - workspace.height * newScale) / 2
                        )
                        zoom = newZoom
                    },
                    onPan: { delta in
                        panOffset = CGSize(
                            width: panOffset.width + delta.width,
                            height: panOffset.height + delta.height
                        )
                    },
                    onKeyDown: { event in
                        handleLightBurnKey(event, viewportSize: proxy.size, baseScale: baseScale)
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                if showingContextMenu {
                    lightBurnContextMenu(in: proxy.size)
                        .zIndex(3)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .clipped()
        .sheet(item: $traceEditorImage) { image in
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
        .sheet(isPresented: Binding(
            get: { adjustImageID != nil && objects.contains(where: { $0.id == adjustImageID }) },
            set: { if !$0 { adjustImageID = nil } }
        )) {
            if let id = adjustImageID, let idx = objects.firstIndex(where: { $0.id == id }) {
                AdjustImageEditorSheet(object: $objects[idx])
            }
        }
        .sheet(isPresented: $showingOffsetSheet) {
            let sources = objects.filter { selectedLayerIDs().contains($0.id) && $0.kind != .image }
            OffsetShapesSheet(sourceObjects: sources, workspace: workspace) { offsetObj, deleteOrig in
                if deleteOrig {
                    let ids = Set(sources.map(\.id))
                    objects.removeAll { ids.contains($0.id) }
                }
                objects.append(offsetObj)
                selection = offsetObj.id
                selectedIDs = [offsetObj.id]
                status = "Created offset shape (\(offsetObj.label))"
            }
        }
        .sheet(isPresented: $showingGridArraySheet) {
            let sources = objects.filter { selectedLayerIDs().contains($0.id) }
            GridArraySheet(sourceObjects: sources, workspace: workspace) { copies in
                objects.append(contentsOf: copies)
                selectedIDs.formUnion(copies.map(\.id))
                status = "Created Grid Array (\(copies.count) copies)"
            }
        }
        .sheet(isPresented: $showingCircularArraySheet) {
            let sources = objects.filter { selectedLayerIDs().contains($0.id) }
            CircularArraySheet(sourceObjects: sources, workspace: workspace) { copies in
                objects.append(contentsOf: copies)
                selectedIDs.formUnion(copies.map(\.id))
                status = "Created Circular Array (\(copies.count) copies)"
            }
        }
    }

    private func beginInteraction(at location: CGPoint, button: CanvasMouseButton, scale: Double, origin: CGPoint) {
        guard scale > 0 else { interaction = Interaction.none; return }
        showingContextMenu = false
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
                interaction = .contextClick
            }
            return
        }
        guard button == .left else { interaction = Interaction.none; return }
        let currentSelection = selectedIDs.isEmpty ? Set(selection.map { [$0] } ?? []) : selectedIDs
        let currentObjects = objects.filter { currentSelection.contains($0.id) }

        // In Node edit mode, check if user clicked a vertex handle on the selected path
        if activeTool == "Node edit", currentObjects.count == 1, let obj = currentObjects.first, obj.kind == .path, !obj.isLocked {
            let center = CGPoint(x: obj.x + obj.width / 2, y: obj.y + obj.height / 2)
            let subs = obj.resolvedSubpaths
            for (sIdx, sub) in subs.enumerated() {
                for (pIdx, pt) in sub.points.enumerated() {
                    let ws = rotatePoint(CGPoint(x: obj.x + pt.x, y: obj.y + pt.y), around: center, degrees: obj.rotation)
                    let screenPt = CGPoint(x: origin.x + ws.x * scale, y: origin.y + ws.y * scale)
                    if distance(location, screenPt) <= 9 {
                        if let oIdx = objects.firstIndex(where: { $0.id == obj.id }) {
                            objects[oIdx].pathSubpaths = subs
                        }
                        interaction = .moveNode(obj.id, sIdx, pIdx)
                        return
                    }
                }
            }
        }

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
        if currentObjects.count == 1, let selected = currentObjects.first?.id, let object = currentObjects.first, !object.isLocked {
            if let handle = ResizeHandle.allCases.first(where: { handle in
                distance(location, cornerPosition(object, handle: handle, scale: scale, origin: origin)) <= 11
            }) {
                interaction = .resize(selected, handle)
                initialFrame = CGRect(x: object.x, y: object.y, width: object.width, height: object.height)
                initialPathPoints = object.pathPoints
                initialPathSubpaths = object.pathSubpaths
                return
            }
        }
        switch activeTool {
        case "Position Laser":
            onPositionLaser?(point)
            status = String(format: "Position Laser → X %.1f mm, Y %.1f mm", point.x, workspace.height - point.y)
            interaction = Interaction.none
        case "Add Tabs":
            if let idx = objects.indices.reversed().first(where: { objects[$0].isVisible && contains(point, in: objects[$0]) }) {
                objects[idx].tabsEnabled = true
                objects[idx].tabCount = max(2, min(16, objects[idx].tabCount + 1))
                selectObject(objects[idx])
                status = "Enabled \(objects[idx].tabCount) tabs (\(String(format: "%.1f", objects[idx].tabSize)) mm) on \(objects[idx].label)"
            }
            interaction = Interaction.none
        case "Radius":
            if let idx = objects.indices.reversed().first(where: { objects[$0].isVisible && contains(point, in: objects[$0]) }) {
                if objects[idx].kind == .rectangle || objects[idx].kind == .polygon {
                    let maxR = min(objects[idx].width, objects[idx].height) * 0.45
                    objects[idx].cornerRadius = min(maxR, objects[idx].cornerRadius + 3.0)
                    selectObject(objects[idx])
                    status = String(format: "Applied %.1f mm corner radius to %@", objects[idx].cornerRadius, objects[idx].label)
                } else if objects[idx].kind == .path {
                    let subs = objects[idx].resolvedSubpaths.map { sub in
                        PathSubpath(points: ShapeGeometry.filletPolygon(sub.points, radius: 3.0, isClosed: sub.isClosed), isClosed: sub.isClosed)
                    }
                    objects[idx].pathSubpaths = subs
                    objects[idx].pathPoints = subs.first?.points ?? []
                    selectObject(objects[idx])
                    status = "Filleted corners on \(objects[idx].label)"
                }
            }
            interaction = Interaction.none
        case "Select", "Node edit":
            if let hit = objects.reversed().first(where: { object in
                guard object.isVisible else { return false }
                let rect = CGRect(x: object.x, y: object.y, width: max(object.width, 12 / scale), height: max(object.height, 12 / scale))
                return rect.insetBy(dx: -7 / scale, dy: -7 / scale).contains(unrotatedPoint(point, for: object))
            }) {
                if activeTool == "Node edit" && hit.kind != .path && hit.kind != .image,
                   let idx = objects.firstIndex(where: { $0.id == hit.id }) {
                    let converted = ShapeGeometry.convertToPath(objects[idx])
                    objects[idx] = converted
                    selectObject(converted)
                    status = "Converted \(converted.label) to editable path nodes"
                    interaction = Interaction.none
                    return
                }
                selectObject(hit)
                if hit.isLocked {
                    status = "\(hit.label) is locked"
                    interaction = Interaction.none
                    return
                }
                let movingIDs = selectedIDs
                interaction = .move(movingIDs)
                initialFrame = CGRect(x: hit.x, y: hit.y, width: hit.width, height: hit.height)
                initialPathPoints = hit.pathPoints
                initialPathSubpaths = hit.pathSubpaths
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
            let appliedDX = min(workspace.width - initialBounds.maxX, max(-initialBounds.minX, dx))
            let appliedDY = min(workspace.height - initialBounds.maxY, max(-initialBounds.minY, dy))
            var changed = objects
            for index in changed.indices where ids.contains(changed[index].id) && !changed[index].isLocked {
                guard let original = initialTransforms[changed[index].id] else { continue }
                changed[index].x = original.x + appliedDX
                changed[index].y = original.y + appliedDY
            }
            objects = changed
            status = ids.count > 1 ? "Moving \(ids.count) layers" : "Moving layer"
        case .moveNode(let id, let sIdx, let pIdx):
            guard let idx = objects.firstIndex(where: { $0.id == id }) else { return }
            let wsPt = workspacePoint(location, scale: scale, origin: origin)
            let unrot = unrotatedPoint(wsPt, for: objects[idx])
            let localPt = CGPoint(x: max(0, min(objects[idx].width, unrot.x - objects[idx].x)),
                                  y: max(0, min(objects[idx].height, unrot.y - objects[idx].y)))
            var subs = objects[idx].resolvedSubpaths
            guard sIdx < subs.count, pIdx < subs[sIdx].points.count else { return }
            let wasClosedMatch = subs[sIdx].isClosed && subs[sIdx].points.count > 2 &&
                (pIdx == 0 || pIdx == subs[sIdx].points.count - 1) &&
                hypot(subs[sIdx].points.first!.x - subs[sIdx].points.last!.x,
                      subs[sIdx].points.first!.y - subs[sIdx].points.last!.y) < 0.05
            subs[sIdx].points[pIdx] = localPt
            if wasClosedMatch {
                subs[sIdx].points[0] = localPt
                subs[sIdx].points[subs[sIdx].points.count - 1] = localPt
            }
            objects[idx].pathSubpaths = subs
            objects[idx].pathPoints = subs.first?.points ?? []
            status = String(format: "Node #%d → (%.1f, %.1f mm)", pIdx + 1, wsPt.x, wsPt.y)
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
            for index in changed.indices where ids.contains(changed[index].id) && !changed[index].isLocked {
                guard let original = initialTransforms[changed[index].id] else { continue }
                let originalCenter = CGPoint(x: original.x + original.width / 2, y: original.y + original.height / 2)
                let rotatedCenter = rotatePoint(originalCenter, around: groupCenter, degrees: degrees)
                changed[index].x = rotatedCenter.x - original.width / 2
                changed[index].y = rotatedCenter.y - original.height / 2
                changed[index].rotation = original.rotation + degrees
            }
            if let rotatedBounds = bounds(for: transforms(for: ids, from: changed)) {
                let shiftX = rotatedBounds.width > workspace.width ? -rotatedBounds.minX : (rotatedBounds.minX < 0 ? -rotatedBounds.minX : (rotatedBounds.maxX > workspace.width ? workspace.width - rotatedBounds.maxX : 0))
                let shiftY = rotatedBounds.height > workspace.height ? -rotatedBounds.minY : (rotatedBounds.minY < 0 ? -rotatedBounds.minY : (rotatedBounds.maxY > workspace.height ? workspace.height - rotatedBounds.maxY : 0))
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
        defer { interaction = nil; initialFrame = nil; initialPathPoints = []; initialPathSubpaths = []; initialTransforms = [:]; initialPointerAngle = nil; initialGroupCenter = nil; initialGroupBounds = nil; dragStart = nil; draftPoints = []; marqueeStart = nil; marqueeEnd = nil; rightClickTargetID = nil }
        if case .contextClick = interaction {
            if let pointerStart, hypot(location.x - pointerStart.x, location.y - pointerStart.y) < 4 {
                contextMenuImageID = rightClickTargetID.flatMap { id in
                    objects.first(where: { $0.id == id && $0.kind == .image })?.id
                } ?? objects.first(where: { selectedLayerIDs().contains($0.id) && $0.kind == .image })?.id
                contextMenuLocation = location
                showingContextMenu = true
            }
            return
        }
        if case .marquee(let fullyContained) = interaction, let start = dragStart {
            let end = workspacePoint(location, scale: scale, origin: origin)
            if let pointerStart, hypot(location.x - pointerStart.x, location.y - pointerStart.y) >= 4 {
                selectLayers(from: start, to: end, fullyContained: fullyContained)
            } else if fullyContained {
                contextMenuImageID = rightClickTargetID.flatMap { id in
                    objects.first(where: { $0.id == id && $0.kind == .image })?.id
                } ?? objects.first(where: { selectedLayerIDs().contains($0.id) && $0.kind == .image })?.id
                contextMenuLocation = location
                showingContextMenu = true
            } else {
                selection = nil; selectedIDs = []
            }
            return
        }
        if case .moveNode = interaction {
            status = "Updated path node"
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
                status = String(format: "Measured %.1f mm (ΔX %.1f, ΔY %.1f)", hypot(end.x - start.x, end.y - start.y), abs(end.x - start.x), abs(end.y - start.y))
            }
            return
        }
        let end = workspacePoint(location, scale: scale, origin: origin)
        let left = min(start.x, end.x), top = min(start.y, end.y)
        let width = max(1, abs(end.x - start.x)), height = max(1, abs(end.y - start.y))
        switch activeTool {
        case "Text":
            let item = DesignObject(kind: .text, x: min(workspace.width - 20, max(0, start.x)), y: min(workspace.height - 20, max(0, start.y)), width: 100, height: 24, label: "Text", color: activeLayerColor, isToolLayer: activeIsToolLayer, fontFamily: "Helvetica")
            objects.append(item); selection = item.id; selectedIDs = [item.id]; activeTool = "Select"; status = "Placed text · Select tool active"
        case "Rectangle", "Circle", "Polygon":
            let kind: DesignObject.Kind = activeTool == "Rectangle" ? .rectangle : (activeTool == "Circle" ? .circle : .polygon)
            let w = width < 3 ? 40 : width
            let h = height < 3 ? 40 : height
            let item = DesignObject(kind: kind, x: left, y: top, width: w, height: h,
                                    label: "\(kind.rawValue) \(objects.count + 1)", color: activeLayerColor, isToolLayer: activeIsToolLayer)
            objects.append(item); selection = item.id; selectedIDs = [item.id]; activeTool = "Select"; status = "Added \(kind.rawValue.lowercased()) · Select tool active"
        case "Line":
            let points = [start, end].map { CGPoint(x: $0.x - left, y: $0.y - top) }
            let item = DesignObject(kind: .path, x: left, y: top, width: width, height: height,
                                    label: "Line \(objects.count + 1)", color: activeLayerColor, isToolLayer: activeIsToolLayer, pathPoints: points)
            objects.append(item); selection = item.id; selectedIDs = [item.id]; activeTool = "Select"; status = "Added line · Select tool active"
        case "Pen":
            let points = (draftPoints + [end]).map { CGPoint(x: $0.x - left, y: $0.y - top) }
            let item = DesignObject(kind: .path, x: left, y: top, width: width, height: height,
                                    label: "Pen path \(objects.count + 1)", color: activeLayerColor, isToolLayer: activeIsToolLayer, pathPoints: points)
            objects.append(item); selection = item.id; selectedIDs = [item.id]; activeTool = "Select"; status = "Added pen path · Select tool active"
        default: break
        }
    }

    private func resize(id: UUID, handle: ResizeHandle, dx: Double, dy: Double) {
        guard let frame = initialFrame, let index = objects.firstIndex(where: { $0.id == id }) else { return }
        let minSize = 2.0
        let left: Double, right: Double, top: Double, bottom: Double
        if handle.u == 0 { right = frame.maxX; left = min(right - minSize, max(0, frame.minX + dx)) }
        else { left = frame.minX; right = max(left + minSize, min(workspace.width, frame.maxX + dx)) }
        if handle.v == 0 { bottom = frame.maxY; top = min(bottom - minSize, max(0, frame.minY + dy)) }
        else { top = frame.minY; bottom = max(top + minSize, min(workspace.height, frame.maxY + dy)) }
        let width = right - left, height = bottom - top
        var changed = objects
        changed[index].x = left; changed[index].y = top; changed[index].width = width; changed[index].height = height
        if frame.width > 0, frame.height > 0 {
            let sx = width / frame.width, sy = height / frame.height
            if !initialPathPoints.isEmpty {
                changed[index].pathPoints = initialPathPoints.map { CGPoint(x: $0.x * sx, y: $0.y * sy) }
            }
            if !initialPathSubpaths.isEmpty {
                changed[index].pathSubpaths = initialPathSubpaths.map { subpath in
                    PathSubpath(points: subpath.points.map { CGPoint(x: $0.x * sx, y: $0.y * sy) }, isClosed: subpath.isClosed)
                }
            }
        }
        objects = changed
    }

    private func resizeGroup(ids: Set<UUID>, handle: ResizeHandle, dx: Double, dy: Double) {
        guard let bounds = initialGroupBounds, bounds.width > 0, bounds.height > 0 else { return }
        let movingX = handle.u == 0
            ? min(Double(bounds.maxX) - 2, max(0, Double(bounds.minX) + dx))
            : max(Double(bounds.minX) + 2, min(workspace.width, Double(bounds.maxX) + dx))
        let movingY = handle.v == 0
            ? min(Double(bounds.maxY) - 2, max(0, Double(bounds.minY) + dy))
            : max(Double(bounds.minY) + 2, min(workspace.height, Double(bounds.maxY) + dy))
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
            changed[index].pathSubpaths = original.pathSubpaths.map { subpath in
                PathSubpath(points: subpath.points.map { CGPoint(x: $0.x * scaleX, y: $0.y * scaleY) }, isClosed: subpath.isClosed)
            }
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
                                       pathPoints: object.pathPoints, pathSubpaths: object.pathSubpaths))
        })
    }

    private func bounds(for objects: [DesignObject]) -> CGRect? {
        let rects = objects.map { object in
            rotatedBounds(for: LayerTransform(x: object.x, y: object.y, width: object.width,
                                              height: object.height, rotation: object.rotation,
                                              pathPoints: object.pathPoints, pathSubpaths: object.pathSubpaths))
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
        guard ids.count > 1 else {
            showingContextMenu = false
            return
        }
        let groupID = UUID()
        for index in objects.indices where ids.contains(objects[index].id) {
            objects[index].groupID = groupID
        }
        selectedIDs = ids
        showingContextMenu = false
        status = "Grouped \(ids.count) shapes"
    }

    private func ungroupSelectedLayers() {
        let ids = selectedLayerIDs()
        let selectedObjs = objects.filter { ids.contains($0.id) }
        let groupIDs = Set(selectedObjs.compactMap(\.groupID))
        if !groupIDs.isEmpty {
            for index in objects.indices where objects[index].groupID.map(groupIDs.contains) == true {
                objects[index].groupID = nil
            }
            showingContextMenu = false
            status = "Ungrouped shapes"
            return
        }
        // Like LightBurn: when ungrouping an ungrouped compound vector path or text,
        // split its subpaths into individual vector objects so each piece can be edited separately.
        var newObjects: [DesignObject] = []
        var newSelection: Set<UUID> = []
        var brokenCount = 0
        for obj in objects {
            if ids.contains(obj.id) && (obj.kind == .path || obj.kind == .text) {
                let parts = ShapeGeometry.breakApartSubpaths(obj)
                if parts.count > 1 {
                    newObjects.append(contentsOf: parts)
                    newSelection.formUnion(parts.map(\.id))
                    brokenCount += parts.count
                } else {
                    newObjects.append(obj)
                    newSelection.insert(obj.id)
                }
            } else {
                newObjects.append(obj)
            }
        }
        if brokenCount > 0 {
            objects = newObjects
            selectedIDs = newSelection
            selection = newSelection.first
            showingContextMenu = false
            status = "Ungrouped vector into \(brokenCount) separate shapes"
        } else {
            showingContextMenu = false
            status = "Nothing to ungroup"
        }
    }

    private func breakApartSelectedVectors() {
        let ids = selectedLayerIDs()
        var newObjects: [DesignObject] = []
        var newSelection: Set<UUID> = []
        var segmentCount = 0
        for obj in objects {
            if ids.contains(obj.id) && obj.kind != .image && !obj.isLocked {
                // First try breaking compound subpaths if multiple exist; otherwise explode into individual segments
                let subparts = ShapeGeometry.breakApartSubpaths(obj)
                if subparts.count > 1 {
                    newObjects.append(contentsOf: subparts)
                    newSelection.formUnion(subparts.map(\.id))
                    segmentCount += subparts.count
                } else {
                    let segs = ShapeGeometry.breakApartSegments(obj)
                    newObjects.append(contentsOf: segs)
                    newSelection.formUnion(segs.map(\.id))
                    segmentCount += segs.count
                }
            } else {
                newObjects.append(obj)
            }
        }
        guard segmentCount > 0 else {
            showingContextMenu = false
            return
        }
        objects = newObjects
        selectedIDs = newSelection
        selection = newSelection.first
        showingContextMenu = false
        status = "Broke apart vectors into \(segmentCount) pieces"
    }

    // MARK: - LightBurn Right-Click Context Menu & Actions

    @ViewBuilder
    private func lightBurnContextMenu(in containerSize: CGSize) -> some View {
        let ids = selectedLayerIDs()
        let selectedObjs = objects.filter { ids.contains($0.id) }
        let hasSelection = !selectedObjs.isEmpty
        let hasVectorSelection = selectedObjs.contains(where: { $0.kind != .image })
        let canUngroupOrBreak = selectedObjs.contains { obj in
            obj.groupID != nil ||
            (obj.kind == .path && obj.resolvedSubpaths.count > 1) ||
            (obj.kind == .text && ShapeGeometry.localSubpaths(for: obj).count > 1)
        }
        let targetImage = objects.first(where: { $0.id == contextMenuImageID && $0.kind == .image })
            ?? selectedObjs.first(where: { $0.kind == .image })
        let menuW: CGFloat = 232
        let menuH: CGFloat = 460
        let posX = min(containerSize.width - menuW / 2 - 8, max(menuW / 2 + 8, contextMenuLocation.x + menuW / 2))
        let posY = min(containerSize.height - menuH / 2 - 8, max(menuH / 2 + 8, contextMenuLocation.y + menuH / 2 - 40))

        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 1) {
                contextMenuItem("Undo", shortcut: "⌘Z", icon: "arrow.uturn.backward") {
                    showingContextMenu = false
                    onUndo?()
                }
                contextMenuItem("Redo", shortcut: "⇧⌘Z", icon: "arrow.uturn.forward") {
                    showingContextMenu = false
                    onRedo?()
                }

                Divider().padding(.vertical, 3)

                contextMenuItem("Cut", shortcut: "⌘X", icon: "scissors", enabled: hasSelection) {
                    copySelectedLayers()
                    deleteSelectedLayers()
                }
                contextMenuItem("Copy", shortcut: "⌘C", icon: "doc.on.doc", enabled: hasSelection) {
                    copySelectedLayers()
                }
                contextMenuItem("Paste", shortcut: "⌘V", icon: "doc.on.clipboard", enabled: !clipboardObjects.isEmpty) {
                    pasteClipboardLayers()
                }
                contextMenuItem("Duplicate", shortcut: "⌘D", icon: "plus.square.on.square", enabled: hasSelection) {
                    duplicateSelectedLayers()
                }
                contextMenuItem("Delete", shortcut: "⌫", icon: "trash", enabled: hasSelection, destructive: true) {
                    deleteSelectedLayers()
                }

                Divider().padding(.vertical, 3)

                contextMenuItem("Select All", shortcut: "⌘A", icon: "selection.pin.in.out", enabled: !objects.isEmpty) {
                    let visible = objects.filter(\.isVisible)
                    selectedIDs = Set(visible.map(\.id))
                    selection = visible.first?.id
                    showingContextMenu = false
                    status = "Selected all \(visible.count) objects"
                }
                contextMenuItem("Invert Selection", shortcut: "⇧⌘I", icon: "arrow.triangle.2.circlepath", enabled: !objects.isEmpty) {
                    let current = selectedLayerIDs()
                    let inverted = objects.filter { $0.isVisible && !current.contains($0.id) }
                    selectedIDs = Set(inverted.map(\.id))
                    selection = inverted.first?.id
                    showingContextMenu = false
                    status = "Inverted selection (\(inverted.count) objects)"
                }

                Divider().padding(.vertical, 3)

                contextMenuItem("Group", shortcut: "⌘G", icon: "square.3.layers.3d", enabled: ids.count > 1) {
                    groupSelectedLayers()
                }
                contextMenuItem("Ungroup", shortcut: "⌘U / ⇧⌘G", icon: "square.3.layers.3d.down.right", enabled: canUngroupOrBreak) {
                    ungroupSelectedLayers()
                }
                contextMenuItem("Break Apart Vectors", shortcut: "⌥B", icon: "scissors.badge.ellipsis", enabled: hasVectorSelection) {
                    breakApartSelectedVectors()
                }

                Divider().padding(.vertical, 3)

                contextMenuItem("Convert to Path", shortcut: "⌘P", icon: "point.topleft.down.to.point.bottomright.curvepath", enabled: hasVectorSelection) {
                    convertSelectedToPath()
                }
                contextMenuItem("Convert to Bitmap", shortcut: "⌥B", icon: "photo.badge.plus", enabled: hasSelection) {
                    convertSelectedToBitmap()
                }

                if let image = targetImage {
                    Divider().padding(.vertical, 3)
                    contextMenuItem("Trace Image…", shortcut: "⌥T", icon: "waveform.path.ecg.rectangle") {
                        traceEditorImage = image
                        showingContextMenu = false
                    }
                    contextMenuItem("Adjust Image…", shortcut: "⌥I", icon: "slider.horizontal.below.rectangle") {
                        adjustImageID = image.id
                        showingContextMenu = false
                    }
                }

                Divider().padding(.vertical, 3)

                contextMenuItem("Offset Shapes…", shortcut: "⌥O", icon: "square.on.square.dashed", enabled: hasVectorSelection) {
                    showingContextMenu = false
                    showingOffsetSheet = true
                }
                contextMenuItem("Boolean Weld", shortcut: "⌘W", icon: "circle.grid.cross.fill", enabled: selectedObjs.count >= 2 && hasVectorSelection) {
                    performBoolean(.weld)
                }
                contextMenuItem("Boolean Union", shortcut: "⌥U", icon: "plus.circle", enabled: selectedObjs.count >= 2 && hasVectorSelection) {
                    performBoolean(.union)
                }
                contextMenuItem("Boolean Subtract (A - B)", shortcut: "⌥S", icon: "minus.circle", enabled: selectedObjs.count >= 2 && hasVectorSelection) {
                    performBoolean(.subtract)
                }
                contextMenuItem("Boolean Intersection", shortcut: "⌥N", icon: "multiply.circle", enabled: selectedObjs.count >= 2 && hasVectorSelection) {
                    performBoolean(.intersect)
                }

                Divider().padding(.vertical, 3)

                contextMenuItem("Grid Array…", shortcut: "", icon: "square.grid.3x2", enabled: hasSelection) {
                    showingContextMenu = false
                    showingGridArraySheet = true
                }
                contextMenuItem("Circular Array…", shortcut: "", icon: "circle.dotted", enabled: hasSelection) {
                    showingContextMenu = false
                    showingCircularArraySheet = true
                }

                Divider().padding(.vertical, 3)

                contextMenuItem("Flip Horizontal", shortcut: "⌘H", icon: "arrow.left.and.right.righttriangle.left.righttriangle.right", enabled: hasSelection) {
                    flipSelected(horizontal: true)
                }
                contextMenuItem("Flip Vertical", shortcut: "⌘J", icon: "arrow.up.and.down.righttriangle.up.righttriangle.down", enabled: hasSelection) {
                    flipSelected(horizontal: false)
                }
                contextMenuItem("Rotate 90° CW", shortcut: "", icon: "rotate.right", enabled: hasSelection) {
                    rotateSelected(by: 90)
                }
                contextMenuItem("Rotate 90° CCW", shortcut: "", icon: "rotate.left", enabled: hasSelection) {
                    rotateSelected(by: -90)
                }
                contextMenuItem("Move to Page Center", shortcut: "P", icon: "viewfinder", enabled: hasSelection) {
                    centerSelectedInPage()
                }

                Divider().padding(.vertical, 3)

                contextMenuItem("Push to Front", shortcut: "⌘]", icon: "square.3.layers.3d.top.filled", enabled: hasSelection) {
                    reorderSelected(toFront: true)
                }
                contextMenuItem("Push to Back", shortcut: "⌘[", icon: "square.3.layers.3d.bottom.filled", enabled: hasSelection) {
                    reorderSelected(toFront: false)
                }

                if let first = selectedObjs.first {
                    Divider().padding(.vertical, 3)
                    contextMenuItem(first.isLocked ? "Unlock Selected Shape" : "Lock Selected Shape", shortcut: "⌘L", icon: first.isLocked ? "lock.open" : "lock") {
                        toggleLockSelected()
                    }
                    contextMenuItem("Cut Settings Editor…", shortcut: "⌘E", icon: "slider.horizontal.3") {
                        showingContextMenu = false
                        onOpenCutSettings?(first.id)
                    }
                }
            }
            .padding(6)
        }
        .frame(width: menuW, height: min(menuH, containerSize.height - 24))
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.18), lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 12, x: 0, y: 6)
        .position(x: posX, y: posY)
    }

    private func contextMenuItem(
        _ title: String,
        shortcut: String,
        icon: String,
        enabled: Bool = true,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 16)
                    .foregroundStyle(destructive ? Color.red : (enabled ? Color.orange : Color.secondary.opacity(0.45)))
                Text(title)
                    .font(.system(size: 11.5))
                    .foregroundStyle(destructive ? Color.red : (enabled ? Color.primary : Color.secondary.opacity(0.45)))
                Spacer()
                if !shortcut.isEmpty {
                    Text(shortcut)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary.opacity(enabled ? 0.8 : 0.35))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4.5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func copySelectedLayers() {
        let ids = selectedLayerIDs()
        clipboardObjects = objects.filter { ids.contains($0.id) }
        showingContextMenu = false
        status = "Copied \(clipboardObjects.count) object\(clipboardObjects.count == 1 ? "" : "s")"
    }

    private func pasteClipboardLayers() {
        guard !clipboardObjects.isEmpty else { return }
        var newIDs: Set<UUID> = []
        let groupRemap = Dictionary(uniqueKeysWithValues: Set(clipboardObjects.compactMap(\.groupID)).map { ($0, UUID()) })
        for item in clipboardObjects {
            var copy = item
            copy.id = UUID()
            copy.x = min(workspace.width - copy.width, max(0, item.x + 8))
            copy.y = min(workspace.height - copy.height, max(0, item.y + 8))
            if let gid = item.groupID { copy.groupID = groupRemap[gid] }
            objects.append(copy)
            newIDs.insert(copy.id)
        }
        selectedIDs = newIDs
        selection = newIDs.first
        showingContextMenu = false
        status = "Pasted \(newIDs.count) object\(newIDs.count == 1 ? "" : "s")"
    }

    private func duplicateSelectedLayers() {
        copySelectedLayers()
        pasteClipboardLayers()
        status = "Duplicated selection"
    }

    private func deleteSelectedLayers() {
        let ids = selectedLayerIDs()
        objects.removeAll { ids.contains($0.id) && !$0.isLocked }
        selectedIDs = []
        selection = objects.last?.id
        showingContextMenu = false
        status = "Deleted selected object\(ids.count == 1 ? "" : "s")"
    }

    private func convertSelectedToPath() {
        let ids = selectedLayerIDs()
        var convertedCount = 0
        for idx in objects.indices where ids.contains(objects[idx].id) && objects[idx].kind != .image {
            objects[idx] = ShapeGeometry.convertToPath(objects[idx])
            convertedCount += 1
        }
        showingContextMenu = false
        status = "Converted \(convertedCount) object\(convertedCount == 1 ? "" : "s") to editable paths"
    }

    private func convertSelectedToBitmap() {
        let ids = selectedLayerIDs()
        var added: [DesignObject] = []
        var removed: Set<UUID> = []
        for obj in objects where ids.contains(obj.id) {
            if let bmp = ImageImporter.convertToBitmap(obj) {
                added.append(bmp)
                removed.insert(obj.id)
            }
        }
        guard !added.isEmpty else { showingContextMenu = false; return }
        objects.removeAll { removed.contains($0.id) }
        objects.append(contentsOf: added)
        selectedIDs = Set(added.map(\.id))
        selection = added.first?.id
        showingContextMenu = false
        status = "Converted \(added.count) object\(added.count == 1 ? "" : "s") to bitmap image"
    }

    private func performBoolean(_ op: BooleanOperationKind) {
        let ids = selectedLayerIDs()
        let selected = objects.filter { ids.contains($0.id) && $0.kind != .image }
        guard selected.count >= 2,
              let result = ShapeGeometry.booleanOperation(op, objects: selected, workspace: workspace) else {
            showingContextMenu = false
            status = "Select at least 2 overlapping vector shapes for \(op.rawValue)"
            return
        }
        let removeIDs = Set(selected.map(\.id))
        objects.removeAll { removeIDs.contains($0.id) }
        objects.append(result)
        selection = result.id
        selectedIDs = [result.id]
        showingContextMenu = false
        status = "Applied Boolean \(op.rawValue)"
    }

    private func flipSelected(horizontal: Bool) {
        let ids = selectedLayerIDs()
        let selected = objects.filter { ids.contains($0.id) }
        guard let b = bounds(for: selected) else { showingContextMenu = false; return }
        for idx in objects.indices where ids.contains(objects[idx].id) && !objects[idx].isLocked {
            if horizontal {
                objects[idx].x = Double(b.maxX) - (objects[idx].x - Double(b.minX)) - objects[idx].width
                let w = objects[idx].width
                objects[idx].pathPoints = objects[idx].pathPoints.map { CGPoint(x: w - $0.x, y: $0.y) }
                objects[idx].pathSubpaths = objects[idx].pathSubpaths.map { sub in
                    PathSubpath(points: sub.points.map { CGPoint(x: w - $0.x, y: $0.y) }, isClosed: sub.isClosed)
                }
            } else {
                objects[idx].y = Double(b.maxY) - (objects[idx].y - Double(b.minY)) - objects[idx].height
                let h = objects[idx].height
                objects[idx].pathPoints = objects[idx].pathPoints.map { CGPoint(x: $0.x, y: h - $0.y) }
                objects[idx].pathSubpaths = objects[idx].pathSubpaths.map { sub in
                    PathSubpath(points: sub.points.map { CGPoint(x: $0.x, y: h - $0.y) }, isClosed: sub.isClosed)
                }
            }
        }
        showingContextMenu = false
        status = horizontal ? "Flipped selection horizontally" : "Flipped selection vertically"
    }

    private func rotateSelected(by degrees: Double) {
        let ids = selectedLayerIDs()
        for idx in objects.indices where ids.contains(objects[idx].id) && !objects[idx].isLocked {
            objects[idx].rotation = (objects[idx].rotation + degrees).truncatingRemainder(dividingBy: 360)
        }
        showingContextMenu = false
        status = "Rotated selection \(Int(degrees))°"
    }

    private func centerSelectedInPage() {
        let ids = selectedLayerIDs()
        let selected = objects.filter { ids.contains($0.id) }
        guard let b = bounds(for: selected) else { showingContextMenu = false; return }
        let dx = workspace.width / 2 - Double(b.midX)
        let dy = workspace.height / 2 - Double(b.midY)
        for idx in objects.indices where ids.contains(objects[idx].id) && !objects[idx].isLocked {
            objects[idx].x = min(workspace.width - objects[idx].width, max(0, objects[idx].x + dx))
            objects[idx].y = min(workspace.height - objects[idx].height, max(0, objects[idx].y + dy))
        }
        showingContextMenu = false
        status = "Centered selection in workspace"
    }

    private func reorderSelected(toFront: Bool) {
        let ids = selectedLayerIDs()
        let picked = objects.filter { ids.contains($0.id) }
        let remaining = objects.filter { !ids.contains($0.id) }
        objects = toFront ? (remaining + picked) : (picked + remaining)
        showingContextMenu = false
        status = toFront ? "Moved selection to front" : "Moved selection to back"
    }

    private func toggleLockSelected() {
        let ids = selectedLayerIDs()
        let shouldLock = !(objects.first(where: { ids.contains($0.id) })?.isLocked ?? false)
        for idx in objects.indices where ids.contains(objects[idx].id) {
            objects[idx].isLocked = shouldLock
        }
        showingContextMenu = false
        status = shouldLock ? "Locked selected shapes" : "Unlocked selected shapes"
    }

    private enum AlignmentEdge {
        case left, right, top, bottom, centerH, centerV
    }

    private func alignSelected(_ edge: AlignmentEdge) {
        let ids = selectedLayerIDs()
        let selected = objects.filter { ids.contains($0.id) }
        guard selected.count >= 2, let b = bounds(for: selected) else {
            showingContextMenu = false
            return
        }
        for idx in objects.indices where ids.contains(objects[idx].id) && !objects[idx].isLocked {
            switch edge {
            case .left: objects[idx].x = Double(b.minX)
            case .right: objects[idx].x = Double(b.maxX) - objects[idx].width
            case .top: objects[idx].y = Double(b.minY)
            case .bottom: objects[idx].y = Double(b.maxY) - objects[idx].height
            case .centerH: objects[idx].x = Double(b.midX) - objects[idx].width / 2
            case .centerV: objects[idx].y = Double(b.midY) - objects[idx].height / 2
            }
        }
        showingContextMenu = false
        status = "Aligned selection"
    }

    private func nudgeSelected(dx: Double, dy: Double) {
        let ids = selectedLayerIDs()
        guard !ids.isEmpty else { return }
        for idx in objects.indices where ids.contains(objects[idx].id) && !objects[idx].isLocked {
            objects[idx].x = min(workspace.width - objects[idx].width, max(0, objects[idx].x + dx))
            objects[idx].y = min(workspace.height - objects[idx].height, max(0, objects[idx].y + dy))
        }
        status = String(format: "Nudged selection (%.2f, %.2f mm)", dx, dy)
    }

    private func handleLightBurnKey(_ event: NSEvent, viewportSize: CGSize, baseScale: Double) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let cmd = flags.contains(.command) || flags.contains(.control)
        let shift = flags.contains(.shift)
        let opt = flags.contains(.option)
        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let keyCode = event.keyCode

        // Escape: cancel current drawing or clear selection / switch to Select tool
        if keyCode == 53 {
            if showingContextMenu {
                showingContextMenu = false
                return true
            }
            if !draftPoints.isEmpty {
                draftPoints.removeAll()
                interaction = nil
                status = "Canceled drawing"
                return true
            }
            if activeTool != "Select" {
                activeTool = "Select"
                status = "Select tool"
                return true
            }
            selectedIDs = []
            selection = nil
            status = "Cleared selection"
            return true
        }

        // Delete / Forward Delete
        if !cmd && !opt && (keyCode == 51 || keyCode == 117) {
            guard !selectedLayerIDs().isEmpty else { return false }
            deleteSelectedLayers()
            return true
        }

        // Arrow key nudging (Default: 1 mm, Shift: 5 mm, Cmd/Ctrl: 0.1 mm)
        if keyCode == 123 || keyCode == 124 || keyCode == 125 || keyCode == 126 {
            let step = shift ? 5.0 : (cmd ? 0.1 : 1.0)
            switch keyCode {
            case 123: nudgeSelected(dx: -step, dy: 0)
            case 124: nudgeSelected(dx: step, dy: 0)
            case 126: nudgeSelected(dx: 0, dy: -step)
            case 125: nudgeSelected(dx: 0, dy: step)
            default: break
            }
            return true
        }

        // Page Up / Page Down or Cmd+] / Cmd+[
        if keyCode == 116 || (cmd && chars == "]") {
            reorderSelected(toFront: true)
            return true
        }
        if keyCode == 121 || (cmd && chars == "[") {
            reorderSelected(toFront: false)
            return true
        }

        // Command / Control shortcuts (LightBurn standard)
        if cmd && !opt {
            switch chars {
            case "z":
                if shift { onRedo?() } else { onUndo?() }
                return true
            case "y":
                onRedo?()
                return true
            case "x":
                copySelectedLayers()
                deleteSelectedLayers()
                return true
            case "c":
                copySelectedLayers()
                return true
            case "v":
                pasteClipboardLayers()
                return true
            case "d":
                duplicateSelectedLayers()
                return true
            case "a":
                if shift {
                    zoom = 1.0
                    panOffset = .zero
                    status = "Zoomed to frame all"
                } else {
                    let visible = objects.filter(\.isVisible)
                    selectedIDs = Set(visible.map(\.id))
                    selection = visible.first?.id
                    status = "Selected all \(visible.count) objects"
                }
                return true
            case "i":
                if shift {
                    let current = selectedLayerIDs()
                    let inverted = objects.filter { $0.isVisible && !current.contains($0.id) }
                    selectedIDs = Set(inverted.map(\.id))
                    selection = inverted.first?.id
                    status = "Inverted selection (\(inverted.count) objects)"
                    return true
                }
            case "g":
                if shift {
                    ungroupSelectedLayers()
                } else {
                    groupSelectedLayers()
                }
                return true
            case "u":
                ungroupSelectedLayers()
                return true
            case "p":
                convertSelectedToPath()
                return true
            case "w":
                performBoolean(.weld)
                return true
            case "h":
                flipSelected(horizontal: true)
                return true
            case "j":
                flipSelected(horizontal: false)
                return true
            case "l":
                toggleLockSelected()
                return true
            case "r":
                activeTool = "Rectangle"
                status = "Draw Rectangle tool"
                return true
            case "e":
                activeTool = "Ellipse"
                status = "Draw Ellipse tool"
                return true
            case "t":
                activeTool = "Text"
                status = "Create/Edit Text tool"
                return true
            case "f":
                activeTool = "Offset"
                showingOffsetSheet = true
                return true
            case "m":
                activeTool = "Measure"
                status = "Measure tool"
                return true
            case "0":
                zoom = 1.0
                panOffset = .zero
                status = "Zoom to Page (100%)"
                return true
            case "=", "+":
                zoom *= 1.25
                return true
            case "-":
                zoom = max(0.05, zoom / 1.25)
                return true
            default:
                break
            }
        }

        // Option / Alt shortcuts (LightBurn standard)
        if opt && !cmd {
            switch chars {
            case "t":
                let ids = selectedLayerIDs()
                if let img = objects.first(where: { ids.contains($0.id) && $0.kind == .image }) ?? objects.first(where: { $0.kind == .image }) {
                    traceEditorImage = img
                    return true
                }
            case "i":
                let ids = selectedLayerIDs()
                if let img = objects.first(where: { ids.contains($0.id) && $0.kind == .image }) ?? objects.first(where: { $0.kind == .image }) {
                    adjustImageID = img.id
                    return true
                }
            case "o":
                showingOffsetSheet = true
                return true
            case "b":
                breakApartSelectedVectors()
                return true
            case "u", "+":
                performBoolean(.union)
                return true
            case "s", "-":
                performBoolean(.subtract)
                return true
            case "n", "*":
                performBoolean(.intersect)
                return true
            default:
                break
            }
        }

        // Single-key LightBurn shortcuts (no Cmd/Opt)
        if !cmd && !opt {
            switch chars {
            case "p":
                centerSelectedInPage()
                return true
            case "l":
                alignSelected(.left)
                return true
            case "r":
                alignSelected(.right)
                return true
            case "t":
                alignSelected(.top)
                return true
            case "b":
                alignSelected(.bottom)
                return true
            case "c":
                alignSelected(.centerH)
                return true
            case "e":
                alignSelected(.centerV)
                return true
            case ".":
                rotateSelected(by: 90)
                return true
            case ",":
                rotateSelected(by: -90)
                return true
            default:
                break
            }
        }

        return false
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
        let shaded = object.layerMode != .line
        let shade = object.color.opacity(0.4)
        ZStack {
            Rectangle().fill(Color.black.opacity(0.001)).frame(width: w, height: h)
            switch object.kind {
            case .rectangle:
                let r = CGFloat(object.cornerRadius * scale)
                if shaded { RoundedRectangle(cornerRadius: r).fill(shade).frame(width: w, height: h) }
                RoundedRectangle(cornerRadius: r).stroke(object.color, style: StrokeStyle(lineWidth: selected ? 2 : 1.4, dash: object.isToolLayer ? [5, 3] : [])).frame(width: w, height: h)
            case .circle:
                if shaded { Ellipse().fill(shade).frame(width: w, height: h) }
                Ellipse().stroke(object.color, style: StrokeStyle(lineWidth: selected ? 2 : 1.4, dash: object.isToolLayer ? [5, 3] : [])).frame(width: w, height: h)
            case .polygon:
                let polyPoints = ShapeGeometry.localPolygonPoints(width: object.width, height: object.height, sides: object.polygonSides, cornerRadius: object.cornerRadius)
                let polyPath = Path { path in
                    guard let first = polyPoints.first else { return }
                    path.move(to: CGPoint(x: first.x * scale, y: first.y * scale))
                    for pt in polyPoints.dropFirst() {
                        path.addLine(to: CGPoint(x: pt.x * scale, y: pt.y * scale))
                    }
                    path.closeSubpath()
                }
                if shaded { polyPath.fill(shade).frame(width: w, height: h) }
                polyPath.stroke(object.color, style: StrokeStyle(lineWidth: selected ? 2 : 1.4, dash: object.isToolLayer ? [5, 3] : [])).frame(width: w, height: h)
            case .text:
                let renderScale = min(scale, 8.0)
                let displayText = object.fontUppercase ? object.label.uppercased() : object.label
                let baseFitted = SystemFontCatalog.fittedTextMetrics(
                    label: displayText, family: object.fontFamily,
                    width: object.width, height: object.height,
                    bold: object.fontBold, italic: object.fontItalic
                ).fittedFontSize
                Text(displayText)
                    .font(.custom(SystemFontCatalog.font(family: object.fontFamily, size: 100,
                                                         bold: object.fontBold, italic: object.fontItalic).fontName,
                                  size: max(1, baseFitted * CGFloat(renderScale))))
                    .underline(object.fontUnderline, color: object.color)
                    .strikethrough(object.fontStrikethrough, color: object.color)
                    .lineLimit(1).minimumScaleFactor(1)
                    .foregroundStyle(object.color)
                    .frame(width: object.width * renderScale, height: object.height * renderScale)
                    .scaleEffect(scale / max(0.0001, renderScale))
                    .frame(width: w, height: h)
            case .line:
                Path { path in path.move(to: .zero); path.addLine(to: CGPoint(x: w, y: h)) }
                    .stroke(object.color, lineWidth: selected ? 2 : 1.4).frame(width: w, height: h)
            case .path:
                let subpaths = object.resolvedSubpaths
                let outline = Path { path in
                    for subpath in subpaths {
                        guard let first = subpath.points.first else { continue }
                        path.move(to: CGPoint(x: first.x * scale, y: first.y * scale))
                        for point in subpath.points.dropFirst() {
                            path.addLine(to: CGPoint(x: point.x * scale, y: point.y * scale))
                        }
                        if subpath.isClosed { path.closeSubpath() }
                    }
                }
                if shaded {
                    let closedOutline = Path { path in
                        for subpath in subpaths where subpath.isClosed || subpath.points.count > 2 {
                            guard let first = subpath.points.first else { continue }
                            path.move(to: CGPoint(x: first.x * scale, y: first.y * scale))
                            for point in subpath.points.dropFirst() {
                                path.addLine(to: CGPoint(x: point.x * scale, y: point.y * scale))
                            }
                            path.closeSubpath()
                        }
                    }
                    closedOutline.fill(shade, style: FillStyle(eoFill: true)).frame(width: w, height: h)
                }
                outline.stroke(object.color, style: StrokeStyle(lineWidth: selected ? 2 : 1.4, dash: object.isToolLayer ? [5, 3] : [])).frame(width: w, height: h)
            case .image:
                let hasProcessing = object.imageDitherMode != .grayscale ||
                    abs(object.imageBrightness) > 0.01 ||
                    abs(object.imageContrast) > 0.01 ||
                    abs(object.imageGamma - 1.0) > 0.01 ||
                    object.imageEnhanceRadius > 0.1
                if hasProcessing, let processed = ImageImporter.processedNSImage(for: object) {
                    Image(nsImage: processed).resizable().interpolation(.none)
                        .frame(width: w, height: h).clipped()
                        .overlay(Rectangle().stroke(object.color, lineWidth: selected ? 2 : 1.2))
                } else if let data = object.imageData, let image = NSImage(data: data) {
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
        CGPoint(x: min(workspace.width, max(0, (location.x - origin.x) / scale)), y: min(workspace.height, max(0, (location.y - origin.y) / scale)))
    }

    private func grid(origin: CGPoint, scale: Double, viewportSize: CGSize) -> some View {
        Canvas { context, _ in
            guard scale > 0 else { return }
            var stepMM = 10.0
            while stepMM * scale > 120.0 {
                stepMM /= 10.0
            }
            while stepMM * scale < 8.0 {
                stepMM *= 10.0
            }
            let spacing = stepMM * scale
            let wsMinX = origin.x
            let wsMaxX = origin.x + workspace.width * scale
            let wsMinY = origin.y
            let wsMaxY = origin.y + workspace.height * scale

            let visMinX = max(wsMinX, 0)
            let visMaxX = min(wsMaxX, viewportSize.width)
            let visMinY = max(wsMinY, 0)
            let visMaxY = min(wsMaxY, viewportSize.height)
            guard visMaxX > visMinX, visMaxY > visMinY else { return }

            let startStepX = max(0, Int(floor((visMinX - origin.x) / spacing)))
            let endStepX = min(Int(ceil(workspace.width / stepMM)), Int(ceil((visMaxX - origin.x) / spacing)))
            let startStepY = max(0, Int(floor((visMinY - origin.y) / spacing)))
            let endStepY = min(Int(ceil(workspace.height / stepMM)), Int(ceil((visMaxY - origin.y) / spacing)))

            var minor = Path()
            var major = Path()
            if startStepX <= endStepX {
                for step in startStepX...endStepX {
                    let x = origin.x + CGFloat(step) * spacing
                    if x >= visMinX - 1 && x <= visMaxX + 1 {
                        if step % 5 == 0 {
                            major.move(to: CGPoint(x: x, y: visMinY))
                            major.addLine(to: CGPoint(x: x, y: visMaxY))
                        } else {
                            minor.move(to: CGPoint(x: x, y: visMinY))
                            minor.addLine(to: CGPoint(x: x, y: visMaxY))
                        }
                    }
                }
            }
            if startStepY <= endStepY {
                for step in startStepY...endStepY {
                    let y = origin.y + CGFloat(step) * spacing
                    if y >= visMinY - 1 && y <= visMaxY + 1 {
                        if step % 5 == 0 {
                            major.move(to: CGPoint(x: visMinX, y: y))
                            major.addLine(to: CGPoint(x: visMaxX, y: y))
                        } else {
                            minor.move(to: CGPoint(x: visMinX, y: y))
                            minor.addLine(to: CGPoint(x: visMaxX, y: y))
                        }
                    }
                }
            }
            context.stroke(minor, with: .color(.white.opacity(0.055)), lineWidth: 0.5)
            context.stroke(major, with: .color(.white.opacity(0.11)), lineWidth: 0.65)
        }
    }
}

private enum CanvasMouseButton: Equatable { case left, right }

private struct CanvasMouseInput: NSViewRepresentable {
    var onMove: (CGPoint?) -> Void
    var onDown: (CGPoint, CanvasMouseButton) -> Void
    var onDrag: (CGPoint) -> Void
    var onUp: (CGPoint) -> Void
    var onZoom: ((CGPoint, Double) -> Void)? = nil
    var onPan: ((CGSize) -> Void)? = nil
    var onKeyDown: ((NSEvent) -> Bool)? = nil

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
        view.onZoom = onZoom
        view.onPan = onPan
        view.onKeyDown = onKeyDown
    }

    final class MouseView: NSView {
        var onMove: ((CGPoint?) -> Void)?
        var onDown: ((CGPoint, CanvasMouseButton) -> Void)?
        var onDrag: ((CGPoint) -> Void)?
        var onUp: ((CGPoint) -> Void)?
        var onZoom: ((CGPoint, Double) -> Void)?
        var onPan: ((CGSize) -> Void)?
        var onKeyDown: ((NSEvent) -> Bool)?
        private var lastMiddlePoint: CGPoint?
        private var isSpacebarPressed = false
        private var lastSpaceDragPoint: CGPoint?

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

        override func mouseDown(with event: NSEvent) {
            let pt = canvasPoint(for: event)
            window?.makeFirstResponder(self)
            if isSpacebarPressed {
                lastSpaceDragPoint = pt
                return
            }
            handleDown(event, button: .left)
        }
        override func rightMouseDown(with event: NSEvent) { handleDown(event, button: .right) }
        override func otherMouseDown(with event: NSEvent) {
            lastMiddlePoint = canvasPoint(for: event)
        }
        override func mouseMoved(with event: NSEvent) { onMove?(canvasPoint(for: event)) }
        override func mouseExited(with event: NSEvent) { onMove?(nil) }
        override func mouseDragged(with event: NSEvent) {
            let current = canvasPoint(for: event)
            if isSpacebarPressed {
                if let prev = lastSpaceDragPoint {
                    onPan?(CGSize(width: current.x - prev.x, height: current.y - prev.y))
                }
                lastSpaceDragPoint = current
                return
            }
            onDrag?(current)
        }
        override func rightMouseDragged(with event: NSEvent) {
            onDrag?(canvasPoint(for: event))
        }
        override func otherMouseDragged(with event: NSEvent) {
            let current = canvasPoint(for: event)
            if let prev = lastMiddlePoint {
                onPan?(CGSize(width: current.x - prev.x, height: current.y - prev.y))
            }
            lastMiddlePoint = current
        }

        override func mouseUp(with event: NSEvent) {
            if isSpacebarPressed {
                lastSpaceDragPoint = nil
                return
            }
            onUp?(canvasPoint(for: event))
        }
        override func rightMouseUp(with event: NSEvent) {
            onUp?(canvasPoint(for: event))
        }
        override func otherMouseUp(with event: NSEvent) {
            lastMiddlePoint = nil
        }

        override func keyDown(with event: NSEvent) {
            if event.keyCode == 49 { // Spacebar
                isSpacebarPressed = true
                return
            }
            if onKeyDown?(event) == true {
                return
            }
            super.keyDown(with: event)
        }

        override func keyUp(with event: NSEvent) {
            if event.keyCode == 49 {
                isSpacebarPressed = false
                lastSpaceDragPoint = nil
                return
            }
            super.keyUp(with: event)
        }

        override func magnify(with event: NSEvent) {
            let factor = max(0.2, 1.0 + Double(event.magnification))
            onZoom?(canvasPoint(for: event), factor)
        }

        override func scrollWheel(with event: NSEvent) {
            let isZoomModifier = event.modifierFlags.contains(.option) || event.modifierFlags.contains(.command)
            if !event.hasPreciseScrollingDeltas || isZoomModifier {
                let delta = Double(event.scrollingDeltaY)
                guard abs(delta) > 0.001 else { return }
                let sensitivity = event.hasPreciseScrollingDeltas ? 0.012 : 0.12
                let factor = exp(delta * sensitivity)
                onZoom?(canvasPoint(for: event), factor)
            } else {
                onPan?(CGSize(width: event.scrollingDeltaX, height: event.scrollingDeltaY))
            }
        }
    }
}
