import Foundation
import CoreGraphics
#if !SNAPAI_MANUAL_TEST_MAIN
@testable import SnapAILogic
#endif

func testImageCropMapsDisplaySelectionToPixels() {
    let pixels = CGSize(width: 2400, height: 1200)
    let display = CGSize(width: 600, height: 300)
    expect(ImageCrop.pixelRect(selection: CGRect(x: 150, y: 75, width: 300, height: 150),
                               displaySize: display, pixelSize: pixels)
           == CGRect(x: 600, y: 300, width: 1200, height: 600),
           "crop maps displayed coordinates to actual pixels independently of screen backing scale")
    expect(ImageCrop.pixelRect(selection: CGRect(x: -20, y: -10, width: 80, height: 40),
                               displaySize: display, pixelSize: pixels)
           == CGRect(x: 0, y: 0, width: 240, height: 120),
           "crop clips a partially outside selection to the image bounds")
    expect(ImageCrop.pixelRect(selection: CGRect(x: 1.1, y: 2.1, width: 1.1, height: 1.1),
                               displaySize: display, pixelSize: pixels)
           == CGRect(x: 4, y: 8, width: 5, height: 5),
           "crop rounds outward to preserve selected edge pixels")
    expect(ImageCrop.pixelRect(selection: .zero, displaySize: display, pixelSize: pixels) == nil,
           "empty crop selection cannot replace the attachment")
    expect(ImageCrop.pixelRect(selection: CGRect(x: 601, y: 0, width: 10, height: 10),
                               displaySize: display, pixelSize: pixels) == nil,
           "fully outside crop selection cannot replace the attachment")

    let irregularPixels = CGSize(width: 4031, height: 3023)
    let irregularDisplay = CGSize(width: 453.37, height: 340)
    for x in stride(from: 0, through: 4000, by: 37) {
        let rect = CGRect(x: x, y: 17, width: min(31, 4031 - x), height: 2999)
        let shown = ImageCrop.displayRect(pixelRect: rect, displaySize: irregularDisplay,
                                          pixelSize: irregularPixels)!
        expect(ImageCrop.pixelRect(selection: shown, displaySize: irregularDisplay,
                                   pixelSize: irregularPixels) == rect,
               "pixel controls preserve exact integer edges through noninteger display scaling")
    }
    let clipped = ImageCrop.displayRect(pixelRect: CGRect(x: -3, y: 2, width: 10, height: 10),
                                        displaySize: CGSize(width: 3.7, height: 3.7),
                                        pixelSize: CGSize(width: 4, height: 4))!
    expect(ImageCrop.pixelRect(selection: clipped, displaySize: CGSize(width: 3.7, height: 3.7),
                               pixelSize: CGSize(width: 4, height: 4)) == CGRect(x: 0, y: 2, width: 4, height: 2),
           "pixel input conversion clips to source bounds")
    let fractional = ImageCrop.displayRect(pixelRect: CGRect(x: 9.99999, y: 2, width: 1.00002, height: 1),
                                           displaySize: irregularDisplay, pixelSize: irregularPixels)!
    expect(ImageCrop.pixelRect(selection: fractional, displaySize: irregularDisplay,
                               pixelSize: irregularPixels) == CGRect(x: 9, y: 2, width: 3, height: 1),
           "real subpixel edges still round outward beyond floating point representation tolerance")
    expect(ImageCrop.pixelRect(selection: CGRect(x: 1, y: 1, width: CGFloat(1).ulp, height: 1),
                               displaySize: CGSize(width: 4, height: 4),
                               pixelSize: CGSize(width: 4, height: 4)) == nil,
           "representation-sized selections cannot produce a nonnil empty pixel rectangle")
}

func testImageCropProducesSelectedPixelContent() {
    var bytes = [UInt8](repeating: 0, count: 4 * 4 * 4)
    for row in 0..<4 {
        for column in 0..<4 {
            let offset = (row * 4 + column) * 4
            bytes[offset] = row < 2 ? 255 : 0
            bytes[offset + 2] = row < 2 ? 0 : 255
            bytes[offset + 3] = 255
        }
    }
    let provider = CGDataProvider(data: Data(bytes) as CFData)!
    let image = CGImage(width: 4, height: 4, bitsPerComponent: 8, bitsPerPixel: 32,
                        bytesPerRow: 16, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    let top = ImageCrop.crop(image, selection: CGRect(x: 0, y: 0, width: 2, height: 1),
                             displaySize: CGSize(width: 2, height: 2))!
    let bottom = ImageCrop.crop(image, selection: CGRect(x: 0, y: 1, width: 2, height: 1),
                                displaySize: CGSize(width: 2, height: 2))!
    expect(top.width == 4 && top.height == 2 && bottom.width == 4 && bottom.height == 2,
           "crop creates smaller pixel images rather than changing only the preview")
    let topData = top.dataProvider!.data!
    let bottomData = bottom.dataProvider!.data!
    let topBytes = CFDataGetBytePtr(topData)!
    let bottomBytes = CFDataGetBytePtr(bottomData)!
    expect(topBytes[0] == 255 && topBytes[2] == 0 && bottomBytes[0] == 0 && bottomBytes[2] == 255,
           "SwiftUI top-left selections preserve the corresponding CGImage rows without a vertical flip")
    let display = CGSize(width: 3.7, height: 3.7)
    let pixelInput = CGRect(x: 1, y: 3, width: 1, height: 1)
    let selection = ImageCrop.displayRect(pixelRect: pixelInput, displaySize: display,
                                          pixelSize: CGSize(width: 4, height: 4))!
    let selected = ImageCrop.crop(image, selection: selection, displaySize: display)!
    let selectedData = selected.dataProvider!.data!
    let selectedBytes = CFDataGetBytePtr(selectedData)!
    expect(selected.width == 1 && selected.height == 1 && selectedBytes[0] == 0 && selectedBytes[2] == 255,
           "pixel controls crop the selected source pixel even when its display size is below one point")
}
