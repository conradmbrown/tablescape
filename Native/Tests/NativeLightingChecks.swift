import Foundation
import simd

@main struct NativeLightingChecks {
    static func main() throws {
        var checks = 0
        let originalOverride = NativeComposition.actorLighting(actor:["type":1043],kind:"npc")
        precondition(originalOverride.ambient == 134 && originalOverride.contrast == 1200)
        let serverOverride = NativeComposition.actorLighting(actor:["type":1043,"lightAmbient":90,"lightContrast":910],kind:"npc")
        precondition(serverOverride.ambient == 90 && serverOverride.contrast == 910)
        let playerDefault = NativeComposition.actorLighting(actor:["type":1043],kind:"player")
        precondition(playerDefault.ambient == 64 && playerDefault.contrast == 850)
        func require(_ value:Bool,_ message:String) {precondition(value,message);checks += 1}
        func rgb(_ v:SIMD4<Float>)->SIMD3<Float> {SIMD3(v.x,v.y,v.z)}
        func color(_ packed:Int,_ light:Int)->SIMD3<Float> {
            rgb(NativeModel.palette((packed & 0xff80)+max(2,min(126,(light*(packed & 127))>>7))))
        }
        func close(_ actual:SIMD3<Float>,_ expected:SIMD3<Float>,_ message:String) {
            require(simd_distance(actual,expected)<0.00001,message)
        }
        func preserved(_ before:[NativeMesh],_ after:[NativeMesh],_ name:String) {
            require(before.count==after.count,name+": material groups")
            for (a,b) in zip(before,after) {
                require(a.indices==b.indices && a.textureID==b.textureID,name+": topology/texture")
                require(a.faceColors==b.faceColors && a.faceRenderTypes==b.faceRenderTypes && a.priorities==b.priorities,name+": face metadata")
                require(a.sourceModel==b.sourceModel && a.slot==b.slot && a.sourceVertices==b.sourceVertices && a.vertexLabels==b.vertexLabels && a.faceLabels==b.faceLabels,name+": source identity/labels")
                require(a.vertices.count==b.vertices.count && zip(a.vertices,b.vertices).allSatisfy {$0.position==$1.position && $0.uv==$1.uv && $0.color.w==$1.color.w},name+": positions/UV/alpha")
            }
        }
        // In original Y-down coordinates this face has the exact normal (-256,0,0).
        let model=NativeModel(id:999,positions:[SIMD3(0,0,0),SIMD3(0,1,0),SIMD3(0,0,1)],faces:[SIMD3(0,1,2)],colors:[5000],renderTypes:[0],alpha:[128],priorities:[9],vertexLabels:[1,1,1],faceLabels:[2],textureBases:[])
        let raw=model.mesh()
        close(rgb(raw[0].vertices[0].color),rgb(NativeModel.palette(5000)),"Raw meshes must retain deferred-lighting input")
        require(raw[0].vertices[0].color.w==127.0/255 && raw[0].priorities==[9],"Source alpha/priority")
        require(raw[0].faceColors==[5000] && raw[0].faceRenderTypes==[0],"Source HSL/render flags")
        let object=NativeModelLighting.shade(meshes:raw,lighting:.object)
        // Object length=floor(sqrt(5100))=71; scale=768*71>>8=213.
        // Actor length=floor(sqrt(4300))=65; scale=850*65>>8=215.
        close(rgb(object[0].vertices[0].color),color(5000,124),"Object original integer lighting")
        let actor=NativeModelLighting.shade(meshes:raw,lighting:.actor)
        close(rgb(actor[0].vertices[0].color),color(5000,99),"Actor original direction and light magnitude")
        require(actor[0].vertices[0].color != object[0].vertices[0].color,"Actor/object profiles must differ")
        close(rgb(model.mesh(lit:true)[0].vertices[0].color),color(5000,124),"Low-level lit compatibility")
        close(rgb(NativeModelLighting.shade(meshes:raw,lighting:.portrait)[0].vertices[0].color),color(5000,124),"Portrait original profile")
        preserved(raw,actor,"Actor shading")
        let custom=NativeModelLighting.shade(meshes:raw,lighting:NativeLighting(direction:SIMD3(-1,0,0)))
        close(rgb(custom[0].vertices[0].color),color(5000,149),"Light vector magnitude cannot stay hardcoded at 71")
        var flat=model;flat.renderTypes=[1]
        close(rgb(flat.mesh(lit:true)[0].vertices[0].color),color(5000,104),"Flat normal uses scale plus half scale")
        close(rgb(NativeModelLighting.shade(meshes:flat.mesh(),lighting:.actor)[0].vertices[0].color),color(5000,87),"Flat actor lighting")
        let yaw=simd_float3x3(simd_quatf(angle:.pi/2,axis:SIMD3(0,1,0)))
        let turned=model.mesh(mirrored:true,lit:true,lightingTransform:yaw)
        close(rgb(turned[0].vertices[0].color),color(5000,4),"Mirrored transformed cache winding")
        let mirrorRaw=model.mesh(mirrored:true)
        preserved(mirrorRaw,NativeModelLighting.shade(meshes:mirrorRaw,lighting:.object),"Mirrored shading")
        // Textured cache faces use four brightness banks plus the original bit shift.
        var texture=model;texture.colors=[2];texture.renderTypes=[2];texture.textureBases=[SIMD3(0,1,2)]
        let textured=texture.mesh(recolorPairs:[SIMD2(2,0),SIMD2(0,4)])
        require(textured[0].textureID==4 && textured[0].faceColors==[4],"Sequential door texture recolor retained")
        let samples:[(Int,Float)]=[(200,1),(127,1),(112,1),(111,0.875),(96,0.875),(95,0.75),(80,0.75),(79,0.625),(64,0.625),(63,0.5),(48,0.5),(47,0.4375),(32,0.4375),(31,0.375),(16,0.375),(15,0.3125),(0,0.3125),(-40,0.3125)]
        for (light,intensity) in samples {
            let shaded=NativeModelLighting.shade(meshes:textured,lighting:NativeLighting(ambient:light,direction:.zero))
            close(rgb(shaded[0].vertices[0].color),SIMD3(repeating:intensity),"Original texture bank for light \(light)")
            require(shaded[0].vertices[0].color.w==127.0/255,"Texture lighting preserves alpha")
        }
        preserved(textured,NativeModelLighting.shade(meshes:textured,lighting:.actor),"Texture shading")
        // Opposite smooth faces meet at just the origin. Separate source models
        // must merge there only when the original multipart composition asks.
        var other=model;other.id=1000;other.positions=[.zero,SIMD3(0,0,2),SIMD3(0,2,0)]
        let split=raw+other.mesh()
        let separate=NativeModelLighting.shade(meshes:split,lighting:.object)
        close(rgb(separate[0].vertices[0].color),color(5000,124),"Independent source normal")
        close(rgb(separate[1].vertices[0].color),color(5000,4),"Independent opposite source normal")
        let merged=NativeModelLighting.shade(meshes:split,lighting:.object,mergeCoincidentVertices:true)
        close(rgb(merged[0].vertices[0].color),color(5000,64),"Multipart seam averaged normal")
        close(rgb(merged[1].vertices[0].color),color(5000,64),"Both seam sides share normal")
        close(rgb(merged[0].vertices[1].color),color(5000,124),"Noncoincident multipart vertex stays independent")
        preserved(split,merged,"Multipart shading")
        other.renderTypes=[1]
        let mixed=NativeModelLighting.shade(meshes:raw+other.mesh(),lighting:.object,mergeCoincidentVertices:true)
        close(rgb(mixed[0].vertices[0].color),color(5000,124),"Flat faces cannot contaminate smooth normal")
        close(rgb(mixed[1].vertices[0].color),color(5000,24),"Flat opposite normal stays per face")
        // One model split into color/texture material groups must still share
        // its original source vertex; flat flags remain attached to each face.
        var grouped=model
        grouped.positions += [SIMD3(0,0,2),SIMD3(0,2,0)]
        grouped.vertexLabels=[1,1,1,1,1];grouped.faces=[SIMD3(0,1,2),SIMD3(0,3,4)]
        grouped.colors=[5000,4];grouped.renderTypes=[0,2];grouped.textureBases=[SIMD3(0,3,4)]
        grouped.alpha=[128,64];grouped.priorities=[9,1];grouped.faceLabels=[2,3]
        let groupedRaw=grouped.mesh(),groupedLit=NativeModelLighting.shade(meshes:groupedRaw,lighting:.object)
        close(rgb(groupedLit[0].vertices[0].color),color(5000,64),"Source normals span material groups")
        close(rgb(groupedLit[1].vertices[0].color),SIMD3(repeating:0.625),"Textured group shares original source normal")
        preserved(groupedRaw,groupedLit,"Material group shading")
        grouped.colors=[5000,6000];grouped.renderTypes=[0,1]
        let ordered=grouped.mesh()[0]
        require(ordered.faceColors==[6000,5000] && ordered.faceRenderTypes==[1,0] && ordered.priorities==[1,9],"Face metadata follows stable priority ordering")
        // Relighting after pose must honor the animation's current alpha.
        let faded=NativeAnimator.apply(meshes:raw,frame:NativeFrame(delay:1,transforms:[NativeTransform(type:5,x:16,y:0,z:0,labels:[2])]))
        require(faded[0].vertices[0].color.w==0,"Alpha animation fixture")
        preserved(faded,NativeModelLighting.shade(meshes:faded,lighting:.portrait),"Posed portrait shading")
        var overlay=raw[0];overlay.faceColors=[];overlay.faceRenderTypes=[]
        let untouched=NativeModelLighting.shade(meshes:[overlay],lighting:.actor)[0]
        require(zip(overlay.vertices,untouched.vertices).allSatisfy {$0.color==$1.color},"Explicit-color terrain and overlays are not relit")
        let body=NativeAssetPart(models:[1],recolS:[10,20,30,40,50],recolD:[11,21,31,41,51],slot:0)
        var sequence=NativeSequence(id:1,frames:[])
        sequence.replaceheldright=512;sequence.rightMale=NativeAssetPart(models:[2],recolS:[7],recolD:[8])
        let replacement=NativeAnimator.replacementParts([body],sequence:sequence,gender:0).last!
        require(replacement.slot==3 && replacement.recolS==[7,10,20,30,40,50] && replacement.recolD==[8,11,21,31,41,51],"Held body recolors missing")
        print("PASS \(checks) analytic original lighting checks: object/actor/portrait directions, integer smooth/flat normals, mirrored winding, texture banks, multipart seams and material splits, metadata/recolors/alpha preservation, deferred pose lighting")
    }
}
