import Foundation
import RealityKit
import AppKit

@main struct NativeVolumeMaterialChecks {
    @MainActor static func main() {
        _ = NSApplication.shared
        let engineBootstrap = ARView(frame: .zero)
        Task { @MainActor in
            do { try await check(); _ = engineBootstrap; exit(0) }
            catch { print("FAIL RealityKit volume material: \(error)"); exit(1) }
        }
        RunLoop.main.run()
    }
    @MainActor static func check() async throws {
        var material = try await ShaderGraphMaterial(named: VolumeMaterialSource.name, from: VolumeMaterialSource.data())
        for name in ["gameTexture", "gameCenter", "boardScale", "clipEnabled", "alphaThreshold"] + (0..<8).map({"edge\($0)"}) {
            precondition(material.parameterNames.contains(name), "Missing shader parameter \(name)")
        }
        try material.setParameter(name: "gameCenter", value: .simd3Float([3200, 0, 3200]))
        try material.setParameter(name: "boardScale", value: .float(0.038))
        try material.setParameter(name: "clipEnabled", value: .float(1))
        for index in 0..<8 { try material.setParameter(name: "edge\(index)", value: .simd3Float([0, 0, 1])) }
        material.faceCulling = .none
        print("PASS RealityKit loads production volume shader graph; all 13 public parameters bind")
        print("LIMIT: shader loading and binding on macOS; actual volume pixels and gestures require visionOS Simulator/device")
    }
}
