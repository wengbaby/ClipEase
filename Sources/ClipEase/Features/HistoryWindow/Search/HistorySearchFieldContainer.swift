import SwiftUI
import AppKit

extension HistoryWindowView {
    var searchField: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(toolbarSecondaryForeground)
                .frame(width: 16, height: 24)
                .opacity(searchUIState.isFieldVisualVisible ? 1 : 0)

            GeometryReader { availableSpace in
                let insertionIndex = min(
                    max(0, searchTextInsertionIndex),
                    searchTokens.count
                )
                let inputWidth = max(
                    24,
                    availableSpace.size.width - searchLeadingContentWidth - 3
                )

                ScrollViewReader { scrollProxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 0) {
                            ForEach(Array(searchTokens.enumerated()), id: \.element.id) { index, token in
                                if index > 0 {
                                    searchTokenInsertionGap(at: index)
                                }

                                if insertionIndex == index {
                                    searchTextInput(
                                        scrollProxy: scrollProxy,
                                        width: inputWidth
                                    )
                                }

                                searchTokenView(token)
                                    .id(token.id)
                            }

                            if !searchTokens.isEmpty {
                                searchTokenInsertionGap(at: searchTokens.count)
                            }

                            if insertionIndex == searchTokens.count {
                                searchTextInput(
                                    scrollProxy: scrollProxy,
                                    width: inputWidth
                                )
                            }
                        }
                        .id("search-leading-content")
                        .frame(minWidth: availableSpace.size.width, alignment: .leading)
                    }
                    .background(HorizontalScrollWheelRedirector(
                        scope: .auxiliaryRail,
                        isEnabled: inputState.isWindowVisible
                    ))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        searchUIState.selectedTokenKind = nil
                        focusSearchField()
                    }
                    .onChange(of: searchTokens) { _ in
                        searchTextInsertionIndex = searchTokens.count
                        scrollProxy.scrollTo("search-text-field", anchor: .trailing)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .background(searchTokenWidthMeasurer)

            if isSearchActive {
                Button(action: clearSearchTextAndFilters) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(toolbarSecondaryForeground)
                .help(L("清空搜索"))
            }

            Button(action: toggleSearchFilterPanel) {
                Image(systemName: searchUIState.criteria.hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(searchUIState.criteria.hasActiveFilters ? Color(red: 0.18, green: 0.55, blue: 1.0) : toolbarSecondaryForeground)
            .help(L("搜索筛选"))
            .popover(isPresented: $searchUIState.isFilterPanelPresented, arrowEdge: .bottom) {
                searchFilterPanel
                    .fixedSize()
                    .background(SearchPanelWindowReader(onWindowChange: { _ in
                        refreshSearchInteractionScreenFrames()
                    }))
            }
        }
        .onPreferenceChange(SearchLeadingContentWidthPreferenceKey.self) { width in
            guard abs(searchLeadingContentWidth - width) > 0.5 else {
                return
            }
            searchLeadingContentWidth = width
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 34, maxHeight: 34)
        .background {
            RoundedRectangle(cornerRadius: searchGlassSurfaceStyle.cornerRadius + 2, style: .continuous)
                .fill(Color.white.opacity(
                    searchUIState.isFieldVisualVisible ? searchGlassSurfaceStyle.fillOpacity : 0
                ))
                .overlay {
                    RoundedRectangle(cornerRadius: searchGlassSurfaceStyle.cornerRadius + 2, style: .continuous)
                        .strokeBorder(
                            Color(red: 0.18, green: 0.55, blue: 1.0)
                                .opacity(searchUIState.isFieldVisualVisible ? 0.86 : 0),
                            lineWidth: searchUIState.isFieldVisualVisible ? 2.5 : 0
                        )
                        .shadow(
                            color: Color(red: 0.18, green: 0.55, blue: 1.0)
                                .opacity(searchUIState.isFieldVisualVisible ? 0.62 : 0),
                            radius: searchUIState.isFieldVisualVisible ? 9 : 0
                        )
                }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            searchUIState.selectedTokenKind = nil
            focusSearchField()
        }
        .background(
            SearchInteractionLiveRegion(
                isActive: searchUIState.isVisible,
                onRegister: { view in
                    SearchInteractionRegionRegistry.shared.register(view)
                },
                onUnregister: { view in
                    SearchInteractionRegionRegistry.shared.unregister(view)
                }
            )
        )
        .background(
            SearchInteractionScreenFrameReader(isActive: searchUIState.isVisible) { frame in
                if viewportState.searchControlScreenFrame != frame {
                    viewportState.searchControlScreenFrame = frame
                }
            }
        )
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: SearchInteractionFramePreferenceKey.self,
                    value: searchUIState.isVisible ? [proxy.frame(in: .named("historyWindow")).insetBy(dx: -8, dy: -8)] : []
                )
            }
        )
        .opacity(searchUIState.isFieldVisualVisible ? 1 : 0)
        .foregroundStyle(toolbarPrimaryForeground)
        .scaleEffect(x: searchUIState.isFieldVisualVisible ? 1 : 0.01, y: searchUIState.isFieldVisualVisible ? 1 : 0.94, anchor: .center)
        .allowsHitTesting(searchUIState.isVisible)
        .animation(.easeInOut(duration: 0.22), value: searchUIState.isFieldVisualVisible)
    }

    var searchTokenWidthMeasurer: some View {
        HStack(spacing: 6) {
            ForEach(searchTokens) { token in
                searchTokenView(token)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .hidden()
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: SearchLeadingContentWidthPreferenceKey.self,
                    value: proxy.size.width
                )
            }
        )
    }

    @ViewBuilder
    func searchTextInput(
        scrollProxy: ScrollViewProxy,
        width: CGFloat
    ) -> some View {
        SearchTextField(
            text: $searchUIState.text,
            isFocused: $isSearchFocused,
            isComposing: $isSearchTextComposing,
            pendingComposedInputEvent: $pendingComposedSearchInputEvent,
            focusRequestID: searchFocusRequestID,
            searchHasHandedOffFocusToCard: searchUIState.hasHandedOffFocusToCard,
            hasSearchResult: !filteredItems.isEmpty,
            hasSearchTokens: !searchTokens.isEmpty,
            hidesInsertionPoint: searchUIState.selectedTokenKind != nil,
            textColor: toolbarPrimaryNSColor,
            font: searchTypography.nsFont,
            onFocusChanged: synchronizeSearchTextFieldFocus,
            onEnterFirstResult: enterFirstSearchResultFromSearchField,
            onDeleteLastToken: handleSearchTokenBackspace,
            onCancel: handleSearchCancel,
            onReachLeadingContent: {
                withAnimation(.easeOut(duration: 0.12)) {
                    scrollProxy.scrollTo("search-leading-content", anchor: .leading)
                }
            },
            onReachTrailingContent: {
                withAnimation(.easeOut(duration: 0.12)) {
                    scrollProxy.scrollTo("search-text-field", anchor: .trailing)
                }
            }
        )
        .font(searchTypography.swiftUIFont)
        .frame(width: width)
        .id("search-text-field")
    }

    func searchTokenInsertionGap(at index: Int) -> some View {
        Color.clear
            .frame(width: 6, height: 20)
            .contentShape(Rectangle())
            .onTapGesture {
                searchTextInsertionIndex = index
                focusSearchField()
            }
    }

    func searchTokenView(_ token: HistorySearchToken) -> some View {
        let isSelected = searchUIState.selectedTokenKind == token.kind
        let selectedBackground = Color(red: 0.18, green: 0.55, blue: 1.0)
        let addedBackground = Color(red: 0.82, green: 0.91, blue: 1.0)
        let addedStroke = Color(red: 0.45, green: 0.68, blue: 0.92)

        return HStack(spacing: 4) {
            SearchFilterChipIcon(
                systemImage: token.kind.iconName,
                iconFileName: token.iconFileName,
                fallbackSystemImage: token.kind.iconName
            )

            Text(token.title)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)

            Button {
                removeSearchToken(token)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(L("移除\(token.title)"))
        }
        .padding(.leading, 8)
        .padding(.trailing, 6)
        .frame(height: 24)
        .foregroundStyle(isSelected ? .white : Color(red: 0.08, green: 0.22, blue: 0.38))
        .background(isSelected ? selectedBackground : addedBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isSelected ? selectedBackground : addedStroke.opacity(0.7), lineWidth: 1)
        }
        .fixedSize()
        .contentShape(Rectangle())
        .onTapGesture {
            searchUIState.isFilterPanelPresented = false
            if searchUIState.selectedTokenKind == token.kind {
                searchUIState.selectedTokenKind = nil
                focusSearchField()
            } else {
                searchUIState.selectedTokenKind = token.kind
                focusSearchField()
            }
        }
    }
}
