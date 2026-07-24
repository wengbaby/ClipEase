import AppKit
import Foundation
import SwiftUI

struct HistoryPreviewImageLoadRequest: Hashable, Sendable {
    let assetRequest: HistoryImageAssetRequest
    let liveTextURL: URL
    let preferredPointSize: NSSize?
}

enum HistoryPreviewImageLoadRequestBuilder {
    static func historyImage(
        fileName: String,
        contentPointSize: CGSize,
        displayScale: CGFloat,
        preferredPointSize: NSSize?,
        isActive: Bool
    ) -> HistoryPreviewImageLoadRequest? {
        guard isActive,
              let bounds = pixelBounds(
                contentPointSize: contentPointSize,
                displayScale: displayScale
              ),
              let assetRequest = HistoryImageAssetRequest.popoverHistoryImage(
                fileName: fileName,
                maximumPixelWidth: bounds.width,
                maximumPixelHeight: bounds.height,
                priority: .visible
              ) else {
            return nil
        }
        return HistoryPreviewImageLoadRequest(
            assetRequest: assetRequest,
            liveTextURL: assetRequest.primaryURL,
            preferredPointSize: preferredPointSize
        )
    }

    static func fileImage(
        url: URL,
        cacheIdentity: String,
        contentPointSize: CGSize,
        displayScale: CGFloat,
        isActive: Bool
    ) -> HistoryPreviewImageLoadRequest? {
        guard isActive,
              let bounds = pixelBounds(
                contentPointSize: contentPointSize,
                displayScale: displayScale
              ),
              let assetRequest = HistoryImageAssetRequest.popoverFileImage(
                url: url,
                cacheIdentity: cacheIdentity,
                maximumPixelWidth: bounds.width,
                maximumPixelHeight: bounds.height,
                priority: .visible
              ) else {
            return nil
        }
        return HistoryPreviewImageLoadRequest(
            assetRequest: assetRequest,
            liveTextURL: url,
            preferredPointSize: nil
        )
    }

    private static func pixelBounds(
        contentPointSize: CGSize,
        displayScale: CGFloat
    ) -> (width: Int, height: Int)? {
        let scaledWidth = contentPointSize.width * displayScale
        let scaledHeight = contentPointSize.height * displayScale
        guard scaledWidth.isFinite,
              scaledHeight.isFinite,
              scaledWidth > 0,
              scaledHeight > 0,
              scaledWidth <= CGFloat(Int.max),
              scaledHeight <= CGFloat(Int.max) else {
            return nil
        }
        return (
            width: Int(ceil(scaledWidth)),
            height: Int(ceil(scaledHeight))
        )
    }
}

enum HistoryPreviewImagePlaceholderState: Hashable, Sendable {
    case idle
    case loading
    case failed
}

enum HistoryPreviewImagePlaceholderPresentation: Hashable, Sendable {
    case photo
    case progress
    case error
}

enum HistoryPreviewImagePlaceholderStyle: Hashable, Sendable {
    case history
    case file

    func presentation(
        for state: HistoryPreviewImagePlaceholderState
    ) -> HistoryPreviewImagePlaceholderPresentation {
        switch self {
        case .history:
            return .photo
        case .file:
            switch state {
            case .idle:
                return .photo
            case .loading:
                return .progress
            case .failed:
                return .error
            }
        }
    }
}

struct HistoryPreviewLoadedImage: @unchecked Sendable {
    let request: HistoryPreviewImageLoadRequest
    let image: NSImage
}

@MainActor
final class HistoryPreviewImageLoadOwner: ObservableObject {
    typealias Loader = @Sendable (HistoryImageAssetRequest) async throws -> HistoryImageAsset?

    enum Phase: Equatable {
        case idle
        case loading
        case loaded(HistoryPreviewLoadedImage)
        case failed

        static func == (lhs: Phase, rhs: Phase) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.loading, .loading), (.failed, .failed):
                return true
            case let (.loaded(left), .loaded(right)):
                return left.request == right.request && left.image === right.image
            default:
                return false
            }
        }
    }

    @Published private(set) var phase: Phase = .idle

    private enum LoadResult {
        case loaded(NSImage)
        case failed
        case cancelled
    }

    private let loader: Loader
    private var task: Task<Void, Never>?
    private var activeRequest: HistoryPreviewImageLoadRequest?
    private var generation = 0
    private var isDismantled = false

    init(loader: @escaping Loader = { request in
        try await HistoryImageAssetLoader.shared.loadVisible(request)
    }) {
        self.loader = loader
    }

    @discardableResult
    func replace(with request: HistoryPreviewImageLoadRequest) -> Task<Void, Never>? {
        guard !isDismantled else {
            return nil
        }
        if activeRequest == request {
            switch phase {
            case .loading, .loaded:
                return task
            case .idle, .failed:
                break
            }
        }

        task?.cancel()
        task = nil
        generation &+= 1
        let expectedGeneration = generation
        activeRequest = request
        phase = .loading
        let loader = self.loader

        task = Task { [weak self] in
            let result: LoadResult
            do {
                guard let asset = try await loader(request.assetRequest) else {
                    result = .failed
                    self?.finish(result, request: request, generation: expectedGeneration)
                    return
                }
                try Task.checkCancellation()
                guard let image = asset.image.copy() as? NSImage else {
                    result = .failed
                    self?.finish(result, request: request, generation: expectedGeneration)
                    return
                }
                if let preferredPointSize = request.preferredPointSize {
                    image.size = preferredPointSize
                }
                result = .loaded(image)
            } catch is CancellationError {
                result = .cancelled
            } catch {
                result = .failed
            }
            self?.finish(result, request: request, generation: expectedGeneration)
        }
        return task
    }

    func deactivate() {
        guard !isDismantled else {
            return
        }
        cancelAndReset()
    }

    func dismantle() {
        guard !isDismantled else {
            return
        }
        isDismantled = true
        cancelAndReset()
    }

    private func finish(
        _ result: LoadResult,
        request: HistoryPreviewImageLoadRequest,
        generation expectedGeneration: Int
    ) {
        guard !isDismantled,
              generation == expectedGeneration,
              activeRequest == request else {
            return
        }
        task = nil
        switch result {
        case .loaded(let image):
            phase = .loaded(HistoryPreviewLoadedImage(request: request, image: image))
        case .failed:
            phase = .failed
        case .cancelled:
            activeRequest = nil
            phase = .idle
        }
    }

    private func cancelAndReset() {
        generation &+= 1
        activeRequest = nil
        task?.cancel()
        task = nil
        phase = .idle
    }

    deinit {
        task?.cancel()
    }
}

@MainActor
struct HistoryPreviewImageLoadView: View {
    let request: HistoryPreviewImageLoadRequest?
    let isActive: Bool
    let isHighlighted: Bool
    let placeholderStyle: HistoryPreviewImagePlaceholderStyle

    @StateObject private var owner: HistoryPreviewImageLoadOwner

    init(
        request: HistoryPreviewImageLoadRequest?,
        isActive: Bool,
        isHighlighted: Bool,
        placeholderStyle: HistoryPreviewImagePlaceholderStyle,
        owner: HistoryPreviewImageLoadOwner = HistoryPreviewImageLoadOwner()
    ) {
        self.request = request
        self.isActive = isActive
        self.isHighlighted = isHighlighted
        self.placeholderStyle = placeholderStyle
        _owner = StateObject(wrappedValue: owner)
    }

    var body: some View {
        Group {
            if isActive,
               let request,
               case let .loaded(value) = owner.phase,
               value.request == request {
                LiveTextImagePreview(
                    image: value.image,
                    url: value.request.liveTextURL,
                    isHighlighted: isHighlighted
                )
                .id(value.request)
            } else {
                placeholder
            }
        }
        .task(id: request) {
            guard isActive, let request else {
                owner.deactivate()
                return
            }
            owner.replace(with: request)
        }
        .onChange(of: isActive) { active in
            if !active {
                owner.deactivate()
            }
        }
        .onDisappear {
            owner.deactivate()
        }
    }

    @ViewBuilder
    private var placeholder: some View {
        switch placeholderStyle.presentation(for: placeholderState) {
        case .photo:
            Image(systemName: "photo")
                .font(.system(size: 52, weight: .regular))
                .foregroundStyle(Color(red: 0.18, green: 0.55, blue: 1.0))
                .allowsHitTesting(false)
        case .progress:
            ZStack {
                Color.white
                ProgressView()
                    .controlSize(.small)
            }
        case .error:
            ZStack {
                Color.white
                Image(systemName: "photo.badge.exclamationmark")
                    .font(.system(size: 42, weight: .regular))
                    .foregroundStyle(Color(red: 0.18, green: 0.55, blue: 1.0))
                    .accessibilityLabel(L("无法加载图片预览"))
                    .help(L("无法加载图片预览"))
                    .allowsHitTesting(false)
            }
        }
    }

    private var placeholderState: HistoryPreviewImagePlaceholderState {
        guard isActive else {
            return .idle
        }
        guard request != nil else {
            return .failed
        }
        switch owner.phase {
        case .idle:
            return .idle
        case .loading:
            return .loading
        case .failed:
            return .failed
        case .loaded:
            return .loading
        }
    }
}
