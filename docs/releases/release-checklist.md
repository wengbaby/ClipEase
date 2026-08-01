# ClipEase 发布检查清单

## 性能发布门禁

发布候选必须使用干净 worktree 和完整提交 SHA。自动门禁固定执行：

```bash
swift test -c release --no-parallel
swift build -c release \
  -Xswiftc -strict-concurrency=complete \
  -Xswiftc -warnings-as-errors
scripts/run-performance-benchmarks.sh
```

性能矩阵必须保存基线 `ad4013cce2a4e0a1648de2277126c736c0700b39`、候选 SHA、5 次预热、30 次正式样本、原始样本和比较报告。任何 p99 超过停止阈值的单轮结果都必须交错复测，不能自动接受变慢后的新基线。

## M1 8GB 绝对认证

日常 M2 Max 相对比较不能替代发布认证。发布前需要在真实 M1 8GB 设备完成 macOS 13 和 macOS 26 两个系统卷的完整认证，固定夹具为 `S1K`、`T10K`、`M100K` 和 `A3K`，并至少连续三轮全部通过：

- 启动、捕获、搜索、存储、内存、退出和资产处理达到质量合同中的 M1 绝对门槛。
- 必测故障包括迁移中断、磁盘满、数据库损坏、SIGKILL、锁屏/睡眠恢复、30 张 8MiB 图片、25 页 PDF 和 100 次窗口开关。
- 每轮保存结构化 benchmark JSON、原始样本、故障注入报告和对应 `.trace` 证据，所有报告中的 subject SHA 必须一致。

## 视觉与 Instruments 双门槛

每个 macOS 26 候选必须保存静态截图及 60Hz/120Hz 录屏逐帧对照，覆盖普通卡片、搜索高亮、预览、窗口开合、液态玻璃和动画恢复。出现玻璃、阴影、动画或可见布局差异时，性能通过也不能自动放行。

使用 `scripts/capture-performance-traces.sh` 采集 SwiftUI、Time Profiler、Animation Hitches、System Trace、Power Profiler、Allocations 和 Leaks；File Activity 仅允许在用户主动开启的本地详细诊断中采集。通过 `scripts/performance/validate_release_certification.py` 校验 manifest、trace、报告 SHA、隐私字段和环境后，才可写入发布证据。

## 本地诊断与隐私

正式版默认只启用 signpost。详细诊断必须是用户主动开启的本地模式，30 秒采样、10MiB/7 天上限、有界队列和丢弃计数；不得出现剪贴板内容、搜索文本、路径或用户文件内容。发布证据中必须包含隐私扫描结果，且不得上传诊断数据。

## 免费发布失败恢复

正式发布脚本失败后，先确认标签、Release 与 DMG 的远端状态，再选择一种恢复路径：

1. 使用 `gh release create` 重新创建或补齐 Release。
2. 使用 **GitHub 网页备用**流程手工上传已经验证过 SHA-256 的 DMG。
3. 使用 **GitHub API 备用**流程恢复自动发布，并再次核对远端标签、附件与校验值。

恢复操作不得跳过本地测试、DMG 挂载验证、远端附件检查和 SHA-256 复核。
