import Foundation
import simd
@main struct NativeAnimationPerformanceChecks {
    static func main() throws {
        precondition(CommandLine.arguments.count == 2,"Expected repository directory")
        let source=URL(fileURLWithPath:CommandLine.arguments[1])
        let pack=source.appendingPathComponent("Native/TableScape/Resources/AssetPack"),fixtures=source.appendingPathComponent("Native/Tests/Fixtures")
        func model(_ id:Int)throws->[NativeMesh] {try NativeModel.decode(Data(contentsOf:pack.appendingPathComponent("models/\(id).ob2")),id:id).mesh()}
        let player=try [292,151,254,230,176,181,249].flatMap {try model($0)}
        var cases:[([NativeMesh],NativeSequence)]=[]
        let idle=try JSONDecoder().decode(NativeSequence.self,from:Data(contentsOf:fixtures.appendingPathComponent("idle-sequence.json")))
        cases.append((player,idle))
        let death=try JSONDecoder().decode(NativeSequence.self,from:Data(contentsOf:fixtures.appendingPathComponent("death-sequence.json")))
        cases.append((player,death))
        let effects=try JSONSerialization.jsonObject(with:Data(contentsOf:fixtures.appendingPathComponent("original-effects.json"))) as! [[String:Any]]
        for effect in effects {
            let sequence=try JSONDecoder().decode(NativeSequence.self,from:JSONSerialization.data(withJSONObject:effect["sequenceData"]!))
            cases.append((try model(effect["model"] as! Int),sequence))
        }
        var checked=0,vertices=0
        func compare(_ a:[NativeMesh],_ b:[NativeMesh],_ context:String) {
            precondition(a.count==b.count,context)
            for m in a.indices {
                precondition(a[m].indices==b[m].indices && a[m].textureID==b[m].textureID && a[m].vertices.count==b[m].vertices.count,context)
                for i in a[m].vertices.indices {
                    let av=a[m].vertices[i],bv=b[m].vertices[i]
                    for n in 0..<3 {precondition(av.position[n].bitPattern==bv.position[n].bitPattern,"\(context) position \(m)/\(i)/\(n) \(av.position[n]) != \(bv.position[n])")}
                    for n in 0..<4 {precondition(av.color[n].bitPattern==bv.color[n].bitPattern,"\(context) color \(m)/\(i)/\(n)")}
                    precondition(av.uv==bv.uv,context);vertices += 1
                }
            }
            checked += 1
        }
        for (meshes,sequence) in cases {
            for frame in sequence.frames {compare(NativeAnimatorBeforeOptimization.apply(meshes:meshes,frame:frame),NativeAnimator.apply(meshes:meshes,frame:frame),"sequence \(sequence.id)")}
            for loop in [false,true] {for n in 0..<50 {
                let time=Double(n)*sequence.duration/17.3
                compare(NativeAnimatorBeforeOptimization.pose(meshes:meshes,sequence:sequence,time:time,loop:loop),NativeAnimator.pose(meshes:meshes,sequence:sequence,time:time,loop:loop),"pose \(sequence.id) \(time)")
            }}
        }
        // Deterministic adversarial coverage for every label byte, missing labels, duplicates,
        // all transform types, reused shared pivots and clamped alpha. PRNG seed is fixed.
        var seed:UInt64=0x274_808_836
        func random(_ limit:Int)->Int {seed=seed &* 6364136223846793005 &+ 1442695040888963407;return Int((seed >> 32) % UInt64(limit))}
        var synthetic=player
        for m in synthetic.indices {for i in synthetic[m].vertices.indices {
            synthetic[m].vertexLabels[i]=i%19==0 ? -1:random(256)
            synthetic[m].faceLabels[i]=i%23==0 ? -1:random(256)
        }}
        for iteration in 0..<120 {
            var transforms:[NativeTransform]=[]
            for kind in [0,2,1,0,3,5,2,4] {
                var labels=(0..<48).map {_ in random(256)};labels += [0,63,64,127,128,191,192,255,255]
                transforms.append(NativeTransform(type:kind,x:random(511)-255,y:random(511)-255,z:random(511)-255,labels:labels))
            }
            let frame=NativeFrame(delay:1,transforms:transforms)
            compare(NativeAnimatorBeforeOptimization.apply(meshes:synthetic,frame:frame),NativeAnimator.apply(meshes:synthetic,frame:frame),"random \(iteration)")
        }
        print("PASS exact Float.bitPattern parity: \(checked) original/random frames and interpolated poses; \(vertices) vertices (positions, RGBA and UV), sequence IDs \(cases.map {$0.1.id})")
        var sink:Float=0
        @inline(never) func measure(_ optimized:Bool)->Double {
            let start=DispatchTime.now().uptimeNanoseconds
            for n in 0..<240 {for (meshes,sequence) in cases {
                let time=Double(n)*0.0237
                let output=optimized ? NativeAnimator.pose(meshes:meshes,sequence:sequence,time:time):NativeAnimatorBeforeOptimization.pose(meshes:meshes,sequence:sequence,time:time)
                sink += output[0].vertices[(n*7)%output[0].vertices.count].position.y
            }}
            return Double(DispatchTime.now().uptimeNanoseconds-start)/1_000_000
        }
        _=measure(false);_=measure(true)
        var before:[Double]=[],after:[Double]=[]
        for n in 0..<5 {if n%2==0 {before.append(measure(false));after.append(measure(true))} else {after.append(measure(true));before.append(measure(false))}}
        let b=before.sorted()[2],a=after.sorted()[2]
        print(String(format:"BENCH optimized Swift -O: 1200 original poses per run, 5 alternating samples; before median %.2fms, after %.2fms, speedup %.2fx, reduction %.1f%%",b,a,b/a,(b-a)/b*100))
        print("before_ms=\(before) after_ms=\(after) checksum=\(sink)")
    }
}
