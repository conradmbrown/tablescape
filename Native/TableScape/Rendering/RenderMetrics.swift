import Foundation
import QuartzCore

final class RenderMetrics:@unchecked Sendable {
    static let shared=RenderMetrics()
    private let lock=NSLock()
    private var samples:[(Double,Double,Double)]=[]
    private var dropped=0
    private var cpuSamples:[Double]=[]
    private var uploadBytes=0
    private var lateSubmissions=0
    private var uploadDeferrals=0
    private var bufferAllocations=0
    private var bufferReuses=0
    func geometryBuffer(reused:Bool){lock.lock();if reused{bufferReuses+=1}else{bufferAllocations+=1};lock.unlock()}
    private var displayTimes:[Double]=[]
    private var sceneTimes:[Double]=[]
    func displayCallback(_ time:Double){lock.lock();displayTimes.append(time);if displayTimes.count>120{displayTimes.removeFirst()};lock.unlock()}
    func sceneSnapshot(_ time:Double){lock.lock();sceneTimes.append(time);if sceneTimes.count>120{sceneTimes.removeFirst()};lock.unlock()}
    private var viewDetails:[String:Double]=[:]
    func view(_ values:[String:Double]){lock.lock();viewDetails=values;lock.unlock()}
    func encode(seconds:Double,bytes:Int,late:Bool){lock.lock();cpuSamples.append(seconds);if cpuSamples.count>600{cpuSamples.removeFirst(cpuSamples.count-600)};uploadBytes=bytes;if late{lateSubmissions+=1};lock.unlock()}
    func deferredUpload(){lock.lock();uploadDeferrals+=1;lock.unlock()}
    func record(cpu:Double,gpu:Double){lock.lock();samples.append((CACurrentMediaTime(),cpu,gpu));if samples.count>600{samples.removeFirst(samples.count-600)};lock.unlock()}
    func miss(){lock.lock();dropped+=1;lock.unlock()}
    func snapshot()->[String:Double]{
        lock.lock();defer{lock.unlock()};let recent=samples.suffix(120),count=Double(recent.count)
        guard count>1,let first=recent.first,let last=recent.last else{return["samples":count,"skippedFrames":Double(dropped)]}
        let times=recent.map{$0.1}.sorted(),gpu=recent.map{$0.2}.sorted()
        let cpu=cpuSamples.sorted()
        let values:[String:Double] = ["cpuEncodeMedianMs":cpu.isEmpty ? 0:cpu[cpu.count/2]*1000,"lastFrameUploadBytes":Double(uploadBytes),"lateCPUSubmissions":Double(lateSubmissions),"deferredUploads":Double(uploadDeferrals),"geometryBufferAllocations":Double(bufferAllocations),"geometryBufferReuses":Double(bufferReuses),"samples":Double(samples.count),"commandCompletionsPerSecond":(count-1)/max(0.001,last.0-first.0),"driverMedianMs":times[times.count/2]*1000,"driverP95Ms":times[min(times.count-1,Int(Double(times.count)*0.95))]*1000,"gpuMedianMs":gpu[gpu.count/2]*1000,"skippedFrames":Double(dropped)]
        var result=viewDetails.merging(values){_,new in new}
        for (key,times) in [("mainDisplayCallbacksPerSecond",displayTimes),("sceneSnapshotsPerSecond",sceneTimes)] {if let first=times.first,let last=times.last,times.count>1 {result[key]=Double(times.count-1)/max(0.001,last-first)}}
        return result
    }
}
