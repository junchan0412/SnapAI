import CoreGraphics

package enum ImageCrop {
    package static func displayRect(pixelRect: CGRect, displaySize: CGSize, pixelSize: CGSize) -> CGRect? {
        guard displaySize.width > 0, displaySize.height > 0,
              pixelSize.width > 0, pixelSize.height > 0,
              pixelRect.origin.x.isFinite, pixelRect.origin.y.isFinite,
              pixelRect.width.isFinite, pixelRect.height.isFinite else { return nil }
        let clipped = pixelRect.standardized.intersection(CGRect(origin: .zero, size: pixelSize))
        guard !clipped.isNull, clipped.width > 0, clipped.height > 0 else { return nil }
        let left = clipped.minX / pixelSize.width * displaySize.width
        let top = clipped.minY / pixelSize.height * displaySize.height
        let right = clipped.maxX / pixelSize.width * displaySize.width
        let bottom = clipped.maxY / pixelSize.height * displaySize.height
        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }

    private static func stablePixelEdge(_ value: CGFloat, extent: CGFloat) -> CGFloat {
        // Coordinate scaling and CGRect edge addition can accumulate a few ULPs.
        // Only snap within eight representable steps at the image's pixel extent.
        let integer = value.rounded()
        return abs(value - integer) <= extent.ulp * 8 ? integer : value
    }

    package static func pixelRect(selection: CGRect, displaySize: CGSize, pixelSize: CGSize) -> CGRect? {
        guard displaySize.width > 0, displaySize.height > 0,
              pixelSize.width > 0, pixelSize.height > 0,
              selection.origin.x.isFinite, selection.origin.y.isFinite,
              selection.width.isFinite, selection.height.isFinite else { return nil }
        let clipped = selection.standardized.intersection(CGRect(origin: .zero, size: displaySize))
        guard !clipped.isNull, clipped.width > 0, clipped.height > 0 else { return nil }
        let left = floor(stablePixelEdge(clipped.minX / displaySize.width * pixelSize.width, extent: pixelSize.width))
        let top = floor(stablePixelEdge(clipped.minY / displaySize.height * pixelSize.height, extent: pixelSize.height))
        let right = min(pixelSize.width, ceil(stablePixelEdge(clipped.maxX / displaySize.width * pixelSize.width, extent: pixelSize.width)))
        let bottom = min(pixelSize.height, ceil(stablePixelEdge(clipped.maxY / displaySize.height * pixelSize.height, extent: pixelSize.height)))
        guard right > left, bottom > top else { return nil }
        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }

    package static func crop(_ image: CGImage, selection: CGRect, displaySize: CGSize) -> CGImage? {
        guard let rect = pixelRect(selection: selection, displaySize: displaySize,
                                   pixelSize: CGSize(width: image.width, height: image.height)) else { return nil }
        return image.cropping(to: rect)
    }
}
