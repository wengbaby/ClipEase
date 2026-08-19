import SwiftUI
import AppKit

extension HistoryWindowView {
    @ViewBuilder
    var historyRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            ZStack(alignment: .topLeading) {
                CardRailScrollViewBinder {
                    updateCardRailVisibleRect()
                    requestNextHistoryPageIfNeeded()
                }
                    .frame(width: 0, height: 0)

                ForEach(renderedWindowItems) { item in
                    historyCard(item)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.96)
                                .combined(with: .opacity),
                            removal: .scale(scale: 0.985)
                                .combined(with: .opacity)
                        ))
                        .frame(width: historyCardWidth)
                        .offset(x: cardDocumentX(for: item.id))
                }
            }
            .frame(width: historyRailContentWidth, height: HistoryWindowPanelMetrics.railFrameHeight, alignment: .topLeading)
            .padding(.top, selectedCardTopContentInset)
            .padding(.bottom, 8)
            .padding(.bottom, HistoryWindowPanelMetrics.railBottomPadding - 8)
        }
    }

    @ViewBuilder
    func historyCard(_ item: HistoryPreviewItem) -> some View {
        let isSelected = selectedItemID == item.id
        let isCardFocused = isSelected && HistoryCardFocusPolicy.isCardFocusActive(
            selectedItemID: selectedItemID,
            isSearchFieldFocused: isSearchFocused || inputState.isTextInputFocusedSnapshot,
            searchHasHandedOffFocusToCard: searchUIState.hasHandedOffFocusToCard
        )
        let isHovered = hoveredCardID == item.id
        let isPressed = pressedCardID == item.id
        let isEnteringLatestItem = enteringItemIDs.contains(item.id)
        let visualState = HistoryCardVisualState(
            isSelected: isSelected,
            isKeyboardFocused: isCardFocused,
            isHovered: isHovered,
            isPressed: isPressed,
            isEnteringLatestItem: isEnteringLatestItem,
            isShortcutOverlayVisible: isShortcutOverlayVisible,
            environment: glassEnvironment,
            renderPlan: HistoryGlassPolicy.resolve(
                role: isSelected ? .selectedCard : .card,
                environment: glassEnvironment
            ),
            cardStyle: appearanceSettings.cardStyle
        )
        let presentation = HistoryCardPresentationPolicy.resolve(visualState)
        let isShowingEntranceSheen = entranceSheenItemIDs.contains(item.id) && presentation.showsEntranceSheen
        let cardScale = CGFloat(presentation.scale)

        let group = item.groupID.flatMap { store.group(with: $0) }

        HistoryCardView(
            item: item,
            searchQuery: appliedSearchQuery,
            shortcutNumber: shortcutNumber(for: item.id),
            isShortcutOverlayVisible: isShortcutOverlayVisible,
            isHovered: isHovered,
            isPressed: isPressed,
            isEnteringLatestItem: isEnteringLatestItem,
            isSelected: isSelected,
            visualState: visualState,
            groupIconName: group?.iconName,
            groupColorHex: group?.colorHex,
            onClick: {
                selectCardForPrimaryClick(item)
            },
            onDoubleClick: {
                blurSearchFieldForCardInteraction()
                pasteItem(item.id)
            },
            onPreview: {
                showPreview(item.id)
            },
            onRightMouseDown: {
                selectCardForContextMenu(item)
            },
            onMenu: {
                cardMenu(for: item)
            },
            onFileDragStatus: showStatus,
            onHoverChanged: { isHovered in
                setCardHover(item.id, isHovered: isHovered)
            },
            onPressChanged: { isPressed in
                setCardPress(item.id, isPressed: isPressed)
            },
            onMouseExitedWindow: closeWindowForCardDrag
        )
        .equatable()
        .background {
            if trackedCardGeometryIDs.contains(item.id) {
                CardViewportFrameReader(itemID: item.id)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    visualState.isKeyboardFocused ? Color(red: 0.08, green: 0.38, blue: 0.90) : (isSelected ? Color(red: 0.18, green: 0.55, blue: 1.0).opacity(0.92) : Color.black.opacity(0.08)),
                    lineWidth: presentation.borderWidth
                )
                .allowsHitTesting(false)
        }
        .overlay {
            if presentation.focusRingWidth > 0 {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color(red: 0.08, green: 0.38, blue: 0.90), lineWidth: presentation.focusRingWidth)
                    .padding(-4)
                    .overlay {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .stroke(Color.white.opacity(0.92), lineWidth: 1)
                            .padding(2)
                    }
                    .allowsHitTesting(false)
            }
        }
        .overlay {
            if isShowingEntranceSheen {
                latestCardEntranceSheen
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .allowsHitTesting(false)
            }
        }
        .shadow(
            color: .black.opacity(0),
            radius: 0,
            x: 0,
            y: 0
        )
        .scaleEffect(cardScale, anchor: .center)
        .animation(.easeOut(duration: visualState.environment.reduceMotion ? 0.12 : 0.18), value: isCardFocused)
        .animation(.easeOut(duration: visualState.environment.reduceMotion ? 0.12 : 0.22), value: isEnteringLatestItem)
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .animation(.easeOut(duration: 0.06), value: isPressed)
        .id(item.id)
        .contentShape(Rectangle())
        .zIndex(isPressed ? 4 : (isHovered ? 3 : (isCardFocused ? 2 : 0)))
    }

    var latestCardEntranceSheen: some View {
        HistoryCardEntranceSheen(
            startTime: entranceSheenStartTime,
            duration: latestItemEntranceSheenDuration
        )
    }
}
