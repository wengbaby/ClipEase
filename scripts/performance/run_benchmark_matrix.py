#!/usr/bin/env python3
"""Run Release ClipEase benchmarks, optionally interleaving two worktrees."""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
import re
import shutil
import signal
import sqlite3
import subprocess
import sys
import tempfile
import threading
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


HARNESS_ROOT = Path(__file__).resolve().parents[2]
RUNTIME_EVIDENCE_SPEC = importlib.util.spec_from_file_location(
    "_clipease_matrix_runtime_evidence",
    Path(__file__).with_name("write_runtime_evidence.py"),
)
if RUNTIME_EVIDENCE_SPEC is None or RUNTIME_EVIDENCE_SPEC.loader is None:
    raise RuntimeError("could not load runtime evidence validators")
RUNTIME_EVIDENCE = importlib.util.module_from_spec(RUNTIME_EVIDENCE_SPEC)
RUNTIME_EVIDENCE_SPEC.loader.exec_module(RUNTIME_EVIDENCE)
DRIVER_FILTER = "enterprisePerformanceBenchmarkDriver"
LOCKED_BASELINE_SUBJECT_GIT_SHA = "ad4013cce2a4e0a1648de2277126c736c0700b39"
DIAGNOSTICS_STORE_COLUMNS = {
    "id",
    "timestamp",
    "name",
    "category",
    "duration_ms",
    "item_count",
    "result_count",
    "payload",
    "payload_bytes",
}
DIAGNOSTICS_PAYLOAD_FIELDS = {
    "id",
    "timestamp",
    "name",
    "category",
    "durationMS",
    "metadata",
    "isMainThread",
}
ANSI_ESCAPE_PATTERN = re.compile(
    r"\x1B(?:\][^\x07]*(?:\x07|\x1B\\)|"
    r"\[[0-?]*[ -/]*[@-~]|[@-_])"
)
CONTROL_CHARACTER_PATTERN = re.compile(
    r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]"
)
FILE_URL_PATTERN = re.compile(r"file:///[^\r\n]*")
ABSOLUTE_PATH_PATTERN = re.compile(r"(?<![A-Za-z0-9._/-])/[^\r\n]*")
PERSISTED_FAILURE_LOG_MAX_BYTES = 64 * 1024
PERSISTED_FAILURE_SECTION_MAX_BYTES = 20 * 1024
SUBPROCESS_OUTPUT_LIMIT_BYTES = 1 * 1024 * 1024
SUBPROCESS_READ_CHUNK_BYTES = 64 * 1024
SUBPROCESS_POLL_INTERVAL_SECONDS = 0.01
SUBPROCESS_TERMINATION_GRACE_SECONDS = 0.5


def command_output(arguments: list[str], cwd: Path | None = None) -> str:
    try:
        result = run_bounded_process(
            arguments,
            cwd=cwd or Path.cwd(),
            environment=None,
            timeout=30,
        )
    except OSError:
        return "unavailable"
    if result.returncode != 0 or result.termination_reason is not None:
        return "unavailable"
    stdout = result.stdout.decode("utf-8", errors="replace")
    return " ".join(stdout.strip().split()) or "unavailable"


def sysctl_value(name: str) -> str:
    return command_output(["/usr/sbin/sysctl", "-n", name])


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def validate_detailed_local_diagnostics_store(path: Path) -> int:
    if not path.is_file():
        raise RuntimeError(
            f"detailedLocal diagnostics store does not exist: {path}"
        )
    connection: sqlite3.Connection | None = None
    try:
        connection = sqlite3.connect(
            path.resolve().as_uri() + "?mode=ro",
            uri=True,
        )
        if connection.execute("PRAGMA quick_check").fetchone() != ("ok",):
            raise RuntimeError("detailedLocal diagnostics store failed quick_check")
        columns = {
            row[1]
            for row in connection.execute(
                "PRAGMA table_info(performance_events)"
            )
        }
        if columns != DIAGNOSTICS_STORE_COLUMNS:
            raise RuntimeError(
                "detailedLocal diagnostics store schema does not match ClipEase"
            )
        rows = connection.execute(
            "SELECT payload, payload_bytes FROM performance_events"
        ).fetchall()
        if not rows:
            raise RuntimeError(
                "detailedLocal diagnostics store contains no captured events"
            )
        for payload_text, payload_bytes in rows:
            payload = json.loads(payload_text)
            if (
                not isinstance(payload, dict)
                or not DIAGNOSTICS_PAYLOAD_FIELDS.issubset(payload)
                or payload_bytes != len(payload_text.encode("utf-8"))
            ):
                raise RuntimeError(
                    "detailedLocal diagnostics event payload is invalid"
                )
        return len(rows)
    except (json.JSONDecodeError, sqlite3.Error) as error:
        raise RuntimeError(
            f"detailedLocal diagnostics store is invalid: {error}"
        ) from error
    finally:
        if connection is not None:
            connection.close()


def snapshot_detailed_local_diagnostics_store(
    source: Path,
    destination: Path,
) -> None:
    validate_detailed_local_diagnostics_store(source)
    if destination.exists():
        raise RuntimeError(
            f"refusing to replace diagnostics snapshot: {destination}"
        )
    destination.parent.mkdir(parents=True, exist_ok=True)
    source_connection: sqlite3.Connection | None = None
    destination_connection: sqlite3.Connection | None = None
    try:
        source_connection = sqlite3.connect(
            source.resolve().as_uri() + "?mode=ro",
            uri=True,
        )
        destination_connection = sqlite3.connect(destination)
        source_connection.backup(destination_connection)
        destination_connection.commit()
    except sqlite3.Error as error:
        raise RuntimeError(
            f"could not snapshot detailedLocal diagnostics store: {error}"
        ) from error
    finally:
        if destination_connection is not None:
            destination_connection.close()
        if source_connection is not None:
            source_connection.close()
    destination.chmod(0o600)
    validate_detailed_local_diagnostics_store(destination)


def git_worktree_status(root: Path) -> list[str]:
    try:
        result = run_bounded_process(
            [
                "/usr/bin/git",
                "status",
                "--porcelain",
                "--untracked-files=all",
            ],
            cwd=root,
            environment=None,
            timeout=30,
        )
    except OSError:
        raise RuntimeError("could not inspect Git worktree status") from None
    if result.returncode != 0 or result.termination_reason is not None:
        raise RuntimeError("could not inspect Git worktree status")
    stdout = result.stdout.decode("utf-8", errors="replace")
    return [line for line in stdout.splitlines() if line]


def hardware_environment() -> dict[str, str]:
    return {
        "model": sysctl_value("hw.model"),
        "chip": sysctl_value("machdep.cpu.brand_string"),
        "memoryBytes": sysctl_value("hw.memsize"),
        "physicalCPUCount": sysctl_value("hw.physicalcpu"),
    }


def os_environment() -> dict[str, str]:
    return {
        "productVersion": command_output(["/usr/bin/sw_vers", "-productVersion"]),
        "buildVersion": command_output(["/usr/bin/sw_vers", "-buildVersion"]),
    }


def normalized_power_state(output: str) -> str:
    for state in ("AC Power", "Battery Power"):
        if f"'{state}'" in output:
            return state
    return "unavailable"


def normalized_thermal_state(output: str) -> str:
    normalized = " ".join(output.split())
    if not normalized or normalized == "unavailable":
        return "unavailable"
    limits = [
        int(value)
        for value in re.findall(
            r"(?:CPU_Speed_Limit|Scheduler_Limit)\s*=\s*(\d+)",
            normalized,
        )
    ]
    if limits:
        return "nominal" if all(value >= 100 for value in limits[:2]) else "constrained"
    lowered = normalized.lower()
    if "warning level" in lowered and "no thermal warning level" not in lowered:
        return "constrained"
    if "performance warning" in lowered and "no performance warning" not in lowered:
        return "constrained"
    if "no thermal warning level" in lowered and "no performance warning level" in lowered:
        return "nominal"
    return "unavailable"


def measurement_environment(
    *,
    hardware: dict[str, str] | None = None,
    operating_system: dict[str, str] | None = None,
) -> dict[str, Any]:
    return {
        "hardware": hardware or hardware_environment(),
        "os": operating_system or os_environment(),
        "powerState": normalized_power_state(
            command_output(["/usr/bin/pmset", "-g", "batt"])
        ),
        "thermalState": normalized_thermal_state(
            command_output(["/usr/bin/pmset", "-g", "therm"])
        ),
    }


def validate_measurement_environment(environment: dict[str, Any]) -> None:
    hardware = environment.get("hardware")
    operating_system = environment.get("os")
    if not isinstance(hardware, dict) or not hardware:
        raise RuntimeError("hardware metadata is unavailable")
    if not isinstance(operating_system, dict) or not operating_system:
        raise RuntimeError("operating-system metadata is unavailable")
    values = [*hardware.values(), *operating_system.values()]
    if any(str(value).strip() in ("", "unavailable") for value in values):
        raise RuntimeError("measurement metadata contains unavailable values")
    if environment.get("powerState") != "AC Power":
        raise RuntimeError("enterprise benchmarks require stable AC power")
    if environment.get("thermalState") != "nominal":
        raise RuntimeError("enterprise benchmarks require nominal thermal state")


def assert_environment_stable(
    expected: dict[str, Any],
    actual: dict[str, Any],
) -> None:
    validate_measurement_environment(actual)
    if actual != expected:
        raise RuntimeError(
            "measurement environment changed during benchmark run: "
            f"expected={expected!r}, actual={actual!r}"
        )


def interleaved_versions(versions: list[str], iteration: int) -> list[str]:
    if len(versions) < 2 or iteration % 2 == 0:
        return list(versions)
    return list(reversed(versions))


def output_relative_path(path: Path, output_root: Path, label: str) -> str:
    try:
        return path.resolve().relative_to(output_root.resolve()).as_posix()
    except ValueError as error:
        raise RuntimeError(f"{label} is outside the output root") from error


def output_summary(
    *,
    output_root: Path,
    run_id: str,
    runs: dict[str, "VersionRun"],
    comparison_path: Path | None,
    runtime_evidence_path: Path | None,
) -> dict[str, Any]:
    return {
        "runID": run_id,
        "outputRoot": ".",
        "reports": {
            name: output_relative_path(
                version.report_path,
                output_root,
                f"{name} report",
            )
            for name, version in runs.items()
        },
        "comparison": (
            output_relative_path(
                comparison_path,
                output_root,
                "comparison",
            )
            if comparison_path
            else None
        ),
        "runtimeEvidence": (
            output_relative_path(
                runtime_evidence_path,
                output_root,
                "runtime evidence",
            )
            if runtime_evidence_path
            else None
        ),
    }


class VersionRun:
    def __init__(
        self,
        name: str,
        root: Path,
        output_root: Path,
        fixture_root: Path,
        manifest_path: Path,
        trace_path: Path | None,
        subject_git_sha: str | None,
    ) -> None:
        self.name = name
        self.root = root.resolve()
        self.output_root = output_root / name
        self.fixture_root = fixture_root
        self.manifest_path = manifest_path
        self.work_root = self.output_root / "work"
        self.raw_output = self.output_root / "raw-samples.jsonl"
        self.report_path = output_root / f"{name}-benchmark-report.json"
        self.trace_path = trace_path.resolve() if trace_path else None
        self.subject_git_sha = subject_git_sha

    def environment(self, action: str, iteration: int | None = None) -> dict[str, str]:
        environment = dict(os.environ)
        environment.update(
            {
                "CLIPEASE_PERFORMANCE_FIXTURE_MANIFEST": str(self.manifest_path),
                "CLIPEASE_PERFORMANCE_FIXTURE_ROOT": str(self.fixture_root),
                "CLIPEASE_BENCHMARK_WORK_ROOT": str(self.work_root),
                "CLIPEASE_BENCHMARK_RAW_OUTPUT": str(self.raw_output),
                "CLIPEASE_BENCHMARK_ACTION": action,
            }
        )
        if iteration is not None:
            environment["CLIPEASE_BENCHMARK_ITERATION"] = str(iteration)
        else:
            environment.pop("CLIPEASE_BENCHMARK_ITERATION", None)
        return environment


class BoundedProcessResult:
    def __init__(
        self,
        *,
        returncode: int,
        stdout: bytes,
        stderr: bytes,
        termination_reason: str | None,
    ):
        self.returncode = returncode
        self.stdout = stdout
        self.stderr = stderr
        self.termination_reason = termination_reason


class HeadTailByteBuffer:
    def __init__(self, maximum_bytes: int):
        self._head_limit = maximum_bytes // 2
        self._tail_limit = maximum_bytes - self._head_limit
        self._head = bytearray()
        self._tail = bytearray()
        self._total_bytes = 0

    def append(self, chunk: bytes) -> None:
        self._total_bytes += len(chunk)
        head_remaining = self._head_limit - len(self._head)
        if head_remaining > 0:
            self._head.extend(chunk[:head_remaining])
            chunk = chunk[head_remaining:]
        if chunk:
            self._tail.extend(chunk)
            overflow = len(self._tail) - self._tail_limit
            if overflow > 0:
                del self._tail[:overflow]

    def value(self) -> bytes:
        stored_bytes = len(self._head) + len(self._tail)
        marker = (
            b"\n<...truncated...>\n"
            if self._total_bytes > stored_bytes
            else b""
        )
        return bytes(self._head) + marker + bytes(self._tail)


class SharedOutputBudget:
    def __init__(self, maximum_bytes: int):
        self._maximum_bytes = maximum_bytes
        self._total_bytes = 0
        self._lock = threading.Lock()
        self.exceeded = threading.Event()

    def record(self, byte_count: int) -> None:
        with self._lock:
            self._total_bytes += byte_count
            if self._total_bytes > self._maximum_bytes:
                self.exceeded.set()


def drain_process_stream(
    stream: Any,
    capture: HeadTailByteBuffer,
    budget: SharedOutputBudget,
) -> None:
    try:
        while True:
            chunk = stream.read(SUBPROCESS_READ_CHUNK_BYTES)
            if not chunk:
                return
            capture.append(chunk)
            budget.record(len(chunk))
    except (OSError, ValueError):
        return
    finally:
        try:
            stream.close()
        except OSError:
            pass


def process_group_exists(process_group_id: int) -> bool:
    try:
        os.killpg(process_group_id, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True


def terminate_process_group(process: subprocess.Popen[Any]) -> None:
    process_group_id = process.pid
    try:
        os.killpg(process_group_id, signal.SIGTERM)
    except ProcessLookupError:
        pass

    deadline = time.monotonic() + SUBPROCESS_TERMINATION_GRACE_SECONDS
    while (
        process_group_exists(process_group_id)
        and time.monotonic() < deadline
    ):
        process.poll()
        time.sleep(SUBPROCESS_POLL_INTERVAL_SECONDS)

    if process_group_exists(process_group_id):
        try:
            os.killpg(process_group_id, signal.SIGKILL)
        except ProcessLookupError:
            pass
    try:
        process.wait(timeout=SUBPROCESS_TERMINATION_GRACE_SECONDS)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait()


def run_bounded_process(
    arguments: list[str],
    cwd: Path,
    environment: dict[str, str] | None,
    timeout: float,
) -> BoundedProcessResult:
    process = subprocess.Popen(
        arguments,
        cwd=cwd,
        env=environment,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=False,
        bufsize=0,
        start_new_session=True,
        close_fds=True,
    )
    if process.stdout is None or process.stderr is None:
        terminate_process_group(process)
        raise RuntimeError("controlled subprocess pipes were not created")

    stdout_capture = HeadTailByteBuffer(PERSISTED_FAILURE_SECTION_MAX_BYTES)
    stderr_capture = HeadTailByteBuffer(PERSISTED_FAILURE_SECTION_MAX_BYTES)
    output_budget = SharedOutputBudget(SUBPROCESS_OUTPUT_LIMIT_BYTES)
    readers = [
        threading.Thread(
            target=drain_process_stream,
            args=(process.stdout, stdout_capture, output_budget),
            daemon=True,
        ),
        threading.Thread(
            target=drain_process_stream,
            args=(process.stderr, stderr_capture, output_budget),
            daemon=True,
        ),
    ]
    for reader in readers:
        reader.start()

    deadline = time.monotonic() + timeout
    termination_reason: str | None = None
    while process.poll() is None:
        if output_budget.exceeded.is_set():
            termination_reason = "output-limit"
            break
        if time.monotonic() >= deadline:
            termination_reason = "timeout"
            break
        time.sleep(SUBPROCESS_POLL_INTERVAL_SECONDS)

    if termination_reason is not None:
        terminate_process_group(process)
    else:
        process.wait()

    for reader in readers:
        reader.join(timeout=SUBPROCESS_TERMINATION_GRACE_SECONDS)
    if any(reader.is_alive() for reader in readers):
        terminate_process_group(process)
        for stream in (process.stdout, process.stderr):
            try:
                stream.close()
            except OSError:
                pass
        for reader in readers:
            reader.join(timeout=SUBPROCESS_TERMINATION_GRACE_SECONDS)
    if output_budget.exceeded.is_set():
        termination_reason = "output-limit"

    return BoundedProcessResult(
        returncode=process.returncode,
        stdout=stdout_capture.value(),
        stderr=stderr_capture.value(),
        termination_reason=termination_reason,
    )


def run_checked(
    arguments: list[str],
    cwd: Path,
    environment: dict[str, str] | None,
    timeout: float,
    failure_log: Path,
    accepted_returncodes: frozenset[int] = frozenset({0}),
) -> int:
    private_roots = (cwd, failure_log.parent)
    try:
        result = run_bounded_process(
            arguments,
            cwd=cwd,
            environment=environment,
            timeout=timeout,
        )
    except OSError as error:
        persist_command_failure(
            arguments=arguments,
            status="LAUNCH FAILED",
            stdout=b"",
            stderr=f"{type(error).__name__}: {error}",
            failure_log=failure_log,
            private_roots=private_roots,
        )
        raise RuntimeError(
            f"command could not start; see {failure_log.name}"
        ) from None

    if result.termination_reason == "timeout":
        persist_command_failure(
            arguments=arguments,
            status=f"TIMEOUT AFTER {timeout} SECONDS",
            stdout=result.stdout,
            stderr=result.stderr,
            failure_log=failure_log,
            private_roots=private_roots,
        )
        raise RuntimeError(
            f"command timed out after {timeout} seconds; "
            f"see {failure_log.name}"
        )
    if result.termination_reason == "output-limit":
        persist_command_failure(
            arguments=arguments,
            status=(
                "OUTPUT LIMIT EXCEEDED "
                f"({SUBPROCESS_OUTPUT_LIMIT_BYTES} BYTES)"
            ),
            stdout=result.stdout,
            stderr=result.stderr,
            failure_log=failure_log,
            private_roots=private_roots,
        )
        raise RuntimeError(
            f"command exceeded the output limit; see {failure_log.name}"
        )
    if result.returncode in accepted_returncodes:
        return result.returncode

    persist_command_failure(
        arguments=arguments,
        status=f"EXIT CODE {result.returncode}",
        stdout=result.stdout,
        stderr=result.stderr,
        failure_log=failure_log,
        private_roots=private_roots,
    )
    raise RuntimeError(
        f"command failed with exit code {result.returncode}; "
        f"see {failure_log.name}"
    )


def persisted_failure_text(
    value: object,
    private_roots: tuple[Path, ...],
) -> str:
    if isinstance(value, bytes):
        text = value.decode("utf-8", errors="replace")
    else:
        text = str(value)
    text = ANSI_ESCAPE_PATTERN.sub("", text)
    text = CONTROL_CHARACTER_PATTERN.sub("", text)
    root_strings = sorted(
        {str(root.resolve()) for root in private_roots},
        key=len,
        reverse=True,
    )
    for root in root_strings:
        text = text.replace(root, "<absolute-path>")
    text = FILE_URL_PATTERN.sub("<absolute-path>", text)
    return ABSOLUTE_PATH_PATTERN.sub("<absolute-path>", text)


def bounded_utf8_text(value: str, maximum_bytes: int) -> str:
    encoded = value.encode("utf-8")
    if len(encoded) <= maximum_bytes:
        return value
    marker = b"\n<...truncated...>\n"
    content_budget = maximum_bytes - len(marker)
    head_budget = content_budget // 2
    tail_budget = content_budget - head_budget
    return (
        encoded[:head_budget].decode("utf-8", errors="ignore")
        + marker.decode("ascii")
        + encoded[-tail_budget:].decode("utf-8", errors="ignore")
    )


def persist_command_failure(
    *,
    arguments: list[str],
    status: str,
    stdout: object,
    stderr: object,
    failure_log: Path,
    private_roots: tuple[Path, ...],
) -> None:
    command_text = bounded_utf8_text(
        persisted_failure_text(" ".join(arguments), private_roots),
        PERSISTED_FAILURE_SECTION_MAX_BYTES,
    )
    stdout_text = bounded_utf8_text(
        persisted_failure_text(stdout, private_roots),
        PERSISTED_FAILURE_SECTION_MAX_BYTES,
    )
    stderr_text = bounded_utf8_text(
        persisted_failure_text(stderr, private_roots),
        PERSISTED_FAILURE_SECTION_MAX_BYTES,
    )
    document = (
        f"STATUS\n{status}\n\n"
        f"COMMAND\n{command_text}\n\n"
        f"STDOUT\n{stdout_text}\n\n"
        f"STDERR\n{stderr_text}"
    )
    document = bounded_utf8_text(
        document,
        PERSISTED_FAILURE_LOG_MAX_BYTES,
    )
    failure_log.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    failure_log.parent.chmod(0o700)
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{failure_log.name}.",
        dir=failure_log.parent,
    )
    temporary_path = Path(temporary_name)
    try:
        os.fchmod(descriptor, 0o600)
        with os.fdopen(descriptor, "wb") as stream:
            descriptor = -1
            stream.write(document.encode("utf-8"))
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary_path, failure_log)
        failure_log.chmod(0o600)
    finally:
        if descriptor >= 0:
            os.close(descriptor)
        temporary_path.unlink(missing_ok=True)


def ensure_harness_available(version: VersionRun) -> None:
    driver = version.root / "Tests/ClipEaseTests/EnterprisePerformanceBenchmarkDriverTests.swift"
    if not driver.is_file():
        raise RuntimeError(
            f"{version.name} worktree does not contain the benchmark driver: {driver}"
        )


def validate_version_subject(version: VersionRun) -> None:
    actual = command_output(
        ["/usr/bin/git", "rev-parse", "HEAD"],
        cwd=version.root,
    )
    if version.subject_git_sha is None or actual != version.subject_git_sha:
        raise RuntimeError(
            f"{version.name} subject SHA mismatch: "
            f"expected={version.subject_git_sha!r}, actual={actual!r}"
        )
    if (
        version.name == "baseline"
        and actual != LOCKED_BASELINE_SUBJECT_GIT_SHA
    ):
        raise RuntimeError(
            "baseline worktree is not the locked ad4013c performance baseline"
        )


def build(version: VersionRun) -> None:
    version.output_root.mkdir(parents=True, exist_ok=True)
    run_checked(
        [
            "swift",
            "test",
            "-c",
            "release",
            "--filter",
            DRIVER_FILTER,
        ],
        cwd=version.root,
        environment=None,
        timeout=900,
        failure_log=version.output_root / "build-failure.log",
    )


def run_driver(version: VersionRun, action: str, iteration: int | None = None) -> None:
    run_checked(
        [
            "swift",
            "test",
            "-c",
            "release",
            "--skip-build",
            "--filter",
            DRIVER_FILTER,
        ],
        cwd=version.root,
        environment=version.environment(action, iteration),
        timeout=900 if action == "prepare" else 180,
        failure_log=version.output_root / f"{action}-failure.log",
    )


def collect_trace(
    version: VersionRun,
    run_id: str,
) -> tuple[str, Path | None]:
    if version.trace_path is None:
        return "not-collected", None
    if not version.trace_path.exists():
        raise RuntimeError(f"trace path does not exist: {version.trace_path}")
    if version.trace_path.suffix != ".trace":
        raise RuntimeError(f"trace artifact must use the .trace suffix: {version.trace_path}")
    manifest_path = version.trace_path / "clipease-trace-manifest.json"
    try:
        manifest = json.loads(manifest_path.read_text())
    except (OSError, json.JSONDecodeError) as error:
        raise RuntimeError(
            f"trace manifest is unavailable or invalid: {manifest_path}"
        ) from error
    if manifest.get("schemaVersion") != 2:
        raise RuntimeError("trace manifest schemaVersion must be 2")
    if manifest.get("runID") != run_id:
        raise RuntimeError("trace manifest runID does not match the benchmark matrix")
    if manifest.get("subjectGitSHA") != version.subject_git_sha:
        raise RuntimeError(
            "trace manifest subjectGitSHA does not match the benchmark subject"
        )
    if manifest.get("targetProcess") != "ClipEase":
        raise RuntimeError("trace manifest targetProcess must be ClipEase")
    if "targetPID" in manifest or "hostAbsolutePath" in manifest:
        raise RuntimeError("trace manifest contains a forbidden host field")
    if set(manifest) != RUNTIME_EVIDENCE.TRACE_MANIFEST_FIELDS:
        raise RuntimeError("trace manifest fields do not match schema")
    executable = manifest.get("executable")
    if (
        not isinstance(executable, dict)
        or set(executable) != RUNTIME_EVIDENCE.TRACE_EXECUTABLE_FIELDS
    ):
        raise RuntimeError("trace executable fields do not match schema")
    traces = manifest.get("traces")
    if (
        not isinstance(traces, list)
        or any(
            not isinstance(trace, dict)
            or not RUNTIME_EVIDENCE.TRACE_ENTRY_REQUIRED_FIELDS <= set(trace)
            or not set(trace) <= RUNTIME_EVIDENCE.TRACE_ENTRY_ALLOWED_FIELDS
            for trace in traces
        )
    ):
        raise RuntimeError("trace entry fields do not match schema")
    destination = version.output_root / "artifacts" / version.trace_path.name
    destination.parent.mkdir(parents=True, exist_ok=True)
    if version.trace_path.is_dir():
        shutil.copytree(version.trace_path, destination)
    else:
        shutil.copy2(version.trace_path, destination)
    return "available", destination


def write_report(
    version: VersionRun,
    run_id: str,
    warmups: int,
    sample_count: int,
    environment: dict[str, Any],
) -> Path | None:
    trace_status, trace_path = collect_trace(version, run_id)
    git_sha = command_output(["/usr/bin/git", "rev-parse", "HEAD"], cwd=version.root)
    subject_git_sha = version.subject_git_sha or git_sha
    harness_path = (
        version.root
        / "Tests/ClipEaseTests/EnterprisePerformanceBenchmarkDriverTests.swift"
    )
    hardware = json.dumps(
        environment["hardware"],
        sort_keys=True,
        separators=(",", ":"),
    )
    operating_system = json.dumps(
        environment["os"],
        sort_keys=True,
        separators=(",", ":"),
    )
    arguments = [
        sys.executable,
        str(HARNESS_ROOT / "scripts/performance/write_benchmark_report.py"),
        "--samples",
        str(version.raw_output),
        "--fixtures",
        str(version.manifest_path),
        "--fixture-root",
        str(version.fixture_root),
        "--output",
        str(version.report_path),
        "--run-id",
        run_id,
        "--git-sha",
        git_sha,
        "--subject-git-sha",
        subject_git_sha,
        "--harness-sha256",
        file_sha256(harness_path),
        "--worktree-status",
        json.dumps(git_worktree_status(version.root), separators=(",", ":")),
        "--hardware",
        hardware,
        "--os",
        operating_system,
        "--power-state",
        str(environment["powerState"]),
        "--thermal-state",
        str(environment["thermalState"]),
        "--warmups",
        str(warmups),
        "--sample-count",
        str(sample_count),
        "--raw-artifact",
        str(version.raw_output),
        "--trace-status",
        trace_status,
    ]
    if trace_path is not None:
        arguments.extend(["--trace-path", str(trace_path)])
    run_checked(
        arguments,
        cwd=HARNESS_ROOT,
        environment=None,
        timeout=120,
        failure_log=version.output_root / "report-failure.log",
    )
    return trace_path


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--candidate-root", required=True, type=Path)
    parser.add_argument("--baseline-root", type=Path)
    parser.add_argument("--candidate-only", action="store_true")
    parser.add_argument("--baseline-subject-sha")
    parser.add_argument("--candidate-subject-sha")
    parser.add_argument("--output-root", type=Path)
    parser.add_argument("--candidate-trace", type=Path)
    parser.add_argument("--baseline-trace", type=Path)
    parser.add_argument("--runtime-samples", type=Path)
    parser.add_argument("--baseline-poi-export", type=Path)
    parser.add_argument("--candidate-poi-export", type=Path)
    parser.add_argument("--baseline-diagnostics-export", type=Path)
    parser.add_argument("--candidate-diagnostics-export", type=Path)
    parser.add_argument("--warmups", required=True, type=int)
    parser.add_argument("--sample-count", required=True, type=int)
    parser.add_argument(
        "--profile",
        choices=("daily-relative", "m1-8gb-release"),
        default="daily-relative",
    )
    parser.add_argument("--require-trace", action="store_true")
    parser.add_argument("--run-id")
    return parser.parse_args()


def validate_arguments(args: argparse.Namespace) -> None:
    if args.warmups != 5 or args.sample_count != 30:
        raise SystemExit("enterprise benchmark contract requires exactly 5 warmups and 30 samples")
    if args.candidate_only and args.baseline_root is not None:
        raise SystemExit("--candidate-only cannot be combined with --baseline-root")
    if not args.candidate_only and args.baseline_root is None:
        raise SystemExit(
            "a baseline worktree is required; use --candidate-only only for non-gating diagnostics"
        )
    if args.profile == "m1-8gb-release" and args.candidate_only:
        raise SystemExit("M1 release certification cannot run candidate-only")
    if not args.candidate_only and (
        args.baseline_subject_sha is None
        or args.candidate_subject_sha is None
    ):
        raise SystemExit(
            "gating runs require explicit baseline and candidate subject SHAs"
        )
    if (args.require_trace or args.profile == "m1-8gb-release") and (
        args.candidate_trace is None
        or (not args.candidate_only and args.baseline_trace is None)
    ):
        raise SystemExit(
            "trace-gated runs require candidate and baseline .trace artifacts"
        )
    if (
        (args.require_trace or args.profile == "m1-8gb-release")
        and args.run_id is None
    ):
        raise SystemExit(
            "trace-gated runs require an explicit --run-id shared with trace capture"
        )
    if args.profile == "m1-8gb-release" and args.runtime_samples is None:
        raise SystemExit(
            "M1 release certification requires externally captured runtime samples"
        )
    if args.profile == "m1-8gb-release" and (
        args.baseline_poi_export is None
        or args.candidate_poi_export is None
    ):
        raise SystemExit(
            "M1 release certification requires baseline and candidate POI exports"
        )
    if args.profile == "m1-8gb-release" and (
        args.baseline_diagnostics_export is None
        or args.candidate_diagnostics_export is None
    ):
        raise SystemExit(
            "M1 release certification requires baseline and candidate "
            "detailedLocal diagnostics exports"
        )
    if args.profile == "m1-8gb-release":
        for label, path, suffix in (
            ("runtime samples", args.runtime_samples, ".jsonl"),
            ("baseline POI export", args.baseline_poi_export, ".xml"),
            ("candidate POI export", args.candidate_poi_export, ".xml"),
        ):
            if not path.is_file() or path.suffix.lower() != suffix:
                raise SystemExit(
                    f"M1 {label} must be an existing {suffix} artifact"
                )
        try:
            RUNTIME_EVIDENCE.validate_poi_export(
                args.baseline_poi_export,
                run_id=args.run_id,
                subject_git_sha=args.baseline_subject_sha.lower(),
                trace_tree_sha256=RUNTIME_EVIDENCE.tree_sha256(
                    args.baseline_trace
                ),
            )
            RUNTIME_EVIDENCE.validate_poi_export(
                args.candidate_poi_export,
                run_id=args.run_id,
                subject_git_sha=args.candidate_subject_sha.lower(),
                trace_tree_sha256=RUNTIME_EVIDENCE.tree_sha256(
                    args.candidate_trace
                ),
            )
        except ValueError as error:
            raise SystemExit(
                f"M1 runtime privacy evidence is invalid: {error}"
            ) from error
        for label, path in (
            ("baseline", args.baseline_diagnostics_export),
            ("candidate", args.candidate_diagnostics_export),
        ):
            try:
                validate_detailed_local_diagnostics_store(path)
            except RuntimeError as error:
                raise SystemExit(
                    f"M1 {label} diagnostics export is invalid: {error}"
                ) from error
    if args.run_id is not None and re.fullmatch(
        r"[A-Za-z0-9][A-Za-z0-9._:-]{0,127}",
        args.run_id,
    ) is None:
        raise SystemExit("--run-id contains unsupported characters")


def main() -> None:
    args = parse_arguments()
    validate_arguments(args)

    run_id = (
        args.run_id
        or datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    )
    output_root = (
        args.output_root.resolve()
        if args.output_root
        else (args.candidate_root.resolve() / ".build/performance" / run_id)
    )
    if output_root.exists():
        raise SystemExit(f"output root must be new: {output_root}")
    output_root.mkdir(parents=True)
    static_hardware = hardware_environment()
    static_operating_system = os_environment()
    initial_environment = measurement_environment(
        hardware=static_hardware,
        operating_system=static_operating_system,
    )
    validate_measurement_environment(initial_environment)

    fixture_root = output_root / "fixtures"
    manifest_path = output_root / "fixtures.json"
    run_checked(
        [
            sys.executable,
            str(HARNESS_ROOT / "scripts/performance/generate_fixtures.py"),
            "--output",
            str(manifest_path),
            "--payload-directory",
            str(fixture_root),
        ],
        cwd=HARNESS_ROOT,
        environment=None,
        timeout=300,
        failure_log=output_root / "fixture-generation-failure.log",
    )

    runs: dict[str, VersionRun] = {}
    if args.baseline_root is not None:
        runs["baseline"] = VersionRun(
            "baseline",
            args.baseline_root,
            output_root,
            fixture_root,
            manifest_path,
            args.baseline_trace,
            args.baseline_subject_sha,
        )
    runs["candidate"] = VersionRun(
        "candidate",
        args.candidate_root,
        output_root,
        fixture_root,
        manifest_path,
        args.candidate_trace,
        args.candidate_subject_sha,
    )

    for version in runs.values():
        ensure_harness_available(version)
        validate_version_subject(version)
        build(version)
        run_driver(version, "prepare")

    version_names = list(runs)
    for iteration in range(args.warmups):
        for name in interleaved_versions(version_names, iteration):
            assert_environment_stable(
                initial_environment,
                measurement_environment(
                    hardware=static_hardware,
                    operating_system=static_operating_system,
                ),
            )
            run_driver(runs[name], "warmup")
    for iteration in range(args.sample_count):
        for name in interleaved_versions(version_names, iteration):
            assert_environment_stable(
                initial_environment,
                measurement_environment(
                    hardware=static_hardware,
                    operating_system=static_operating_system,
                ),
            )
            run_driver(runs[name], "sample", iteration)
    assert_environment_stable(
        initial_environment,
        measurement_environment(
            hardware=static_hardware,
            operating_system=static_operating_system,
        ),
    )

    copied_traces: dict[str, Path | None] = {}
    for name, version in runs.items():
        copied_traces[name] = write_report(
            version,
            run_id,
            args.warmups,
            args.sample_count,
            initial_environment,
        )

    runtime_evidence_path: Path | None = None
    if args.profile == "m1-8gb-release":
        runtime_evidence_path = output_root / "runtime-evidence.json"
        baseline_trace = copied_traces.get("baseline")
        candidate_trace = copied_traces.get("candidate")
        if baseline_trace is None or candidate_trace is None:
            raise RuntimeError(
                "M1 runtime evidence requires copied baseline and candidate traces"
            )
        runtime_artifact_root = output_root / "runtime-artifacts"
        runtime_artifact_root.mkdir()
        runtime_samples = runtime_artifact_root / "runtime-samples.jsonl"
        baseline_poi_export = runtime_artifact_root / "baseline-poi.xml"
        candidate_poi_export = runtime_artifact_root / "candidate-poi.xml"
        baseline_diagnostics_export = (
            runtime_artifact_root / "baseline-diagnostics.sqlite"
        )
        candidate_diagnostics_export = (
            runtime_artifact_root / "candidate-diagnostics.sqlite"
        )
        privacy_probe_receipt = (
            runtime_artifact_root / "privacy-probe-receipt.json"
        )
        try:
            shutil.copy2(args.runtime_samples, runtime_samples)
            shutil.copy2(args.baseline_poi_export, baseline_poi_export)
            shutil.copy2(args.candidate_poi_export, candidate_poi_export)
        except OSError as error:
            raise RuntimeError(
                f"could not package runtime evidence inputs: {error}"
            ) from error
        snapshot_detailed_local_diagnostics_store(
            args.baseline_diagnostics_export,
            baseline_diagnostics_export,
        )
        snapshot_detailed_local_diagnostics_store(
            args.candidate_diagnostics_export,
            candidate_diagnostics_export,
        )
        run_checked(
            [
                sys.executable,
                str(HARNESS_ROOT / "scripts/performance/write_runtime_evidence.py"),
                "--samples",
                str(runtime_samples),
                "--output",
                str(runtime_evidence_path),
                "--run-id",
                run_id,
                "--baseline-subject-git-sha",
                str(args.baseline_subject_sha),
                "--candidate-subject-git-sha",
                str(args.candidate_subject_sha),
                "--baseline-trace",
                str(baseline_trace),
                "--candidate-trace",
                str(candidate_trace),
                "--baseline-poi-export",
                str(baseline_poi_export),
                "--candidate-poi-export",
                str(candidate_poi_export),
                "--privacy-probe-receipt-output",
                str(privacy_probe_receipt),
                "--baseline-diagnostics-export",
                str(baseline_diagnostics_export),
                "--candidate-diagnostics-export",
                str(candidate_diagnostics_export),
            ],
            cwd=HARNESS_ROOT,
            environment=None,
            timeout=600,
            failure_log=output_root / "runtime-evidence-failure.log",
        )

    comparison_path: Path | None = None
    comparison_exit_code = 0
    if "baseline" in runs:
        comparison_path = output_root / "comparison.json"
        comparison_exit_code = run_checked(
            [
                sys.executable,
                str(HARNESS_ROOT / "scripts/performance/compare_benchmark_reports.py"),
                "--baseline",
                str(runs["baseline"].report_path),
                "--candidate",
                str(runs["candidate"].report_path),
                "--output",
                str(comparison_path),
                "--profile",
                args.profile,
                *(["--require-trace"] if args.require_trace else []),
            ],
            cwd=HARNESS_ROOT,
            environment=None,
            timeout=120,
            failure_log=output_root / "comparison-failure.log",
            accepted_returncodes=frozenset({0, 2}),
        )

    summary = output_summary(
        output_root=output_root,
        run_id=run_id,
        runs=runs,
        comparison_path=comparison_path,
        runtime_evidence_path=runtime_evidence_path,
    )
    print(json.dumps(summary, indent=2, sort_keys=True))
    if comparison_exit_code != 0:
        raise SystemExit(comparison_exit_code)


if __name__ == "__main__":
    main()
