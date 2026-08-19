import SwiftUI
import AppKit

extension HistoryWindowView {
    @ViewBuilder
    var shortcutButtons: some View {
        Group {
            Button(action: { pasteItem(selectedItemID) }) {
                EmptyView()
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: [])
            .disabled(shouldSuppressHistoryCommandShortcuts)
            .frame(width: 0, height: 0)
            .opacity(0)

            Button(action: { pastePlainTextItem(selectedItemID) }) {
                EmptyView()
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: [.shift])
            .disabled(shouldSuppressHistoryCommandShortcuts)
            .frame(width: 0, height: 0)
            .opacity(0)

            Button(action: handleCommandFSearch) {
                EmptyView()
            }
            .buttonStyle(.plain)
            .keyboardShortcut("f", modifiers: [.command])
            .disabled(shouldSuppressHistoryCommandShortcuts)
            .frame(width: 0, height: 0)
            .opacity(0)

            Button(action: { copyItem(selectedItemID) }) {
                EmptyView()
            }
            .buttonStyle(.plain)
            .keyboardShortcut("c", modifiers: [.command])
            .disabled(shouldSuppressHistoryCommandShortcuts)
            .frame(width: 0, height: 0)
            .opacity(0)

            Button(action: { copyPlainTextItem(selectedItemID) }) {
                EmptyView()
            }
            .buttonStyle(.plain)
            .keyboardShortcut("c", modifiers: [.shift, .command])
            .disabled(shouldSuppressHistoryCommandShortcuts)
            .frame(width: 0, height: 0)
            .opacity(0)

            Button(action: handleEditShortcut) {
                EmptyView()
            }
            .buttonStyle(.plain)
            .keyboardShortcut("e", modifiers: [.command])
            .disabled(!canEditSelectedItemFromShortcut)
            .frame(width: 0, height: 0)
            .opacity(0)

            Button(action: { togglePinned(selectedItemID) }) {
                EmptyView()
            }
            .buttonStyle(.plain)
            .keyboardShortcut("p", modifiers: [.command])
            .disabled(shouldSuppressHistoryCommandShortcuts)
            .frame(width: 0, height: 0)
            .opacity(0)

            Button(action: appMenuController.showSettings) {
                EmptyView()
            }
            .buttonStyle(.plain)
            .keyboardShortcut(",", modifiers: [.command])
            .disabled(shouldSuppressHistoryCommandShortcuts)
            .frame(width: 0, height: 0)
            .opacity(0)

            Button(action: closeWindowFromShortcut) {
                EmptyView()
            }
            .buttonStyle(.plain)
            .keyboardShortcut("w", modifiers: [.command])
            .disabled(shouldSuppressHistoryCommandShortcuts)
            .frame(width: 0, height: 0)
            .opacity(0)

            Button(action: createTextFromShortcut) {
                EmptyView()
            }
            .buttonStyle(.plain)
            .keyboardShortcut("n", modifiers: [.command])
            .disabled(shouldSuppressHistoryCommandShortcuts)
            .frame(width: 0, height: 0)
            .opacity(0)

            Button(action: toggleRecordingFromShortcut) {
                EmptyView()
            }
            .buttonStyle(.plain)
            .keyboardShortcut("t", modifiers: [.command])
            .disabled(shouldSuppressHistoryCommandShortcuts)
            .frame(width: 0, height: 0)
            .opacity(0)
        }
    }

    var toolbar: some View {
        ZStack {
            HStack(spacing: 12) {
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(toolbarSecondaryForeground)

                HStack(spacing: 7) {
                    Image(nsImage: ClipEaseAppIcon.roundedImage(ClipEaseAppIcon.image(size: NSSize(width: 18, height: 18)), size: NSSize(width: 18, height: 18)))
                        .resizable()
                        .frame(width: 18, height: 18)

                    Text(L("轻贴"))
                        .font(titleTypography.swiftUIFont)
                        .foregroundStyle(toolbarPrimaryForeground)
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            topTrack
                .frame(maxWidth: .infinity)

            HStack(spacing: 12) {
                Button(action: toggleWindowPinnedOpen) {
                    Image(systemName: inputState.isWindowPinnedOpen ? "pin.fill" : "pin")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(inputState.isWindowPinnedOpen ? Color(red: 0.18, green: 0.55, blue: 1.0) : toolbarSecondaryForeground)
                }
                .buttonStyle(.plain)
                .help(inputState.isWindowPinnedOpen ? L("取消钉住主窗口") : L("钉住主窗口"))

                if !accessibilityPermissionState.isTrusted {
                    authorizationButton
                }

                moreMenu
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 22)
        .frame(height: HistoryWindowPanelMetrics.toolbarHeight)
    }

    var topTrack: some View {
        GeometryReader { proxy in
            let widthPlan = HistoryGlassToolbarWidthPolicy.resolve(
                availableWidth: proxy.size.width,
                isSearchExpanded: searchUIState.shouldShowField
            )

            ScrollViewReader { scrollProxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        searchField
                            .frame(width: widthPlan.searchWidth, alignment: .leading)
                            .id("search-field")

                        Group {
                            searchToggleButton
                                .id("search-toggle")

                            allHistoryGroupButton
                                .id(HistoryGroupSelection.all.scrollID)

                            systemGroupButton(.pinned)
                                .id(HistoryGroupSelection.pinned.scrollID)

                            ForEach(store.groups) { group in
                                groupButton(group, compact: isSearchControlExpanded)
                                    .id(HistoryGroupSelection.group(group.id).scrollID)
                            }

                            if !isSearchControlExpanded {
                                newGroupButton
                                    .id("new-group")
                            }

                            if isSearchControlExpanded || isSearchActive {
                                resultCountBadge
                                    .id("result-count")
                            }
                        }
                        .animation(.easeOut(duration: 0.10), value: isSearchControlExpanded)
                    }
                    .frame(minWidth: widthPlan.trackWidth, alignment: .center)
                    .padding(.vertical, 1)
                    .animation(.easeOut(duration: 0.16), value: searchUIState.shouldShowField)
                }
                .background(HorizontalScrollWheelRedirector(
                    scope: .auxiliaryRail,
                    isEnabled: inputState.isWindowVisible
                ))
                .onChange(of: groupUIState.pendingGroupTrackScrollID) { scrollID in
                    guard let scrollID else {
                        return
                    }

                    withAnimation(.easeOut(duration: 0.18)) {
                        scrollProxy.scrollTo(scrollID, anchor: .trailing)
                    }
                    groupUIState.pendingGroupTrackScrollID = nil
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: 30)
        .confirmationDialog(
            L("删除分组？"),
            isPresented: Binding(
                get: { groupUIState.groupPendingDeletion != nil },
                set: { isPresented in
                    if !isPresented {
                        groupUIState.groupPendingDeletion = nil
                    }
                }
            ),
            titleVisibility: .visible,
            presenting: groupUIState.groupPendingDeletion
        ) { group in
            Button(L("删除分组和内容"), role: .destructive) {
                deleteGroup(group)
            }

            Button(L("取消"), role: .cancel) {}
        } message: { group in
            Text(L("会删除“\(group.name)”中的 \(store.itemCount(inGroup: group.id)) 条内容，无法恢复。"))
        }
    }
}
