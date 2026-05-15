#!/usr/bin/env swift
// Regenerates ../AppIcon.icns from ../data/usagi.svg.
//
//   swift scripts/make-icns.swift     # run from the repo root
//
// build.sh copies AppIcon.icns into the bundle (Info.plist's CFBundleIconFile
// is "AppIcon"). The source art is composited onto a rounded-rect with the
// usual ~9.4% macOS icon-grid margin so it sits right next to other app icons.

import AppKit
import CoreGraphics

let root = FileManager.default.currentDirectoryPath
let srcPath = "\(root)/data/usagi.svg"
let icnsPath = "\(root)/AppIcon.icns"
let iconsetPath = "\(root)/AppIcon.iconset"

guard let nsImage = NSImage(contentsOfFile: srcPath) else {
    FileHandle.standardError.write("error: can't load \(srcPath)\n".data(using: .utf8)!)
    exit(1)
}

try? FileManager.default.removeItem(atPath: iconsetPath)
try! FileManager.default.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

func render(_ px: Int) -> CGImage {
    let ctx = CGContext(
        data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    ctx.interpolationQuality = .high
    let s = CGFloat(px)
    let margin = (s * 0.0938).rounded()
    let box = CGRect(x: margin, y: margin, width: s - 2 * margin, height: s - 2 * margin)
    let radius = box.width * 0.2237
    ctx.addPath(CGPath(roundedRect: box, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.clip()
    ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))   // matches the source's black field
    ctx.fill(box)
    // Rasterize the SVG at the target rect so the glow's feGaussianBlur is
    // computed at output resolution. cgImage(forProposedRect:) would freeze
    // it at NSImage's default raster size and re-scale.
    let prev = NSGraphicsContext.current
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    nsImage.draw(in: box, from: .zero, operation: .sourceOver, fraction: 1.0)
    NSGraphicsContext.current = prev
    return ctx.makeImage()!
}

func write(_ img: CGImage, _ name: String) {
    let rep = NSBitmapImageRep(cgImage: img)
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: "\(iconsetPath)/\(name)"))
}

// One render per unique pixel size; some sizes serve two .iconset slots.
let plan: [(Int, [String])] = [
    (16,   ["icon_16x16.png"]),
    (32,   ["icon_16x16@2x.png", "icon_32x32.png"]),
    (64,   ["icon_32x32@2x.png"]),
    (128,  ["icon_128x128.png"]),
    (256,  ["icon_128x128@2x.png", "icon_256x256.png"]),
    (512,  ["icon_256x256@2x.png", "icon_512x512.png"]),
    (1024, ["icon_512x512@2x.png"]),
]
for (px, names) in plan {
    let img = render(px)
    for name in names { write(img, name) }
}

let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconsetPath, "-o", icnsPath]
try! p.run()
p.waitUntilExit()
guard p.terminationStatus == 0 else { exit(p.terminationStatus) }
try? FileManager.default.removeItem(atPath: iconsetPath)
print("wrote \(icnsPath)")
