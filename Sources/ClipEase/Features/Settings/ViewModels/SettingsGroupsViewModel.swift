import Foundation

enum SettingsGroupsBulkDeleteDecision: Equatable {
    case none
    case deleteImmediately
    case confirm
}

enum SettingsGroupsViewModel {
    nonisolated static func subtitle(
        groups: [ClipboardGroup],
        itemCount: (ClipboardGroup.ID) -> Int
    ) -> String {
        guard !groups.isEmpty else {
            return "暂无分组"
        }

        let groupedItemCount = groups.reduce(0) { partialResult, group in
            partialResult + itemCount(group.id)
        }
        return "\(groups.count) 个分组，\(groupedItemCount) 条内容"
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

    nonisolated static func bulkDeleteDecision(
        selectedIDs: Set<ClipboardGroup.ID>,
        itemCount: (ClipboardGroup.ID) -> Int
    ) -> SettingsGroupsBulkDeleteDecision {
        guard !selectedIDs.isEmpty else {
            return .none
        }

        if selectedIDs.contains(where: { itemCount($0) > 0 }) {
            return .confirm
        }

        return .deleteImmediately
    }
}
