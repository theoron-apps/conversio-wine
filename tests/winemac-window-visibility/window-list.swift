import Foundation
import CoreGraphics
let seconds = Double(CommandLine.arguments.dropFirst().first ?? "35") ?? 35
let processID = CommandLine.arguments.count > 2 ? Int(CommandLine.arguments[2]) : nil
let end = Date().addingTimeInterval(seconds)
var previous = Set<String>()
while Date() < end {
    let windows = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    var current = Set<String>()
    for w in windows {
        if let processID, (w[kCGWindowOwnerPID as String] as? Int) != processID { continue }
        let title = w[kCGWindowName as String] as? String ?? ""
        guard title.hasPrefix("Conversio visibility") else { continue }
        let entry: [String: Any] = ["title": title, "pid": w[kCGWindowOwnerPID as String] ?? 0,
            "window": w[kCGWindowNumber as String] ?? 0, "onscreen": w[kCGWindowIsOnscreen as String] ?? false,
            "bounds": w[kCGWindowBounds as String] ?? [:], "layer": w[kCGWindowLayer as String] ?? 0]
        let data = try! JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys])
        let json = String(decoding: data, as: UTF8.self)
        current.insert(json)
        if !previous.contains(json) { print(String(format: "%.3f ", Date().timeIntervalSince1970) + json); fflush(stdout) }
    }
    previous = current
    Thread.sleep(forTimeInterval: 0.1)
}
