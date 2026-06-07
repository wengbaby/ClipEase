import SwiftUI

struct SettingsDiagnosticsSection: View {
    @ObservedObject var diagnostics: PerformanceDiagnosticsService
    let onOpenLogsDirectory: () -> Void
    let onCleanupLogs: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsSection(title: "性能采样", subtitle: diagnostics.summaryText) {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("启用性能采样和日志记录", isOn: $diagnostics.isEnabled)
                        .toggleStyle(.switch)

                    HStack(spacing: 10) {
                        historyButton("打开诊断目录", minWidth: 104, action: onOpenLogsDirectory)
                        historyButton("清理诊断日志", minWidth: 108, action: onCleanupLogs)
                    }

                    HStack(spacing: 16) {
                        Stepper(
                            "保留 \(diagnostics.retentionDays) 天",
                            value: $diagnostics.retentionDays,
                            in: 1...30
                        )
                        .frame(width: 128, alignment: .leading)

                        Stepper(
                            "最多 \(diagnostics.maxLogSizeMB) MB",
                            value: $diagnostics.maxLogSizeMB,
                            in: 1...100
                        )
                        .frame(width: 144, alignment: .leading)
                    }
                    .font(.system(size: 12, weight: .regular))

                    if let url = diagnostics.currentLogFileURL {
                        Text(url.path)
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .textSelection(.enabled)
                    }
                }
            }

            SettingsSection(title: "实时概览", subtitle: "最近 \(diagnostics.recentEvents.count) 条采样事件") {
                VStack(alignment: .leading, spacing: 12) {
                    resourceOverview

                    performanceBars

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("慢操作")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)

                        let slowEvents = SettingsDiagnosticsViewModel.visibleSlowEvents(from: diagnostics.recentEvents)
                        if slowEvents.isEmpty {
                            Text("暂无超过 16ms 的慢操作。")
                                .font(.system(size: 12, weight: .regular))
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(slowEvents) { event in
                                performanceEventRow(event)
                            }
                        }
                    }
                }
            }

            SettingsSection(title: "最近日志", subtitle: "只记录耗时、数量、阶段和类型，不记录剪贴板正文") {
                VStack(alignment: .leading, spacing: 8) {
                    let recentEvents = SettingsDiagnosticsViewModel.visibleRecentEvents(from: diagnostics.recentEvents)
                    if recentEvents.isEmpty {
                        Text("暂无日志。操作历史窗口、搜索或预览后会出现在这里。")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(recentEvents) { event in
                            performanceEventRow(event)
                        }
                    }
                }
            }
        }
    }

    private var resourceOverview: some View {
        let snapshot = diagnostics.latestResourceSnapshot

        return HStack(spacing: 10) {
            performanceMetricTile(
                iconName: "cpu",
                title: "CPU",
                value: snapshot.map { PerformanceDiagnosticsService.formatPercent($0.cpuPercent) } ?? "--",
                color: color(for: SettingsDiagnosticsViewModel.cpuSeverity(for: snapshot?.cpuPercent ?? 0))
            )

            performanceMetricTile(
                iconName: "memorychip",
                title: "内存",
                value: snapshot.map { PerformanceDiagnosticsService.formatMB($0.memoryMB) } ?? "--",
                color: color(for: SettingsDiagnosticsViewModel.memorySeverity(for: snapshot?.memoryMB ?? 0))
            )

            performanceMetricTile(
                iconName: "point.3.connected.trianglepath.dotted",
                title: "线程",
                value: snapshot.map { "\($0.threadCount)" } ?? "--",
                color: .blue
            )

            performanceMetricTile(
                iconName: "waveform.path.ecg",
                title: "主线程",
                value: snapshot.map { PerformanceDiagnosticsService.formatMS($0.mainThreadLatencyMS) } ?? "--",
                color: color(for: SettingsDiagnosticsViewModel.durationSeverity(for: snapshot?.mainThreadLatencyMS ?? 0))
            )
        }
    }

    private func performanceMetricTile(
        iconName: String,
        title: String,
        value: String,
        color: Color
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                Text(value)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private var performanceBars: some View {
        let events = SettingsDiagnosticsViewModel.barEvents(from: diagnostics.recentEvents)
        let maxDuration = max(events.map(\.durationMS).max() ?? 1, 1)

        return HStack(alignment: .bottom, spacing: 3) {
            ForEach(events) { event in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(color(for: SettingsDiagnosticsViewModel.durationSeverity(for: event.durationMS)))
                    .frame(width: 8, height: max(4, CGFloat(event.durationMS / maxDuration) * 72))
                    .help("\(event.name) \(PerformanceDiagnosticsService.formatMS(event.durationMS))")
            }

            if events.isEmpty {
                Text("暂无采样数据")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: 78, alignment: .bottomLeading)
    }

    private func performanceEventRow(_ event: PerformanceDiagnosticEvent) -> some View {
        let color = color(for: SettingsDiagnosticsViewModel.durationSeverity(for: event.durationMS))

        return HStack(spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.name)
                    .font(.system(size: 12, weight: .semibold))

                Text(SettingsDiagnosticsViewModel.detailText(for: event))
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(PerformanceDiagnosticsService.formatMS(event.durationMS))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func historyButton(
        _ title: String,
        minWidth: CGFloat = 88,
        prominent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        if prominent {
            Button(title, action: action)
                .buttonStyle(.borderedProminent)
                .frame(minWidth: minWidth)
        } else {
            Button(title, action: action)
                .buttonStyle(.bordered)
                .frame(minWidth: minWidth)
        }
    }

    private func color(for severity: SettingsDiagnosticsSeverity) -> Color {
        switch severity {
        case .normal:
            return .green
        case .warning:
            return .yellow
        case .elevated:
            return .orange
        case .critical:
            return .red
        }
    }
}
