import Foundation

struct SettingsHistoryDataActionCoordinator {
    struct AuthoritativeHistoryData: Sendable {
        let items: [ClipboardItem]
        let groups: [ClipboardGroup]
        let mutationGeneration: UInt64
    }

    struct GroupDeletionAssessment: Equatable, Sendable {
        let itemCount: Int
        let mutationGeneration: UInt64

        init(itemCount: Int, mutationGeneration: UInt64 = 0) {
            self.itemCount = itemCount
            self.mutationGeneration = mutationGeneration
        }

        var requiresConfirmation: Bool {
            itemCount > 0
        }
    }

    enum GroupDeletionAssessmentValidation: Equatable, Sendable {
        case current
        case requiresReassessment(GroupDeletionAssessment)
    }

    enum GroupDeletionExecutionResult: Equatable, Sendable {
        case deleted(
            assessment: GroupDeletionAssessment,
            deletedGroupIDs: Set<ClipboardGroup.ID>
        )
        case requiresReassessment(GroupDeletionAssessment)
        case noGroupsDeleted
    }

    struct ConfirmationPrompt: Equatable {
        let title: String
        let message: String
        let confirmTitle: String
        let cancelTitle: String
    }

    @MainActor
    static func authoritativeHistoryData(
        from store: ClipboardHistoryStore
    ) async throws -> AuthoritativeHistoryData {
        let snapshot = try await store.authoritativeSnapshot()
        return AuthoritativeHistoryData(
            items: snapshot.history.items,
            groups: snapshot.history.groups,
            mutationGeneration: snapshot.mutationGeneration
        )
    }

    @MainActor
    static func groupDeletionAssessment(
        for groupID: ClipboardGroup.ID,
        from store: ClipboardHistoryStore
    ) async throws -> GroupDeletionAssessment {
        try await groupDeletionAssessment(for: [groupID], from: store)
    }

    @MainActor
    static func groupDeletionAssessment(
        for groupIDs: Set<ClipboardGroup.ID>,
        from store: ClipboardHistoryStore
    ) async throws -> GroupDeletionAssessment {
        guard !groupIDs.isEmpty else {
            return GroupDeletionAssessment(
                itemCount: 0,
                mutationGeneration: store.currentMutationGeneration
            )
        }

        let historyData = try await authoritativeHistoryData(from: store)
        return GroupDeletionAssessment(
            itemCount: historyData.items.reduce(into: 0) { count, item in
                if let groupID = item.groupID, groupIDs.contains(groupID) {
                    count += 1
                }
            },
            mutationGeneration: historyData.mutationGeneration
        )
    }

    @MainActor
    static func validateGroupDeletionAssessment(
        _ assessment: GroupDeletionAssessment,
        for groupIDs: Set<ClipboardGroup.ID>,
        from store: ClipboardHistoryStore
    ) async throws -> GroupDeletionAssessmentValidation {
        guard !store.isCurrentMutationGeneration(assessment.mutationGeneration) else {
            return .current
        }

        return .requiresReassessment(
            try await groupDeletionAssessment(for: groupIDs, from: store)
        )
    }

    @MainActor
    static func executeGroupDeletion(
        _ assessment: GroupDeletionAssessment,
        for groupIDs: Set<ClipboardGroup.ID>,
        from store: ClipboardHistoryStore
    ) async throws -> GroupDeletionExecutionResult {
        switch try await validateGroupDeletionAssessment(
            assessment,
            for: groupIDs,
            from: store
        ) {
        case .current:
            return deleteGroups(groupIDs, assessment: assessment, from: store)
        case .requiresReassessment(let updatedAssessment):
            guard !updatedAssessment.requiresConfirmation else {
                return .requiresReassessment(updatedAssessment)
            }
            return deleteGroups(groupIDs, assessment: updatedAssessment, from: store)
        }
    }

    static func groupDeletionStatus(
        for result: GroupDeletionExecutionResult
    ) -> String? {
        switch result {
        case .deleted(let assessment, _):
            return groupDeletionSuccessStatus(authoritativeAssessment: assessment)
        case .noGroupsDeleted:
            return L("分组不存在")
        case .requiresReassessment:
            return nil
        }
    }

    static func groupDeletionSuccessStatus(
        authoritativeAssessment: GroupDeletionAssessment
    ) -> String {
        authoritativeAssessment.itemCount > 0
            ? L("已删除分组和 \(authoritativeAssessment.itemCount) 条内容")
            : L("已删除分组")
    }

    @MainActor
    private static func deleteGroups(
        _ groupIDs: Set<ClipboardGroup.ID>,
        assessment: GroupDeletionAssessment,
        from store: ClipboardHistoryStore
    ) -> GroupDeletionExecutionResult {
        let deletion = store.deleteGroupsWithResult(groupIDs)
        guard deletion.didDeleteAnyGroup else {
            return .noGroupsDeleted
        }
        return .deleted(
            assessment: assessment,
            deletedGroupIDs: deletion.deletedGroupIDs
        )
    }

    @MainActor
    static func cleanOrphanedAttachments(
        historyData: AuthoritativeHistoryData,
        from store: ClipboardHistoryStore
    ) async throws -> OrphanedAttachmentCleanupResult {
        let items = historyData.items
        let candidates = await Task.detached(priority: .utility) {
            OrphanedAttachmentCleaner.candidates(items: items)
        }.value
        return try await store.deleteUnreferencedAttachmentCandidates(
            candidates,
            discoveredAtMutationGeneration: historyData.mutationGeneration
        )
    }

    @MainActor
    static func repairHistoryData(
        historyData: AuthoritativeHistoryData,
        from store: ClipboardHistoryStore
    ) async throws -> HistoryDataRepairReport {
        let items = historyData.items
        let before = await Task.detached(priority: .utility) {
            HistoryDataHealthChecker.check(items: items)
        }.value
        let cleanup = try await cleanOrphanedAttachments(historyData: historyData, from: store)
        let afterHistoryData = try await authoritativeHistoryData(from: store)
        let afterItems = afterHistoryData.items
        let after = await Task.detached(priority: .utility) {
            HistoryDataHealthChecker.check(items: afterItems)
        }.value
        return HistoryDataRepairReport(
            before: before,
            removedFiles: cleanup.removedFiles,
            removedBytes: cleanup.removedBytes,
            after: after
        )
    }

    static func backupImportDuplicatePrompt(duplicateCount: Int) -> ConfirmationPrompt? {
        guard duplicateCount > 0 else {
            return nil
        }

        return ConfirmationPrompt(
            title: L("发现重复历史"),
            message: L("备份包中有 \(duplicateCount) 条历史已存在。"),
            confirmTitle: L("跳过重复"),
            cancelTitle: L("取消导入")
        )
    }

    static func backupImportStatusText(
        importedCount: Int,
        result: BackupImportResult
    ) -> String {
        if importedCount == 0, result.items.isEmpty {
            return result.missingAttachmentCount > 0
                ? L("没有可导入的新历史，缺失附件 \(result.missingAttachmentCount) 个")
                : L("没有可导入的新历史")
        }

        let duplicateOrSkippedCount = max(0, result.totalItems - importedCount)
        var parts = [L("已导入 \(importedCount) 条")]
        if duplicateOrSkippedCount > 0 {
            parts.append(L("跳过 \(duplicateOrSkippedCount) 条"))
        }
        if result.missingAttachmentCount > 0 {
            parts.append(L("缺失附件 \(result.missingAttachmentCount) 个"))
        }
        return parts.joined(separator: "，")
    }
}
