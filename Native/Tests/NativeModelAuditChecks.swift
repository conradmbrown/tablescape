import Foundation
import CryptoKit
import CoreGraphics
import CoreText
import ImageIO
import simd

/// Exhaustive original-pack geometry/color audit plus a small software-rendered
/// comparison gallery. This does not substitute for RealityKit/device pictures.
@main @MainActor enum NativeModelAuditChecks {
    struct AuditFailure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw AuditFailure(message: message) }
    }
    static func finite(_ v: SIMD3<Float>) -> Bool { v.x.isFinite && v.y.isFinite && v.z.isFinite }
    static func rgb(_ v: NativeVertex) -> SIMD3<Float> { SIMD3(v.color.x,v.color.y,v.color.z) }

    /// Compare against actual source topology/alpha as well as the unlit path.
    /// Lighting may change RGB only; no lighting formula is duplicated here.
    static func validate(_ model: NativeModel, raw: [NativeMesh], shaded: [NativeMesh]) throws -> (changed: Int, texturedRange: Float) {
        try require(raw.count == shaded.count, "model \(model.id): mesh groups changed")
        try require(raw.reduce(0) { $0 + $1.indices.count } == model.faces.count * 3, "model \(model.id): source triangle coverage")
        let faceOrder = model.faces.indices.sorted { model.priorities[$0] == model.priorities[$1] ? $0 < $1 : model.priorities[$0] < model.priorities[$1] }
        var changed = 0, texturedLow: Float = .greatestFiniteMagnitude, texturedHigh: Float = -.greatestFiniteMagnitude
        for (before,after) in zip(raw,shaded) {
            try require(before.textureID == after.textureID && before.indices == after.indices, "model \(model.id): texture or topology changed")
            try require(before.vertices.count == after.vertices.count && before.vertices.count == before.indices.count, "model \(model.id): split vertex count changed")
            try require(before.sourceModel == after.sourceModel && before.sourceVertices == after.sourceVertices && before.slot == after.slot, "model \(model.id): source identity changed")
            try require(before.vertexLabels == after.vertexLabels && before.faceLabels == after.faceLabels && before.priorities == after.priorities, "model \(model.id): animation labels or priorities changed")
            try require(before.faceColors == after.faceColors && before.faceRenderTypes == after.faceRenderTypes, "model \(model.id): original face metadata changed")
            let faces = faceOrder.filter { (model.renderTypes[$0] & 2 != 0 ? model.colors[$0] : -1) == before.textureID }
            try require(faces.count * 3 == before.vertices.count, "model \(model.id): source group coverage")
            for (index,sourceFace) in faces.enumerated() {
                let face = model.faces[sourceFace], sources = [face.x,face.y,face.z], base = index * 3
                try require(Array(before.indices[base..<(base+3)]) == [UInt32(base),UInt32(base+2),UInt32(base+1)], "model \(model.id): original winding")
                try require(before.priorities[index] == model.priorities[sourceFace], "model \(model.id): source priority")
                for corner in 0..<3 {
                    let i = base + corner, a = before.vertices[i], b = after.vertices[i]
                    try require(finite(b.position) && finite(rgb(b)) && b.color.w.isFinite && b.uv.x.isFinite && b.uv.y.isFinite, "model \(model.id): nonfinite vertex")
                    try require(b.position == model.positions[sources[corner]] && b.position == a.position && b.uv == a.uv, "model \(model.id): source position/bounds or UV changed")
                    try require(b.color.w == Float(255-model.alpha[sourceFace])/255 && b.color.w == a.color.w, "model \(model.id): source alpha changed")
                    try require((0..<4).allSatisfy { b.color[$0] >= -0.00001 && b.color[$0] <= 1.00001 }, "model \(model.id): color outside normalized bounds")
                    try require(after.sourceVertices[i] == sources[corner] && after.vertexLabels[i] == model.vertexLabels[sources[corner]] && after.faceLabels[i] == model.faceLabels[sourceFace], "model \(model.id): source labels changed")
                    if simd_distance(rgb(a),rgb(b)) > 0.00001 { changed += 1 }
                    if after.textureID >= 0 {
                        try require(abs(b.color.x-b.color.y) < 0.00001 && abs(b.color.x-b.color.z) < 0.00001, "model \(model.id): textured lighting introduced a tint")
                        texturedLow = min(texturedLow,b.color.x); texturedHigh = max(texturedHigh,b.color.x)
                    }
                }
            }
        }
        return (changed,texturedLow <= texturedHigh ? texturedHigh-texturedLow : 0)
    }
    static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL,"public.png" as CFString,1,nil) else { throw AuditFailure(message:"PNG destination") }
        CGImageDestinationAddImage(destination,image,nil)
        try require(CGImageDestinationFinalize(destination),"PNG encoding")
    }
    static func pixels(_ image: CGImage) -> [UInt8] { Array(image.dataProvider!.data! as Data) }
    static func text(_ string: String, x: CGFloat, y: CGFloat, size: CGFloat, in context: CGContext) {
        let attributes: [NSAttributedString.Key:Any] = [NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString,size,nil), NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray:0.92,alpha:1)]
        context.textPosition = CGPoint(x:x,y:y)
        CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string:string,attributes:attributes)),context)
    }

    static func main() async throws {
        try require(CommandLine.arguments.count == 3,"Expected original asset pack and output directory")
        let pack = URL(fileURLWithPath:CommandLine.arguments[1]), out = URL(fileURLWithPath:CommandLine.arguments[2])
        try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
        let manifest = try JSONDecoder().decode(NativePackManifest.self,from:Data(contentsOf:pack.appendingPathComponent("manifest.json")))
        let entries = manifest.assets.filter { $0.kind == "model" }.sorted { ($0.id ?? -1) < ($1.id ?? -1) }
        try require(manifest.revision == 274 && entries.count == 4556,"Expected the complete original revision-274 pack (4556 models)")
        try require(Set(entries.compactMap(\.id)).count == entries.count,"Duplicate/missing original model identities")
        let profiles: [(String,NativeLighting)] = [("actor",.actor),("object",.object)]
        var rows: [[String:Any]] = [], failures: [[String:Any]] = []
        var totalFaces = 0, totalVertices = 0, degenerateFaces = 0, alphaFaces = 0, texturedModels = 0
        var changedByProfile = ["actor":0,"object":0], variedByProfile = ["actor":0,"object":0]
        let start = Date()
        for entry in entries {
            do {
                guard let id = entry.id else { throw AuditFailure(message:"Missing model id") }
                let bytes = try Data(contentsOf:pack.appendingPathComponent(entry.path))
                try require(bytes.count == entry.bytes && SHA256.hash(data:bytes).map { String(format:"%02x",$0) }.joined() == entry.sha256,"model \(id): original manifest integrity")
                let model = try NativeModel.decode(bytes,id:id), raw = model.mesh()
                let degenerate = model.faces.filter { f in simd_length_squared(simd_cross(model.positions[f.y]-model.positions[f.x],model.positions[f.z]-model.positions[f.x])) < 1e-12 }.count
                let textured = model.renderTypes.filter { $0 & 2 != 0 }.count
                var row: [String:Any] = ["id":id,"bytes":bytes.count,"vertices":model.positions.count,"faces":model.faces.count,"degenerateFaces":degenerate,"texturedFaces":textured,"alphaFaces":model.alpha.filter { $0 != 0 }.count]
                for (name,profile) in profiles {
                    let shaded = NativeModelLighting.shade(meshes:raw,lighting:profile)
                    let result = try validate(model,raw:raw,shaded:shaded)
                    row[name+"ChangedVertices"] = result.changed
                    row[name+"TexturedBrightnessRange"] = result.texturedRange
                    if result.changed > 0 { changedByProfile[name,default:0] += 1 }
                    if textured > 0 && result.texturedRange > 0.00001 { variedByProfile[name,default:0] += 1 }
                    if name == "object" {
                        let direct = model.mesh(lit:true)
                        try require(direct.count == shaded.count && zip(direct,shaded).allSatisfy { a,b in a.vertices.map(\.color) == b.vertices.map(\.color) },"model \(id): mesh(lit:true) does not apply production object lighting")
                    }
                }
                totalFaces += model.faces.count; totalVertices += model.positions.count
                degenerateFaces += degenerate; alphaFaces += model.alpha.filter { $0 != 0 }.count
                if textured > 0 { texturedModels += 1 }
                rows.append(row)
            } catch { failures.append(["id":entry.id ?? -1,"error":error.localizedDescription]) }
            if (rows.count + failures.count) % 500 == 0 { print("Audited \(rows.count+failures.count)/\(entries.count) original models; failures=\(failures.count)"); fflush(stdout) }
        }
        var report: [String:Any] = ["revision":274,"expectedModels":entries.count,"auditedModels":rows.count,"failedModels":failures,"faces":totalFaces,"vertices":totalVertices,"degenerateFaces":degenerateFaces,"alphaFaces":alphaFaces,"texturedModels":texturedModels,"modelsWithChangedRGB":changedByProfile,"texturedModelsWithVariedBrightness":variedByProfile,"models":rows,"limits":"Offline source geometry and production lighting/composition; software images capped at 112px. Not RealityKit GPU or physical headset proof. Uniform lighting is permitted for flat, degenerate, coincident-normal or saturated geometry; all models still receive finite/topology/alpha checks."]
        func saveReport() throws {
            report["elapsedSeconds"] = Date().timeIntervalSince(start)
            try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("model-audit.json"),options:.atomic)
        }
        try saveReport()
        try require(failures.isEmpty,"\(failures.count) model audits failed; see model-audit.json")
        for (name,_) in profiles { try require(variedByProfile[name,default:0] > 0,"All textured models have uniform \(name) lighting") }

        let store = NativeAssetStore(fetch:{_ in throw NativeAssetError.missing("offline model audit disallows network")},packURL:pack,cacheURL:out.appendingPathComponent("Cache"))
        struct Sample { let name: String; let ids: [Int]; let actor: Bool; var source: [Int] = []; var destination: [Int] = []; var effectType: Int? = nil }
        let samples = [
            Sample(name:"Cow",ids:[3341,3342],actor:true),
            Sample(name:"Goblin",ids:[2951,2953,2955,2956],actor:true),
            Sample(name:"Armed Goblin",ids:[2951,2953,2955,2956,2957],actor:true),
            Sample(name:"Man",ids:[215,246,292,151,176,254,181],actor:true,source:[2340,14724],destination:[4226,4226]),
            Sample(name:"Default male player",ids:[230,249,292,151,176,254,181],actor:true),
            Sample(name:"Coins (ground item)",ids:[2484],actor:false),
            Sample(name:"Textured 1003",ids:[1003],actor:false),
            Sample(name:"Textured 1004",ids:[1004],actor:false),
            Sample(name:"Textured 1005",ids:[1005],actor:false),
            Sample(name:"Effect 3081",ids:[3081],actor:true,effectType:91),
            Sample(name:"Effect 3082",ids:[3082],actor:true,effectType:92),
            Sample(name:"Effect 3091",ids:[3091],actor:true,effectType:111)
        ]
        let width = 600, rowHeight = 168, height = 60 + ((samples.count+1)/2)*rowHeight
        guard let sheet = CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { throw AuditFailure(message:"Gallery context") }
        sheet.setFillColor(CGColor(gray:0.10,alpha:1)); sheet.fill(CGRect(x:0,y:0,width:width,height:height))
        text("Original revision 274 · production lighting comparison",x:16,y:CGFloat(height-24),size:16,in:sheet)
        text("Unlit reference vs lit composition · software view, 112 px per image",x:16,y:CGFloat(height-44),size:11,in:sheet)
        var gallery: [[String:Any]] = []
        for (index,sample) in samples.enumerated() {
            let parts = [NativeAssetPart(models:sample.ids,recolS:sample.source,recolD:sample.destination)]
            let before = try await NativeComposition.meshes(parts:parts,store:store,lighting:nil)
            var lighting: NativeLighting = sample.actor ? .actor : .object
            let offsets = sample.effectType.map { NativeDefinitionLighting.effect(type:$0) } ?? .zero
            lighting.ambient += offsets.x; lighting.contrast += offsets.y
            let after = try await NativeComposition.meshes(parts:parts,store:store,lighting:lighting)
            try require(before.count == after.count,"\(sample.name): composition groups changed")
            var changed = 0
            for (a,b) in zip(before,after) {
                try require(a.indices == b.indices && a.textureID == b.textureID && a.vertices.count == b.vertices.count,"\(sample.name): composition topology changed")
                for (v,w) in zip(a.vertices,b.vertices) {
                    try require(v.position == w.position && v.uv == w.uv && v.color.w == w.color.w,"\(sample.name): composition geometry/UV/alpha changed")
                    if simd_distance(rgb(v),rgb(w)) > 0.00001 { changed += 1 }
                }
            }
            try require(changed > 0,"\(sample.name): original representative remained unlit")
            var textures: [Int:Data] = [:]
            for id in Set(after.map(\.textureID).filter { $0 >= 0 }) { textures[id] = try await store.texture(id) }
            let originalImage = try NativePortraitRenderer.rasterize(meshes:before,textureData:textures,pitch:0.25,yaw:0.55)
            let shadedImage = try NativePortraitRenderer.rasterize(meshes:after,textureData:textures,pitch:0.25,yaw:0.55)
            let originalPixels = pixels(originalImage), shadedPixels = pixels(shadedImage)
            let visible = stride(from:3,to:shadedPixels.count,by:4).filter { shadedPixels[$0] > 0 }.count
            var changedPixels = 0
            for pixel in stride(from:0,to:shadedPixels.count,by:4) {
                let redChanged = originalPixels[pixel] != shadedPixels[pixel]
                let greenChanged = originalPixels[pixel+1] != shadedPixels[pixel+1]
                let blueChanged = originalPixels[pixel+2] != shadedPixels[pixel+2]
                if redChanged || greenChanged || blueChanged { changedPixels += 1 }
            }
            try require(visible > 10 && changedPixels > 0,"\(sample.name): representative comparison did not show changed visible shading")
            try require(stride(from:3,to:shadedPixels.count,by:4).allSatisfy { originalPixels[$0] == shadedPixels[$0] },"\(sample.name): software comparison changed coverage/alpha")
            let x = CGFloat((index%2)*300+12), top = CGFloat(height-60-(index/2)*rowHeight)
            text(sample.name,x:x,y:top-15,size:13,in:sheet)
            text("Unlit",x:x,y:top-32,size:10,in:sheet)
            let profileLabel = sample.effectType.map { "Lit · effect \($0)" } ?? (sample.actor ? "Lit · actor" : "Lit · object")
            text(profileLabel,x:x+145,y:top-32,size:10,in:sheet)
            sheet.draw(originalImage,in:CGRect(x:x,y:top-148,width:112,height:112))
            sheet.draw(shadedImage,in:CGRect(x:x+145,y:top-148,width:112,height:112))
            var comparison: [String:Any] = ["name":sample.name,"models":sample.ids,"profile":sample.actor ? "actor":"object","ambient":lighting.ambient,"contrast":lighting.contrast,"direction":[lighting.direction.x,lighting.direction.y,lighting.direction.z],"changedVertices":changed,"visiblePixels":visible,"changedPixels":changedPixels]
            if let type = sample.effectType {
                comparison["effectType"] = type
                comparison["definitionAmbientOffset"] = offsets.x
                comparison["definitionContrastOffset"] = offsets.y
                comparison["definitionSource"] = "NativeDefinitionLighting.effect; original effect/model identities verified by Fixtures/original-effects.json"
            }
            gallery.append(comparison)
        }
        try writePNG(sheet.makeImage()!,to:out.appendingPathComponent("model-lighting-comparison.png"))
        report["gallery"] = gallery; try saveReport()
        print("PASS: \(rows.count) hash-verified original models, \(totalFaces) faces, actor/object lighting; source positions/topology/UV/alpha/labels/priorities preserved")
        print("Textured variation: actor=\(variedByProfile["actor",default:0]), object=\(variedByProfile["object",default:0]) of \(texturedModels) textured models; \(degenerateFaces) legitimate degenerate faces counted")
        print("Gallery: \(samples.count) before/after production-composition pairs; \(out.path)/model-lighting-comparison.png")
    }
}
