import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


class ReleaseCoveragePolicyTests(unittest.TestCase):
    def test_release_script_generates_candidate_bound_coverage_evidence(self):
        script = (ROOT / "scripts/release.sh").read_text(encoding="utf-8")

        required_fragments = [
            "swift test -c release --no-parallel --enable-code-coverage",
            "swift test -c release --show-codecov-path --skip-build",
            "swift-code-coverage.json",
            "changed-code-coverage.json",
            "check_changed_code_coverage.py",
            '--repository-root "$ROOT_DIR"',
            '--coverage-json "$COVERAGE_JSON_PATH"',
            '--base-ref "$COVERAGE_BASE_REF"',
            "--minimum-percent 80",
            '--output "$COVERAGE_REPORT_PATH"',
        ]
        for fragment in required_fragments:
            with self.subTest(fragment=fragment):
                self.assertIn(fragment, script)


if __name__ == "__main__":
    unittest.main()
