import AppKit
import SwiftUI

struct AdaptiveGlassPanelBackground: View {
    let plan: HistoryGlassRenderPlan

    var body: some View {
#if compiler(>=6.2)
        if #available(macOS 26.0, *), plan.path == .native {
            NativeHistoryGlassPanelBackground(plan: plan)
        } else {
            CompatibilityHistoryGlassPanelBackground(plan: plan)
        }
#else
        CompatibilityHistoryGlassPanelBackground(plan: plan)
#endif
    }
}

private struct CompatibilityHistoryGlassPanelBackground: View {
    let plan: HistoryGlassRenderPlan

    var body: some View {
        ZStack {
            if plan.usesBackdropEffect {
                VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
            }

            plan.materialTheme.gradient
                .opacity(plan.path == .opaque ? 0 : plan.windowEffectOpacity)
            HistoryGlassSurfaceFill(tokens: plan.tokens)
        }
        .ignoresSafeArea()
    }
}

struct AdaptiveGlassControlsBackground: View {
    let plan: HistoryGlassRenderPlan

    var body: some View {
#if compiler(>=6.2)
        if #available(macOS 26.0, *), plan.path == .native {
            NativeHistoryGlassControlsBackground(plan: plan)
        } else {
            CompatibilityHistoryGlassControlsBackground(plan: plan)
        }
#else
        CompatibilityHistoryGlassControlsBackground(plan: plan)
#endif
    }
}

struct HistoryToolbarGlassTrack<Content: View>: View {
    let plan: HistoryGlassRenderPlan
    let cornerRadius: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
#if compiler(>=6.2)
        if #available(macOS 26.0, *), plan.path == .native {
            GlassEffectContainer(spacing: 10) {
                content
                    .glassEffect(
                        .regular.interactive(),
                        in: .rect(cornerRadius: cornerRadius)
                    )
            }
        } else {
            compatibilityTrack
        }
#else
        compatibilityTrack
#endif
    }

    private var compatibilityTrack: some View {
        content
            .background {
                AdaptiveGlassControlsBackground(plan: plan)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
    }
}

private struct CompatibilityHistoryGlassControlsBackground: View {
    let plan: HistoryGlassRenderPlan

    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(plan.materialTheme.gradient)
            .opacity(plan.path == .opaque ? plan.tokens.surfaceOpacity : min(0.78, plan.windowEffectOpacity))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    HistoryGlassSurfaceFillColor.boundaryColor(for: plan.tokens),
                    lineWidth: plan.tokens.boundaryWidth
                )
        }
    }
}

#if compiler(>=6.2)
@available(macOS 26.0, *)
private struct NativeHistoryGlassPanelBackground: View {
    let plan: HistoryGlassRenderPlan

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.clear)
                .glassEffect(.regular, in: .rect(cornerRadius: 0))
            plan.materialTheme.gradient
                .opacity(plan.windowEffectOpacity * 0.58)
        }
            .ignoresSafeArea()
    }
}

@available(macOS 26.0, *)
private struct NativeHistoryGlassControlsBackground: View {
    let plan: HistoryGlassRenderPlan

    var body: some View {
        ZStack {
            HistoryGlassSurfaceFill(tokens: plan.tokens)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            plan.materialTheme.gradient
                .opacity(plan.windowEffectOpacity * 0.45)
        }
    }
}
#endif

struct AdaptiveGlassCardSurface: View {
    let visualState: HistoryCardVisualState

    var body: some View {
#if compiler(>=6.2)
        if #available(macOS 26.0, *), visualState.renderPlan.path == .native {
            if HistoryNativeGlassSurfacePolicy.rendersSurface(
                role: visualState.isSelected ? .selectedCard : .card,
                plan: visualState.renderPlan,
                cardStyle: visualState.cardStyle
            ) {
                Color.clear
                    .glassEffect(
                        visualState.isSelected ? .regular.interactive() : .regular,
                        in: .rect(cornerRadius: 12)
                    )
            } else {
                Color.clear
            }
        } else {
            compatibilitySurface
        }
#else
        compatibilitySurface
#endif
    }

    private var compatibilitySurface: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(surfaceGradient)
            .opacity(surfaceOpacity)
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        boundaryColor,
                        lineWidth: boundaryWidth
                    )
            }
            .shadow(color: glowColor, radius: glowRadius)
    }

    private var surfaceGradient: LinearGradient {
        visualState.cardStyle.materialTheme.gradient
    }

    private var surfaceOpacity: Double {
        visualState.environment.cardEffectOpacity
    }

    private var boundaryColor: Color {
        if visualState.cardStyle == .deepSpace { return .cyan.opacity(0.9) }
        if visualState.cardStyle == .holographic || visualState.cardStyle == .prism { return .white.opacity(0.95) }
        return HistoryGlassSurfaceFillColor.boundaryColor(for: visualState.renderPlan.tokens)
    }

    private var boundaryWidth: Double {
        visualState.renderPlan.tokens.boundaryWidth
    }

    private var glowColor: Color {
        switch visualState.cardStyle {
        case .holographic: .pink.opacity(0.65)
        case .prism: .cyan.opacity(0.6)
        case .deepSpace: .indigo.opacity(0.7)
        case .jelly: .purple.opacity(0.55)
        default: .clear
        }
    }

    private var glowRadius: CGFloat {
        switch visualState.cardStyle {
        case .holographic, .prism, .deepSpace, .jelly:
            visualState.isHovered ? 18 : 10
        default:
            0
        }
    }
}

private struct HistoryGlassSurfaceFill: View {
    let tokens: HistoryGlassTokens

    var body: some View {
        HistoryGlassSurfaceFillColor.color(for: tokens)
            .opacity(tokens.surfaceOpacity)
    }
}

private enum HistoryGlassSurfaceFillColor {
    static func color(for tokens: HistoryGlassTokens) -> Color {
        switch tokens.surfaceTone {
        case .panel:
            Color(nsColor: .windowBackgroundColor)
        case .controls:
            Color.white.opacity(0.26)
        case .card:
            Color.white.opacity(0.30)
        case .selectedCard:
            Color(red: 0.36, green: 0.67, blue: 1.0).opacity(0.30)
        case .opaqueSystem:
            Color(nsColor: .windowBackgroundColor)
        }
    }

    static func boundaryColor(for tokens: HistoryGlassTokens) -> Color {
        switch tokens.boundaryTone {
        case .neutral:
            Color.white.opacity(0.42)
        case .selected:
            Color(red: 0.18, green: 0.55, blue: 1.0).opacity(0.92)
        case .keyboardFocus:
            Color(red: 0.08, green: 0.38, blue: 0.90)
        case .highContrast:
            Color.primary
        }
    }
}
