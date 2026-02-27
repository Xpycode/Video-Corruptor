import SwiftUI

/// An NSButton wrapper that renders native macOS rectangular-bezel buttons
/// instead of SwiftUI's pill-shaped `.bordered` style.
struct AppKitButton: NSViewRepresentable {
    let title: String
    let action: @MainActor () -> Void
    var isDefault: Bool = false
    var controlSize: NSControl.ControlSize = .regular
    var isEnabled: Bool = true
    var keyEquivalent: String = ""

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: title, target: context.coordinator, action: #selector(Coordinator.clicked))
        button.bezelStyle = .rounded
        button.controlSize = controlSize
        button.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        button.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        button.title = title
        button.controlSize = controlSize
        button.isEnabled = isEnabled
        button.keyEquivalent = keyEquivalent

        if isDefault {
            button.keyEquivalent = "\r"
            button.bezelStyle = .rounded
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    @MainActor
    final class Coordinator: NSObject {
        let action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func clicked() { action() }
    }
}

// MARK: - Convenience modifiers

extension AppKitButton {
    func appKitControlSize(_ size: NSControl.ControlSize) -> AppKitButton {
        var copy = self
        copy.controlSize = size
        return copy
    }

    func appKitDefault(_ isDefault: Bool = true) -> AppKitButton {
        var copy = self
        copy.isDefault = isDefault
        return copy
    }

    func appKitEnabled(_ enabled: Bool) -> AppKitButton {
        var copy = self
        copy.isEnabled = enabled
        return copy
    }

    func appKitKeyEquivalent(_ key: String) -> AppKitButton {
        var copy = self
        copy.keyEquivalent = key
        return copy
    }
}
