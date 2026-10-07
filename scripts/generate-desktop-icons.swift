#!/usr/bin/env swift
import AppKit

// Run from the repository root. Export the approved artwork without stretching it.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let source = root.appendingPathComponent("logo/thoughtvault-vault-mark.png")
guard let image = NSImage(contentsOf: source) else { fatalError("Missing source artwork") }
let fm = FileManager.default
let temporary = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".iconset")
try fm.createDirectory(at: temporary, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: temporary) }

func png(_ size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    let scale = CGFloat(size) / max(image.size.width, image.size.height)
    let width = image.size.width * scale, height = image.size.height * scale
    image.draw(in: NSRect(x: (CGFloat(size)-width)/2, y: (CGFloat(size)-height)/2,
                         width: width, height: height), from: .zero, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}
func save(_ data: Data, _ path: String) throws {
    try data.write(to: root.appendingPathComponent(path), options: .atomic)
}
let mac = "macos/Assets.xcassets/AppIcon.appiconset/"
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let filename = "icon_\(base)x\(base)\(scale == 2 ? "@2x" : "").png"
        let data = png(base * scale)
        try save(data, mac + filename)
        try data.write(to: temporary.appendingPathComponent(filename))
    }
}
for path in ["macos/Assets.xcassets/AppLogo.imageset/app-logo.png",
             "windows/src/assets/app-logo.png", "windows/public/icon.png"] {
    try save(png(512), path)
}
for (size, name) in [(32, "32x32.png"), (128, "128x128.png"), (256, "128x128@2x.png")] {
    try save(png(size), "windows/src-tauri/icons/" + name)
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", temporary.path, "-o",
                      root.appendingPathComponent("windows/src-tauri/icons/icon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
precondition(iconutil.terminationStatus == 0, "ICNS export failed")

// ICO directory followed by lossless PNG entries, including small taskbar sizes.
func le<T: FixedWidthInteger>(_ value: T) -> Data {
    var little = value.littleEndian
    return withUnsafeBytes(of: &little) { Data($0) }
}
let sizes = [16, 24, 32, 48, 64, 128, 256]
let frames = sizes.map(png)
var ico = le(UInt16(0)) + le(UInt16(1)) + le(UInt16(sizes.count))
var offset = 6 + 16 * sizes.count
for (size, frame) in zip(sizes, frames) {
    ico.append(contentsOf: [UInt8(size % 256), UInt8(size % 256), 0, 0])
    ico += le(UInt16(1)) + le(UInt16(32)) + le(UInt32(frame.count)) + le(UInt32(offset))
    offset += frame.count
}
for frame in frames { ico += frame }
try save(ico, "windows/src-tauri/icons/icon.ico")
print("Exported macOS and Windows desktop icons from \(source.lastPathComponent)")
