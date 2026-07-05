import AppKit

/// Draws a menu-bar template icon stylized after the Planka logo: a rounded
/// kanban board with three columns of differing heights. Being a template
/// image, it automatically adapts to light/dark menu bars.
enum StatusIcon {
    static func image() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setStroke()
            NSColor.black.setFill()

            // Board outline
            let board = NSBezierPath(roundedRect: NSRect(x: 1.5, y: 2.0, width: 15, height: 14), xRadius: 3.5, yRadius: 3.5)
            board.lineWidth = 1.6
            board.stroke()

            // Three kanban columns (Planka-style: middle column shorter)
            let colWidth: CGFloat = 2.6
            let topY: CGFloat = 12.6
            let radius: CGFloat = 1.3
            func column(x: CGFloat, height: CGFloat) {
                let r = NSRect(x: x, y: topY - height, width: colWidth, height: height)
                NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius).fill()
            }
            column(x: 4.0, height: 7.4)
            column(x: 7.7, height: 4.6)
            column(x: 11.4, height: 6.2)
            return true
        }
        image.isTemplate = true
        return image
    }
}
