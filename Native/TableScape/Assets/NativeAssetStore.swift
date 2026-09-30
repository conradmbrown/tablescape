import Foundation
import CryptoKit

struct NativeTerrain: @unchecked Sendable {
    var x: Int
    var z: Int
    var level: Int
    var meshes: [NativeMesh]
    var locs: [[String: Any]]

    static func decode(_ data: Data) throws -> NativeTerrain {
        guard data.count <= 32_000_000,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["revision"] as? Int == 274,
              let groups = object["meshes"] as? [[String: Any]], groups.count <= 128 else { throw NativeAssetError.malformed("terrain payload") }
        var meshes: [NativeMesh] = []
        var totalCoordinates = 0
        for group in groups {
            guard let values = group["vertices"] as? [NSNumber], let colors = group["colours"] as? [NSNumber], let uv = group["uv"] as? [NSNumber],
                  values.count % 9 == 0, colors.count == values.count, uv.count == values.count / 3 * 2,
                  values.count <= 2_000_000 else { throw NativeAssetError.malformed("terrain geometry") }
            totalCoordinates += values.count
            guard totalCoordinates <= 2_000_000 else { throw NativeAssetError.malformed("terrain vertex budget") }
            var mesh = NativeMesh(vertices: [], indices: [], textureID: group["texture"] as? Int ?? -1)
            mesh.vertices.reserveCapacity(values.count/3)
            for i in 0..<values.count/3 {
                let p = SIMD3(values[i*3].floatValue,values[i*3+1].floatValue,values[i*3+2].floatValue)
                let c = SIMD4(colors[i*3].floatValue,colors[i*3+1].floatValue,colors[i*3+2].floatValue,Float(1))
                let t = SIMD2(uv[i*2].floatValue,uv[i*2+1].floatValue)
                guard p.x.isFinite, p.y.isFinite, p.z.isFinite, c.x.isFinite, c.y.isFinite, c.z.isFinite, t.x.isFinite, t.y.isFinite else { throw NativeAssetError.malformed("non-finite terrain vertex") }
                mesh.vertices.append(NativeVertex(position:p,color:c,uv:t)); mesh.indices.append(UInt32(i))
            }
            meshes.append(mesh)
        }
        return NativeTerrain(x: object["x"] as? Int ?? 0, z: object["z"] as? Int ?? 0, level: object["level"] as? Int ?? 0, meshes: meshes, locs: object["locs"] as? [[String:Any]] ?? [])
    }
}

struct NativePackManifest: Codable, Sendable {
    struct Entry: Codable, Sendable {
        var kind: String
        var id: Int?
        var path: String
        var sha256: String
        var bytes: Int
        var dependencies: [String]?
    }
    var version: Int
    var revision: Int
    var source: String
    var assets: [Entry]
}

/// Small original pack plus verified asynchronous cache. Never blocks the render thread.
actor NativeAssetStore {
    typealias Fetch = @Sendable (String) async throws -> Data
    private let fetch: Fetch
    private let packURL: URL?
    private let diskURL: URL?
    private var manifest: [String:NativePackManifest.Entry] = [:]
    private var manifestError: Error?
    private var models: [Int:NativeModel] = [:]
    private var modelOrder: [Int] = []
    private var modelBytes = 0
    private var modelRequests: [Int:Task<NativeModel,Error>] = [:]
    private var sequences: [Int:NativeSequence] = [:]
    private var sequenceOrder: [Int] = []
    private var sequenceBytes = 0
    private var sequenceRequests: [Int:Task<NativeSequence,Error>] = [:]
    private var textures: [Int:Data] = [:]
    private var textureOrder: [Int] = []
    private var textureBytes = 0
    private var textureRequests: [Int:Task<Data,Error>] = [:]
    private var chunks: [String:NativeTerrain] = [:]
    private var chunkOrder: [String] = []
    private var chunkRequests: [String:Task<NativeTerrain,Error>] = [:]
    private let memoryLimit = 64 * 1024 * 1024
    private let diskLimit = 48 * 1024 * 1024

    init(fetch: @escaping Fetch, bundle: Bundle = .main, packURL: URL? = nil, cacheURL: URL? = nil) {
        self.fetch = fetch
        let flatPack = bundle.resourceURL?.appendingPathComponent("AssetPack", isDirectory:true)
        let nestedPack = bundle.resourceURL?.appendingPathComponent("Resources/AssetPack", isDirectory:true)
        self.packURL = packURL ?? ([flatPack,nestedPack].compactMap { $0 }.first { FileManager.default.fileExists(atPath:$0.appendingPathComponent("manifest.json").path) })
        self.diskURL = cacheURL ?? FileManager.default.urls(for:.cachesDirectory,in:.userDomainMask).first?.appendingPathComponent("TableScape/revision274-v1",isDirectory:true)
        do {
            guard let url = self.packURL?.appendingPathComponent("manifest.json") else { throw NativeAssetError.missing("manifest.json") }
            let data = try Data(contentsOf:url), decoded = try JSONDecoder().decode(NativePackManifest.self,from:data)
            guard decoded.version == 1, decoded.revision == 274 else { throw NativeAssetError.unsupported(decoded.revision) }
            for entry in decoded.assets {
                guard !entry.path.hasPrefix("/"), !entry.path.split(separator:"/").contains(".."), entry.sha256.count == 64, entry.bytes >= 0 else { throw NativeAssetError.malformed("manifest path") }
                manifest[entry.path] = entry
            }
        } catch { manifestError = error }
    }

    func model(_ id: Int) async throws -> NativeModel {
        guard (0...65535).contains(id) else { throw NativeAssetError.malformed("model id") }
        if let model = models[id] { touch(id,&modelOrder); return model }
        if let task = modelRequests[id] { return try await task.value }
        let task = Task { let bytes = try await self.asset(path:"models/\(id).ob2",route:"/v1/models/\(id)"); return try NativeModel.decode(bytes,id:id) }
        modelRequests[id] = task
        do {
            let model = try await task.value; modelRequests[id] = nil
            models[id] = model; modelBytes += model.byteCount; touch(id,&modelOrder)
            while modelBytes > memoryLimit, modelOrder.count > 1 { let key = modelOrder.removeFirst(); modelBytes -= models.removeValue(forKey:key)?.byteCount ?? 0 }
            return model
        } catch { modelRequests[id] = nil; throw error }
    }

    func texture(_ id: Int) async throws -> Data {
        if let data = textures[id] { touch(id,&textureOrder); return data }
        if let task = textureRequests[id] { return try await task.value }
        let task = Task { try await self.asset(path:"textures/\(id).png",route:"/v1/textures/\(id)") }
        textureRequests[id] = task
        do {
            let data = try await task.value; textureRequests[id] = nil; textures[id] = data; textureBytes += data.count; touch(id,&textureOrder)
            while textureBytes > 8*1024*1024, textureOrder.count > 1 { textureBytes -= textures.removeValue(forKey:textureOrder.removeFirst())?.count ?? 0 }
            return data
        } catch { textureRequests[id] = nil; throw error }
    }

    func sequence(_ id: Int) async throws -> NativeSequence {
        guard (0...65535).contains(id) else { throw NativeAssetError.malformed("sequence id") }
        if let s = sequences[id] { touch(id,&sequenceOrder); return s }
        if let task = sequenceRequests[id] { return try await task.value }
        let task = Task { let data = try await self.fetch("/v1/sequence/\(id)"); guard data.count < 8_000_000 else { throw NativeAssetError.malformed("sequence length") }; return try JSONDecoder().decode(NativeSequence.self,from:data) }
        sequenceRequests[id] = task
        do {
            let seq = try await task.value; sequenceRequests[id] = nil
            guard seq.id == id, seq.frames.count <= 10000,
                  seq.frames.allSatisfy({ $0.delay >= 0 && $0.delay <= 65535 && $0.transforms.count <= 512 && $0.transforms.allSatisfy { (0...5).contains($0.type) && (-32768...32767).contains($0.x) && (-32768...32767).contains($0.y) && (-32768...32767).contains($0.z) && $0.labels.count <= 256 && $0.labels.allSatisfy { (0...255).contains($0) } } }) else { throw NativeAssetError.malformed("sequence identity or transforms") }
            sequences[id] = seq; sequenceBytes += seq.byteCount; touch(id,&sequenceOrder)
            while sequenceOrder.count > 128 || sequenceBytes > 16*1024*1024 && sequenceOrder.count > 1 { sequenceBytes -= sequences.removeValue(forKey:sequenceOrder.removeFirst())?.byteCount ?? 0 }
            return seq
        } catch { sequenceRequests[id] = nil; throw error }
    }

    func terrain(x: Int, z: Int, level: Int) async throws -> NativeTerrain {
        guard (0...3).contains(level), x % 16 == 0, z % 16 == 0 else { throw NativeAssetError.malformed("chunk coordinate") }
        let key = "\(x):\(z):\(level)"
        if let chunk = chunks[key] { touch(key,&chunkOrder); return chunk }
        if let task = chunkRequests[key] { return try await task.value }
        let task = Task { let bytes = try await self.fetch("/v1/chunk?x=\(x)&z=\(z)&level=\(level)"); return try NativeTerrain.decode(bytes) }
        chunkRequests[key] = task
        do {
            let chunk = try await task.value; chunkRequests[key] = nil; chunks[key] = chunk; touch(key,&chunkOrder)
            while chunkOrder.count > 25 { chunks[chunkOrder.removeFirst()] = nil }
            return chunk
        } catch { chunkRequests[key] = nil; throw error }
    }

    func clearTransient() {
        for task in chunkRequests.values { task.cancel() }; chunkRequests.removeAll(); chunks.removeAll(); chunkOrder.removeAll()
        for task in sequenceRequests.values { task.cancel() }; sequenceRequests.removeAll()
    }

    func statistics() -> (models:Int, modelBytes:Int, textures:Int, chunks:Int) { (models.count,modelBytes,textures.count,chunks.count) }

    private func touch<T:Equatable>(_ key:T,_ order:inout [T]) { order.removeAll { $0 == key }; order.append(key) }

    private func asset(path: String, route: String) async throws -> Data {
        if let error = manifestError { throw error }
        guard let entry = manifest[path] else { throw NativeAssetError.missing(path) }
        func verified(_ data:Data) -> Bool { data.count == entry.bytes && SHA256.hash(data:data).map { String(format:"%02x",$0) }.joined() == entry.sha256 }
        if let url = packURL?.appendingPathComponent(path), let data = try? Data(contentsOf:url,options:.mappedIfSafe), verified(data) { return data }
        let destination = diskURL?.appendingPathComponent(path)
        if let url = destination, let data = try? Data(contentsOf:url), verified(data) {
            try? FileManager.default.setAttributes([.modificationDate:Date()],ofItemAtPath:url.path); return data
        }
        try Task.checkCancellation()
        let data = try await fetch(route)
        guard verified(data) else { throw NativeAssetError.integrity(path) }
        if let url = destination {
            try? FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
            try? data.write(to:url,options:.atomic)
            pruneDisk()
        }
        return data
    }

    private func pruneDisk() {
        guard let root = diskURL, let files = FileManager.default.enumerator(at:root,includingPropertiesForKeys:[.fileSizeKey,.contentModificationDateKey,.isRegularFileKey]) else { return }
        var all: [(URL,Int,Date)] = [], total = 0
        for case let url as URL in files {
            guard let values = try? url.resourceValues(forKeys:[.fileSizeKey,.contentModificationDateKey,.isRegularFileKey]), values.isRegularFile == true else { continue }
            let size = values.fileSize ?? 0; total += size; all.append((url,size,values.contentModificationDate ?? .distantPast))
        }
        for (url,size,_) in all.sorted(by: { $0.2 < $1.2 }) where total > diskLimit { if (try? FileManager.default.removeItem(at:url)) != nil { total -= size } }
    }
}
