# 发布候选流程

本文固定轻贴 ClipEase 第一版发布候选包的检查和打包流程。

## 进入 RC 的条件

- 不再新增第一版功能。
- 只修复阻塞 bug、崩溃、数据风险和明显体验问题。
- `docs/RELEASE_NOTES.md` 和 `docs/KNOWN_ISSUES.md` 已更新。
- 当前 Git 工作区干净，且上一轮修改已推送到 GitHub。

## 自动检查

按顺序执行：

```bash
swift build
scripts/smoke_check.py
```

要求：

- 调试构建通过。
- smoke check 全部通过。
- 如果检查失败，先修复失败项，不进入 RC 打包。

## 手动回归

按 [第一版回归测试清单](./FIRST_VERSION_TEST_CHECKLIST.md) 验收。

分工：

- 开发侧确认可自动化或可静态检查的项目。
- 用户侧确认真实 UI、动画、粘贴目标、权限和交互手感。
- 发现阻塞 bug 时，只修 bug，不扩大功能范围。

## 构建 RC 包

当自动检查通过且无已知阻塞问题时，首次进入第一版 RC 需要构建 `1.0.0` 候选包：

```bash
scripts/build-app.sh --bump major --run
```

该命令会：

- 将版本从 `0.x.x` 升到 `1.0.0`。
- 更新时间戳构建号。
- 构建 `.build/ClipEase.app`。
- 关闭旧的 ClipEase 进程并启动新包。

如果已经进入 `1.0.x` RC 修复轮，后续阻塞 bug 修复后使用 patch 规则构建新的候选包：

```bash
scripts/build-app.sh --bump patch --run
```

该命令会递增修复版本，例如 `1.0.1 -> 1.0.2`，同时更新时间戳构建号。

## RC 完成标准

- `.build/ClipEase.app` 可启动。
- 关于页显示当前 RC 版本，例如 `1.0.2(YYMMDD.HHMM)`。
- Git 工作区干净。
- GitHub `main` 已推送最新提交。
- `docs/RELEASE_CANDIDATE_REPORT.md` 已记录本轮检查结果。

## RC 后处理

- 如果用户回归通过：保留当前 `1.0.x` 作为第一版发布候选。
- 如果发现阻塞问题：修复后用 patch 规则进入下一个 `1.0.x(YYMMDD.HHMM)`，再重新跑本流程。
