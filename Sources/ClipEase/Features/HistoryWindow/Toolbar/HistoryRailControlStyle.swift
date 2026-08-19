import SwiftUI

struct HistoryRailControlButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HistoryRailControlButtonBody(configuration: configuration)
    }
}

struct HistoryRailControlButtonBody: View {
    let configuration: HistoryRailControlButtonStyle.Configuration
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        let style = HistoryGlassToolbarControlPolicy.style
        let showsInteractiveMotion = !reduceMotion

        configuration.label
            .scaleEffect(
                showsInteractiveMotion
                    ? (configuration.isPressed ? style.pressedScale : (isHovered ? 1.01 : 1))
                    : 1
            )
            .onHover { hovering in
                isHovered = hovering
            }
            .animation(.easeOut(duration: 0.10), value: isHovered)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

extension View {
    func historyRailControlStyle() -> some View {
        buttonStyle(HistoryRailControlButtonStyle())
    }
}
