import AppKit
import Foundation
@preconcurrency import VisionKit

@available(macOS 13.0, *)
struct LiveTextAnalysisRequest: @unchecked Sendable {
    let image: NSImage
    let locales: [String]
}

@available(macOS 13.0, *)
struct LiveTextAnalysisValue: @unchecked Sendable {
    let analysis: ImageAnalysis
}

@available(macOS 13.0, *)
protocol LiveTextImageAnalyzing: Sendable {
    var isSupported: Bool { get }

    func analyze(_ request: LiveTextAnalysisRequest) async throws -> LiveTextAnalysisValue
}

@available(macOS 13.0, *)
final class SystemLiveTextImageAnalyzer: LiveTextImageAnalyzing {
    private let analyzer = ImageAnalyzer()

    var isSupported: Bool {
        ImageAnalyzer.isSupported
    }

    func analyze(_ request: LiveTextAnalysisRequest) async throws -> LiveTextAnalysisValue {
        var configuration = ImageAnalyzer.Configuration([.text])
        configuration.locales = request.locales
        let analysis = try await analyzer.analyze(
            request.image,
            orientation: .up,
            configuration: configuration
        )
        return LiveTextAnalysisValue(analysis: analysis)
    }
}

@MainActor
final class LiveTextAnalysisLifecycle<Value> {
    typealias Operation = @MainActor () async throws -> Value
    typealias Apply = @MainActor (Result<Value, any Error>) -> Void

    private var task: Task<Void, Never>?
    private var generation: UInt64 = 0
    private var isDismantled = false

    @discardableResult
    func replace(
        operation: @escaping Operation,
        apply: @escaping Apply
    ) -> Task<Void, Never>? {
        guard !isDismantled else {
            return nil
        }

        generation &+= 1
        let requestedGeneration = generation
        task?.cancel()

        let pendingTask = Task { @MainActor [weak self] in
            let result: Result<Value, any Error>
            do {
                result = .success(try await operation())
            } catch {
                result = .failure(error)
            }

            guard let self,
                  !Task.isCancelled,
                  !isDismantled,
                  generation == requestedGeneration else {
                return
            }

            task = nil
            apply(result)
        }
        task = pendingTask
        return pendingTask
    }

    func cancel() {
        guard !isDismantled else {
            return
        }
        generation &+= 1
        task?.cancel()
        task = nil
    }

    func dismantle() {
        guard !isDismantled else {
            return
        }
        isDismantled = true
        generation &+= 1
        task?.cancel()
        task = nil
    }

    deinit {
        task?.cancel()
    }
}
