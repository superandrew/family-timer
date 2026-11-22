import AppKit

/// A small floating window with a message and up to two buttons. It stays on top, appears on
/// every Space and over full-screen apps (games), and never blocks the agent's run loop.
@MainActor
final class Notice {
    private var window: NSWindow?
    private let label = NSTextField(wrappingLabelWithString: "")
    private let primary = NSButton(title: "", target: nil, action: nil)
    private let secondary = NSButton(title: "", target: nil, action: nil)
    private var primaryAction: (() -> Void)?
    private var secondaryAction: (() -> Void)?

    var isVisible: Bool { window?.isVisible ?? false }

    func show(_ text: String, primary primaryTitle: String, _ primaryAction: (() -> Void)? = nil,
              secondary secondaryTitle: String? = nil, _ secondaryAction: (() -> Void)? = nil) {
        let window = self.window ?? makeWindow()
        label.stringValue = text
        primary.title = primaryTitle
        self.primaryAction = primaryAction
        secondary.isHidden = secondaryTitle == nil
        secondary.title = secondaryTitle ?? ""
        self.secondaryAction = secondaryAction
        window.layoutIfNeeded()
        window.center()
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKey()
    }

    /// Changes the text of the window if it is open, without moving it.
    func update(_ text: String) {
        if isVisible { label.stringValue = text }
    }

    func close() {
        window?.orderOut(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 140),
                             styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
        window.title = "FamilyTimer"
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false

        label.font = .systemFont(ofSize: 14)
        label.preferredMaxLayoutWidth = 340
        for button in [primary, secondary] {
            button.bezelStyle = .rounded
            button.target = self
        }
        primary.action = #selector(primaryPressed)
        primary.keyEquivalent = "\r"
        secondary.action = #selector(secondaryPressed)

        let buttons = NSStackView(views: [secondary, primary])
        buttons.orientation = .horizontal
        let stack = NSStackView(views: [label, buttons])
        stack.orientation = .vertical
        stack.alignment = .trailing
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 16, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = NSView()
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor),
            stack.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor),
            label.widthAnchor.constraint(equalToConstant: 340),
        ])
        self.window = window
        return window
    }

    @objc private func primaryPressed() {
        let action = primaryAction
        close()
        action?()
    }

    @objc private func secondaryPressed() {
        let action = secondaryAction
        close()
        action?()
    }
}
