import Foundation
import CoreGraphics
import CoreText
import ImageIO
import Darwin

@main
struct ImageMemoryBenchmarks {
    static func memory() -> [String: Any] {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        precondition(status == KERN_SUCCESS)
        return ["physical_footprint_bytes": info.phys_footprint,
                "lifetime_peak_physical_footprint_bytes": info.ledger_phys_footprint_peak]
    }

    static func main() throws {
        let args = CommandLine.arguments
        let url = URL(fileURLWithPath: args[2])
        if args[1] == "generate" {
            let context = CGContext(data: nil, width: 6000, height: 4000, bitsPerComponent: 8,
                                    bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 6000, height: 4000))
            let font = CTFontCreateWithName("Helvetica" as CFString, 96, nil)
            for row in 0..<12 {
                let text = NSAttributedString(string: "SnapAI large image memory fixture row \(row + 1).",
                    attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font,
                                 NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1)])
                context.textPosition = CGPoint(x: 200, y: 3700 - row * 290)
                CTLineDraw(CTLineCreateWithAttributedString(text), context)
            }
            let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
            CGImageDestinationAddImage(destination, context.makeImage()!, nil)
            precondition(CGImageDestinationFinalize(destination))
            return
        }
        var rows: [[String: Any]] = []
        rows.append(["stage": "baseline", "memory": memory()])
        for iteration in 1...30 {
            try autoreleasepool {
                var start = ProcessInfo.processInfo.systemUptime
                let data = try Data(contentsOf: url)
                rows.append(["iteration": iteration, "stage": "read", "milliseconds": (ProcessInfo.processInfo.systemUptime - start) * 1000, "compressed_bytes": data.count, "memory": memory()])
                start = ProcessInfo.processInfo.systemUptime
                autoreleasepool {
                    let source = CGImageSourceCreateWithData(data as CFData, nil)!
                    let decoded = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)!
                    precondition(decoded.width == 6000 && decoded.height == 4000)
                    let raster = CGContext(data: nil, width: decoded.width, height: decoded.height, bitsPerComponent: 8,
                                           bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                    raster.draw(decoded, in: CGRect(x: 0, y: 0, width: decoded.width, height: decoded.height))
                    withExtendedLifetime(raster) {
                        rows.append(["iteration": iteration, "stage": "forced_raster_decode", "milliseconds": (ProcessInfo.processInfo.systemUptime - start) * 1000, "memory": memory()])
                    }
                }
                start = ProcessInfo.processInfo.systemUptime
                let outcome = SnapAIImageTextRecognition.recognizeText(in: data)
                var result: [String: Any] = ["iteration": iteration, "stage": "production_data_ocr", "milliseconds": (ProcessInfo.processInfo.systemUptime - start) * 1000, "memory": memory()]
                switch outcome {
                case .recognized(let recognized):
                    result["outcome"] = "recognized"
                    result["characters"] = recognized.text.count
                    result["confidence"] = recognized.confidence
                    result["recognized_fixture_text"] = recognized.text
                    result["contains_fixture_text"] = recognized.text.contains("memory fixture")
                default: result["outcome"] = String(describing: outcome)
                }
                rows.append(result)
            }
            rows.append(["iteration": iteration, "stage": "released", "memory": memory()])
            Thread.sleep(forTimeInterval: 1)
            rows.append(["iteration": iteration, "stage": "released_after_1s", "memory": memory()])
        }
        Thread.sleep(forTimeInterval: 5)
        rows.append(["stage": "final_released_after_5s", "memory": memory()])
        let result: [String: Any] = ["dimensions": [6000, 4000], "iterations": 30,
            "scope": "isolated synchronous production Data-to-Vision OCR; separate forced ImageIO + CGContext raster decode probe; no window, QuickInput model, attachment optimization, SwiftUI deletion, or cloud request",
            "peak_definition": "Mach task_vm_info ledger_phys_footprint_peak is process lifetime high-water mark, not stage-specific peak",
            "release_definition": "local Data/CGImage/OCR result references and autorelease pool released; system framework caches remain possible; no forced allocator purge",
            "samples": rows]
        let json = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        FileHandle.standardOutput.write(json)
    }
}
