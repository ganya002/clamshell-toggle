import AppKit

enum Glyph {
    static func image(awake: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            draw(in: rect, awake: awake)
            return true
        }
        image.isTemplate = true
        return image
    }

    static func draw(in rect: CGRect, awake: Bool) {
        let scale = min(rect.width, rect.height) / 18
        func x(_ value: CGFloat) -> CGFloat { rect.minX + value * scale }
        func y(_ value: CGFloat) -> CGFloat { rect.minY + value * scale }
        func point(_ px: CGFloat, _ py: CGFloat) -> CGPoint { CGPoint(x: x(px), y: y(py)) }

        NSColor.black.set()
        let weight = 1.35 * scale

        let base = NSBezierPath(
            roundedRect: CGRect(x: x(2.15), y: y(2.15), width: 13.7 * scale, height: 3.35 * scale),
            xRadius: 1.05 * scale,
            yRadius: 1.05 * scale
        )
        base.lineWidth = weight
        if awake {
            base.fill()
        } else {
            base.stroke()
        }

        let lid = NSBezierPath()
        lid.move(to: point(3.35, 6.55))
        lid.line(to: point(14.65, 6.55))
        lid.line(to: point(12.55, 15.15))
        lid.curve(to: point(5.45, 15.15), controlPoint1: point(12.15, 15.55), controlPoint2: point(5.85, 15.55))
        lid.close()
        lid.lineWidth = weight
        lid.lineJoinStyle = .round
        if awake {
            lid.fill()
            NSColor.black.withAlphaComponent(0).setFill()
            let slit = NSBezierPath(
                roundedRect: CGRect(x: x(6.15), y: y(8.15), width: 5.7 * scale, height: 1.15 * scale),
                xRadius: 0.55 * scale,
                yRadius: 0.55 * scale
            )
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            slit.fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
        } else {
            lid.stroke()
            let hinge = NSBezierPath()
            hinge.move(to: point(7.1, 6.55))
            hinge.line(to: point(10.9, 6.55))
            hinge.lineWidth = weight
            hinge.lineCapStyle = .round
            hinge.stroke()
        }
    }
}
