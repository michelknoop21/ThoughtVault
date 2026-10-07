#!/usr/bin/env swift
import AppKit

// Run from the repository root after generating the platform icons.
let catalog = "macos/Assets.xcassets/AppIcon.appiconset/"
let contents = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: catalog + "Contents.json"))) as! [String: Any]
for entry in contents["images"] as! [[String: String]] {
    let file = entry["filename"]!
    let expected = Int(entry["size"]!.split(separator: "x")[0])! * (entry["scale"] == "2x" ? 2 : 1)
    let bitmap = NSBitmapImageRep(data: try Data(contentsOf: URL(fileURLWithPath: catalog + file)))!
    precondition(bitmap.pixelsWide == expected && bitmap.pixelsHigh == expected, "Invalid icon dimensions: \(file)")
    if entry["platform"] == "ios" {
        for (x, y) in [(0, 0), (expected - 1, 0), (0, expected - 1), (expected - 1, expected - 1)] {
            precondition(bitmap.colorAt(x: x, y: y)!.alphaComponent == 1, "iOS icon must be opaque")
        }
    }
}
let ico = try Data(contentsOf: URL(fileURLWithPath: "windows/src-tauri/icons/icon.ico"))
precondition(Array(ico.prefix(6)) == [0, 0, 1, 0, 7, 0], "Missing Windows icon resolutions")
for (index, size) in [16, 24, 32, 48, 64, 128, 256].enumerated() {
    precondition(Int(ico[6 + index * 16]) == size % 256, "Wrong Windows frame size")
}
print("PASS: macOS dimensions, opaque iOS icon, seven Windows ICO resolutions")
