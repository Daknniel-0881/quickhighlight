import CoreGraphics

enum MagnifierGeometry {
    /// Computes the source crop rectangle in the captured frame's top-left pixel coordinates.
    ///
    /// The lens destination is measured in screen points. To zoom, we sample a smaller source
    /// area (`innerSize / zoom`) and then draw that crop back into the full lens destination.
    static func cropRect(
        cursorPoint: CGPoint,
        primaryScreenHeightPoints: CGFloat,
        innerSizePoints: CGSize,
        zoom: CGFloat,
        pointToPixelScale: CGSize,
        framePixelSize: CGSize
    ) -> CGRect {
        guard primaryScreenHeightPoints > 0,
              innerSizePoints.width > 0,
              innerSizePoints.height > 0,
              pointToPixelScale.width > 0,
              pointToPixelScale.height > 0,
              framePixelSize.width > 0,
              framePixelSize.height > 0 else {
            return .null
        }

        let z = max(zoom, 0.01)
        let cursorPxX = cursorPoint.x * pointToPixelScale.width
        let cursorPxY = (primaryScreenHeightPoints - cursorPoint.y) * pointToPixelScale.height
        let captureSizePxW = (innerSizePoints.width / z) * pointToPixelScale.width
        let captureSizePxH = (innerSizePoints.height / z) * pointToPixelScale.height

        let rawCrop = CGRect(
            x: cursorPxX - captureSizePxW / 2,
            y: cursorPxY - captureSizePxH / 2,
            width: captureSizePxW,
            height: captureSizePxH
        ).integral

        return rawCrop.intersection(CGRect(origin: .zero, size: framePixelSize))
    }

    static func ciCropRect(fromTopLeftCropRect cropRect: CGRect, framePixelHeight: CGFloat) -> CGRect {
        CGRect(
            x: cropRect.minX,
            y: framePixelHeight - cropRect.maxY,
            width: cropRect.width,
            height: cropRect.height
        )
    }
}
