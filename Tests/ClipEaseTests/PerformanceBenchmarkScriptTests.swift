import Foundation
import Testing

@Test func releaseBenchmarkRunnerUsesRequiredReproducibleSamplingContract() throws {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let script = try String(contentsOf: root.appendingPathComponent("scripts/run-performance-benchmarks.sh"))

    #expect(script.contains("WARMUP_COUNT=5"))
    #expect(script.contains("SAMPLE_COUNT=30"))
    #expect(script.contains("scripts/performance/generate_fixtures.py"))
    #expect(script.contains("scripts/performance/run_benchmark_matrix.py"))
    #expect(script.contains("--candidate-root"))
    #expect(script.contains("--warmups"))
    #expect(script.contains("--sample-count"))
    #expect(script.contains("ad4013c"))
    #expect(script.contains("--baseline-subject-sha"))
    #expect(script.contains("PERFORMANCE_CANDIDATE_ONLY"))
    #expect(script.contains("--candidate-subject-sha \"$(git -C \"$ROOT_DIR\" rev-parse HEAD)\""))
    #expect(script.contains("Gating benchmarks require a clean candidate worktree"))
    #expect(!script.contains("system_profiler"))
}

@Test func benchmarkMatrixUsesInnerWorkloadSamplesAndSupportsInterleavedComparison() throws {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let runner = try String(
        contentsOf: root.appendingPathComponent("scripts/performance/run_benchmark_matrix.py")
    )

    #expect(runner.contains("enterprisePerformanceBenchmarkDriver"))
    #expect(runner.contains("--skip-build"))
    #expect(runner.contains("CLIPEASE_BENCHMARK_ACTION"))
    #expect(runner.contains("CLIPEASE_BENCHMARK_ITERATION"))
    #expect(runner.contains("interleaved_versions"))
    #expect(runner.contains("compare_benchmark_reports.py"))
    #expect(runner.contains("write_runtime_evidence.py"))
    #expect(runner.contains("--baseline-root"))
    #expect(runner.contains("--runtime-samples"))
    #expect(runner.contains("--baseline-poi-export"))
    #expect(runner.contains("--candidate-poi-export"))
    #expect(runner.contains("--baseline-diagnostics-export"))
    #expect(runner.contains("--candidate-diagnostics-export"))
    #expect(runner.contains("snapshot_detailed_local_diagnostics_store"))
    #expect(runner.contains("trace-status"))
    #expect(runner.contains("assert_environment_stable"))
}

@Test func releaseCertificationGateRequiresExternalM1AndVisualEvidence() throws {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let validator = try String(
        contentsOf: root.appendingPathComponent(
            "scripts/performance/validate_release_certification.py"
        )
    )

    #expect(validator.contains("\"macOS13\": 3"))
    #expect(validator.contains("\"macOS26\": 3"))
    #expect(validator.contains("macOS26_120Hz"))
    #expect(validator.contains("faultInjection"))
    #expect(validator.contains("runtimeEvidence"))
    #expect(validator.contains("benchmarkKind"))
    #expect(validator.contains("changedCodeCoveragePercent"))
    #expect(validator.contains("\"baselineAccepted\": False"))
}

@Test func benchmarkDriverKeepsMicroAndRuntimeMetricLayersSeparate() throws {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let driver = try String(
        contentsOf: root.appendingPathComponent(
            "Tests/ClipEaseTests/EnterprisePerformanceBenchmarkDriverTests.swift"
        )
    )

    for metric in [
        "startup_snapshot_s1k",
        "search_t10k_sqlite",
        "upsert_t10k",
        "fts_cold_m100k",
        "fts_hot_m100k",
        "page_1k_m100k",
        "asset_scan_a3k",
        "asset_decode_a3k",
    ] {
        #expect(driver.contains("metrics[\"\(metric)\"]"))
    }
    #expect(!driver.contains("metrics[\"cold_start\"]"))
    #expect(!driver.contains("metrics[\"first_window_usable\"]"))
}

@Test func benchmarkA3KMeasuresProductAttachmentScanPath() throws {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let driver = try String(
        contentsOf: root.appendingPathComponent(
            "Tests/ClipEaseTests/EnterprisePerformanceBenchmarkDriverTests.swift"
        )
    )

    #expect(driver.contains("HistoryDataHealthChecker.check"))
    #expect(driver.contains("prepareAssetScanFixture"))
    #expect(driver.contains("linkItem"))
    #expect(driver.contains("Images"))
    #expect(driver.contains("Thumbnails"))
    #expect(driver.contains("RichTexts"))
}

@Test func instrumentsCaptureMatrixIncludesEveryRequiredProfiler() throws {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let script = try String(
        contentsOf: root.appendingPathComponent(
            "scripts/capture-performance-traces.sh"
        )
    )

    for requiredTool in [
        "SwiftUI",
        "Time Profiler",
        "Points of Interest",
        "Animation Hitches",
        "Core Animation FPS",
        "System Trace",
        "Power Profiler",
        "Allocations",
        "Leaks",
    ] {
        #expect(script.contains(requiredTool))
    }
    #expect(script.contains("--include-sensitive-local-traces"))
    #expect(script.contains("File Activity"))
    #expect(script.contains("local-only-sensitive-paths"))
    #expect(script.contains("file-activity-excluded"))
    #expect(!script.contains("\"targetPID\":"))
    #expect(script.contains("Refusing to replace existing trace collection"))
    #expect(script.contains("--run-id"))
    #expect(script.contains("--subject-git-sha"))
    #expect(script.contains("--source-root"))
    #expect(script.contains("--executable"))
    #expect(script.contains("\"schemaVersion\": 2"))
    #expect(script.contains("machOUUIDs"))
}
