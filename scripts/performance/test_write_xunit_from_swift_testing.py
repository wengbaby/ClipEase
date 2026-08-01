import importlib.util
import tempfile
import unittest
import xml.etree.ElementTree as ElementTree
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "write_xunit_from_swift_testing",
    ROOT / "scripts/performance/write_xunit_from_swift_testing.py",
)
converter = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(converter)


class SwiftTestingXUnitTests(unittest.TestCase):
    def test_converts_passing_swift_testing_log_with_identity(self):
        log = """\
◇ Test firstCase() started.
✔ Test firstCase() passed after 0.010 seconds.
◇ Test secondCase() started.
✔ Test secondCase() passed after 0.020 seconds.
✔ Test run with 2 tests in 0 suites passed after 0.030 seconds.
"""

        report = converter.build_xunit_document(
            log,
            subject_git_sha="a" * 40,
            command="swift test -c release --no-parallel",
        )
        root = ElementTree.fromstring(report)

        self.assertEqual(root.tag, "testsuites")
        self.assertEqual(root.attrib["subjectGitSHA"], "a" * 40)
        self.assertEqual(
            root.attrib["command"], "swift test -c release --no-parallel"
        )
        self.assertEqual(root.attrib["tests"], "2")
        self.assertEqual(root.attrib["failures"], "0")
        self.assertEqual(root.attrib["errors"], "0")
        self.assertEqual(len(list(root)), 1)
        self.assertEqual(len(list(root[0])), 2)

    def test_converts_failed_swift_testing_log_to_xunit_failure(self):
        log = """\
◇ Test failingCase() started.
✘ Test failingCase() failed after 0.010 seconds.
✔ Test run with 1 test in 0 suites failed after 0.010 seconds.
"""

        report = converter.build_xunit_document(
            log,
            subject_git_sha="b" * 40,
            command="swift test -c release --no-parallel",
        )
        root = ElementTree.fromstring(report)
        suite = root[0]

        self.assertEqual(root.attrib["tests"], "1")
        self.assertEqual(root.attrib["failures"], "1")
        self.assertEqual(suite.attrib["failures"], "1")
        self.assertEqual(suite[0].attrib["name"], "failingCase")
        self.assertEqual(suite[0][0].tag, "failure")

    def test_rejects_missing_summary_or_unfinished_test(self):
        with self.assertRaisesRegex(ValueError, "summary"):
            converter.build_xunit_document(
                "◇ Test unfinished() started.\n",
                subject_git_sha="c" * 40,
                command="swift test -c release --no-parallel",
            )

        with self.assertRaisesRegex(ValueError, "summary count"):
            converter.build_xunit_document(
                """\
◇ Test one() started.
✔ Test one() passed after 0.010 seconds.
✔ Test run with 2 tests in 0 suites passed after 0.010 seconds.
""",
                subject_git_sha="c" * 40,
                command="swift test -c release --no-parallel",
            )

    def test_write_report_creates_parent_and_xml(self):
        log = """\
◇ Test onlyCase() started.
✔ Test onlyCase() passed after 0.010 seconds.
✔ Test run with 1 test in 0 suites passed after 0.010 seconds.
"""
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "nested" / "tests.xml"
            converter.write_xunit_report(
                log,
                output,
                subject_git_sha="d" * 40,
                command="swift test -c release --no-parallel",
            )
            self.assertTrue(output.is_file())
            self.assertEqual(ElementTree.parse(output).getroot().attrib["tests"], "1")


if __name__ == "__main__":
    unittest.main()
