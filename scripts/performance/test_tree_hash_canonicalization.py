import importlib.util
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def load_module(name: str, file_name: str):
    spec = importlib.util.spec_from_file_location(
        name,
        ROOT / "scripts/performance" / file_name,
    )
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


fixture_generator = load_module("fixture_generator", "generate_fixtures.py")
report_writer = load_module("report_writer", "write_benchmark_report.py")
runtime_writer = load_module("runtime_writer", "write_runtime_evidence.py")
certification_validator = load_module(
    "certification_validator",
    "validate_release_certification.py",
)


class TreeHashCanonicalizationTests(unittest.TestCase):
    def test_every_evidence_stage_uses_relative_posix_path_order(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "A3K"
            (root / "assets/heic").mkdir(parents=True)
            (root / "assets/png").mkdir(parents=True)
            (root / "assets.jsonl").write_text("manifest\n")
            (root / "assets/heic/000001.heic").write_bytes(b"heic")
            (root / "assets/png/000002.png").write_bytes(b"png")

            expected = fixture_generator.tree_sha256(root)

            self.assertEqual(report_writer.tree_sha256(root), expected)
            self.assertEqual(runtime_writer.tree_sha256(root), expected)
            self.assertEqual(certification_validator.tree_sha256(root), expected)


if __name__ == "__main__":
    unittest.main()
