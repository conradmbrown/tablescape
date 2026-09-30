import Foundation
import RealityKit
import AppKit
import Metal
import ImageIO

/// Real offscreen GPU rendering of the shipped graph and NativeVertex layout.
/// Loading a ShaderGraphMaterial alone does not compile every graph operation:
/// the former `xz1` swizzle loaded successfully but rendered cyan fallback stripes.
@main struct NativeVolumePixelChecks {
    @MainActor static func main() {
        _ = NSApplication.shared
        let bootstrap = ARView(frame: .zero)
        Task { @MainActor in
            do { try await run(); _ = bootstrap; exit(0) }
            catch { print("FAIL volume GPU pixels: \(error)"); exit(1) }
        }
        RunLoop.main.run()
    }
    static func require(_ condition: Bool, _ message: String) {
        if !condition { print("FAIL volume GPU pixels: \(message)"); fflush(stdout); exit(1) }
    }
    @MainActor static func run() async throws {
        let renderer = try RealityRenderer(), device = MTLCreateSystemDefaultDevice()!
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 256, height: 256, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]; descriptor.storageMode = .shared
        let outputTexture = device.makeTexture(descriptor: descriptor)!
        let output = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: outputTexture))
        let camera = PerspectiveCamera(); camera.position = [0, 0, 3]
        renderer.entities.append(camera); renderer.activeCamera = camera
        renderer.cameraSettings.colorBackground = .color(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        renderer.cameraSettings.isToneMappingEnabled = false

        // Match production LowLevelMesh attributes exactly, with no normals.
        // Game-world coordinates and negative height exercise center subtraction
        // and guarantee the footprint does not introduce a horizontal Y cutoff.
        var vertices: [NativeVertex] = [], indices: [UInt32] = []
        for side in 0..<2 {
            let x0: Float = side == 0 ? -0.8 : 0, x1: Float = side == 0 ? 0 : 0.8
            let color: SIMD4<Float> = side == 0 ? [1, 0.2, 0.2, 1] : [0.2, 1, 0.2, 1]
            let base = UInt32(vertices.count)
            for point: SIMD2<Float> in [[x0, -0.8], [x1, -0.8], [x1, 0.8], [x0, 0.8]] {
                vertices.append(NativeVertex(position: [3200 + point.x, -2 + point.y, 3200], color: color, uv: [side == 0 ? 0.25 : 0.75, 0.5]))
            }
            indices += [base, base + 1, base + 2, base, base + 2, base + 3]
        }
        var meshDescriptor = LowLevelMesh.Descriptor(vertexCapacity: vertices.count, indexCapacity: indices.count)
        meshDescriptor.vertexAttributes = [
            .init(semantic: .position, format: .float3, offset: MemoryLayout<NativeVertex>.offset(of: \.position)!),
            .init(semantic: .color, format: .float4, offset: MemoryLayout<NativeVertex>.offset(of: \.color)!),
            .init(semantic: .uv0, format: .float2, offset: MemoryLayout<NativeVertex>.offset(of: \.uv)!)
        ]
        meshDescriptor.vertexLayouts = [.init(bufferIndex: 0, bufferStride: MemoryLayout<NativeVertex>.stride)]
        let mesh = try LowLevelMesh(descriptor: meshDescriptor)
        mesh.withUnsafeMutableBytes(bufferIndex: 0) { target in vertices.withUnsafeBytes { target.copyMemory(from: $0) } }
        mesh.withUnsafeMutableIndices { target in indices.withUnsafeBytes { target.copyMemory(from: $0) } }
        mesh.parts.replaceAll([.init(indexCount: indices.count, topology: .triangle, materialIndex: 0,
                                    bounds: BoundingBox(min: [3199.2, -2.8, 3199.99], max: [3200.8, -1.2, 3200.01]))])
        var material = try await ShaderGraphMaterial(named: VolumeMaterialSource.name, from: VolumeMaterialSource.data())
        material.faceCulling = .none
        try material.setParameter(name: "gameCenter", value: .simd3Float([3200, 0, 3200]))
        try material.setParameter(name: "boardScale", value: .float(1))
        try material.setParameter(name: "clipEnabled", value: .float(1))
        try material.setParameter(name: "alphaThreshold", value: .float(0.2))
        for index in 0..<8 { try material.setParameter(name: "edge\(index)", value: .simd3Float([0, 0, 1])) }
        let white = try await texture([255, 255, 255, 255, 255, 255, 255, 255])
        try material.setParameter(name: "gameTexture", value: .textureResource(white))
        let entity = ModelEntity(mesh: try await MeshResource(from: mesh), materials: [material])
        entity.position = [-3200, 2, -3200]; renderer.entities.append(entity)

        @MainActor func capture(_ label: String) async throws -> [[UInt8]] {
            entity.model?.materials = [material]
            // Permit RealityKit's asynchronous shader specialization, then read
            // only after the completed GPU command buffer, not a timing guess.
            for _ in 0..<30 {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    do { try renderer.updateAndRender(deltaTime: 1.0/60, cameraOutput: output,
                        onComplete: { _ in continuation.resume() }) }
                    catch { continuation.resume(throwing: error) }
                }
                try await Task.sleep(for: .milliseconds(16))
            }
            var pixels = [UInt8](repeating: 0, count: 256*256*4)
            outputTexture.getBytes(&pixels, bytesPerRow: 256*4, from: MTLRegionMake2D(0, 0, 256, 256), mipmapLevel: 0)
            guard let path = ProcessInfo.processInfo.environment["TABLESCAPE_VOLUME_PIXEL_ARTIFACTS"] else { fatalError("Set TABLESCAPE_VOLUME_PIXEL_ARTIFACTS via the volume test runner") }
            let context = CGContext(data: &pixels, width: 256, height: 256, bitsPerComponent: 8, bytesPerRow: 256*4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path + "/gpu-\(label).png") as CFURL, "public.png" as CFString, 1, nil)!
            CGImageDestinationAddImage(destination, context.makeImage()!, nil); require(CGImageDestinationFinalize(destination), "Could not save \(label)")
            let samples = [101, 155].map { x in Array(pixels[(128*256+x)*4..<(128*256+x)*4+4]) }
            print("GPU \(label) left=\(samples[0]) right=\(samples[1])")
            return samples
        }
        let original = try await capture("vertex-colors")
        require(Int(original[0][0]) > Int(original[0][1])+60 && Int(original[1][1]) > Int(original[1][0])+60, "Original vertex colors missing, or cyan fallback present")
        try material.setParameter(name: "edge0", value: .simd3Float([-1, 0, 0]))
        let xClipped = try await capture("clip-x")
        require(xClipped[0][0] > 100 && xClipped[1].prefix(3).allSatisfy { $0 < 15 }, "XZ plane did not retain left and discard right")
        try material.setParameter(name: "edge0", value: .simd3Float([0, 1, -0.1]))
        let zClipped = try await capture("clip-z")
        require(zClipped.allSatisfy { $0.prefix(3).allSatisfy { $0 < 15 } }, "Z extraction/constant plane offset failed")
        try material.setParameter(name: "clipEnabled", value: .float(0))
        let billboard = try await capture("clip-disabled")
        require(billboard[0][0] > 100 && billboard[1][1] > 100, "Billboard clip bypass failed")
        let colored = try await texture([255, 255, 255, 255, 0, 0, 255, 255])
        try material.setParameter(name: "gameTexture", value: .textureResource(colored))
        let textured = try await capture("texture-uv")
        require(textured[0][0] > 100 && textured[1][2] > 20 && textured[1][1] < 20, "UV0 texture sampling or texture/vertex-color multiply failed")
        let alpha = try await texture([255, 255, 255, 255, 0, 0, 0, 0])
        try material.setParameter(name: "gameTexture", value: .textureResource(alpha))
        let transparent = try await capture("texture-alpha")
        require(transparent[0][0] > 100 && transparent[1].prefix(3).allSatisfy { $0 < 15 }, "Production PNG decoder flattened transparent texels, or texture alpha cutoff failed")
        let magenta = try await texture([255, 255, 255, 255, 255, 0, 255, 255])
        try material.setParameter(name: "gameTexture", value: .textureResource(magenta))
        let keyed = try await capture("texture-magenta")
        require(keyed[0][0] > 100 && keyed[1].prefix(3).allSatisfy { $0 < 15 }, "Original palette-magenta texels were not transparent")
        let fallback = try await TextureResource(image: VolumeTextureImage.decode(nil), options: .init(semantic: .raw))
        try material.setParameter(name: "gameTexture", value: .textureResource(fallback))
        let fallbackPixels = try await capture("texture-fallback")
        require(fallbackPixels[0][0] > 100 && fallbackPixels[1][1] > 100, "Untextured white fallback disappeared")
        try checkDecodedAlpha()
        print("PASS production PNG decoder and graph on actual macOS GPU: opaque/transparent texels, original magenta key, white fallback, NativeVertex/LowLevelMesh colors, UV texture multiplication, alpha discard, game-center subtraction, XZ half-plane clipping, billboard bypass, below-center geometry; decoded partial alpha retained")
        print("LIMIT: offscreen macOS pixels; visionOS system volume, spatial gestures and display performance require separate runtime acceptance")
    }
    @MainActor static func texture(_ bytes: [UInt8]) async throws -> TextureResource {
        // Exercise the same PNG decoding and palette cleanup as the volume renderer.
        // Directly constructing TextureResource bypassed the opaque-white compositing bug.
        let decoded = try VolumeTextureImage.decode(pngData(bytes, width: 2, height: 1))
        return try await TextureResource(image: decoded, options: .init(semantic: .raw))
    }

    static func pngData(_ bytes: [UInt8], width: Int, height: Int) -> Data {
        require(bytes.count == width * height * 4, "Malformed RGBA test fixture")
        let info = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGBitmapInfo(rawValue: info), provider: provider,
                            decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        require(CGImageDestinationFinalize(destination), "Could not encode PNG fixture")
        return data as Data
    }

    static func rgba(_ image: CGImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let info = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        bytes.withUnsafeMutableBytes { storage in
            let context = CGContext(data: storage.baseAddress, width: image.width, height: image.height,
                                    bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info)!
            context.setBlendMode(.copy)
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return bytes
    }

    static func checkDecodedAlpha() throws {
        // Opaque red, half-alpha red, a clear corner, and original palette-zero magenta.
        let fixture: [UInt8] = [255, 0, 0, 255, 128, 0, 0, 128,
                               0, 0, 0, 0, 255, 0, 255, 255]
        let decoded = try VolumeTextureImage.decode(pngData(fixture, width: 2, height: 2))
        require(decoded.width == 2 && decoded.height == 2, "PNG dimensions changed")
        let bytes = rgba(decoded)
        // Row order can differ between Core Graphics images and bitmap contexts.
        let pixels = stride(from: 0, to: bytes.count, by: 4).map { Array(bytes[$0..<$0 + 4]) }
        require(pixels.filter { $0 == [255, 0, 0, 255] }.count == 1, "Opaque artwork was altered")
        require(pixels.filter { abs(Int($0[3]) - 128) <= 1 && abs(Int($0[0]) - 128) <= 1 && $0[1] == 0 && $0[2] == 0 }.count == 1,
                "Partial PNG alpha was flattened or premultiplication changed")
        require(pixels.filter { $0 == [0, 0, 0, 0] }.count == 2, "Clear PNG corner or original magenta background became opaque")
        let fallback = try VolumeTextureImage.decode(nil)
        require(fallback.width == 1 && fallback.height == 1 && rgba(fallback) == [255, 255, 255, 255],
                "Nil texture must remain a single opaque-white texel")
        print("PASS production decoder RGBA: opaque red, half-alpha red, clear corner, magenta key and white fallback")
    }
}
