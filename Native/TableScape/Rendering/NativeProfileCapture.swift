import Foundation
import QuartzCore
import Darwin
import UIKit

@MainActor private final class MainDisplayProbe:NSObject {
    @objc func tick(_ link:CADisplayLink){RenderMetrics.shared.displayCallback(CACurrentMediaTime())}
}

/// Opt-in, bounded diagnostics. Records timings/counts only; never state, identities or credentials.
@MainActor enum NativeProfileCapture {
    static func run(model:TableScapeModel) async {
        let probe=MainDisplayProbe()
        let display=CADisplayLink(target:probe,selector:#selector(MainDisplayProbe.tick(_:)))
        display.add(to:.main,forMode:.common)
        defer{display.invalidate()}
        var samples:[[String:Any]]=[]
        let start=CACurrentMediaTime()
        for _ in 0..<120 {
            if Task.isCancelled {return}
            var info=mach_task_basic_info(),count=mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
            let result=withUnsafeMutablePointer(to:&info){pointer in pointer.withMemoryRebound(to:integer_t.self,capacity:Int(count)){task_info(mach_task_self_,task_flavor_t(MACH_TASK_BASIC_INFO),$0,&count)}}
            var sample:[String:Any]=RenderMetrics.shared.snapshot()
            sample["elapsedSeconds"]=CACurrentMediaTime()-start
            sample["residentBytes"]=result==KERN_SUCCESS ? info.resident_size:0
            sample["sceneUpdateMs"]=model.scene.frameMilliseconds
            sample["receivedHits"]=model.scene.combatFeedback.receivedHits
            sample["drawnHits"]=model.scene.combatFeedback.drawnHits
            sample["drawnHealthBars"]=model.scene.combatFeedback.drawnBars
            sample["regions"]=model.scene.chunkCount;sample["triangles"]=model.scene.triangleCount
            sample["volumeMenuTapCount"]=model.volumeMenuTapCount
            sample["volumeAppearanceCount"]=model.volumeAppearanceCount
            sample["volumeDisappearanceCount"]=model.volumeDisappearanceCount
            sample["volumeOpenRequests"]=model.volumeOpenRequests
            sample["tableLeaveRequests"]=model.tableLeaveRequests
            sample["homeAppearanceCount"]=model.homeAppearanceCount
            sample["renderBoundaryPoints"]=model.scene.exchange.read().boundary.count
            sample["physicalBoundaryPoints"]=model.placement.snapshot.boundary.count
            sample["volumeTapCount"]=model.scene.volumeTapCount
            sample["volumeInputStatus"]=model.scene.volumeInputStatus
            sample["network"]=model.session.networkMetricsSnapshot()
            sample["immersive"]=model.immersive;sample["volumeOpen"]=model.volumeOpen;sample["connected"]=model.session.connected
            samples.append(sample)
            let report:[String:Any]=["platform":ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] == nil ? "visionOS device":"visionOS simulator","gpuTimingIsDeviceAcceptance":false,"samples":samples]
            if let url=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask).first?.appendingPathComponent("profile.json"),let data=try? JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]){try? data.write(to:url,options:.atomic)}
            try? await Task.sleep(nanoseconds:5_000_000_000)
        }
    }
}
