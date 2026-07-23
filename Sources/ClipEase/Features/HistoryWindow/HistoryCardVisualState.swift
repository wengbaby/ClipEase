import Foundation

struct HistoryCardVisualState: Equatable, Sendable {
    let isSelected: Bool
    let isKeyboardFocused: Bool
    let isHovered: Bool
    let isPressed: Bool
    let isEnteringLatestItem: Bool
    let isShortcutOverlayVisible: Bool
    let environment: HistoryGlassEnvironment
    let renderPlan: HistoryGlassRenderPlan
    let cardStyle: AppearanceCardStyle

    init(
        isSelected: Bool,
        isKeyboardFocused: Bool,
        isHovered: Bool,
        isPressed: Bool,
        isEnteringLatestItem: Bool,
        isShortcutOverlayVisible: Bool,
        environment: HistoryGlassEnvironment,
        renderPlan: HistoryGlassRenderPlan,
        cardStyle: AppearanceCardStyle = .liquidGlass
    ) {
        self.isSelected = isSelected
        self.isKeyboardFocused = isKeyboardFocused
        self.isHovered = isHovered
        self.isPressed = isPressed
        self.isEnteringLatestItem = isEnteringLatestItem
        self.isShortcutOverlayVisible = isShortcutOverlayVisible
        self.environment = environment
        self.renderPlan = renderPlan
        self.cardStyle = cardStyle
    }
}

struct HistoryCardPresentation: Equatable, Sendable {
    let scale: Double
    let borderWidth: Double
    let focusRingWidth: Double
    let usesInnerFocusSeparator: Bool
    let showsEntranceSheen: Bool
}

enum HistoryCardPresentationPolicy {
    static func resolve(_ state: HistoryCardVisualState) -> HistoryCardPresentation {
        let supportsMotion = !state.environment.reduceMotion
        return HistoryCardPresentation(
            scale: state.isPressed && supportsMotion ? state.renderPlan.tokens.pressScale : 1,
            borderWidth: state.environment.increaseContrast ? 2 : 1,
            focusRingWidth: state.isKeyboardFocused ? max(state.renderPlan.tokens.focusRingWidth, 3) : 0,
            usesInnerFocusSeparator: state.isKeyboardFocused,
            showsEntranceSheen: state.isEnteringLatestItem && supportsMotion
        )
    }
}
