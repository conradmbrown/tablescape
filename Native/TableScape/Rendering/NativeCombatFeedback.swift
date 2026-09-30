import Foundation
import UIKit
import simd

/// Original hitmark artwork, numeric damage and temporary health bars as native camera-facing quads.
@MainActor final class NativeCombatFeedback {
    private struct Hit {var id:Int;var damage:Int;var type:Int;var until:Double}
    private struct View {var until=0.0;var hits:[Hit]=[]}
    private struct Sprite {var id:Int;var data:Data}
    private struct Motion {
        var samples:[(Int,SIMD3<Float>)]=[]
        mutating func observe(_ p:SIMD3<Float>,tick:Int) {
            if let last=samples.last,tick<last.0 || tick-last.0>8 || simd_distance(last.1,p)>8 {samples=[]}
            if samples.last?.0 != tick {samples.append((tick,p));if samples.count>32 {samples.removeFirst()}}
        }
        func position(_ tick:Double)->SIMD3<Float> {
            guard let first=samples.first else {return .zero};if tick<=Double(first.0) {return first.1}
            for i in 1..<samples.count where tick<Double(samples[i].0) {
                let a=samples[i-1],b=samples[i],t=Float((tick-Double(a.0))/Double(max(1,b.0-a.0)))
                return simd_mix(a.1,b.1,SIMD3(repeating:t))
            }
            return samples.last!.1
        }
    }
    private var views:[String:View]=[:]
    private var seen=Set<Int>()
    private var history:[Int]=[]
    private var sprites:[String:Sprite]=[:]
    private var spriteOrder:[String]=[]
    private var nextTexture=100000
    private var atlas:CGImage?
    private var motion:[String:Motion]=[:]
    private var level:Int?
    private var lastTick=0
    private var originTick=0
    private var originTime=0.0
    private(set) var receivedHits=0
    private(set) var drawnHits=0
    private(set) var drawnBars=0

    init(bundle:Bundle = .main) {
        let candidates=["Feedback/hitmarks.png","Resources/Feedback/hitmarks.png"]
        for relative in candidates {
            if let url=bundle.resourceURL?.appendingPathComponent(relative),let image=UIImage(contentsOfFile:url.path)?.cgImage {atlas=Self.keyMagenta(image);break}
        }
    }

    func reset() {views=[:];seen=[];history=[];motion=[:];level=nil;lastTick=0;originTick=0;originTime=0}

    func update(state:JSONObject,now:Double)->(nodes:[RenderNode],textures:[Int:Data]) {
        let tick=state.int("tick"),currentLevel=state.int("level")
        if level != nil && (level != currentLevel || tick<lastTick) {reset()}
        level=currentLevel
        if lastTick==0 || tick-lastTick>8 {originTick=tick;originTime=now};lastTick=tick
        let renderTick=Double(originTick)+(now-originTime)/0.6-1.3
        var actors:[String:JSONObject]=[:]
        let player=state.object("player")
        if !player.isEmpty {actors["player:\(player.int("id"))"]=player}
        for actor in state.objects("players") {actors["player:\(actor.int("id"))"]=actor}
        for actor in state.objects("npcDeaths") where actor.bool("animDeath") {actors["npc:\(actor.int("id"))"]=actor}
        for actor in state.objects("npcs") {actors["npc:\(actor.int("id"))"]=actor}
        for (key,actor) in actors {
            let size=Float(max(1,actor.double("size",1)))
            let point=SIMD3(Float(actor.double("x"))+size/2+Float(actor.double("offsetX")),Float(actor.double("y"))-Float(actor.double("offsetY")),Float(actor.double("z"))+size/2+Float(actor.double("offsetZ")))
            var track=motion[key] ?? Motion();track.observe(point,tick:tick);motion[key]=track
            var view=views[key] ?? View()
            for raw in actor.objects("hits") {
                let id=raw.int("id",-1)
                guard id>=0,seen.insert(id).inserted else {continue}
                history.append(id);while history.count>4096 {seen.remove(history.removeFirst())}
                let age=Double(max(0,tick-raw.int("tick")))*0.6
                guard age<=3.6 else {continue}
                view.until=now+max(0.1,4.2-age)
                view.hits.append(Hit(id:id,damage:max(0,min(9999,raw.int("damage"))),type:max(0,min(2,raw.int("type"))),until:now+max(0.1,1.8-age)))
                receivedHits += 1
            }
            view.hits.removeAll {$0.until<now}
            if view.hits.count>4 {view.hits=Array(view.hits.suffix(4))}
            if !view.hits.isEmpty || view.until>now {views[key]=view}else{views[key]=nil}
        }
        views=views.filter {actors[$0.key] != nil};motion=motion.filter {actors[$0.key] != nil}
        // Keep 64 displayed damage sprites and 64 overhead actors at most.
        let visible=views.keys.sorted().prefix(64)
        var selections:[(String,Hit,Int)]=[]
        for key in visible {if let view=views[key] {for (slot,hit) in view.hits.enumerated() where selections.count<64 {selections.append((key,hit,slot))}}}
        let protected=Set(selections.map {"\($0.1.type):\($0.1.damage)"})
        var nodes:[RenderNode]=[]
        func anchor(_ key:String,_ actor:JSONObject)->SIMD3<Float> {
            let p=motion[key]?.position(renderTick) ?? .zero
            return p+SIMD3(0,Float(max(0.6,actor.double("scaleY",1)))*2.05+0.2,0)
        }
        for key in visible {
            guard let actor=actors[key],let view=views[key],view.until>now,actor.int("maxHp")>0 else {continue}
            let fraction=Float(max(0,min(1,actor.double("hp")/actor.double("maxHp"))))
            var mesh=NativeMesh(vertices:[],indices:[])
            addQuad(&mesh,left:-0.58,bottom:0.34,right:0.58,top:0.52,color:SIMD4(0,0,0,1))
            addQuad(&mesh,left:-0.55,bottom:0.37,right:0.55,top:0.49,color:SIMD4(0.65,0,0,1))
            if fraction>0 {addQuad(&mesh,left:-0.55,bottom:0.37,right:-0.55+1.1*fraction,top:0.49,color:SIMD4(0,1,0,1))}
            var node=RenderNode(geometry:RenderGeometry(mesh),transform:scTranslation(anchor(key,actor)));node.billboard=true
            nodes.append(node);drawnBars += 1
        }
        for (key,hit,slot) in selections {
            guard let actor=actors[key],let sprite=sprite(type:hit.type,damage:hit.damage,protected:protected) else {continue}
            var mesh=NativeMesh(vertices:[],indices:[],textureID:sprite.id)
            let x=Float(slot%2)*0.5-0.25,y = -Float(slot/2)*0.5
            addQuad(&mesh,left:x-0.36,bottom:y-0.36,right:x+0.36,top:y+0.36,color:SIMD4(repeating:1))
            var node=RenderNode(geometry:RenderGeometry(mesh),transform:scTranslation(anchor(key,actor)));node.billboard=true
            nodes.append(node);drawnHits += 1
        }
        return (nodes,Dictionary(uniqueKeysWithValues:sprites.values.map {($0.id,$0.data)}))
    }

    private func addQuad(_ mesh:inout NativeMesh,left:Float,bottom:Float,right:Float,top:Float,color:SIMD4<Float>) {
        let base=UInt32(mesh.vertices.count)
        mesh.vertices += [NativeVertex(position:SIMD3(left,bottom,0),color:color,uv:SIMD2(0,1)),NativeVertex(position:SIMD3(right,bottom,0),color:color,uv:SIMD2(1,1)),NativeVertex(position:SIMD3(right,top,0),color:color,uv:SIMD2(1,0)),NativeVertex(position:SIMD3(left,top,0),color:color,uv:SIMD2(0,0))]
        mesh.indices += [base,base+1,base+2,base,base+2,base+3]
    }

    private func sprite(type:Int,damage:Int,protected:Set<String>)->Sprite? {
        let key="\(type):\(damage)"
        if let cached=sprites[key] {spriteOrder.removeAll {$0==key};spriteOrder.append(key);return cached}
        guard let atlas else {return nil}
        let width=atlas.width/3
        guard let crop=atlas.cropping(to:CGRect(x:type*width,y:0,width:width,height:atlas.height)) else {return nil}
        let size=CGSize(width:96,height:96),format=UIGraphicsImageRendererFormat();format.opaque=false;format.scale=1
        let image=UIGraphicsImageRenderer(size:size,format:format).image {context in
            context.cgContext.interpolationQuality = .none
            UIImage(cgImage:crop).draw(in:CGRect(origin:.zero,size:size))
            let text=String(damage) as NSString
            let paragraph=NSMutableParagraphStyle();paragraph.alignment = .center
            let font=UIFont.monospacedDigitSystemFont(ofSize:39,weight:.bold)
            let attributes:[NSAttributedString.Key:Any]=[.font:font,.foregroundColor:UIColor.white,.strokeColor:UIColor.black,.strokeWidth:-3,.paragraphStyle:paragraph]
            let height=text.size(withAttributes:attributes).height
            text.draw(in:CGRect(x:0,y:(size.height-height)/2-1,width:size.width,height:height+2),withAttributes:attributes)
        }
        guard let data=image.pngData() else {return nil}
        while sprites.count>=64 {
            guard let old=spriteOrder.first(where:{!protected.contains($0)}) else {return nil}
            sprites[old]=nil;spriteOrder.removeAll {$0==old}
        }
        let entry=Sprite(id:nextTexture,data:data);nextTexture += 1;sprites[key]=entry;spriteOrder.append(key)
        return entry
    }

    /// Original PNGs encode transparent palette zero as opaque magenta.
    private static func keyMagenta(_ image:CGImage)->CGImage? {
        let width=image.width,height=image.height,row=width*4
        guard width>0,height>0,width*height<1_000_000 else {return nil}
        var pixels=[UInt8](repeating:0,count:row*height)
        let bitmap=CGBitmapInfo.byteOrder32Big.rawValue|CGImageAlphaInfo.premultipliedLast.rawValue
        let rendered=pixels.withUnsafeMutableBytes {bytes -> Bool in
            guard let context=CGContext(data:bytes.baseAddress,width:width,height:height,bitsPerComponent:8,bytesPerRow:row,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:bitmap) else {return false}
            context.draw(image,in:CGRect(x:0,y:0,width:width,height:height));return true
        }
        guard rendered else {return nil}
        for i in stride(from:0,to:pixels.count,by:4) where pixels[i]==255 && pixels[i+1]==0 && pixels[i+2]==255 {pixels[i]=0;pixels[i+1]=0;pixels[i+2]=0;pixels[i+3]=0}
        guard let provider=CGDataProvider(data:Data(pixels) as CFData) else {return nil}
        return CGImage(width:width,height:height,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:row,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:bitmap),provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent)
    }
}
