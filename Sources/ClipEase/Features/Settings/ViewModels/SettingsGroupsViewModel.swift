import Foundation

enum SettingsGroupsViewModel {
    nonisolated static func subtitle(
        groups: [ClipboardGroup],
        itemCount: (ClipboardGroup.ID) -> Int
    ) -> String {
        guard !groups.isEmpty else {
            return L("暂无分组")
        }

        let groupedItemCount = groups.reduce(0) { partialResult, group in
            partialResult + itemCount(group.id)
        }
        return L("\(groups.count) 个分组，\(groupedItemCount) 条内容")
    }

    nonisolated static func filteredIcons(query: String) -> [String] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return ClipboardGroup.defaultIcons
        }

        return ClipboardGroup.defaultIcons.filter {
            $0.localizedCaseInsensitiveContains(trimmedQuery)
        }
    }

}
