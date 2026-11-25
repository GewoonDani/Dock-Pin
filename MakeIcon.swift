import AppKit
import ImageIO

// Package the PNG representations directly; iconutil cannot encode them in this environment.
func lengthBytes(_ value: Int) -> Data {
    var bigEndian = UInt32(value).bigEndian
    return withUnsafeBytes(of: &bigEndian) { Data($0) }
}

let entries = [
    ("ic04", "16x16"), ("ic05", "32x32"),
    ("ic07", "128x128"), ("ic08", "256x256"), ("ic09", "512x512"),
    ("ic10", "512x512@2x"), ("ic11", "16x16@2x"),
    ("ic12", "32x32@2x"), ("ic13", "128x128@2x"), ("ic14", "256x256@2x")
]
var payload = Data()
for (type, size) in entries {
    let png = try Data(contentsOf: URL(fileURLWithPath: "build/AppIcon.iconset/icon_\(size).png"))
    precondition(png.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]), "Expected a PNG icon representation")
    var representation = png
    if type == "ic04" || type == "ic05" {
        // Finder expects ARGB planes here; PNG payloads render as coloured noise.
        let bitmap = NSBitmapImageRep(data: png)!
        var planes = [[UInt8]](repeating: [], count: 4)
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                let color = bitmap.colorAt(x: x, y: y)!.usingColorSpace(.genericRGB)!
                for (plane, component) in [color.alphaComponent, color.redComponent, color.greenComponent, color.blueComponent].enumerated() {
                    planes[plane].append(UInt8(max(0, min(255, (component * 255).rounded()))))
                }
            }
        }
        representation = Data("ARGB".utf8)
        for plane in planes {
            for offset in stride(from: 0, to: plane.count, by: 128) {
                let end = min(offset + 128, plane.count)
                representation.append(UInt8(end - offset - 1))
                representation.append(contentsOf: plane[offset..<end])
            }
        }
    }
    payload.append(Data(type.utf8))
    payload.append(lengthBytes(representation.count + 8))
    payload.append(representation)
}
var icon = Data("icns".utf8)
icon.append(lengthBytes(payload.count + 8))
icon.append(payload)
let destination = URL(fileURLWithPath: "build/Dock Pin.app/Contents/Resources/DockPinIcon-v3.icns")
try icon.write(to: destination, options: .atomic)
precondition(NSImage(contentsOf: destination) != nil, "macOS could not decode the generated app icon")
let source = CGImageSourceCreateWithURL(destination as CFURL, nil)!
precondition(CGImageSourceGetCount(source) == entries.count, "Missing icon representations")
for index in entries.indices {
    guard let decoded = CGImageSourceCreateImageAtIndex(source, index, nil) else {
        fatalError("Cannot decode icon representation \(index)")
    }
    precondition(decoded.width == decoded.height, "Icon representation must be square")
    if decoded.width == 16 || decoded.width == 32 {
        let size = decoded.width
        let expected = NSBitmapImageRep(data: try Data(contentsOf: URL(fileURLWithPath: "build/AppIcon.iconset/icon_\(size)x\(size).png")))!
        let actual = NSBitmapImageRep(cgImage: decoded)
        for y in 0..<size {
            for x in 0..<size {
                let a = actual.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
                let b = expected.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
                let aValues = [a.alphaComponent, a.redComponent * a.alphaComponent, a.greenComponent * a.alphaComponent, a.blueComponent * a.alphaComponent]
                let bValues = [b.alphaComponent, b.redComponent * b.alphaComponent, b.greenComponent * b.alphaComponent, b.blueComponent * b.alphaComponent]
                precondition(zip(aValues, bValues).allSatisfy { abs($0 - $1) < 3.0 / 255 }, "Small icon pixels changed during encoding")
            }
        }
        let preview = NSBitmapImageRep(cgImage: decoded)
        try preview.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "build/verified-\(size).png"))
    }
}
print("App icon packaged; all \(entries.count) representations decoded successfully")
