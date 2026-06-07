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
    let branchPushRange = try #require(script.range(of: "git push origin \"HEAD:${PUBLISH_BRANCH}\""))

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

private func releaseScript() throws -> String {
    let path = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("scripts/release.sh")
    return try String(contentsOf: path, encoding: .utf8)
}
