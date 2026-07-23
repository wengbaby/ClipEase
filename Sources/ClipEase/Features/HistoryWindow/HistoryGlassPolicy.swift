import Foundation

enum HistoryGlassRole: Equatable, Sendable {
    case panel
    case controls
    case card
    case selectedCard
    case focusRing
    case popover
}

enum HistoryGlassPath: Equatable, Sendable {
    case opaque
    case compatibility
    case native
}

struct HistoryGlassEnvironment: Equatable, Sendable {
    let supportsNativeGlass: Bool
    let reduceTransparency: Bool
    let reduceMotion: Bool
    let increaseContrast: Bool
    let isDarkMode: Bool
    let isWindowActive: Bool
    let prefersLiquidGlass: Bool
    let prefersGlassMotion: Bool
    let materialTheme: AppearanceMaterialTheme
    let windowEffectOpacity: Double
    let cardEffectOpacity: Double
    let cardHeaderColorIntensity: Double
    let groupColorIntensity: Double
    let toolbarTextContrast: Double
    let cardTypography: AppearanceTypography

    init(
        supportsNativeGlass: Bool,
        reduceTransparency: Bool,
        reduceMotion: Bool,
        increaseContrast: Bool,
        isDarkMode: Bool,
        isWindowActive: Bool,
        prefersLiquidGlass: Bool = true,
        prefersGlassMotion: Bool = true,
        materialTheme: AppearanceMaterialTheme = .liquidGlass,
        windowEffectOpacity: Double = 0.68,
        cardEffectOpacity: Double = 0.84,
        cardHeaderColorIntensity: Double = 1,
        groupColorIntensity: Double = 1,
        toolbarTextContrast: Double = 1,
        cardTypography: AppearanceTypography = AppearanceTypographyRole.card.defaultTypography
    ) {
        self.supportsNativeGlass = supportsNativeGlass
        self.reduceTransparency = reduceTransparency
        self.reduceMotion = reduceMotion
        self.increaseContrast = increaseContrast
        self.isDarkMode = isDarkMode
        self.isWindowActive = isWindowActive
        self.prefersLiquidGlass = prefersLiquidGlass
        self.prefersGlassMotion = prefersGlassMotion
        self.materialTheme = materialTheme
        self.windowEffectOpacity = min(max(windowEffectOpacity, 0), 1)
        self.cardEffectOpacity = min(max(cardEffectOpacity, 0), 1)
        self.cardHeaderColorIntensity = min(max(cardHeaderColorIntensity, 0), 1)
        self.groupColorIntensity = min(max(groupColorIntensity, 0), 1)
        self.toolbarTextContrast = min(max(toolbarTextContrast, 0), 1)
        self.cardTypography = cardTypography
    }
}

enum HistoryGlassRuntime {
    static var supportsNativeGlass: Bool {
#if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            true
        } else {
            false
        }
#else
        false
#endif
    }
}

enum HistoryGlassSurfaceTone: Equatable, Sendable {
    case panel
    case controls
    case card
    case selectedCard
    case opaqueSystem
}

enum HistoryGlassBoundaryTone: Equatable, Sendable {
    case neutral
    case selected
    case keyboardFocus
    case highContrast
}

struct HistoryGlassTokens: Equatable, Sendable {
    let surfaceTone: HistoryGlassSurfaceTone
    let surfaceOpacity: Double
    let boundaryTone: HistoryGlassBoundaryTone
    let boundaryOpacity: Double
    let boundaryWidth: Double
    let focusRingWidth: Double
    let pressScale: Double
    let allowsSpatialMotion: Bool
}

struct HistoryGlassRenderPlan: Equatable, Sendable {
    let path: HistoryGlassPath
    let usesBackdropEffect: Bool
    let tokens: HistoryGlassTokens
    let materialTheme: AppearanceMaterialTheme
    let windowEffectOpacity: Double
}

struct HistoryGlassPanelBackingState: Equatable, Sendable {
    let isOpaque: Bool
}

struct HistoryGlassSearchSurfaceStyle: Equatable, Sendable {
    let fillOpacity: Double
    let boundaryOpacity: Double
    let cornerRadius: Double
}

struct HistoryGlassToolbarLayoutStyle: Equatable, Sendable {
    let fillsAvailableWidth: Bool
    let horizontalInset: Double
    let cornerRadius: Double
}

struct HistoryGlassToolbarWidthPlan: Equatable, Sendable {
    let trackWidth: Double
    let searchWidth: Double
    let groupRailMinimumWidth: Double
}

struct HistoryGlassToolbarCenterLayout: Equatable, Sendable {
    let searchCenterX: Double
    let searchWidth: Double
}

struct HistoryGlassToolbarControlStyle: Equatable, Sendable {
    let idleFillOpacity: Double
    let selectedFillOpacity: Double
    let boundaryOpacity: Double
    let hoverReflectionOpacity: Double
    let pressedScale: Double
}

enum HistoryGlassPanelBackingPolicy {
    static func resolve(plan: HistoryGlassRenderPlan) -> HistoryGlassPanelBackingState {
        HistoryGlassPanelBackingState(isOpaque: plan.path == .opaque)
    }
}

enum HistoryGlassSearchSurfacePolicy {
    static func resolve(
        plan: HistoryGlassRenderPlan,
        environment: HistoryGlassEnvironment
    ) -> HistoryGlassSearchSurfaceStyle {
        let fillOpacity = plan.path == .opaque
            ? (environment.isDarkMode ? 0.14 : 0.08)
            : 0

        return HistoryGlassSearchSurfaceStyle(
            fillOpacity: fillOpacity,
            boundaryOpacity: environment.increaseContrast ? 0.85 : 0,
            cornerRadius: 9
        )
    }
}

enum HistoryGlassToolbarCenterLayoutPolicy {
    private static let preferredSearchWidth = 360.0
    private static let minimumSearchWidth = 160.0
    private static let minimumRailClearance = 16.0

    static func resolve(
        contentWidth: Double,
        leadingControlsWidth: Double,
        trailingControlsWidth: Double,
        isSearchExpanded: Bool
    ) -> HistoryGlassToolbarCenterLayout {
        let safeContentWidth = max(0, contentWidth)
        let centeredWidthBudget = max(
            0,
            safeContentWidth - 2 * max(leadingControlsWidth, trailingControlsWidth) - minimumRailClearance * 2
        )
        let searchWidth = isSearchExpanded
            ? max(minimumSearchWidth, min(preferredSearchWidth, centeredWidthBudget))
            : 0

        return HistoryGlassToolbarCenterLayout(
            searchCenterX: safeContentWidth / 2,
            searchWidth: min(searchWidth, safeContentWidth)
        )
    }
}

enum HistoryGlassToolbarLayoutPolicy {
    static let style = HistoryGlassToolbarLayoutStyle(
        fillsAvailableWidth: true,
        horizontalInset: 0,
        cornerRadius: 16
    )
}

enum HistoryGlassToolbarWidthPolicy {
    private static let expandedSearchFraction = 0.40
    private static let minimumExpandedSearchWidth = 320.0
    private static let maximumExpandedSearchWidth = 480.0
    private static let groupRailMinimumWidth = 176.0

    static func resolve(
        availableWidth: Double,
        isSearchExpanded: Bool
    ) -> HistoryGlassToolbarWidthPlan {
        let trackWidth = max(0, availableWidth)
        let reservedGroupWidth = min(trackWidth, groupRailMinimumWidth)

        guard isSearchExpanded else {
            return HistoryGlassToolbarWidthPlan(
                trackWidth: trackWidth,
                searchWidth: 0,
                groupRailMinimumWidth: reservedGroupWidth
            )
        }

        let availableSearchWidth = max(0, trackWidth - reservedGroupWidth)
        let proportionalSearchWidth = min(
            availableSearchWidth,
            trackWidth * expandedSearchFraction
        )
        let searchWidth = min(maximumExpandedSearchWidth, max(
            min(minimumExpandedSearchWidth, availableSearchWidth),
            proportionalSearchWidth
        ))

        return HistoryGlassToolbarWidthPlan(
            trackWidth: trackWidth,
            searchWidth: searchWidth,
            groupRailMinimumWidth: reservedGroupWidth
        )
    }
}

enum HistoryGlassToolbarControlPolicy {
    static let style = HistoryGlassToolbarControlStyle(
        idleFillOpacity: 0.08,
        selectedFillOpacity: 0.32,
        boundaryOpacity: 0,
        hoverReflectionOpacity: 0,
        pressedScale: 0.985
    )
}

enum HistoryGlassPolicy {
    static func resolve(
        role: HistoryGlassRole,
        environment: HistoryGlassEnvironment
    ) -> HistoryGlassRenderPlan {
        let path = path(for: environment)
        return HistoryGlassRenderPlan(
            path: path,
            usesBackdropEffect: usesBackdropEffect(
                role: role,
                path: path,
                prefersLiquidGlass: environment.prefersLiquidGlass
            ),
            tokens: tokens(role: role, path: path, environment: environment),
            materialTheme: environment.materialTheme,
            windowEffectOpacity: environment.windowEffectOpacity
        )
    }

    private static func path(for environment: HistoryGlassEnvironment) -> HistoryGlassPath {
        if environment.reduceTransparency {
            return .opaque
        }

        return environment.supportsNativeGlass && environment.prefersLiquidGlass ? .native : .compatibility
    }

    private static func usesBackdropEffect(
        role: HistoryGlassRole,
        path: HistoryGlassPath,
        prefersLiquidGlass: Bool
    ) -> Bool {
        guard path != .opaque, prefersLiquidGlass else {
            return false
        }

        switch role {
        case .panel:
            return true
        case .controls, .card, .selectedCard, .focusRing, .popover:
            return false
        }
    }

    private static func tokens(
        role: HistoryGlassRole,
        path: HistoryGlassPath,
        environment: HistoryGlassEnvironment
    ) -> HistoryGlassTokens {
        let isOpaque = path == .opaque
        let isFocusRing = role == .focusRing
        let isSelected = role == .selectedCard
        let surfaceTone = isOpaque ? HistoryGlassSurfaceTone.opaqueSystem : surfaceTone(for: role)
        let boundaryTone: HistoryGlassBoundaryTone

        if isFocusRing {
            boundaryTone = .keyboardFocus
        } else if environment.increaseContrast {
            boundaryTone = .highContrast
        } else if isSelected {
            boundaryTone = .selected
        } else {
            boundaryTone = .neutral
        }

        return HistoryGlassTokens(
            surfaceTone: surfaceTone,
            surfaceOpacity: surfaceOpacity(for: role, isOpaque: isOpaque, isWindowActive: environment.isWindowActive),
            boundaryTone: boundaryTone,
            boundaryOpacity: environment.increaseContrast ? 1 : (isFocusRing ? 0.9 : 0),
            boundaryWidth: environment.increaseContrast ? 2 : 1,
            focusRingWidth: isFocusRing ? 3 : 0,
            pressScale: environment.reduceMotion ? 1 : 0.99,
            allowsSpatialMotion: !isOpaque && !environment.reduceMotion && environment.prefersGlassMotion
        )
    }

    private static func surfaceTone(for role: HistoryGlassRole) -> HistoryGlassSurfaceTone {
        switch role {
        case .panel:
            .panel
        case .controls:
            .controls
        case .selectedCard:
            .selectedCard
        case .card, .focusRing, .popover:
            .card
        }
    }

    private static func surfaceOpacity(
        for role: HistoryGlassRole,
        isOpaque: Bool,
        isWindowActive: Bool
    ) -> Double {
        guard !isOpaque else {
            return 1
        }

        let activeOpacity: Double
        switch role {
        case .panel:
            activeOpacity = 0.78
        case .controls:
            activeOpacity = 0.54
        case .card, .focusRing, .popover:
            activeOpacity = 0.72
        case .selectedCard:
            activeOpacity = 0.88
        }

        return isWindowActive ? activeOpacity : activeOpacity - 0.04
    }
}

struct HistoryGlassSceneComposition: Equatable, Sendable {
    let panelPlan: HistoryGlassRenderPlan
    let controlsPlan: HistoryGlassRenderPlan
    let cardPlans: [HistoryGlassRenderPlan]

    init(environment: HistoryGlassEnvironment, renderedCardCount: Int) {
        precondition((0...20).contains(renderedCardCount), "Rendered card count must remain within the rail budget.")
        panelPlan = HistoryGlassPolicy.resolve(role: .panel, environment: environment)
        controlsPlan = HistoryGlassPolicy.resolve(role: .controls, environment: environment)
        cardPlans = Array(
            repeating: HistoryGlassPolicy.resolve(role: .card, environment: environment),
            count: renderedCardCount
        )
    }

    var panelBackdropCount: Int {
        panelPlan.usesBackdropEffect ? 1 : 0
    }

    var controlsBackdropCount: Int {
        controlsPlan.usesBackdropEffect ? 1 : 0
    }

    var cardBackdropCount: Int {
        cardPlans.count(where: \.usesBackdropEffect)
    }

    var isWithinBudget: Bool {
        panelBackdropCount <= 1 && controlsBackdropCount <= 1 && cardBackdropCount == 0
    }
}
