import Foundation

enum SystemHistoryGroup: CaseIterable, Identifiable, Equatable, Sendable {
    case pinned

    var id: String {
        title
    }

    var selection: HistoryGroupSelection {
        switch self {
        case .pinned:
            .pinned
        }
    }

    var searchGroup: HistorySearchGroup {
        switch self {
        case .pinned:
            .pinned
        }
    }

    var title: String {
        switch self {
        case .pinned:
            L("置顶")
        }
    }

    var selectedStatus: String {
        switch self {
        case .pinned:
            L("只看置顶")
        }
    }

    var help: String {
        switch self {
        case .pinned:
            L("显示置顶内容")
        }
    }
}
