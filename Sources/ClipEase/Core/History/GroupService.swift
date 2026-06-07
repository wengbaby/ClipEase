import Foundation

enum GroupService {
    enum RenameResult: Equatable {
        case renamed
        case unchanged
        case empty
        case duplicate
        case notFound
    }

    static func sortGroupsAndBuildIndex(_ groups: inout [ClipboardGroup]) -> [ClipboardGroup.ID: Int] {
        groups.sort { lhs, rhs in
            lhs.sortOrder == rhs.sortOrder ? lhs.createdAt < rhs.createdAt : lhs.sortOrder < rhs.sortOrder
        }
        for index in groups.indices {
            groups[index].sortOrder = index
        }
        return rebuildGroupIndex(groups)
    }

    static func rebuildGroupIndex(_ groups: [ClipboardGroup]) -> [ClipboardGroup.ID: Int] {
        var indexByID: [ClipboardGroup.ID: Int] = [:]
        indexByID.reserveCapacity(groups.count)
        for (index, group) in groups.enumerated() {
            indexByID[group.id] = index
        }
        return indexByID
    }

    static func groupIndex(
        for id: ClipboardGroup.ID,
        groups: [ClipboardGroup],
        indexByID: inout [ClipboardGroup.ID: Int]
    ) -> Int? {
        guard let index = indexByID[id],
              groups.indices.contains(index),
              groups[index].id == id else {
            indexByID = rebuildGroupIndex(groups)
            guard let repairedIndex = indexByID[id],
                  groups.indices.contains(repairedIndex),
                  groups[repairedIndex].id == id else {
                return nil
            }
            return repairedIndex
        }

        return index
    }

    static func renameGroup(
        _ id: ClipboardGroup.ID,
        name: String,
        groups: inout [ClipboardGroup],
        indexByID: inout [ClipboardGroup.ID: Int],
        now: Date = Date()
    ) -> RenameResult {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return .empty
        }

        guard let index = groupIndex(for: id, groups: groups, indexByID: &indexByID) else {
            return .notFound
        }

        if normalizedGroupName(groups[index].name) == normalizedGroupName(trimmedName) {
            return .unchanged
        }

        guard isGroupNameAvailable(trimmedName, groups: groups, excluding: id) else {
            return .duplicate
        }

        groups[index].name = trimmedName
        groups[index].updatedAt = now
        return .renamed
    }

    static func updateGroupAppearance(
        _ id: ClipboardGroup.ID,
        colorHex: String?,
        iconName: String?,
        groups: inout [ClipboardGroup],
        indexByID: inout [ClipboardGroup.ID: Int],
        now: Date = Date()
    ) -> Bool {
        guard let index = groupIndex(for: id, groups: groups, indexByID: &indexByID) else {
            return false
        }

        if let colorHex {
            groups[index].colorHex = colorHex
        }
        if let iconName {
            groups[index].iconName = iconName
        }
        groups[index].updatedAt = now
        return true
    }

    static func uniqueGroupName(baseName: String, groups: [ClipboardGroup]) -> String {
        let trimmedBaseName = baseName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedBaseName = trimmedBaseName.isEmpty ? ClipboardGroup.defaultName : trimmedBaseName
        if isGroupNameAvailable(resolvedBaseName, groups: groups) {
            return resolvedBaseName
        }

        var index = 2
        while true {
            let candidate = "\(resolvedBaseName) \(index)"
            if isGroupNameAvailable(candidate, groups: groups) {
                return candidate
            }
            index += 1
        }
    }

    static func updateGroupCountOnMove(
        from oldGroupID: ClipboardGroup.ID?,
        to newGroupID: ClipboardGroup.ID?,
        countByGroupID: inout [ClipboardGroup.ID: Int]
    ) {
        guard oldGroupID != newGroupID else {
            return
        }

        if let oldGroupID,
           let count = countByGroupID[oldGroupID] {
            let nextCount = max(0, count - 1)
            if nextCount == 0 {
                countByGroupID[oldGroupID] = nil
            } else {
                countByGroupID[oldGroupID] = nextCount
            }
        }

        if let newGroupID {
            countByGroupID[newGroupID, default: 0] += 1
        }
    }

    static func normalizedGroupName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
    }

    static func isGroupNameAvailable(
        _ name: String,
        groups: [ClipboardGroup],
        excluding id: ClipboardGroup.ID? = nil
    ) -> Bool {
        let normalizedName = normalizedGroupName(name)
        return !groups.contains { group in
            if group.id == id {
                return false
            }
            return normalizedGroupName(group.name) == normalizedName
        }
    }
}
