import importlib.util
import hashlib
import json
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "check_changed_code_coverage",
    ROOT / "scripts/performance/check_changed_code_coverage.py",
)
coverage_gate = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(coverage_gate)


class ChangedCodeCoverageTests(unittest.TestCase):
    def test_receipt_metadata_binds_coverage_bytes_and_worktree_state(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            subprocess.run(["/usr/bin/git", "init", "-q"], cwd=root, check=True)
            subprocess.run(
                ["/usr/bin/git", "config", "user.email", "coverage@example.com"],
                cwd=root,
                check=True,
            )
            subprocess.run(
                ["/usr/bin/git", "config", "user.name", "Coverage Test"],
                cwd=root,
                check=True,
            )
            coverage_path = root / "coverage.json"
            coverage_path.write_text(json.dumps({"data": []}) + "\n")
            subprocess.run(
                ["/usr/bin/git", "add", coverage_path.name],
                cwd=root,
                check=True,
            )
            subprocess.run(["/usr/bin/git", "commit", "-qm", "baseline"], cwd=root, check=True)

            metadata = coverage_gate.receipt_metadata(root, coverage_path, "HEAD")

            self.assertEqual(metadata["baseRef"], "HEAD")
            self.assertEqual(metadata["coverageJSON"], coverage_path.name)
            self.assertEqual(
                metadata["coverageJSONSHA256"],
                hashlib.sha256(coverage_path.read_bytes()).hexdigest(),
            )
            self.assertTrue(metadata["worktreeClean"])

            (root / "untracked.txt").write_text("dirty\n")
            self.assertFalse(
                coverage_gate.receipt_metadata(root, coverage_path, "HEAD")[
                    "worktreeClean"
                ]
            )

    def test_subject_git_sha_reads_current_head(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            subprocess.run(["/usr/bin/git", "init", "-q"], cwd=root, check=True)
            subprocess.run(
                ["/usr/bin/git", "config", "user.email", "coverage@example.com"],
                cwd=root,
                check=True,
            )
            subprocess.run(
                ["/usr/bin/git", "config", "user.name", "Coverage Test"],
                cwd=root,
                check=True,
            )
            source = root / "Sources/ClipEase/Tracked.swift"
            source.parent.mkdir(parents=True)
            source.write_text("let tracked = true\n")
            subprocess.run(
                ["/usr/bin/git", "add", source.relative_to(root).as_posix()],
                cwd=root,
                check=True,
            )
            subprocess.run(["/usr/bin/git", "commit", "-qm", "baseline"], cwd=root, check=True)

            expected = subprocess.run(
                ["/usr/bin/git", "rev-parse", "HEAD"],
                cwd=root,
                check=True,
                capture_output=True,
                text=True,
            ).stdout.strip()
            self.assertEqual(coverage_gate.subject_git_sha(root), expected)

    def test_git_diff_includes_untracked_production_swift_files(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            subprocess.run(
                ["/usr/bin/git", "init", "-q"],
                cwd=root,
                check=True,
            )
            subprocess.run(
                ["/usr/bin/git", "config", "user.email", "coverage@example.com"],
                cwd=root,
                check=True,
            )
            subprocess.run(
                ["/usr/bin/git", "config", "user.name", "Coverage Test"],
                cwd=root,
                check=True,
            )
            tracked = root / "Sources/ClipEase/Tracked.swift"
            tracked.parent.mkdir(parents=True)
            tracked.write_text("let tracked = true\n")
            subprocess.run(
                ["/usr/bin/git", "add", tracked.relative_to(root).as_posix()],
                cwd=root,
                check=True,
            )
            subprocess.run(
                ["/usr/bin/git", "commit", "-qm", "baseline"],
                cwd=root,
                check=True,
            )
            untracked = root / "Sources/ClipEase/Untracked.swift"
            untracked.write_text("let untracked = true\n")

            diff = coverage_gate.git_diff(root, "HEAD")
            changed = coverage_gate.changed_lines_from_diff(diff)

            self.assertEqual(
                changed["Sources/ClipEase/Untracked.swift"],
                {1},
            )

    def test_counts_only_executable_changed_production_lines(self):
        diff = """\
diff --git a/Sources/ClipEase/A.swift b/Sources/ClipEase/A.swift
--- a/Sources/ClipEase/A.swift
+++ b/Sources/ClipEase/A.swift
@@ -1,0 +2,4 @@
+one
+two
+three
+four
diff --git a/Tests/ClipEaseTests/A.swift b/Tests/ClipEaseTests/A.swift
--- a/Tests/ClipEaseTests/A.swift
+++ b/Tests/ClipEaseTests/A.swift
@@ -1,0 +1,2 @@
+test
+test
"""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "Sources/ClipEase/A.swift"
            source.parent.mkdir(parents=True)
            source.write_text("source")
            coverage = {
                "data": [{
                    "files": [{
                        "filename": str(source),
                        "segments": [
                            [2, 1, 1, True, True, False],
                            [3, 1, 0, True, True, False],
                            [4, 1, 1, False, False, False],
                            [5, 1, 9, True, True, True],
                        ],
                    }],
                }],
            }

            changed = coverage_gate.changed_lines_from_diff(diff)
            lines = coverage_gate.executable_line_counts(coverage, root)
            report = coverage_gate.build_report(changed, lines, 80)

            self.assertEqual(report["changedExecutableLineCount"], 2)
            self.assertEqual(report["coveredChangedExecutableLineCount"], 1)
            self.assertEqual(report["changedCodeCoveragePercent"], 50)
            self.assertEqual(
                report["files"]["Sources/ClipEase/A.swift"]["uncoveredLines"],
                [3],
            )
            self.assertEqual(report["decision"], "fail")

    def test_passes_at_exactly_eighty_percent_and_fails_closed_without_lines(self):
        changed = {"Sources/A.swift": {1, 2, 3, 4, 5}}
        coverage = {"Sources/A.swift": {1: 1, 2: 1, 3: 1, 4: 1, 5: 0}}

        report = coverage_gate.build_report(changed, coverage, 80)
        empty = coverage_gate.build_report({}, {}, 80)

        self.assertEqual(report["decision"], "pass")
        self.assertEqual(report["changedCodeCoveragePercent"], 80)
        self.assertEqual(empty["decision"], "fail")


if __name__ == "__main__":
    unittest.main()
