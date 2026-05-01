import CoreGraphics
import Foundation

@inline(__always)
func expectClose(_ actual: CGFloat, _ expected: CGFloat, _ message: String) {
    if abs(actual - expected) > 0.001 {
        fatalError("\(message): expected \(expected), got \(actual)")
    }
}

@main
struct GeometryRegression {
    static func main() {
        let centered = MagnifierGeometry.cropRect(
            cursorPoint: CGPoint(x: 500, y: 300),
            primaryScreenHeightPoints: 900,
            innerSizePoints: CGSize(width: 300, height: 200),
            zoom: 2.0,
            pointToPixelScale: CGSize(width: 2, height: 2),
            framePixelSize: CGSize(width: 2000, height: 1800)
        )
        expectClose(centered.width, 300, "zoom should shrink source crop width")
        expectClose(centered.height, 200, "zoom should shrink source crop height")
        expectClose(centered.midX, 1000, "cursor x should map from points to pixels")
        expectClose(centered.midY, 1200, "cursor y should flip from AppKit to top-left pixels")

        let edge = MagnifierGeometry.cropRect(
            cursorPoint: CGPoint(x: 10, y: 890),
            primaryScreenHeightPoints: 900,
            innerSizePoints: CGSize(width: 300, height: 200),
            zoom: 3.0,
            pointToPixelScale: CGSize(width: 2, height: 2),
            framePixelSize: CGSize(width: 2000, height: 1800)
        )
        expectClose(edge.minX, 0, "left edge should clamp")
        expectClose(edge.minY, 0, "top edge should clamp after y flip")
        if edge.width > 200.001 || edge.height > 134.001 {
            fatalError("clamped crop grew past zoom-derived size: \(edge)")
        }

        print("geometry regression checks passed")
    }
}
