import SwiftUI
import simd

struct PlacementView: View {
    @ObservedObject var placement: TablePlacement

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Table placement", systemImage: "table.furniture")
                    .font(.title2.bold())
                Spacer()
                if placement.snapshot.isConfirmed {
                    Label(placement.snapshot.isVirtual ? "Virtual" : (placement.snapshot.trackingAvailable ? "Anchored" : "Recovering"), systemImage: placement.snapshot.trackingAvailable ? "checkmark.circle.fill" : "location.slash")
                        .foregroundStyle(placement.snapshot.trackingAvailable ? .green : .orange)
                }
            }
            Text(placement.status).font(.callout).foregroundStyle(.secondary)
            if let error = placement.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange).font(.callout)
            }
            if placement.snapshot.isConfirmed {
                confirmedControls
            } else {
                if placement.isPlacingCorners { cornerControls }
                else { detectedSurfaceControls }
                Divider()
                virtualControls
            }
        }
        .padding(20)
        .accessibilityElement(children: .contain)
        }
    }

    private var confirmedControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            boundaryPreview(placement.snapshot.boundary)
            Text(String(format: "Board size: %.2f × %.2f metres", placement.snapshot.size.x, placement.snapshot.size.y))
                .font(.caption).foregroundStyle(.secondary)
            if !placement.snapshot.trackingAvailable {
                Text("Look around the room and toward the table. Game input should remain paused until tracking returns. Reposition only if the saved anchor cannot recover.")
                    .font(.callout)
            }
            if placement.snapshot.isVirtual {
                Divider()
                virtualControls
            }
            Button(placement.snapshot.isVirtual ? "Choose a physical table" : "Reposition table", systemImage: "arrow.triangle.2.circlepath") { placement.resetPlacement() }
        }
    }

    private var detectedSurfaceControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !placement.supportsWorldTracking {
                Label("The simulator does not supply physical room tracking.", systemImage: "desktopcomputer")
                    .font(.callout)
            } else if !placement.isRunning {
                Label("Open the immersive table to scan your room.", systemImage: "viewfinder")
                    .font(.callout)
            } else if placement.surfaces.isEmpty {
                Label("Scanning horizontal surfaces…", systemImage: "viewfinder")
                Text("Look across the tabletop and its edges. If no suitable surface appears, place four corners.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Detected horizontal surfaces").font(.headline)
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(placement.surfaces) { surface in
                            Button {
                                placement.selectedSurfaceID = surface.id
                            } label: {
                                HStack {
                                    Image(systemName: placement.selectedSurfaceID == surface.id ? "checkmark.circle.fill" : "circle")
                                    Text(surface.title)
                                    Spacer()
                                }.frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(placement.selectedSurfaceID == surface.id ? .cyan : .gray)
                            .accessibilityLabel("Select \(surface.title)")
                        }
                    }
                }.frame(maxHeight: 180)
                if let surface = placement.selectedSurface { boundaryPreview(surface.boundary) }
            }
            HStack {
                Button("Four-corner fallback", systemImage: "square.dashed") { placement.beginFourCorners() }
                    .disabled(!placement.isRunning)
                Spacer()
                confirmButton
            }
        }
    }

    private var cornerControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Four corners · \(placement.manualCorners.count) of 4").font(.headline)
            Text("Set the height before the first corner. Look at each corner and pinch, working clockwise around the table. A visible outline shows the boundary.")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Text(String(format: "Table height %.2f m", placement.manualHeight))
                    .monospacedDigit().frame(width: 165, alignment: .leading)
                Slider(value: $placement.manualHeight, in: -1.5...2.0, step: 0.01)
                    .disabled(!placement.manualCorners.isEmpty)
                    .accessibilityLabel("Tabletop height in world metres")
            }
            let points = placement.manualGeometry?.boundary ?? placement.manualCorners.map { SIMD2($0.x, $0.z) }
            boundaryPreview(points)
            HStack {
                Button("Undo corner", systemImage: "arrow.uturn.backward") { placement.undoCorner() }
                    .disabled(placement.manualCorners.isEmpty)
                Button("Cancel") { placement.cancelFourCorners() }
                Spacer()
                confirmButton
            }
        }
    }

    private var confirmButton: some View {
        Button {
            Task { await placement.confirmPlacement() }
        } label: {
            Label(placement.isConfirming ? "Anchoring…" : "Confirm table", systemImage: "checkmark")
        }
        .buttonStyle(.borderedProminent)
        .disabled(!placement.canConfirm)
    }

    private var virtualControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Virtual table").font(.headline)
            Text("Position the board in front of you, below eye level. Changes apply when you press the button. This does not detect or anchor a physical table.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Text(String(format: "Width %.1f m", placement.virtualWidth)).monospacedDigit().frame(width: 105, alignment: .leading)
                Slider(value: $placement.virtualWidth, in: 0.4...2.0, step: 0.1).accessibilityLabel("Virtual board width")
            }
            HStack {
                Text(String(format: "Depth %.1f m", placement.virtualDepth)).monospacedDigit().frame(width: 105, alignment: .leading)
                Slider(value: $placement.virtualDepth, in: 0.4...1.6, step: 0.1).accessibilityLabel("Virtual board depth")
            }
            HStack {
                Text(String(format: "Distance %.2f m", placement.virtualDistance)).monospacedDigit().frame(width: 140, alignment: .leading)
                Slider(value: $placement.virtualDistance, in: 0.8...2.8, step: 0.05).accessibilityLabel("Virtual board distance in front of you")
            }
            HStack {
                Text(String(format: "Below eyes %.2f m", placement.virtualDrop)).monospacedDigit().frame(width: 140, alignment: .leading)
                Slider(value: $placement.virtualDrop, in: 0.15...1.1, step: 0.05).accessibilityLabel("Virtual board height below your eyes")
            }
            Button(placement.snapshot.isVirtual ? "Apply and center in front of me" : "Use virtual table", systemImage: "cube.transparent") { placement.placeVirtualTable() }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("table.virtual.apply")
        }
    }

    private func boundaryPreview(_ points: [SIMD2<Float>]) -> some View {
        Canvas { context, size in
            guard !points.isEmpty else { return }
            let low = points.reduce(SIMD2<Float>(repeating: .infinity)) { simd_min($0, $1) }
            let high = points.reduce(SIMD2<Float>(repeating: -.infinity)) { simd_max($0, $1) }
            let span = simd_max(high - low, SIMD2<Float>(repeating: 0.2))
            let scale: CGFloat = min((size.width - CGFloat(36)) / CGFloat(span.x), (size.height - CGFloat(30)) / CGFloat(span.y))
            let center = (low + high) / 2
            let vertices = points.map { CGPoint(x: size.width / 2 + CGFloat($0.x - center.x) * scale, y: size.height / 2 + CGFloat($0.y - center.y) * scale) }
            var path = Path()
            path.move(to: vertices[0])
            for vertex in vertices.dropFirst() { path.addLine(to: vertex) }
            if vertices.count >= 3 { path.closeSubpath(); context.fill(path, with: .color(.cyan.opacity(0.15))) }
            context.stroke(path, with: .color(.cyan), style: StrokeStyle(lineWidth: 2, dash: vertices.count < 4 ? [4, 4] : []))
            for (index, vertex) in vertices.enumerated() {
                context.fill(Path(ellipseIn: CGRect(x: vertex.x - 4, y: vertex.y - 4, width: 8, height: 8)), with: .color(.cyan))
                context.draw(Text("\(index + 1)").font(.caption2.bold()).foregroundColor(.white), at: CGPoint(x: vertex.x, y: vertex.y - 12))
            }
        }
        .frame(height: 120)
        .background(.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityLabel("Table boundary preview with \(points.count) vertices")
    }
}
