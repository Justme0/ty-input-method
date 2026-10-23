import Cocoa

let size = NSSize(width: 128, height: 128)
let image = NSImage(size: size, flipped: false) { rect in
    NSColor(srgbRed: 0.15, green: 0.42, blue: 0.93, alpha: 1).setFill()
    NSBezierPath(roundedRect: rect.insetBy(dx: 6, dy: 6), xRadius: 28, yRadius: 28).fill()
    let text = "中" as NSString
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 78, weight: .semibold),
        .foregroundColor: NSColor.white,
    ]
    let textSize = text.size(withAttributes: attributes)
    text.draw(
        at: NSPoint(x: (rect.width - textSize.width) / 2, y: (rect.height - textSize.height) / 2 - 2),
        withAttributes: attributes
    )
    return true
}

guard CommandLine.arguments.count > 1,
      let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fputs("生成图标失败\n", stderr)
    exit(1)
}
do {
    try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
} catch {
    fputs("写入图标失败 \(error)\n", stderr)
    exit(1)
}
