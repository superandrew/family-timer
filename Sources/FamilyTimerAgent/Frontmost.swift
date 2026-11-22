import AppKit
import ApplicationServices
import FamilyTimerCore

/// What is in front (SPEC 9): the app and, for a browser, the address and title of the page.
/// Reading the browser needs the Accessibility permission, granted once per Mac by a parent
/// (System Settings > Privacy & Security > Accessibility). Without it only the app is known.
@MainActor
enum FrontmostReader {
    static let browsers: Set<String> = [
        "com.apple.Safari", "com.apple.SafariTechnologyPreview", "com.google.Chrome",
        "org.mozilla.firefox", "com.microsoft.edgemac", "com.brave.Browser",
        "company.thebrowser.Browser", "com.operasoftware.Opera", "com.vivaldi.Vivaldi",
    ]
    /// Chromium builds its accessibility tree only when asked.
    static let chromium: Set<String> = [
        "com.google.Chrome", "com.microsoft.edgemac", "com.brave.Browser",
        "company.thebrowser.Browser", "com.operasoftware.Opera", "com.vivaldi.Vivaldi",
    ]

    static var accessibility: Bool { AXIsProcessTrusted() }

    static func read() -> Frontmost? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier else { return nil }
        var front = Frontmost(bundleID: bundleID, name: app.localizedName ?? bundleID)
        if browsers.contains(bundleID), accessibility {
            let element = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(element, 0.5)
            if chromium.contains(bundleID) {
                AXUIElementSetAttributeValue(element, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            }
            if let window = child(element, kAXFocusedWindowAttribute) {
                front.title = string(window, kAXTitleAttribute)
                front.url = string(window, kAXDocumentAttribute) ?? addressField(in: window)
            }
        }
        return front
    }

    private static func value(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private static func string(_ element: AXUIElement, _ name: String) -> String? {
        value(element, name) as? String
    }

    private static func child(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        guard let v = value(element, name), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }

    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        guard let array = value(element, kAXChildrenAttribute) as? [AnyObject] else { return [] }
        return array.compactMap { CFGetTypeID($0) == AXUIElementGetTypeID() ? ($0 as! AXUIElement) : nil }
    }

    /// The address bar: the first text field or combo box inside a toolbar whose value looks
    /// like an address (no spaces, a dot). Breadth first, bounded.
    private static func addressField(in window: AXUIElement) -> String? {
        var queue: [(AXUIElement, Bool)] = [(window, false)]
        var visited = 0
        while !queue.isEmpty && visited < 600 {
            let (element, inToolbar) = queue.removeFirst()
            visited += 1
            let role = string(element, kAXRoleAttribute) ?? ""
            let toolbar = inToolbar || role == kAXToolbarRole as String
            if toolbar && (role == kAXTextFieldRole as String || role == kAXComboBoxRole as String),
               let value = string(element, kAXValueAttribute),
               !value.contains(" "), value.contains(".") {
                return value
            }
            queue.append(contentsOf: children(element).map { ($0, toolbar) })
        }
        return nil
    }
}
