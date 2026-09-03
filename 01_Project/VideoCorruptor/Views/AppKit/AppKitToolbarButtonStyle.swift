import SwiftUI

/// Compact titlebar control matching the app-shell pattern used by SAR.
struct AppKitToolbarButtonStyle: ButtonStyle {
    @Binding var isOn: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(isOn ? Color.white : Color.primary)
            .frame(width: 28, height: 28)
            .background(
                isOn ? Color.accentColor : Color.primary.opacity(0.07),
                in: RoundedRectangle(cornerRadius: 6)
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 6))
    }
}
