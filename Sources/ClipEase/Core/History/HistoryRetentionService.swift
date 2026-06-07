import Foundation

enum HistoryRetentionService {
    static func expiredItems(
        in items: [ClipboardItem],
        policy: HistoryRetentionPolicy,
        validGroupIDs: Set<ClipboardGroup.ID>,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [ClipboardItem] {
        guard let cutoffDate = cutoffDate(for: policy, now: now, calendar: calendar) else {
            return []
        }

        return items.filter { shouldPrune($0, cutoffDate: cutoffDate, validGroupIDs: validGroupIDs) }
    }

    static func cutoffDate(
        for policy: HistoryRetentionPolicy,
        now: Date,
        calendar: Calendar = .current
    ) -> Date? {
        guard let days = policy.days else {
            return nil
        }

        return calendar.date(byAdding: .day, value: -days, to: now) ?? now
    }

    private static func shouldPrune(
        _ item: ClipboardItem,
        cutoffDate: Date,
        validGroupIDs: Set<ClipboardGroup.ID>
    ) -> Bool {
        let hasValidGroup = item.groupID.map(validGroupIDs.contains) ?? false
        return !item.isPinned && !hasValidGroup && item.createdAt < cutoffDate
    }
}
