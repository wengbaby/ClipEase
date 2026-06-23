import Foundation
import Testing

@Test func releaseScriptVerifiesRemoteBeforePublishing() throws {
    let script = try releaseScript()

    #expect(script.contains("verify_remote_state_before_publish"))
    #expect(script.contains("git fetch origin main"))
    #expect(script.contains("Remote main has commits not present locally"))
}

@Test func releaseScriptRequiresCommittedVersionBeforePublishing() throws {
    let script = try releaseScript()

    #expect(script.contains("ensure_clean_worktree_for_publish"))
    #expect(script.contains("Release publishing requires a clean git worktree"))
}

@Test func releaseScriptPushesBranchBeforeTagAndCleansTagOnFailure() throws {
    let script = try releaseScript()
    let branchPushRange = try #require(script.range(of: "git push origin \"HEAD:${PUBLISH_BRANCH}\""))
    let tagCreateRange = try #require(script.range(of: "git tag \"$TAG\""))

    #expect(branchPushRange.lowerBound < tagCreateRange.lowerBound)
    #expect(script.contains("cleanup_created_tag"))
    #expect(script.contains("git tag -d \"$TAG\""))
}

@Test func releaseScriptDoesNotClearPublishBranchAfterRemoteVerification() throws {
    let script = try releaseScript()

    #expect(!script.contains("PUBLISH_BRANCH=\"\""))
}

@Test func releaseScriptSupportsDryRunWithoutPublishing() throws {
    let script = try releaseScript()

    #expect(script.contains("--dry-run"))
    #expect(script.contains("DRY_RUN=\"true\""))
    #expect(script.contains("Dry run complete. No git tag, GitHub Release, or upload was created."))
}

@Test func releaseScriptDryRunSkipsPublishCommands() throws {
    let script = try releaseScript()
    let dryRunRange = try #require(script.range(of: "if [[ \"$DRY_RUN\" == \"true\" ]]; then"))
    let branchPushRange = try #require(script.range(of: "\n  git push origin \"HEAD:${PUBLISH_BRANCH}\""))

    #expect(dryRunRange.lowerBound < branchPushRange.lowerBound)
}

@Test func releaseScriptBlocksPublishingWhenTestsAreSkipped() throws {
    let script = try releaseScript()

    #expect(script.contains("ensure_tests_run_before_publish"))
    #expect(script.contains("Release publishing cannot use --skip-tests"))
    #expect(script.contains("if [[ \"$PUBLISH\" == \"true\" && \"$DRY_RUN\" != \"true\" && \"$SKIP_TESTS\" == \"true\" ]]; then"))
}

@Test func releaseScriptVerifiesDmgBeforeMounting() throws {
    let script = try releaseScript()
    let verifyRange = try #require(script.range(of: "hdiutil verify \"$DMG_PATH\""))
    let attachRange = try #require(script.range(of: "MOUNT_OUTPUT=\"$(hdiutil attach \"$DMG_PATH\" -nobrowse -readonly)\""))

    #expect(verifyRange.lowerBound < attachRange.lowerBound)
}

@Test func releaseScriptValidatesReleaseNotesVersionMetadata() throws {
    let script = try releaseScript()

    #expect(script.contains("verify_release_notes_metadata"))
    #expect(script.contains("Release notes missing version metadata"))
    #expect(script.contains("Release notes missing DMG name"))
    #expect(script.contains("Release notes missing SHA-256"))
    #expect(script.contains("verify_release_notes_metadata \"$BODY_PATH\" \"$VERSION\" \"$BUILD\" \"$DMG_NAME\" \"$SHA256\""))
}

@Test func releaseScriptVerifiesUploadedAssetHashAfterPublish() throws {
    let script = try releaseScript()
    let releaseCreateRange = try #require(script.range(of: "gh release create \"$TAG\" \"$DMG_PATH\" --title \"$TITLE\" --notes-file \"$BODY_PATH\""))
    let assetHashRange = try #require(script.range(of: "verify_github_release_asset_hash \"$TAG\" \"$DMG_NAME\" \"$SHA256\""))

    #expect(script.contains("gh release download \"$tag\" --pattern \"$asset_name\""))
    #expect(script.contains("GitHub release asset SHA-256 mismatch"))
    #expect(script.contains("Verified GitHub release asset SHA-256"))
    #expect(releaseCreateRange.lowerBound < assetHashRange.lowerBound)
}

@Test func releaseScriptPrintsFreePublishFallbackInstructions() throws {
    let script = try releaseScript()
    let branchPushRange = try #require(script.range(of: "git push origin \"HEAD:${PUBLISH_BRANCH}\""))
    let fallbackRange = try #require(script.range(of: "print_publish_fallback_instructions"))

    #expect(fallbackRange.lowerBound < branchPushRange.lowerBound)
    #expect(script.contains("免费发布失败恢复步骤"))
    #expect(script.contains("gh release create \"$TAG\" \"$DMG_PATH\" --title \"$TITLE\" --notes-file \"$BODY_PATH\""))
    #expect(script.contains("GitHub 网页备用"))
    #expect(script.contains("GitHub API 备用"))
}

@Test func releaseScriptSupportsHumanWrittenNotesFile() throws {
    let script = try releaseScript()

    #expect(script.contains("--notes-file <path>"))
    #expect(script.contains("CUSTOM_NOTES_FILE"))
    #expect(script.contains("resolve_notes_file"))
    #expect(script.contains("Release notes file does not exist"))
    #expect(script.contains("if notes_path:"))
    #expect(script.contains("intro = Path(notes_path).read_text"))
}

@Test func publishCurrentScriptRequiresNotesFileAndRestartsBuiltApp() throws {
    let script = try publishCurrentScript()

    #expect(script.contains("Usage: scripts/publish-current.sh --notes-file <path>"))
    #expect(script.contains("Missing required --notes-file"))
    #expect(script.contains("\"$ROOT_DIR/scripts/release.sh\" --bump none --publish --notes-file \"$NOTES_FILE\""))
    #expect(script.contains("\"$ROOT_DIR/scripts/build-app.sh\" --bump none --preserve-build --run"))
}

@Test func releaseChecklistDocumentsFreeFallbackOnly() throws {
    let checklist = try releaseChecklist()

    #expect(checklist.contains("免费发布失败恢复"))
    #expect(checklist.contains("gh release create"))
    #expect(checklist.contains("GitHub 网页备用"))
    #expect(checklist.contains("GitHub API 备用"))
    #expect(!checklist.contains("notarization"))
    #expect(!checklist.contains("Developer ID"))
}

private func releaseScript() throws -> String {
    let path = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("scripts/release.sh")
    return try String(contentsOf: path, encoding: .utf8)
}

private func releaseChecklist() throws -> String {
    let path = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("docs/releases/release-checklist.md")
    return try String(contentsOf: path, encoding: .utf8)
}

private func publishCurrentScript() throws -> String {
    let path = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("scripts/publish-current.sh")
    return try String(contentsOf: path, encoding: .utf8)
}
