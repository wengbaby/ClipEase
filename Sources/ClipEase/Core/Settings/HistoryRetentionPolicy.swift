import Foundation

enum HistoryRetentionPolicy: Int, CaseIterable, Identifiable {
    case oneDay = 1
    case threeDays = 3
    case fiveDays = 5
    case sevenDays = 7
    case thirtyDays = 30
    case forever = 0

    var id: Int {
        rawValue
    }

    var days: Int? {
        switch self {
        case .forever:
            nil
        case .oneDay, .threeDays, .fiveDays, .sevenDays, .thirtyDays:
            rawValue
        }
    }

    var title: String {
        switch self {
        case .oneDay:
            "保存 1 天"
        case .threeDays:
            "保存 3 天"
        case .fiveDays:
            "保存 5 天"
        case .sevenDays:
            "保存 7 天"
        case .thirtyDays:
            "保存 30 天"
        case .forever:
            "永久保存"
        }
    }

    var shortTitle: String {
        switch self {
        case .oneDay:
            "1 天"
        case .threeDays:
            "3 天"
        case .fiveDays:
            "5 天"
        case .sevenDays:
            "7 天"
        case .thirtyDays:
            "30 天"
        case .forever:
            "永久"
        }
    }
}
