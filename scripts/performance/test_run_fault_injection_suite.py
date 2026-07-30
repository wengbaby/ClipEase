import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "run_fault_injection_suite",
    ROOT / "scripts/performance/run_fault_injection_suite.py",
)
fault_runner = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(fault_runner)


class Completed:
    def __init__(self, returncode: int, stdout: str = "", stderr: str = ""):
        self.returncode = returncode
        self.stdout = stdout
        self.stderr = stderr


class FaultInjectionSuiteTests(unittest.TestCase):
    def test_passed_fault_log_allows_expected_application_failure_message(self):
        test_name = "clipboardMonitorReportsDiskFullWithoutCallingImporter"
        log = (
            "ClipEase failed to stage clipboard payload: diskFull\n"
            f"✔ Test {test_name}() passed after 0.001 seconds.\n"
            "✔ Test run with 1 test in 0 suites passed after 0.001 seconds.\n"
        )

        self.assertTrue(fault_runner.test_log_passed(test_name, log))

    def test_passed_fault_log_rejects_a_swift_testing_failure_marker(self):
        test_name = "clipboardMonitorReportsDiskFullWithoutCallingImporter"
        log = (
            f"✔ Test {test_name}() passed after 0.001 seconds.\n"
            "✘ Test anotherFaultScenario() failed after 0.001 seconds.\n"
            "✘ Test run with 2 tests in 0 suites failed after 0.002 seconds.\n"
        )

        self.assertFalse(fault_runner.test_log_passed(test_name, log))

    def test_suite_runs_every_locked_test_and_writes_hashed_logs(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "source"
            source.mkdir()
            output = root / "evidence" / "fault-injection-report.json"
            subject = "a" * 40
            commands = []

            def runner(arguments, **kwargs):
                commands.append(arguments)
                if arguments[0] == "/usr/bin/git":
                    if "rev-parse" in arguments:
                        return Completed(0, subject + "\n")
                    return Completed(0, "")
                test_name = arguments[-1]
                return Completed(
                    0,
                    f"✔ Test {test_name}() passed after 0.001 seconds.\n"
                    "✔ Test run with 1 test in 0 suites passed after 0.001 seconds.\n",
                )

            decision = fault_runner.run_suite(
                source_root=source,
                output_path=output,
                subject_git_sha=subject,
                command_runner=runner,
            )

            self.assertEqual(decision, "pass")
            report = json.loads(output.read_text())
            self.assertEqual(report["subjectGitSHA"], subject)
            self.assertEqual(
                set(report["scenarios"]),
                set(fault_runner.REQUIRED_FAULT_TESTS),
            )
            swift_commands = [
                command for command in commands if command and command[0] == "swift"
            ]
            self.assertEqual(len(swift_commands), 9)
            self.assertEqual(
                fault_runner.REQUIRED_FAULT_TESTS["imageBurst30x8MiB"],
                "thirtyIndependentEightMiBImagesApplyDeterministicMemoryBackpressure",
            )
            for scenario, test_name in fault_runner.REQUIRED_FAULT_TESTS.items():
                result = report["scenarios"][scenario]
                self.assertEqual(
                    result["command"],
                    fault_runner.test_command(test_name),
                )
                log_path = output.parent / result["log"]["path"]
                self.assertTrue(log_path.is_file())
                self.assertEqual(
                    result["log"]["sha256"],
                    fault_runner.file_sha256(log_path),
                )

    def test_suite_fails_closed_when_a_test_log_has_no_exact_pass_marker(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "source"
            source.mkdir()
            output = root / "evidence" / "fault-injection-report.json"
            subject = "b" * 40

            def runner(arguments, **kwargs):
                if arguments[0] == "/usr/bin/git":
                    if "rev-parse" in arguments:
                        return Completed(0, subject + "\n")
                    return Completed(0, "")
                return Completed(0, "Build complete, but no matching test ran.\n")

            decision = fault_runner.run_suite(
                source_root=source,
                output_path=output,
                subject_git_sha=subject,
                command_runner=runner,
            )

            self.assertEqual(decision, "fail")
            report = json.loads(output.read_text())
            self.assertTrue(
                all(
                    result["status"] == "fail"
                    for result in report["scenarios"].values()
                )
            )

    def test_distinct_reports_use_distinct_non_overwriting_log_directories(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "source"
            source.mkdir()
            subject = "c" * 40

            def runner(arguments, **kwargs):
                if arguments[0] == "/usr/bin/git":
                    if "rev-parse" in arguments:
                        return Completed(0, subject + "\n")
                    return Completed(0, "")
                test_name = arguments[-1]
                return Completed(
                    0,
                    f"✔ Test {test_name}() passed after 0.001 seconds.\n"
                    "✔ Test run with 1 test in 0 suites passed after 0.001 seconds.\n",
                )

            first_output = root / "evidence" / "first-report.json"
            second_output = root / "evidence" / "second-report.json"
            self.assertEqual(
                fault_runner.run_suite(
                    source_root=source,
                    output_path=first_output,
                    subject_git_sha=subject,
                    command_runner=runner,
                ),
                "pass",
            )
            self.assertEqual(
                fault_runner.run_suite(
                    source_root=source,
                    output_path=second_output,
                    subject_git_sha=subject,
                    command_runner=runner,
                ),
                "pass",
            )

            first_report = json.loads(first_output.read_text())
            second_report = json.loads(second_output.read_text())
            first_log = first_output.parent / next(
                iter(first_report["scenarios"].values())
            )["log"]["path"]
            second_log = second_output.parent / next(
                iter(second_report["scenarios"].values())
            )["log"]["path"]
            self.assertNotEqual(first_log.parent, second_log.parent)
            self.assertTrue(first_log.is_file())
            self.assertTrue(second_log.is_file())

    def test_suite_rejects_dirty_or_wrong_source_subject(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "source"
            source.mkdir()

            def wrong_subject(arguments, **kwargs):
                return Completed(0, "c" * 40 + "\n")

            with self.assertRaisesRegex(RuntimeError, "subject"):
                fault_runner.run_suite(
                    source_root=source,
                    output_path=root / "report.json",
                    subject_git_sha="d" * 40,
                    command_runner=wrong_subject,
                )


if __name__ == "__main__":
    unittest.main()
