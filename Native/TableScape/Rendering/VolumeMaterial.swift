import Foundation
import CoreGraphics
import ImageIO

/// A small public MaterialX graph carried as USD text. The graph uses the original
/// mesh's vertex color and UV0, with a single verified game texture per material.
/// It clips in XZ only: the table footprint never removes rivers or lower floors.
enum VolumeMaterialSource {
    static let name = "/TableScape"
    static func data() -> Data {
        var nodes: [String] = []
        func ref(_ node: String) -> String { "</TableScape/\(node).outputs:out>" }
        func node(_ name: String, _ type: String, _ output: String, _ inputs: [String]) {
            nodes.append("def Shader \"\(name)\" {\n uniform token info:id = \"\(type)\"\n " + inputs.joined(separator: "\n ") + "\n \(output) outputs:out\n}")
        }
        node("Color", "ND_geomcolor_color4", "color4f", ["int inputs:index = 0"])
        node("Image", "ND_image_color4", "color4f", ["asset inputs:file.connect = </TableScape.inputs:gameTexture>", "color4f inputs:default = (1, 1, 1, 1)", "string inputs:uaddressmode = \"periodic\"", "string inputs:vaddressmode = \"periodic\"", "string inputs:filtertype = \"linear\""])
        node("Tinted", "ND_multiply_color4", "color4f", ["color4f inputs:in1.connect = \(ref("Color"))", "color4f inputs:in2.connect = \(ref("Image"))"])
        node("RGB", "ND_convert_color4_color3", "color3f", ["color4f inputs:in.connect = \(ref("Tinted"))"])
        node("Alpha", "ND_extract_color4", "float", ["color4f inputs:in.connect = \(ref("Tinted"))", "int inputs:index = 3"])
        node("Position", "ND_position_vector3", "float3", ["string inputs:space = \"object\""])
        node("Relative", "ND_subtract_vector3", "float3", ["float3 inputs:in1.connect = \(ref("Position"))", "float3 inputs:in2.connect = </TableScape.inputs:gameCenter>"])
        node("Scaled", "ND_multiply_vector3FA", "float3", ["float3 inputs:in1.connect = \(ref("Relative"))", "float inputs:in2.connect = </TableScape.inputs:boardScale>"])
        // RealityKit accepts named swizzle channels but silently renders its cyan
        // fallback for a constant channel ("xz1"). Explicit extracts and a combine
        // keep the homogeneous XZ half-plane coordinate valid on the actual GPU.
        node("X", "ND_extract_vector3", "float", ["float3 inputs:in.connect = \(ref("Scaled"))", "int inputs:index = 0"])
        node("Z", "ND_extract_vector3", "float", ["float3 inputs:in.connect = \(ref("Scaled"))", "int inputs:index = 2"])
        node("XZ", "ND_combine3_vector3", "float3", ["float inputs:in1.connect = \(ref("X"))", "float inputs:in2.connect = \(ref("Z"))", "float inputs:in3 = 1"])
        var edgeProduct = ""
        for index in 0..<8 {
            node("Edge\(index)", "ND_dotproduct_vector3", "float", ["float3 inputs:in1.connect = \(ref("XZ"))", "float3 inputs:in2.connect = </TableScape.inputs:edge\(index)>"])
            node("Inside\(index)", "ND_ifgreatereq_float", "float", ["float inputs:value1.connect = \(ref("Edge\(index)"))", "float inputs:value2 = -0.00001", "float inputs:in1 = 1", "float inputs:in2 = 0"])
            if index == 0 { edgeProduct = "Inside0" }
            else {
                let next = "Mask\(index)"
                node(next, "ND_multiply_float", "float", ["float inputs:in1.connect = \(ref(edgeProduct))", "float inputs:in2.connect = \(ref("Inside\(index)"))"])
                edgeProduct = next
            }
        }
        node("Clip", "ND_mix_float", "float", ["float inputs:fg.connect = \(ref(edgeProduct))", "float inputs:bg = 1", "float inputs:mix.connect = </TableScape.inputs:clipEnabled>"])
        node("Opacity", "ND_multiply_float", "float", ["float inputs:in1.connect = \(ref("Alpha"))", "float inputs:in2.connect = \(ref("Clip"))"])
        node("Surface", "ND_realitykit_unlit_surfaceshader", "token", ["color3f inputs:color.connect = \(ref("RGB"))", "float inputs:opacity.connect = \(ref("Opacity"))", "float inputs:opacityThreshold.connect = </TableScape.inputs:alphaThreshold>", "bool inputs:applyPostProcessToneMap = false", "bool inputs:hasPremultipliedAlpha = false"])
        let edges = (0..<8).map { "float3 inputs:edge\($0) = (0, 0, 1)" }.joined(separator: "\n")
        let source = """
        #usda 1.0
        def Material "TableScape" {
          asset inputs:gameTexture
          float3 inputs:gameCenter = (0, 0, 0)
          float inputs:boardScale = 1
          float inputs:clipEnabled = 1
          float inputs:alphaThreshold = 0.2
          \(edges)
          token outputs:mtlx:surface.connect = </TableScape/Surface.outputs:out>
          \(nodes.joined(separator: "\n"))
        }
        """
        return Data(source.utf8)
    }
}

/// Decode the same image pixels used by the table material, including cache palette keys.
enum VolumeTextureImage {
    private struct DecodeError: LocalizedError { let errorDescription: String? }
    static func decode(_ data: Data?) throws -> CGImage {
        let original: CGImage?
        if let data,let source=CGImageSourceCreateWithData(data as CFData,nil) {original=CGImageSourceCreateImageAtIndex(source,0,nil)} else {original=nil}
        let width=original?.width ?? 1,height=original?.height ?? 1
        guard width <= 2048,height <= 2048 else {throw DecodeError(errorDescription: "Volume texture exceeds bound")}
        // Source-over drawing must start clear so PNG alpha survives.
        // Only the untextured material fallback is opaque white.
        var pixels=[UInt8](repeating:original == nil ? 255 : 0,count:width*height*4)
        let flags=CGBitmapInfo.byteOrder32Big.rawValue|CGImageAlphaInfo.premultipliedLast.rawValue
        if let original,let context=CGContext(data:&pixels,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:flags) {
            context.draw(original,in:CGRect(x:0,y:0,width:width,height:height))
            for i in stride(from:0,to:pixels.count,by:4) where pixels[i]==255 && pixels[i+1]==0 && pixels[i+2]==255 {pixels[i]=0;pixels[i+1]=0;pixels[i+2]=0;pixels[i+3]=0}
        }
        guard let provider=CGDataProvider(data:Data(pixels) as CFData),let image=CGImage(width:width,height:height,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:flags),provider:provider,decode:nil,shouldInterpolate:true,intent:.defaultIntent) else {throw DecodeError(errorDescription: "Volume texture could not be decoded")}
        return image
    }
}
