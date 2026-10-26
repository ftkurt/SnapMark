import AppKit

let resources = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let iconset = resources.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func icon(size: Int) -> NSImage {
    let side = CGFloat(size)
    let image = NSImage(size: NSSize(width: side, height: side))
    image.lockFocus()
    let inset = side * 0.06
    let bg = NSBezierPath(roundedRect: NSRect(x: inset, y: inset, width: side - 2 * inset, height: side - 2 * inset),
                          xRadius: side * 0.22, yRadius: side * 0.22)
    NSGradient(colors: [NSColor(calibratedRed: 0.10, green: 0.65, blue: 1.0, alpha: 1),
                        NSColor(calibratedRed: 0.13, green: 0.30, blue: 0.93, alpha: 1)])!.draw(in: bg, angle: -55)

    NSColor.white.setStroke()
    let frame = NSBezierPath()
    frame.lineWidth = side * 0.055
    frame.lineCapStyle = .round
    let lo = side * 0.27, hi = side * 0.73, arm = side * 0.15
    frame.move(to: NSPoint(x: lo + arm, y: hi)); frame.line(to: NSPoint(x: lo, y: hi)); frame.line(to: NSPoint(x: lo, y: hi - arm))
    frame.move(to: NSPoint(x: hi - arm, y: hi)); frame.line(to: NSPoint(x: hi, y: hi)); frame.line(to: NSPoint(x: hi, y: hi - arm))
    frame.move(to: NSPoint(x: lo, y: lo + arm)); frame.line(to: NSPoint(x: lo, y: lo)); frame.line(to: NSPoint(x: lo + arm, y: lo))
    frame.move(to: NSPoint(x: hi, y: lo + arm)); frame.line(to: NSPoint(x: hi, y: lo)); frame.line(to: NSPoint(x: hi - arm, y: lo))
    frame.stroke()

    let pencil = NSBezierPath()
    pencil.lineWidth = side * 0.075; pencil.lineCapStyle = .round
    pencil.move(to: NSPoint(x: side * 0.39, y: side * 0.38))
    pencil.line(to: NSPoint(x: side * 0.67, y: side * 0.66))
    pencil.stroke()
    image.unlockFocus()
    return image
}

func write(_ pixels: Int, name: String) throws {
    let image = icon(size: pixels)
    guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { return }
    try png.write(to: iconset.appendingPathComponent(name))
}

try write(16, name: "icon_16x16.png")
try write(32, name: "icon_16x16@2x.png")
try write(32, name: "icon_32x32.png")
try write(64, name: "icon_32x32@2x.png")
try write(128, name: "icon_128x128.png")
try write(256, name: "icon_128x128@2x.png")
try write(256, name: "icon_256x256.png")
try write(512, name: "icon_256x256@2x.png")
try write(512, name: "icon_512x512.png")
try write(1024, name: "icon_512x512@2x.png")

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("AppIcon.icns").path]
try task.run(); task.waitUntilExit()
guard task.terminationStatus == 0 else { throw NSError(domain: "IconBuild", code: Int(task.terminationStatus)) }
try? FileManager.default.removeItem(at: resources.appendingPathComponent("AppIcon.png"))
try FileManager.default.copyItem(at: iconset.appendingPathComponent("icon_512x512@2x.png"),
                                 to: resources.appendingPathComponent("AppIcon.png"))
try? FileManager.default.removeItem(at: iconset)
