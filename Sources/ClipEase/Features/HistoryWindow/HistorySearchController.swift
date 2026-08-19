import Foundation

enum HistoryGroupSelection: Equatable, Sendable {
    case all
    case pinned
    case group(ClipboardGroup.ID)

    var groupID: ClipboardGroup.ID? {
        switch self {
        case .all, .pinned:
            nil
        case .group(let id):
            id
        }
    }

    init(storageValue: String) {
        switch storageValue {
        case Self.pinned.storageValue:
            self = .pinned
        default:
            if storageValue.hasPrefix(Self.groupStoragePrefix),
               let id = ClipboardGroup.ID(uuidString: String(storageValue.dropFirst(Self.groupStoragePrefix.count))) {
                self = .group(id)
            } else {
                self = .all
            }
        }
    }

    var storageValue: String {
        switch self {
        case .all:
            "all"
        case .pinned:
            "pinned"
        case .group(let id):
            "\(Self.groupStoragePrefix)\(id.uuidString)"
        }
    }

    var scrollID: String {
        "group-selection-\(storageValue)"
    }

    private static let groupStoragePrefix = "group:"
}

struct HistorySearchCriteria: Equatable, Sendable {
    var types: Set<HistorySearchItemType> = []
    var sourceAppNames: Set<String> = []
    var dateRanges: Set<HistorySearchDateRange> = []
    var groups: Set<HistorySearchGroup> = []
    var tokenOrder: [HistorySearchTokenKind] = []

    var hasActiveFilters: Bool {
        !types.isEmpty || !sourceAppNames.isEmpty || !dateRanges.isEmpty || !groups.isEmpty
    }
}

enum HistorySearchItemType: String, CaseIterable, Identifiable, Hashable, Sendable {
    case text
    case link
    case image
    case color
    case file

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .text:
            L("文字")
        case .link:
            L("链接")
        case .image:
            L("图片")
        case .color:
            L("颜色")
        case .file:
            L("文件")
        }
    }

    var iconName: String {
        switch self {
        case .text:
            "text.alignleft"
        case .link:
            "link"
        case .image:
            "photo"
        case .color:
            "paintpalette"
        case .file:
            "doc"
        }
    }

    var previewType: HistoryPreviewType {
        switch self {
        case .text:
            .text
        case .link:
            .link
        case .image:
            .image
        case .color:
            .color
        case .file:
            .file
        }
    }
}

enum HistorySearchDateRange: String, CaseIterable, Identifiable, Hashable, Sendable {
    case today
    case last7Days
    case last30Days

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .today:
            L("今天")
        case .last7Days:
            L("最近 7 天")
        case .last30Days:
            L("最近 30 天")
        }
    }

    func contains(_ date: Date, now: Date) -> Bool {
        let calendar = Calendar.current
        switch self {
        case .today:
            return calendar.isDate(date, inSameDayAs: now)
        case .last7Days:
            return date >= calendar.date(byAdding: .day, value: -7, to: now) ?? now
        case .last30Days:
            return date >= calendar.date(byAdding: .day, value: -30, to: now) ?? now
        }
    }
}

enum HistorySearchGroup: Hashable, Sendable {
    case pinned
    case group(ClipboardGroup.ID)
}

enum HistorySearchTokenKind: Hashable, Sendable {
    case type(HistorySearchItemType)
    case sourceApp(String)
    case date(HistorySearchDateRange)
    case group(HistorySearchGroup)

    var iconName: String {
        switch self {
        case .type(let type):
            type.iconName
        case .sourceApp:
            "app"
        case .date:
            "calendar"
        case .group(.pinned):
            "pin.fill"
        case .group:
            "folder.fill"
        }
    }
}

struct HistorySearchToken: Identifiable, Equatable, Sendable {
    let kind: HistorySearchTokenKind
    let title: String

    var id: HistorySearchTokenKind {
        kind
    }

    static func tokens(
        criteria: HistorySearchCriteria,
        groups: [ClipboardGroup]
    ) -> [HistorySearchToken] {
        var tokenByKind: [HistorySearchTokenKind: HistorySearchToken] = [:]
        var tokens: [HistorySearchToken] = []

        for type in HistorySearchItemType.allCases where criteria.types.contains(type) {
            let token = HistorySearchToken(kind: .type(type), title: type.title)
            tokenByKind[token.kind] = token
        }

        for sourceAppName in criteria.sourceAppNames.sorted() {
            let token = HistorySearchToken(kind: .sourceApp(sourceAppName), title: sourceAppName)
            tokenByKind[token.kind] = token
        }

        for dateRange in HistorySearchDateRange.allCases where criteria.dateRanges.contains(dateRange) {
            let token = HistorySearchToken(kind: .date(dateRange), title: dateRange.title)
            tokenByKind[token.kind] = token
        }

        let systemGroups: [HistorySearchGroup] = [.pinned]
        for group in systemGroups where criteria.groups.contains(group) {
            let token = HistorySearchToken(kind: .group(group), title: group.title(groups: groups))
            tokenByKind[token.kind] = token
        }
        for group in groups where criteria.groups.contains(.group(group.id)) {
            let searchGroup = HistorySearchGroup.group(group.id)
            let token = HistorySearchToken(kind: .group(searchGroup), title: searchGroup.title(groups: groups))
            tokenByKind[token.kind] = token
        }

        var emittedKinds = Set<HistorySearchTokenKind>()
        for kind in criteria.tokenOrder {
            guard let token = tokenByKind[kind],
                  emittedKinds.insert(kind).inserted else {
                continue
            }
            tokens.append(token)
        }

        for type in HistorySearchItemType.allCases {
            appendRemainingToken(.type(type), from: tokenByKind, emittedKinds: &emittedKinds, to: &tokens)
        }
        for sourceAppName in criteria.sourceAppNames.sorted() {
            appendRemainingToken(.sourceApp(sourceAppName), from: tokenByKind, emittedKinds: &emittedKinds, to: &tokens)
        }
        for dateRange in HistorySearchDateRange.allCases {
            appendRemainingToken(.date(dateRange), from: tokenByKind, emittedKinds: &emittedKinds, to: &tokens)
        }
        for group in systemGroups {
            appendRemainingToken(.group(group), from: tokenByKind, emittedKinds: &emittedKinds, to: &tokens)
        }
        for group in groups {
            appendRemainingToken(.group(.group(group.id)), from: tokenByKind, emittedKinds: &emittedKinds, to: &tokens)
        }

        return tokens
    }

    private static func appendRemainingToken(
        _ kind: HistorySearchTokenKind,
        from tokenByKind: [HistorySearchTokenKind: HistorySearchToken],
        emittedKinds: inout Set<HistorySearchTokenKind>,
        to tokens: inout [HistorySearchToken]
    ) {
        guard let token = tokenByKind[kind],
              emittedKinds.insert(kind).inserted else {
            return
        }
        tokens.append(token)
    }
}

struct HistorySearchSourceIdentity: Equatable {
    let count: Int
    let firstID: HistoryPreviewItem.ID?
    let lastID: HistoryPreviewItem.ID?
    let searchFingerprint: Int
    let firstSearchFingerprint: Int?
    let lastSearchFingerprint: Int?

    init(items: [HistoryPreviewItem]) {
        count = items.count
        firstID = items.first?.id
        lastID = items.last?.id
        if let item = items.first {
            searchFingerprint = item.searchFingerprint
        } else {
            searchFingerprint = 0
        }
        firstSearchFingerprint = items.first?.searchFingerprint
        lastSearchFingerprint = items.last?.searchFingerprint
    }
}

struct HistorySearchRequestSignature: Equatable {
    let sourceIdentity: HistorySearchSourceIdentity
    let selectedGroup: String
    let searchText: String
    let criteria: HistorySearchCriteria
}

struct HistorySearchFilterResult: Sendable {
    let items: [HistoryPreviewItem]
    let repositoryResultCount: Int
    let canLoadMore: Bool
    let itemIDs: Set<HistoryPreviewItem.ID>
    let itemIndexByID: [HistoryPreviewItem.ID: Int]

    init(items: [HistoryPreviewItem], repositoryResultCount: Int? = nil, canLoadMore: Bool = false) {
        self.items = items
        self.repositoryResultCount = repositoryResultCount ?? items.count
        self.canLoadMore = canLoadMore
        self.itemIDs = Set(items.map(\.id))
        var itemIndexByID: [HistoryPreviewItem.ID: Int] = [:]
        itemIndexByID.reserveCapacity(items.count)
        for (index, item) in items.enumerated() {
            itemIndexByID[item.id] = index
        }
        self.itemIndexByID = itemIndexByID
    }
}

enum HistorySearchController {
    static func filterItems(
        _ items: [HistoryPreviewItem],
        selectedGroup: HistoryGroupSelection,
        searchText: String,
        criteria: HistorySearchCriteria,
        maxResultCount: Int? = nil,
        now: Date
    ) throws -> [HistoryPreviewItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedQuery = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)

        if usesUnfilteredSearchSource(
            selectedGroup: selectedGroup,
            searchText: searchText,
            criteria: criteria
        ) {
            try Task.checkCancellation()
            return items
        }

        var result: [HistoryPreviewItem] = []
        result.reserveCapacity(min(items.count, maxResultCount ?? items.count))

        for item in items {
            try Task.checkCancellation()

            switch selectedGroup {
            case .all:
                break
            case .pinned:
                if !item.isPinned {
                    continue
                }
            case .group(let selectedGroupID):
                if item.groupID != selectedGroupID {
                    continue
                }
            }

            if !criteria.types.isEmpty,
               !criteria.types.contains(where: { item.type == $0.previewType }) {
                continue
            }

            if !criteria.sourceAppNames.isEmpty,
               !criteria.sourceAppNames.contains(item.sourceAppName) {
                continue
            }

            if !criteria.dateRanges.isEmpty,
               !criteria.dateRanges.contains(where: { $0.contains(item.createdAt, now: now) }) {
                continue
            }

            if !criteria.groups.isEmpty,
               !criteria.groups.contains(where: { itemMatchesSearchGroup(item, group: $0) }) {
                continue
            }

            guard !normalizedQuery.isEmpty else {
                result.append(item)
                if let maxResultCount, result.count >= maxResultCount {
                    break
                }
                continue
            }

            if item.normalizedSearchText.contains(normalizedQuery) {
                result.append(item)
                if let maxResultCount, result.count >= maxResultCount {
                    break
                }
            }
        }

        try Task.checkCancellation()

        if case .group = selectedGroup {
            result.sort(by: {
                ($0.groupedAt ?? .distantPast) > ($1.groupedAt ?? .distantPast)
            })
        }

        try Task.checkCancellation()
        return result
    }

    static func usesUnfilteredSearchSource(
        selectedGroup: HistoryGroupSelection,
        searchText: String,
        criteria: HistorySearchCriteria
    ) -> Bool {
        selectedGroup == .all &&
            searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !criteria.hasActiveFilters
    }

    private static func itemMatchesSearchGroup(
        _ item: HistoryPreviewItem,
        group: HistorySearchGroup
    ) -> Bool {
        switch group {
        case .pinned:
            item.isPinned
        case .group(let groupID):
            item.groupID == groupID
        }
    }
}

enum HistorySearchPaginationPolicy {
    static func shouldLoadMore(
        filteredCount: Int,
        targetCount: Int,
        repositoryResultCount: Int,
        pageSize: Int,
        canLoadMore: Bool
    ) -> Bool {
        guard canLoadMore,
              targetCount > 0,
              pageSize > 0,
              filteredCount < targetCount else {
            return false
        }

        return repositoryResultCount >= pageSize
    }
}

private extension HistorySearchGroup {
    func title(groups: [ClipboardGroup]) -> String {
        switch self {
        case .pinned:
            L("置顶")
        case .group(let groupID):
            groups.first(where: { $0.id == groupID })?.name ?? L("分组")
        }
    }
}
