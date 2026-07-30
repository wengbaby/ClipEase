import Foundation

struct HistoryRetentionRunSchedule: Sendable {
    private var lastRunDate: Date?

    mutating func shouldRun(
        now: Date,
        calendar: Calendar = .current,
        force: Bool = false
    ) -> Bool {
        let runDate = calendar.startOfDay(for: now)
        if !force,
           let lastRunDate,
           calendar.isDate(lastRunDate, inSameDayAs: runDate) {
            return false
        }

        lastRunDate = runDate
        return true
    }
}
