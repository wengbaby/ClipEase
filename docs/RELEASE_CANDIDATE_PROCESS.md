# 发布候选流程

本文固定轻贴 ClipEase 第二版发布候选包的检查和打包流程。

## 进入 RC 的条件

- 不再新增第二版功能。
- 只修复阻塞 bug、崩溃、数据风险和明显体验问题。
- `docs/RELEASE_NOTES.md`、`docs/RELEASE_CANDIDATE_REPORT.md` 和 `docs/KNOWN_ISSUES.md` 已更新。
- 当前 Git 工作区只允许存在明确说明的无关未跟踪文件。
- 用户已完成人工 UI 验收，或阻塞项已记录为待修复。

## 版本规则

- 大版本开发：主版本号 `+1`。
- 新增功能：次版本号 `+0.1`。
- 修复 bug / polish：修订号 `+0.0.1`。
- 每次构建 App 都必须刷新时间戳构建号，格式为 `YYMMDD.HHMM`。

## 构建运行

只要改动了 App 运行代码，先按变更类型构建并运行：

```bash
./scripts/build-app.sh --bump patch --run   # 修复 bug / polish
./scripts/build-app.sh --bump minor --run   # 新增功能
```

该命令会：

- 更新 `Resources/Info.plist` 版本号和构建号。
- 构建 `.build/ClipEase.app`。
- 关闭旧的 ClipEase 进程并启动新包。

只修改发布文档、检查脚本或打包脚本时，不需要为了文档变更单独递增 App 版本。

## 自动检查

当前 `.app` 已构建并运行后，执行最终发布门禁：

```bash
python3 scripts/final_release_gate.py
```

要求：

- `Resources/Info.plist` 版本号和时间戳格式正确。
- `.build/ClipEase.app` 存在，且版本与 `Resources/Info.plist` 一致。
- `docs/RELEASE_CANDIDATE_REPORT.md` 包含当前版本号和构建号。
- smoke check、帮助 / 设置 polish、调试菜单、搜索性能、预览反馈、文件卡片、音效和窗口动画等守卫全部通过。
- `git diff --check` 无空白错误。

如果检查失败，先修复失败项，不进入 RC 打包。

## 手动回归

重点确认：

- 主窗口弹出、关闭、搜索展开和横向滚动是否流畅。
- 文本、图片、PDF、链接、颜色和文件卡片复制 / 粘贴是否符合预期。
- 预览窗口打开、关闭、拖出独立窗口和 `Esc` 关闭是否稳定。
- 图片 / PDF OCR、文本选择和右键复制是否符合当前系统能力。
- 文件卡片 Quick Look、Finder 定位、文件引用复制、路径 fallback 和拖出是否稳定。
- 设置页保存期限、暂停、权限状态、帮助和数据维护入口是否正常。

## 打包 DMG

自动检查和手动回归通过后，使用当前已构建的 `.app` 生成 DMG：

```bash
./scripts/build-dmg.sh
```

脚本只打包 `.build/ClipEase.app`，不会重新编译、不会递增版本号。输出目录为 `dist/`，并打印 SHA-256 校验值。

当前打包方式适合本地测试和直接分享。未完成正式签名 / notarization 时，用户首次打开可能需要右键打开、手动信任，并重新授予辅助功能等隐私权限。

## RC 完成标准

- `.build/ClipEase.app` 可启动，关于页显示当前 RC 版本。
- `python3 scripts/final_release_gate.py` 通过。
- 用户人工验收无阻塞问题。
- `docs/RELEASE_CANDIDATE_REPORT.md` 记录本轮检查和包信息。
- Git 已提交，工作区除明确忽略 / 无关文件外保持干净。

## RC 后处理

- 如果用户回归通过：保留当前 `2.x` 作为第二版发布候选。
- 如果发现阻塞问题：修复后按 patch 规则进入下一个 `2.x.x(YYMMDD.HHMM)`，重新构建运行并重跑本流程。
