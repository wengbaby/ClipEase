import Foundation
import Testing
@testable import ClipEase

@Test func nativeGlassCompositionCountsActualLiquidGlassSurfaces() {
    let composition = HistoryGlassSceneComposition(
        environment: nativeGlassEnvironment(),
        renderedCardCount: 20,
        selectedCardCount: 1,
        cardStyle: .liquidGlass
    )

    #expect(composition.panelNativeGlassSurfaceCount == 1)
    #expect(composition.controlsNativeGlassSurfaceCount == 0)
    #expect(composition.cardNativeGlassSurfaceCount == 20)
    #expect(composition.nativeGlassSurfaceCount == 21)
    #expect(composition.isWithinBudget)
}

@Test func nativeGlassCompositionCountsOnlySelectedNonLiquidCard() {
    let composition = HistoryGlassSceneComposition(
        environment: nativeGlassEnvironment(),
        renderedCardCount: 20,
        selectedCardCount: 1,
        cardStyle: .regular
    )

    #expect(composition.cardNativeGlassSurfaceCount == 1)
    #expect(composition.nativeGlassSurfaceCount == 2)
}

@Test func compatibilityGlassCompositionCountsBackdropInsteadOfNativeSurfaces() {
    let composition = HistoryGlassSceneComposition(
        environment: nativeGlassEnvironment(supportsNativeGlass: false),
        renderedCardCount: 20,
        selectedCardCount: 1,
        cardStyle: .liquidGlass
    )

    #expect(composition.panelBackdropCount == 1)
    #expect(composition.controlsBackdropCount == 0)
    #expect(composition.nativeGlassSurfaceCount == 0)
    #expect(composition.actualGlassSurfaceCount == 1)
}

private func nativeGlassEnvironment(supportsNativeGlass: Bool = true) -> HistoryGlassEnvironment {
    HistoryGlassEnvironment(
        supportsNativeGlass: supportsNativeGlass,
        reduceTransparency: false,
        reduceMotion: false,
        increaseContrast: false,
        isDarkMode: false,
        isWindowActive: true
    )
}
