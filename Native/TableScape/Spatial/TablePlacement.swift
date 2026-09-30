import ARKit
import Combine
import Foundation
import Metal
import QuartzCore
import simd

struct TablePlacementSnapshot: Sendable {
    var originFromTable = matrix_identity_float4x4
    var size = SIMD2<Float>(1.2, 0.8)
    var boundary: [SIMD2<Float>] = []
    var renderBoundary: [SIMD2<Float>] { TableGeometry.renderBoundary(boundary: boundary, size: size) }
    var isConfirmed = false
    var trackingAvailable = false
    var isVirtual = false
}

struct TableSurface: Identifiable, Sendable {
    let id: UUID
    let geometry: TableGeometry
    let classification: String
    var originFromTable: simd_float4x4 { geometry.originFromTable }
    var size: SIMD2<Float> { geometry.size }
    var boundary: [SIMD2<Float>] { geometry.boundary }
    var title: String { "\(classification.capitalized) · \(String(format: "%.2f × %.2f m", size.x, size.y))" }
}

/// Stable render-thread handle; reopening ARKit replaces the provider without invalidating this object.
final class TableTrackingSource: @unchecked Sendable {
    private let lock = NSLock()
    private var provider: WorldTrackingProvider?
    func replace(with provider: WorldTrackingProvider?) {
        lock.lock(); self.provider = provider; lock.unlock()
    }
    func queryDeviceAnchor(atTimestamp timestamp: TimeInterval) -> DeviceAnchor? {
        lock.lock(); let current = provider; lock.unlock()
        guard let current, current.state == .running else { return nil }
        guard let anchor = current.queryDeviceAnchor(atTimestamp: timestamp), anchor.isTracked else { return nil }
        return anchor
    }
}

@MainActor
final class TablePlacement: ObservableObject {
    @Published private(set) var snapshot = TablePlacementSnapshot()
    @Published private(set) var surfaces: [TableSurface] = []
    @Published var selectedSurfaceID: UUID?
    @Published private(set) var manualCorners: [SIMD3<Float>] = []
    @Published private(set) var isPlacingCorners = false
    @Published private(set) var status = "Open the immersive table to begin placement."
    @Published private(set) var errorMessage: String?
    @Published private(set) var isRunning = false
    @Published private(set) var isConfirming = false
    @Published private(set) var devicePose: simd_float4x4?
    @Published var manualHeight: Float = 0.75
    @Published var virtualWidth: Float = 1.2
    @Published var virtualDepth: Float = 0.8
    @Published var virtualDistance: Float = 1.6
    @Published var virtualDrop: Float = 0.45
    /// Optional callback enables the renderer to copy state into its own synchronized snapshot.
    var onSnapshotChanged: ((TablePlacementSnapshot) -> Void)?

    private(set) var worldTracking = WorldTrackingProvider()
    nonisolated let trackingSource = TableTrackingSource()
    private var planeDetection = PlaneDetectionProvider(alignments: [.horizontal])
    private let session = ARKitSession()
    private var tasks: [Task<Void, Never>] = []
    private var anchorID: UUID?
    private var anchorTracked = false
    private var confirmedGeometry: TableGeometry?
    private var lifecycle = UUID()
    private var placementRevision = UUID()
    private var isStarting = false
    private var hasStarted = false
    private let savedTableKey = "TableScape.physicalTable.v1"

    private struct SavedTable: Codable {
        let anchorID: UUID
        let matrix: [Float]
        let size: [Float]
        let boundary: [[Float]]
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: savedTableKey),
           let saved = try? JSONDecoder().decode(SavedTable.self, from: data),
           saved.matrix.count == 16, saved.size.count == 2,
           saved.matrix.allSatisfy({ $0.isFinite }), saved.size.allSatisfy({ $0.isFinite && $0 > 0 }),
           saved.boundary.count >= 3,
           saved.boundary.allSatisfy({ $0.count == 2 && $0.allSatisfy({ $0.isFinite }) }) {
            let c = saved.matrix
            let transform = simd_float4x4(columns: (SIMD4(c[0], c[1], c[2], c[3]), SIMD4(c[4], c[5], c[6], c[7]), SIMD4(c[8], c[9], c[10], c[11]), SIMD4(c[12], c[13], c[14], c[15])))
            anchorID = saved.anchorID
            snapshot = TablePlacementSnapshot(originFromTable: transform, size: SIMD2(saved.size[0], saved.size[1]), boundary: saved.boundary.map { SIMD2($0[0], $0[1]) }, isConfirmed: true, trackingAvailable: false, isVirtual: false)
            status = "Saved table found. Open the immersive space and look around to recover its anchor."
        }
    }

    var supportsWorldTracking: Bool { WorldTrackingProvider.isSupported }
    var supportsPlaneDetection: Bool { PlaneDetectionProvider.isSupported }
    var selectedSurface: TableSurface? { surfaces.first { $0.id == selectedSurfaceID } }
    var manualGeometry: TableGeometry? { try? TableGeometry.validating(corners: manualCorners) }
    var canConfirm: Bool { !isConfirming && isRunning && devicePose != nil && (isPlacingCorners ? manualGeometry != nil : selectedSurface != nil) }

    func start() async {
        guard !isRunning, !isStarting else { return }
        guard WorldTrackingProvider.isSupported else {
            status = "ARKit world tracking is unavailable here. Use an explicit virtual table to play in the simulator."
            return
        }
        let token = UUID()
        lifecycle = token
        isStarting = true
        defer { if lifecycle == token { isStarting = false } }
        if hasStarted {
            tasks.forEach { $0.cancel() }
            tasks.removeAll()
            session.stop()
            worldTracking = WorldTrackingProvider()
            planeDetection = PlaneDetectionProvider(alignments: [.horizontal])
            surfaces = []
            if !snapshot.isConfirmed { selectedSurfaceID = nil }
        }
        hasStarted = true
        anchorTracked = false
        trackingSource.replace(with: worldTracking)
        errorMessage = nil
        status = "Starting world tracking…"
        var providers: [any DataProvider] = [worldTracking]
        if PlaneDetectionProvider.isSupported {
            let result = await session.requestAuthorization(for: [.worldSensing])
            guard token == lifecycle else { return }
            if result[.worldSensing] == .allowed {
                providers.append(planeDetection)
            } else {
                status = "Surface detection permission is unavailable. Use four-corner placement."
            }
        }
        do {
            try await session.run(providers)
            guard token == lifecycle else { return }
            isRunning = true
            if snapshot.isConfirmed && !snapshot.isVirtual {
                status = "Recovering the saved table anchor. Look around the room; the table pose is preserved."
            } else {
                status = providers.count > 1 ? "Look around the table. Choose a highlighted horizontal surface, then confirm." : "World tracking is ready. Use four corners to define your table."
            }
            tasks.append(Task { [weak self] in await self?.observePlanes() })
            tasks.append(Task { [weak self] in await self?.observeAnchors() })
            tasks.append(Task { [weak self] in await self?.observeSession() })
            tasks.append(Task { [weak self] in
                while !Task.isCancelled {
                    self?.updateDeviceTracking()
                    try? await Task.sleep(for: .milliseconds(100))
                }
            })
        } catch {
            guard token == lifecycle else { return }
            errorMessage = "World tracking could not start: \(error.localizedDescription)"
            status = "Tracking unavailable. Reopen the immersive table to retry."
            isRunning = false
        }
    }

    func stop() {
        lifecycle = UUID()
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        persistPhysicalTable()
        session.stop()
        trackingSource.replace(with: nil)
        isStarting = false
        isRunning = false
        devicePose = nil
        if !snapshot.isVirtual {
            snapshot.trackingAvailable = false
            publish()
            status = snapshot.isConfirmed ? "Immersive table closed. The saved anchor will be checked when tracking resumes." : "Open the immersive table to begin placement."
        }
    }

    func beginFourCorners() {
        guard !snapshot.isConfirmed else { return }
        manualCorners = []
        isPlacingCorners = true
        selectedSurfaceID = nil
        errorMessage = nil
        if let devicePose { manualHeight = devicePose.columns.3.y - 0.65 }
        status = "Set the tabletop height, then pinch four corners in order around its edge."
    }

    func cancelFourCorners() {
        manualCorners = []
        isPlacingCorners = false
        errorMessage = nil
        status = "Choose a detected horizontal surface and confirm it."
    }

    func undoCorner() {
        guard !manualCorners.isEmpty else { return }
        manualCorners.removeLast()
        errorMessage = nil
        status = "Corner removed. Place corner \(manualCorners.count + 1) of 4."
    }

    /// Supply world-space positions for a direct-pinch input path, or call handleSelectionRay.
    func addCorner(_ worldPosition: SIMD3<Float>) {
        guard isPlacingCorners, manualCorners.count < 4, !snapshot.isConfirmed else { return }
        guard worldPosition.x.isFinite, worldPosition.y.isFinite, worldPosition.z.isFinite else { return }
        manualCorners.append(worldPosition)
        errorMessage = nil
        if manualCorners.count == 4 {
            do {
                _ = try TableGeometry.validating(corners: manualCorners)
                status = "Four corners are valid. Review the boundary and confirm your table."
            } catch {
                errorMessage = error.localizedDescription
                status = "Adjust the boundary with Undo, then place the last corner again."
            }
        } else { status = "Corner \(manualCorners.count) placed. Place corner \(manualCorners.count + 1) of 4." }
    }

    /// Returns true when placement consumed this pinch; gameplay must not also receive it.
    @discardableResult
    func handleSelectionRay(origin: SIMD3<Float>, direction: SIMD3<Float>) -> Bool {
        guard !snapshot.isConfirmed else { return !snapshot.isVirtual && !snapshot.trackingAvailable }
        guard isRunning, devicePose != nil else { return true }
        let length = simd_length(direction)
        guard length.isFinite, length > 0.0001 else { return true }
        let ray = direction / length
        if isPlacingCorners {
            guard manualCorners.count < 4 else { return true }
            guard abs(ray.y) > 0.00001 else {
                errorMessage = "Look down toward the tabletop to place a corner."
                return true
            }
            let t = (manualHeight - origin.y) / ray.y
            guard t > 0, t < 5 else {
                errorMessage = "Aim at the tabletop within 5 metres. Adjust its height if needed."
                return true
            }
            addCorner(origin + ray * t)
        } else {
            let hits = surfaces.compactMap { surface -> (UUID, Float)? in
                guard let point = surface.geometry.intersect(rayOrigin: origin, rayDirection: ray) else { return nil }
                return (surface.id, simd_distance(origin, point))
            }
            if let nearest = hits.min(by: { $0.1 < $1.1 }) {
                selectedSurfaceID = nearest.0
                status = "Surface selected. Confirm it in the placement panel."
            }
        }
        return true
    }

    func confirmPlacement() async {
        guard canConfirm else { return }
        let geometry: TableGeometry
        if isPlacingCorners {
            do { geometry = try TableGeometry.validating(corners: manualCorners) }
            catch { errorMessage = error.localizedDescription; return }
        } else {
            guard let selectedSurface else { return }
            geometry = selectedSurface.geometry
        }
        let token = lifecycle
        let revision = placementRevision
        let provider = worldTracking
        isConfirming = true
        defer { isConfirming = false }
        let anchor = WorldAnchor(originFromAnchorTransform: geometry.originFromTable)
        let previousID = anchorID
        anchorID = anchor.id
        anchorTracked = false
        do {
            try await provider.addAnchor(anchor)
            guard token == lifecycle, revision == placementRevision else {
                try? await provider.removeAnchor(forID: anchor.id)
                return
            }
            confirmedGeometry = geometry
            snapshot = TablePlacementSnapshot(originFromTable: geometry.originFromTable, size: geometry.size, boundary: geometry.boundary, isConfirmed: true, trackingAvailable: anchorTracked && devicePose != nil, isVirtual: false)
            isPlacingCorners = false
            errorMessage = nil
            status = snapshot.trackingAvailable ? "Table anchored in the room." : "Table anchor created. Waiting for tracking."
            persistPhysicalTable()
            publish()
            if let previousID, previousID != anchor.id { try? await worldTracking.removeAnchor(forID: previousID) }
        } catch {
            guard token == lifecycle, revision == placementRevision else { return }
            anchorID = previousID
            errorMessage = "The table anchor could not be created: \(error.localizedDescription)"
        }
    }

    /// Deliberate simulation path. This never claims to have detected or anchored a physical table.
    func placeVirtualTable(width: Float? = nil, depth: Float? = nil, center: SIMD3<Float>? = nil) {
        placementRevision = UUID()
        UserDefaults.standard.removeObject(forKey: savedTableKey)
        if let width { virtualWidth = width }
        if let depth { virtualDepth = depth }
        let viewer = trackingSource.queryDeviceAnchor(atTimestamp: CACurrentMediaTime())?.originFromAnchorTransform ?? devicePose ?? matrix_identity_float4x4
        let position = center ?? TableGeometry.virtualCenter(viewerTransform: viewer, distance: virtualDistance, drop: virtualDrop)
        let geometry = TableGeometry.rectangle(width: virtualWidth, depth: virtualDepth, center: position)
        removeOwnedAnchor()
        confirmedGeometry = geometry
        snapshot = TablePlacementSnapshot(originFromTable: geometry.originFromTable, size: geometry.size, boundary: geometry.boundary, isConfirmed: true, trackingAvailable: true, isVirtual: true)
        isPlacingCorners = false
        manualCorners = []
        errorMessage = nil
        status = "Virtual table active. Physical placement and tracking are not being tested."
        publish()
    }

    func resetPlacement() {
        placementRevision = UUID()
        UserDefaults.standard.removeObject(forKey: savedTableKey)
        removeOwnedAnchor()
        confirmedGeometry = nil
        snapshot = TablePlacementSnapshot()
        manualCorners = []
        selectedSurfaceID = nil
        isPlacingCorners = false
        errorMessage = nil
        status = isRunning ? "Choose a new surface, or place four corners." : "Choose a virtual table, or open the immersive space for tracking."
        publish()
    }

    private func removeOwnedAnchor() {
        guard let id = anchorID else { return }
        anchorID = nil
        anchorTracked = false
        Task { [worldTracking] in try? await worldTracking.removeAnchor(forID: id) }
    }

    private func publish() { onSnapshotChanged?(snapshot) }

    private func persistPhysicalTable() {
        guard let anchorID, snapshot.isConfirmed, !snapshot.isVirtual else { return }
        let t = snapshot.originFromTable
        let matrix = [t.columns.0, t.columns.1, t.columns.2, t.columns.3].flatMap { [$0.x, $0.y, $0.z, $0.w] }
        let saved = SavedTable(anchorID: anchorID, matrix: matrix, size: [snapshot.size.x, snapshot.size.y], boundary: snapshot.boundary.map { [$0.x, $0.y] })
        if let data = try? JSONEncoder().encode(saved) { UserDefaults.standard.set(data, forKey: savedTableKey) }
    }

    private func updateDeviceTracking() {
        let current = worldTracking.state == .running ? worldTracking.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()) : nil
        devicePose = current?.isTracked == true ? current?.originFromAnchorTransform : nil
        guard snapshot.isConfirmed, !snapshot.isVirtual else { return }
        let tracked = devicePose != nil && anchorTracked
        if tracked != snapshot.trackingAvailable {
            snapshot.trackingAvailable = tracked
            status = tracked ? "Table tracking recovered at its saved anchor." : "Tracking lost. The table remains at its saved position; look around to recover."
            publish()
        }
    }

    private func observePlanes() async {
        for await update in planeDetection.anchorUpdates {
            guard !Task.isCancelled else { return }
            let anchor = update.anchor
            switch update.event {
            case .removed:
                surfaces.removeAll { $0.id == anchor.id }
                if selectedSurfaceID == anchor.id, !snapshot.isConfirmed { selectedSurfaceID = nil }
            case .added, .updated:
                guard anchor.alignment == .horizontal else { continue }
                let extent = anchor.geometry.extent
                guard extent.width >= 0.2, extent.height >= 0.2 else { continue }
                let transform = anchor.originFromAnchorTransform * extent.anchorFromExtentTransform
                let inverseExtent = simd_inverse(extent.anchorFromExtentTransform)
                let vertices = anchor.geometry.meshVertices
                var points: [SIMD2<Float>] = []
                if vertices.format == .float3 {
                    let buffer = vertices.buffer.contents()
                    for index in 0..<vertices.count {
                        let address = buffer.advanced(by: vertices.offset + index * vertices.stride)
                        let x = address.loadUnaligned(as: Float.self)
                        let y = address.advanced(by: 4).loadUnaligned(as: Float.self)
                        let z = address.advanced(by: 8).loadUnaligned(as: Float.self)
                        let point = inverseExtent * SIMD4(x, y, z, 1)
                        points.append(SIMD2(point.x, point.z))
                    }
                }
                var boundary = TableGeometry.boundedHull(TableGeometry.convexHull(points))
                if boundary.count < 3 {
                    boundary = TableGeometry.rectangle(width: extent.width, depth: extent.height, center: .zero).boundary
                }
                let geometry = TableGeometry(originFromTable: transform, size: SIMD2(extent.width, extent.height), boundary: boundary)
                let classification: String
                if #available(visionOS 26.0, *) { classification = String(describing: anchor.surfaceClassification) }
                else { classification = String(describing: anchor.classification) }
                let surface = TableSurface(id: anchor.id, geometry: geometry, classification: classification)
                if let index = surfaces.firstIndex(where: { $0.id == anchor.id }) { surfaces[index] = surface }
                else { surfaces.append(surface) }
                surfaces.sort { $0.size.x * $0.size.y > $1.size.x * $1.size.y }
            @unknown default: break
            }
        }
    }

    private func observeAnchors() async {
        for await update in worldTracking.anchorUpdates {
            guard !Task.isCancelled else { return }
            guard update.anchor.id == anchorID else { continue }
            if update.event == .removed {
                anchorTracked = false
                snapshot.trackingAvailable = false
                status = "The table anchor is unavailable. Reposition the table to continue."
                publish()
            } else {
                anchorTracked = update.anchor.isTracked
                // Only the same confirmed anchor may refine the pose. Never substitute the headset or a detected plane.
                if anchorTracked, snapshot.isConfirmed, !snapshot.isVirtual {
                    snapshot.originFromTable = update.anchor.originFromAnchorTransform
                    publish()
                }
                updateDeviceTracking()
            }
        }
    }

    private func observeSession() async {
        for await event in session.events {
            guard !Task.isCancelled else { return }
            switch event {
            case .authorizationChanged(let type, let status):
                if type == .worldSensing, status == .denied {
                    errorMessage = "World sensing permission was denied. Enable it in Settings to detect surfaces, or use four corners."
                }
            case .dataProviderStateChanged(let providers, let state, let error):
                // Ignore queued events from replaced providers; stopping plane detection
                // alone must not invalidate a still-tracked world anchor.
                let affectsWorld = providers.contains { $0 === worldTracking }
                let affectsPlanes = providers.contains { $0 === planeDetection }
                guard affectsWorld || affectsPlanes else { continue }
                if let error { errorMessage = "ARKit: \(error.localizedDescription)" }
                if affectsPlanes && state == .stopped {
                    surfaces = []
                    if !snapshot.isConfirmed { selectedSurfaceID = nil }
                }
                if affectsWorld && (state == .paused || state == .stopped) {
                    devicePose = nil
                    if state == .stopped {
                        isRunning = false
                        anchorTracked = false
                        trackingSource.replace(with: nil)
                    }
                    if !snapshot.isVirtual {
                        snapshot.trackingAvailable = false
                        status = state == .stopped ? "Tracking stopped. Reopen the immersive table to recover the saved anchor." : "Tracking paused. The table pose is preserved while tracking recovers."
                        publish()
                    }
                }
            @unknown default: break
            }
        }
    }
}
