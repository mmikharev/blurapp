import AppKit

extension NSBezierPath {
    var cgPath: CGPath {
        let path = CGMutablePath()
        let points = UnsafeMutablePointer<NSPoint>.allocate(capacity: 3)
        defer { points.deallocate() }

        for i in 0..<elementCount {
            switch element(at: i, associatedPoints: points) {
            case .moveTo:
                path.move(to: points[0])
            case .lineTo:
                path.addLine(to: points[0])
            case .curveTo:
                path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .closePath:
                path.closeSubpath()
            #if swift(>=5.9)
            // Handle quadratic curves when available in newer SDKs
            case .quadraticCurveTo:
                // Convert quadratic to cubic for CGPath
                let q0 = i > 0 ? path.currentPoint : points[0]
                let q1 = points[0]
                let q2 = points[1]
                let c1 = CGPoint(x: q0.x + (2.0/3.0)*(q1.x - q0.x), y: q0.y + (2.0/3.0)*(q1.y - q0.y))
                let c2 = CGPoint(x: q2.x + (2.0/3.0)*(q1.x - q2.x), y: q2.y + (2.0/3.0)*(q1.y - q2.y))
                path.addCurve(to: q2, control1: c1, control2: c2)
            #endif
            @unknown default:
                break
            }
        }
        return path
    }
}
