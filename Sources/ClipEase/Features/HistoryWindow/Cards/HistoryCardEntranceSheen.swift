import SwiftUI

struct HistoryCardEntranceSheen: View {
    let startTime: CFTimeInterval?
    let duration: CFTimeInterval

    var body: some View {
        TimelineView(.animation) { timeline in
            GeometryReader { proxy in
                let width = max(proxy.size.width, 1)
                let height = max(proxy.size.height, 1)
                let progress = progress(at: timeline.date)
                let sheenOpacity = opacity(for: progress)
                let sheenTravelProgress = travelProgress(for: progress)
                LinearGradient(
                    colors: [
                        .clear,
                        .white.opacity(0),
                        .white.opacity(0.52),
                        .white.opacity(0),
                        .clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(width: width * 1.55, height: height * 1.28)
                .rotationEffect(.degrees(-10))
                .offset(x: -width * 0.78 + sheenTravelProgress * width * 1.7, y: -height * 0.14)
                .opacity(sheenOpacity)
            }
        }
        .clipped()
    }

    private func progress(at date: Date) -> CGFloat {
        guard let startTime else {
            return 0
        }

        let elapsed = date.timeIntervalSinceReferenceDate - startTime
        return min(1, max(0, CGFloat(elapsed / duration)))
    }

    private func opacity(for progress: CGFloat) -> CGFloat {
        if progress <= 0 {
            return 0
        }

        if progress < 0.18 {
            return progress / 0.18
        }

        if progress <= 0.82 {
            return 1
        }

        return max(0, 1 - ((progress - 0.82) / 0.18))
    }

    private func travelProgress(for progress: CGFloat) -> CGFloat {
        guard progress > 0 else {
            return 0
        }

        guard progress < 0.82 else {
            return 1
        }

        return min(1, progress / 0.82)
    }
}
