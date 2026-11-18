import CoreGraphics
import Foundation
// 用法：winshot <进程名> <输出文件>
let owner = CommandLine.arguments[1], out = CommandLine.arguments[2]
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
guard let w = list.first(where: { ($0[kCGWindowOwnerName as String] as? String) == owner && ($0[kCGWindowLayer as String] as? Int) == 0 }),
      let id = w[kCGWindowNumber as String] as? Int else { print("no window"); exit(1) }
let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
p.arguments = ["-x", "-o", "-l\(id)", out]; try! p.run(); p.waitUntilExit(); print("ok \(id)")
