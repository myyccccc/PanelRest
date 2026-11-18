// 生成 App 图标：swift scripts/make_icon.swift <输出目录>
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let S: CGFloat = 1024
let img = NSImage(size: NSSize(width: S, height: S))
img.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

// macOS 图标网格：824×824 圆角方块，留 100 边距
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let squircle = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.35).cgColor)
NSColor.black.setFill(); squircle.fill()
ctx.restoreGState()
squircle.addClip()
NSGradient(colors: [NSColor(calibratedRed: 0.13, green: 0.16, blue: 0.19, alpha: 1),
                    NSColor(calibratedRed: 0.03, green: 0.04, blue: 0.05, alpha: 1)])!.draw(in: body, angle: -90)

let mint = NSColor(calibratedRed: 0.93, green: 0.95, blue: 0.98, alpha: 1)  // 中性银白，不用主题色

// 支架（在显示器后面）
let neck = NSBezierPath(roundedRect: CGRect(x: 462, y: 268, width: 100, height: 120), xRadius: 10, yRadius: 10)
NSColor(calibratedWhite: 0.70, alpha: 1).setFill(); neck.fill()
let foot = NSBezierPath(roundedRect: CGRect(x: 382, y: 248, width: 260, height: 34), xRadius: 17, yRadius: 17)
NSColor(calibratedWhite: 0.82, alpha: 1).setFill(); foot.fill()

// 显示器
let screen = CGRect(x: 222, y: 380, width: 580, height: 360)
let bezel = NSBezierPath(roundedRect: screen, xRadius: 34, yRadius: 34)
NSColor(calibratedWhite: 0.78, alpha: 1).setFill(); bezel.fill()
let panel = NSBezierPath(roundedRect: screen.insetBy(dx: 16, dy: 16), xRadius: 20, yRadius: 20)
NSColor(calibratedWhite: 0.015, alpha: 1).setFill(); panel.fill()
// 屏幕上的月亮（发光）
let c = CGPoint(x: 512, y: 560), r: CGFloat = 92
ctx.saveGState()
NSBezierPath(roundedRect: screen.insetBy(dx: 16, dy: 16), xRadius: 20, yRadius: 20).addClip()
ctx.setShadow(offset: .zero, blur: 60, color: mint.withAlphaComponent(0.6).cgColor)
let moon = NSBezierPath(ovalIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
mint.setFill(); moon.fill()
ctx.restoreGState()
// 用屏幕底色盖掉一块 → 月牙
ctx.saveGState()
NSBezierPath(roundedRect: screen.insetBy(dx: 16, dy: 16), xRadius: 20, yRadius: 20).addClip()
let bite = NSBezierPath(ovalIn: CGRect(x: c.x - r + 52, y: c.y - r + 38, width: 2 * r, height: 2 * r))
NSColor(calibratedWhite: 0.015, alpha: 1).setFill(); bite.fill()
ctx.restoreGState()

// 顶部高光
NSGradient(colors: [NSColor.white.withAlphaComponent(0.10), NSColor.white.withAlphaComponent(0)])!
    .draw(in: CGRect(x: 100, y: 600, width: 824, height: 324), angle: -90)
img.unlockFocus()

let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/icon_1024.png"))
print("ok")
