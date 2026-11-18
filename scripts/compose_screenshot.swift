// 合成 App Store 截图（2880×1800）：swiftc -o /tmp/compose scripts/compose_screenshot.swift && /tmp/compose <窗口截图.png> <输出.png> "<标题>"
import AppKit
let args = CommandLine.arguments  // in out caption
let src = NSImage(contentsOfFile: args[1])!, out = args[2], caption = args[3]
let W = 2880, H = 1800
let bmp = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
bmp.size = NSSize(width: W, height: H)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bmp)
let fw = CGFloat(W), fh = CGFloat(H)
NSGradient(colors: [NSColor(calibratedWhite: 0.14, alpha: 1), NSColor(calibratedWhite: 0.02, alpha: 1)])!.draw(in: NSRect(x: 0, y: 0, width: fw, height: fh), angle: -90)
let para = NSMutableParagraphStyle(); para.alignment = .center
let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 104, weight: .bold), .foregroundColor: NSColor.white, .paragraphStyle: para]
(caption as NSString).draw(in: NSRect(x: 120, y: fh - 330, width: fw - 240, height: 180), withAttributes: attrs)
let rep = src.representations.first!; let sw = CGFloat(rep.pixelsWide), sh = CGFloat(rep.pixelsHigh)
let s = min(2300 / sw, 1250 / sh, 1.9)
let w = sw * s, h = sh * s
let r = NSRect(x: (fw - w) / 2, y: (fh - 380 - h) / 2 + 40, width: w, height: h)
let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.7); shadow.shadowBlurRadius = 60; shadow.shadowOffset = NSSize(width: 0, height: -20)
NSGraphicsContext.saveGraphicsState(); shadow.set(); src.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1); NSGraphicsContext.restoreGraphicsState()
NSGraphicsContext.restoreGraphicsState()
// App Store 不接受带透明通道的截图：转成不透明 JPEG-质量 PNG
let cg = bmp.cgImage!
let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
ctx.draw(cg, in: CGRect(x: 0, y: 0, width: W, height: H))
try! NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
