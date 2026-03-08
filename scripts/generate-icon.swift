#!/usr/bin/env swift
// Generates AppIcon.icns for the Aavaz app bundle.
// Usage: swift scripts/generate-icon.swift <output-dir>

import AppKit

let outputDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build"

func renderIcon(size: CGFloat) -> NSImage {
    return NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
        // Accent purple background with rounded rect
        let accent = NSColor(red: 0x6E / 255.0, green: 0x6A / 255.0, blue: 0xE8 / 255.0, alpha: 1.0)
        let inset = size * 0.03
        let cornerRadius = size * 0.19
        let bgPath = NSBezierPath(roundedRect: rect.insetBy(dx: inset, dy: inset), xRadius: cornerRadius, yRadius: cornerRadius)
        accent.setFill()
        bgPath.fill()

        // Waveform bars
        let barCount = 7
        let barWidth = size * 0.047
        let gap = size * 0.039
        let totalW = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * gap
        let startX = (rect.width - totalW) / 2
        let maxH = size * 0.55
        let centerY = rect.height / 2
        let heights: [CGFloat] = [0.30, 0.55, 0.80, 1.0, 0.75, 0.50, 0.25]

        NSColor.white.setFill()
        for i in 0..<barCount {
            let h = heights[i] * maxH
            let x = startX + CGFloat(i) * (barWidth + gap)
            let y = centerY - h / 2
            let barRect = NSRect(x: x, y: y, width: barWidth, height: h)
            NSBezierPath(roundedRect: barRect, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
        }
        return true
    }
}

// Create iconset directory
let iconsetPath = "\(outputDir)/AppIcon.iconset"
let fm = FileManager.default
try? fm.removeItem(atPath: iconsetPath)
try! fm.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

// Required sizes for .icns
let sizes: [(String, CGFloat)] = [
    ("icon_16x16", 16),
    ("icon_16x16@2x", 32),
    ("icon_32x32", 32),
    ("icon_32x32@2x", 64),
    ("icon_128x128", 128),
    ("icon_128x128@2x", 256),
    ("icon_256x256", 256),
    ("icon_256x256@2x", 512),
    ("icon_512x512", 512),
    ("icon_512x512@2x", 1024),
]

for (name, size) in sizes {
    let img = renderIcon(size: size)
    guard let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        print("Failed to render \(name)")
        continue
    }
    let path = "\(iconsetPath)/\(name).png"
    try! png.write(to: URL(fileURLWithPath: path))
}

// Convert iconset to icns
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconsetPath, "-o", "\(outputDir)/AppIcon.icns"]
try! task.run()
task.waitUntilExit()

// Clean up iconset
try? fm.removeItem(atPath: iconsetPath)

if task.terminationStatus == 0 {
    print("Generated \(outputDir)/AppIcon.icns")
} else {
    print("iconutil failed with status \(task.terminationStatus)")
}
