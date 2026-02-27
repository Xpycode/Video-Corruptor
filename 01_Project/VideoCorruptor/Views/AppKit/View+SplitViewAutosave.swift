import SwiftUI

/// A helper view that finds the enclosing NSSplitView and sets its autosave name.
private struct SplitViewAutosaveHelper: NSViewRepresentable {
    let autosaveName: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            var parent = view.superview
            while parent != nil {
                if let splitView = parent as? NSSplitView {
                    splitView.autosaveName = autosaveName
                    return
                }
                parent = parent?.superview
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

extension View {
    /// Enables divider position autosaving for a SwiftUI `HSplitView` or `VSplitView`.
    ///
    /// Embeds a helper `NSView` that traverses up the view hierarchy to find the
    /// parent `NSSplitView` and sets its `autosaveName` property.
    func autosaveSplitView(named name: String) -> some View {
        self.background(SplitViewAutosaveHelper(autosaveName: name))
    }
}
