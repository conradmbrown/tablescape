// The runner appends this scaffold to the exact current MetalSceneRenderer class.
// Keeping it in one generated compilation unit permits testing its private pool
// without adding hooks or conditional compilation to production code.
extension MetalSceneRenderer {
    func checkGPUBufferLifetime() throws {
        func makeGeometry(_ x:Float)->RenderGeometry {
            RenderGeometry(NativeMesh(vertices:[NativeVertex(position:SIMD3(x,0,0),color:SIMD4(repeating:1)),NativeVertex(position:SIMD3(x,1,0),color:SIMD4(repeating:1)),NativeVertex(position:SIMD3(x,0,1),color:SIMD4(repeating:1))],indices:[0,1,2]))
        }
        func snapshot(_ g:RenderGeometry)->RenderSnapshot {RenderSnapshot(nodes:[RenderNode(geometry:g)])}
        func output()->MTLBuffer {device.makeBuffer(length:256,options:.storageModeShared)!}
        func read(_ buffer:MTLBuffer)->Float {buffer.contents().load(as:Float.self)}
        func copy(_ source:MTLBuffer,_ result:MTLBuffer,_ command:MTLCommandBuffer) {
            let blit=command.makeBlitCommandEncoder()!;blit.copy(from:source,sourceOffset:0,to:result,destinationOffset:0,size:4);blit.endEncoding()
        }
        let gate=device.makeSharedEvent()!,a=makeGeometry(11),b=makeGeometry(22),c=makeGeometry(33)
        let one=output(),two=output(),three=output(),four=output()
        prepare(snapshot(a))
        let first=commandBuffer()!
        precondition(first.retainedReferences,"Expected default Metal resource retention")
        let initial=upload(a)!,secondEye=upload(a)!
        precondition(initial.vertices === secondEye.vertices && geometry[a.id]!.lastUse==1,"Stereo views did not share serial/cache")
        first.encodeWaitForEvent(gate,value:1)
        copy(initial.vertices,one,first);first.commit()
        let second=commandBuffer()!,stillActive=upload(a)!
        precondition(initial.vertices === stillActive.vertices && geometry[a.id]!.lastUse==2,"Latest queued read was not tracked")
        copy(stillActive.vertices,two,second);second.commit()
        prepare(snapshot(b))
        precondition(geometry[a.id]==nil && retired.first!.lastUse==2,"Retired entry lost last queued use")
        let third=commandBuffer()!,replacement=upload(b)!
        precondition(replacement.vertices !== initial.vertices,"Premature reuse while GPU was waiting")
        precondition(read(initial.vertices)==11,"In-flight vertex bytes were overwritten")
        precondition(completion.read()==0,"Blocked commands completed unexpectedly")
        copy(replacement.vertices,three,third);third.commit()
        precondition(commandBuffer()==nil,"Three-command in-flight bound exceeded")
        gate.signaledValue=1
        first.waitUntilCompleted();second.waitUntilCompleted();third.waitUntilCompleted()
        precondition(first.status == .completed && second.status == .completed && third.status == .completed,"GPU command failed")
        precondition(read(one)==11 && read(two)==11 && read(three)==22,"Queued GPU reads observed overwritten data")
        precondition(completion.read()==3,"Completion serial did not cover the finished queue")
        prepare(snapshot(c))
        let fourth=commandBuffer()!,reused=upload(c)!
        precondition(reused.vertices === initial.vertices,"Completed fitting allocation was not reused")
        precondition(retiredBytes<=32*1024*1024 && frameUploads<=24_000_000,"Configured pool/upload bound violated")
        copy(reused.vertices,four,fourth);fourth.commit();fourth.waitUntilCompleted()
        precondition(fourth.status == .completed && read(four)==33,"Reused allocation did not upload new geometry")
        print("PASS exact production Metal buffer pool: two same-command draws share serial; later queued read updates lastUse; blocked GPU prevents overwrite/reuse; three-command bound; GPU readback11/11/22; completion permits same-buffer reuse/readback33; retained references=true")
    }
}
@main struct NativeMetalPoolChecks {
    static func main() throws {
        guard let device=MTLCreateSystemDefaultDevice() else {fatalError("A real Metal device is required")}
        print("Metal device: \(device.name)")
        let renderer=try MetalSceneRenderer(device:device,color:.bgra8Unorm_srgb)
        try renderer.checkGPUBufferLifetime()
    }
}
