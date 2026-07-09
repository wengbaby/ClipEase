import Foundation

enum HistoryWindowLifecycleScheduler {
    static let animatedOpenStartupDelayNanoseconds: UInt64 = 180_000_000

    static func startupDelayNanoseconds(
        requestedDelayNanoseconds: UInt64,
        isWindowVisible: Bool,
        isWindowPresented: Bool,
        isOpenAnimationActive: Bool
    ) -> UInt64? {
        guard isWindowVisible else {
            return nil
        }

        guard isWindowPresented || isOpenAnimationActive else {
            return nil
        }

        guard isOpenAnimationActive else {
            return requestedDelayNanoseconds
        }

        return max(requestedDelayNanoseconds, animatedOpenStartupDelayNanoseconds)
    }
}
