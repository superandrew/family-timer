// Task 0S1 spike: console user, HIDIdleTime, SACLockScreenImmediate.
// Usage: swiftc -O tools/spike0s1.swift -o /tmp/spike0s1 && /tmp/spike0s1 [--lock]
import Foundation
import IOKit
import SystemConfiguration

// 1. Console user
var uid: uid_t = 0
var gid: gid_t = 0
let console = SCDynamicStoreCopyConsoleUser(nil, &uid, &gid) as String?
print("console user: \(console ?? "nil") uid=\(uid) gid=\(gid)")

// 2. HIDIdleTime (nanoseconds)
func hidIdleSeconds() -> Double? {
    let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"))
    guard service != 0 else { return nil }
    defer { IOObjectRelease(service) }
    guard let prop = IORegistryEntryCreateCFProperty(service, "HIDIdleTime" as CFString,
                                                     kCFAllocatorDefault, 0)?.takeRetainedValue(),
          let ns = (prop as? NSNumber)?.uint64Value else { return nil }
    return Double(ns) / 1_000_000_000
}
// Lock state of the console session, read from the IORegistry (what the daemon uses).
func screenLocked() -> String {
    let root = IORegistryGetRootEntry(kIOMainPortDefault)
    defer { IOObjectRelease(root) }
    let users = IORegistryEntryCreateCFProperty(root, "IOConsoleUsers" as CFString,
                                                kCFAllocatorDefault, 0)?.takeRetainedValue() as? [[String: Any]]
    let me = users?.first { ($0["kCGSSessionUserIDKey"] as? NSNumber)?.uint32Value == uid }
    return (me?["CGSSessionScreenIsLocked"] as? Bool) == true ? "LOCKED" : "unlocked"
}

func sample() -> String {
    "HIDIdleTime: \(hidIdleSeconds().map { String(format: "%.2f s", $0) } ?? "nil")  screen: \(screenLocked())"
}
print(sample())

// 3. SACLockScreenImmediate
let path = "/System/Library/PrivateFrameworks/login.framework/Versions/Current/login"
guard let handle = dlopen(path, RTLD_NOW) else {
    print("dlopen failed: \(String(cString: dlerror()))")
    exit(1)
}
guard let sym = dlsym(handle, "SACLockScreenImmediate") else {
    print("SACLockScreenImmediate: symbol NOT found")
    exit(1)
}
print("SACLockScreenImmediate: symbol found")

if CommandLine.arguments.contains("--lock") {
    typealias Fn = @convention(c) () -> Int32
    let fn = unsafeBitCast(sym, to: Fn.self)
    print("calling SACLockScreenImmediate…")
    let rc = fn()
    print("returned \(rc)")
    // Watch HIDIdleTime grow while locked; unlock to stop.
    for _ in 0..<15 {
        Thread.sleep(forTimeInterval: 2)
        print(sample())
    }
}
