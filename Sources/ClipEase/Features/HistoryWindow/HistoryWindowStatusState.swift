import Foundation

struct HistoryWindowStatusState {
    var text: String?
    var generation: UInt64 = 0

    mutating func show(_ text: String) -> UInt64 {
        generation &+= 1
        self.text = text
        return generation
    }

    mutating func clearIfCurrent(generation expectedGeneration: UInt64) -> Bool {
        guard generation == expectedGeneration else {
            return false
        }

        text = nil
        return true
    }
}
