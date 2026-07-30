import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/run-performance-benchmarks.sh"


class PerformanceWrapperTests(unittest.TestCase):
    def test_rejects_override_of_locked_roots_sampling_and_subjects(self):
        for argument in (
            "--baseline-root=/tmp/forged",
            "--candidate-root=/tmp/forged",
            "--warmups=1",
            "--sample-count=1",
            "--baseline-subject-sha=" + "f" * 40,
            "--candidate-only",
        ):
            result = subprocess.run(
                [str(SCRIPT), argument],
                cwd=ROOT,
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 64, argument)
            self.assertIn(
                "Protected benchmark argument cannot be overridden",
                result.stderr,
            )


if __name__ == "__main__":
    unittest.main()
