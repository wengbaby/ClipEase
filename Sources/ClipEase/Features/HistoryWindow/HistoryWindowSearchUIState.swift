import Foundation

struct HistoryWindowSearchUIState {
    var text = ""
    var criteria = HistorySearchCriteria()
    var selectedTokenKind: HistorySearchTokenKind?
    var isVisible = false
    var isFieldLayoutVisible = false
    var isFieldVisualVisible = false
    var isFilterPanelPresented = false
    var pendingTrigger = "unknown"
    var hasHandedOffFocusToCard = false

    var isActive: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || criteria.hasActiveFilters
    }

    var shouldShowField: Bool {
        isVisible || isFieldLayoutVisible
    }

    var hasContent: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || criteria.hasActiveFilters
    }

    mutating func open(trigger: String) {
        pendingTrigger = trigger
        isVisible = true
    }

    mutating func close() {
        isVisible = false
    }

    mutating func clearText() -> Bool {
        hasHandedOffFocusToCard = false
        text = ""
        selectedTokenKind = nil
        return isVisible
    }

    mutating func clearTextAndFilters(trigger: String) -> Bool {
        pendingTrigger = trigger
        hasHandedOffFocusToCard = false
        text = ""
        criteria = HistorySearchCriteria()
        selectedTokenKind = nil
        return isVisible
    }

    mutating func clearAndClose() {
        text = ""
        criteria = HistorySearchCriteria()
        selectedTokenKind = nil
        isVisible = false
    }

    mutating func setFieldPresentationVisible(_ isVisible: Bool) {
        if isVisible {
            isFieldLayoutVisible = true
        } else {
            isFieldVisualVisible = false
        }
    }

    mutating func finishFieldPresentationShow() {
        isFieldVisualVisible = true
    }

    mutating func finishFieldPresentationHide() {
        isFieldLayoutVisible = false
    }

    mutating func toggleFilterPanel(openTrigger: String, closeTrigger: String) -> Bool {
        let willOpen = !isFilterPanelPresented
        pendingTrigger = willOpen ? openTrigger : closeTrigger
        isFilterPanelPresented.toggle()
        return willOpen
    }

    mutating func toggleType(_ type: HistorySearchItemType) {
        pendingTrigger = "filter.type.toggle"
        if criteria.types.contains(type) {
            criteria.types.remove(type)
            removeTokenOrder(.type(type))
        } else {
            criteria.types.insert(type)
            appendTokenOrder(.type(type))
        }
    }

    mutating func toggleSourceApp(_ appName: String) {
        pendingTrigger = "filter.sourceApp.toggle"
        if criteria.sourceAppNames.contains(appName) {
            criteria.sourceAppNames.remove(appName)
            removeTokenOrder(.sourceApp(appName))
        } else {
            criteria.sourceAppNames.insert(appName)
            appendTokenOrder(.sourceApp(appName))
        }
    }

    mutating func toggleDateRange(_ range: HistorySearchDateRange) {
        pendingTrigger = "filter.date.toggle"
        if criteria.dateRanges.contains(range) {
            criteria.dateRanges.remove(range)
            removeTokenOrder(.date(range))
        } else {
            criteria.dateRanges.insert(range)
            appendTokenOrder(.date(range))
        }
    }

    mutating func toggleGroup(_ group: HistorySearchGroup) {
        pendingTrigger = "filter.group.toggle"
        if criteria.groups.contains(group) {
            criteria.groups.remove(group)
            removeTokenOrder(.group(group))
        } else {
            criteria.groups.insert(group)
            appendTokenOrder(.group(group))
        }
    }

    mutating func removeToken(_ kind: HistorySearchTokenKind) {
        pendingTrigger = "search.token.remove"
        switch kind {
        case .type(let type):
            criteria.types.remove(type)
        case .sourceApp(let appName):
            criteria.sourceAppNames.remove(appName)
        case .date(let range):
            criteria.dateRanges.remove(range)
        case .group(let group):
            criteria.groups.remove(group)
        }
        removeTokenOrder(kind)
        selectedTokenKind = nil
    }

    mutating func appendTokenOrder(_ kind: HistorySearchTokenKind) {
        guard !criteria.tokenOrder.contains(kind) else {
            return
        }

        criteria.tokenOrder.append(kind)
    }

    mutating func removeTokenOrder(_ kind: HistorySearchTokenKind) {
        criteria.tokenOrder.removeAll { $0 == kind }
    }

    mutating func pruneTokenOrder(activeKinds: Set<HistorySearchTokenKind>) {
        criteria.tokenOrder.removeAll { !activeKinds.contains($0) }
    }
}
