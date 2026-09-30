// Renders the launch mark (the app icon + wordmark, exported from the design file as SVG) to the 1x/2x/3x PNGs the
// LaunchMark image set holds — the static launch screen and the in-app splash share it.
//   swift Tools/launchmark/rasterize.swift Tools/launchmark/dark.svg App/Poise/Assets.xcassets/LaunchMark.imageset/launchmark_dark
//   swift Tools/launchmark/rasterize.swift Tools/launchmark/light.svg App/Poise/Assets.xcassets/LaunchMark.imageset/launchmark_light
import AppKit
let args = CommandLine.arguments
let svgURL = URL(fileURLWithPath: args[1]), out = args[2]
guard let img = NSImage(contentsOf: svgURL) else { fatalError("cannot read svg") }
for (scale, suffix) in [(1, ""), (2, "@2x"), (3, "@3x")] {
    let w = 96 * scale, h = 146 * scale
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    img.draw(in: NSRect(x: 0, y: 0, width: w, height: h), from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)\(suffix).png"))
}
print("ok")
