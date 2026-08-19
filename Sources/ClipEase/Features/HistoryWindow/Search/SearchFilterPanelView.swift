import SwiftUI

struct SearchFilterPanelView: View {
    @Binding var criteria: HistorySearchCriteria
    let isFilterPanelPresented: Binding<Bool>
    let sourceAppFilterOptions: [HistorySourceAppFilterOption]
    let systemGroups: [SystemHistoryGroup]
    let customGroups: [ClipboardGroup]
    let onClear: () -> Void
    let onClose: () -> Void
    let onToggleType: (HistorySearchItemType) -> Void
    let onToggleSourceApp: (String) -> Void
    let onToggleDateRange: (HistorySearchDateRange) -> Void
    let onToggleGroup: (HistorySearchGroup) -> Void
    let systemGroupIconName: (SystemHistoryGroup) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L("搜索筛选"))
                    .font(.system(size: 14, weight: .semibold))

                Spacer()

                Button(L("清空")) {
                    onClear()
                }
                .disabled(!criteria.hasActiveFilters)

                Button(L("关闭")) {
                    isFilterPanelPresented.wrappedValue = false
                    onClose()
                }
            }

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 14) {
                    SearchFilterSection(title: "Type") {
                        SearchFilterChipGrid {
                            ForEach(HistorySearchItemType.allCases) { type in
                                SearchFilterChip(
                                    title: type.title,
                                    systemImage: type.iconName,
                                    isSelected: criteria.types.contains(type),
                                    action: { onToggleType(type) }
                                )
                            }
                        }
                    }

                    SearchFilterSection(title: "App") {
                        if sourceAppFilterOptions.isEmpty {
                            Text(L("暂无来源"))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                        } else {
                            SearchFilterChipGrid {
                                ForEach(sourceAppFilterOptions) { option in
                                    let appName = option.name
                                    SearchFilterChip(
                                        title: appName,
                                        iconFileName: option.iconFileName,
                                        fallbackSystemImage: "app.fill",
                                        isSelected: criteria.sourceAppNames.contains(appName),
                                        action: { onToggleSourceApp(appName) }
                                    )
                                }
                            }
                        }
                    }

                    SearchFilterSection(title: "Date") {
                        SearchFilterChipGrid {
                            ForEach(HistorySearchDateRange.allCases) { range in
                                SearchFilterChip(
                                    title: range.title,
                                    systemImage: "calendar",
                                    isSelected: criteria.dateRanges.contains(range),
                                    action: { onToggleDateRange(range) }
                                )
                            }
                        }
                    }

                    SearchFilterSection(title: "Group") {
                        SearchFilterChipGrid {
                            ForEach(systemGroups) { group in
                                SearchFilterChip(
                                    title: group.title,
                                    systemImage: systemGroupIconName(group),
                                    isSelected: criteria.groups.contains(group.searchGroup),
                                    action: { onToggleGroup(group.searchGroup) }
                                )
                            }

                            ForEach(customGroups) { group in
                                SearchFilterChip(
                                    title: group.name,
                                    systemImage: group.iconName,
                                    isSelected: criteria.groups.contains(.group(group.id)),
                                    action: { onToggleGroup(.group(group.id)) }
                                )
                            }
                        }
                    }
                }
                .padding(.trailing, 6)
            }
            .frame(width: 420, height: 260)
        }
        .padding(16)
        .frame(width: 440, height: 320)
    }
}
