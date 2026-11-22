import AppKit
import SwiftUI

/// A small floating card with an icon, a title, a line of text, an optional countdown bar and
/// up to two buttons. It stays on top, appears on every Space and over full-screen apps
/// (games), and never blocks the agent's run loop.
@MainActor
final class Notice {
    private let model = NoticeModel()
    private var panel: NoticePanel?
    private var hosting: NSHostingView<NoticeView>?

    var isVisible: Bool { panel?.isVisible ?? false }

    /// `text`: its first sentence becomes the title, the rest the line below.
    /// `countdown`: seconds shown as a bar that empties (the caller acts when it ends).
    func show(_ text: String, icon: String = "⏱", countdown: TimeInterval? = nil,
              primary primaryTitle: String, _ primaryAction: (() -> Void)? = nil,
              secondary secondaryTitle: String? = nil, _ secondaryAction: (() -> Void)? = nil) {
        let (title, message) = Notice.split(text)
        model.icon = icon
        model.title = title
        model.message = message
        model.primary = primaryTitle
        model.secondary = secondaryTitle
        model.total = countdown ?? 0
        model.deadline = countdown.map { Date().addingTimeInterval($0) }
        model.onPrimary = { [weak self] in
            self?.close()
            primaryAction?()
        }
        model.onSecondary = { [weak self] in
            self?.close()
            secondaryAction?()
        }

        let panel = self.panel ?? makePanel()
        place(panel)
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                panel.animator().alphaValue = 1
            }
        } else {
            panel.orderFrontRegardless()
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKey()
    }

    /// Changes the text of the card if it is open, without moving it.
    func update(_ text: String) {
        guard isVisible else { return }
        (model.title, model.message) = Notice.split(text)
    }

    func close() {
        panel?.orderOut(nil)
        model.deadline = nil
    }

    /// First sentence and the rest: "Time is over. The screen locks in 5m." gives
    /// ("Time is over.", "The screen locks in 5m.").
    static func split(_ text: String) -> (title: String, message: String) {
        for separator in [".\n", ". ", "\n"] {
            if let range = text.range(of: separator) {
                let title = String(text[..<range.lowerBound]) + (separator.hasPrefix(".") ? "." : "")
                let message = String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                return (title, message)
            }
        }
        return (text, "")
    }

    private func makePanel() -> NoticePanel {
        let panel = NoticePanel(contentRect: NSRect(x: 0, y: 0, width: NoticeView.width, height: 160),
                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        let hosting = NSHostingView(rootView: NoticeView(model: model))
        panel.contentView = hosting
        self.hosting = hosting
        self.panel = panel
        return panel
    }

    /// Top centre of the screen with the menu bar, sized to the content.
    private func place(_ panel: NSPanel) {
        guard let hosting else { return }
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        let screen = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? .zero
        panel.setFrame(NSRect(x: screen.midX - size.width / 2, y: screen.maxY - size.height - 24,
                              width: size.width, height: size.height), display: true)
    }
}

/// A borderless panel cannot take the keyboard unless it says so (Return on the button).
final class NoticePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class NoticeModel: ObservableObject {
    @Published var icon = "⏱"
    @Published var title = ""
    @Published var message = ""
    @Published var primary = "OK"
    @Published var secondary: String?
    @Published var deadline: Date?
    @Published var total: TimeInterval = 0
    var onPrimary: () -> Void = {}
    var onSecondary: () -> Void = {}
}

struct NoticeView: View {
    static let width: CGFloat = 440
    @ObservedObject var model: NoticeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                Text(model.icon)
                    .font(.system(size: 44))
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.title)
                        .font(.system(size: 17, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    if !model.message.isEmpty {
                        Text(model.message)
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            if let deadline = model.deadline, model.total > 0 {
                TimelineView(.periodic(from: .now, by: 0.1)) { context in
                    let left = max(0, min(model.total, deadline.timeIntervalSince(context.date)))
                    CountdownBar(fraction: left / model.total)
                }
            }
            HStack(spacing: 10) {
                Spacer()
                if let secondary = model.secondary {
                    Button(model.primary) { model.onPrimary() }
                        .controlSize(.large)
                        .keyboardShortcut(.cancelAction)
                    Button(secondary) { model.onSecondary() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                } else {
                    Button(model.primary) { model.onPrimary() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(22)
        .frame(width: Self.width)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
    }
}

/// A thin rounded bar that empties as the seconds pass.
struct CountdownBar: View {
    var fraction: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                Capsule().fill(Color.accentColor)
                    .frame(width: geometry.size.width * max(0, min(1, fraction)))
            }
        }
        .frame(height: 6)
    }
}
