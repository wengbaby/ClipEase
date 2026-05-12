# 轻贴项目指引

本文是项目入口文件，用于说明各项标准文件路径、工作方式和开发推进规则。任何开发工作开始前，先阅读本文，再查看对应专项文档。

## 项目信息

- 中文名：轻贴
- 英文名：ClipEase
- 副标题：简洁好用的 macOS 粘贴板历史助手
- 平台：macOS
- 产品形态：菜单栏常驻 App，底部横向卡片式剪贴板历史窗口

## 标准文件路径

- 产品需求：[docs/PRODUCT_REQUIREMENTS.md](/Users/wpc/code/codex/ClipboardHistory/docs/PRODUCT_REQUIREMENTS.md)
- 技术方案：[docs/TECHNICAL_SPEC.md](/Users/wpc/code/codex/ClipboardHistory/docs/TECHNICAL_SPEC.md)
- 设计规范：[docs/DESIGN_SPEC.md](/Users/wpc/code/codex/ClipboardHistory/docs/DESIGN_SPEC.md)
- 开发步骤：[docs/DEVELOPMENT_PLAN.md](/Users/wpc/code/codex/ClipboardHistory/docs/DEVELOPMENT_PLAN.md)
- 版本规则：[docs/VERSIONING.md](/Users/wpc/code/codex/ClipboardHistory/docs/VERSIONING.md)
- 第一版回归测试清单：[docs/FIRST_VERSION_TEST_CHECKLIST.md](/Users/wpc/code/codex/ClipboardHistory/docs/FIRST_VERSION_TEST_CHECKLIST.md)
- 第一版发布说明：[docs/RELEASE_NOTES.md](/Users/wpc/code/codex/ClipboardHistory/docs/RELEASE_NOTES.md)
- 发布候选流程：[docs/RELEASE_CANDIDATE_PROCESS.md](/Users/wpc/code/codex/ClipboardHistory/docs/RELEASE_CANDIDATE_PROCESS.md)
- 发布候选报告：[docs/RELEASE_CANDIDATE_REPORT.md](/Users/wpc/code/codex/ClipboardHistory/docs/RELEASE_CANDIDATE_REPORT.md)
- 已知限制：[docs/KNOWN_ISSUES.md](/Users/wpc/code/codex/ClipboardHistory/docs/KNOWN_ISSUES.md)
- 日志规范：[docs/DEV_LOG_GUIDE.md](/Users/wpc/code/codex/ClipboardHistory/docs/DEV_LOG_GUIDE.md)
- 每日开发日志目录：[dev-logs](/Users/wpc/code/codex/ClipboardHistory/dev-logs)
- 每日日志脚本：[scripts/daily_log.py](/Users/wpc/code/codex/ClipboardHistory/scripts/daily_log.py)
- 发布前 smoke check：[scripts/smoke_check.py](/Users/wpc/code/codex/ClipboardHistory/scripts/smoke_check.py)

## 工作说明

1. 每次开始开发前，先查看 `docs/DEVELOPMENT_PLAN.md`，只认领当前阶段的一小块任务。
2. 不一次性做太多功能。每个阶段都必须有可验证结果，再进入下一阶段。
3. 涉及体验或范围变化时，先更新 `docs/PRODUCT_REQUIREMENTS.md`，再实施。
4. 涉及架构、权限、存储或系统能力变化时，先更新 `docs/TECHNICAL_SPEC.md`。
5. 涉及界面、颜色、卡片、预览层或交互变化时，先更新 `docs/DESIGN_SPEC.md`。
6. 每天结束开发时，更新当天 `dev-logs/YYYY-MM-DD.md`，记录完成事项、验证结果、风险和待办。
7. 自动日志任务会每天创建或补全当天日志文件，但具体完成事项仍需要开发者按实际工作填写。
8. 每次正式打包 `.app` 必须通过 `scripts/build-app.sh`，由脚本自动递增版本并更新时间戳构建号。
9. 每次代码修改后需要编译、打开本地 App 供测试，并提交到 git。
10. 第一版发布前必须执行 `scripts/smoke_check.py` 和 `docs/FIRST_VERSION_TEST_CHECKLIST.md`，自动检查通过后再做手动验收。

## 当前阶段原则

- 优先稳定：先做菜单栏、窗口、记录、展示、复制粘贴这些核心链路。
- 本地优先：第一版所有数据保存在本机，不做云同步。
- 小步推进：每次实现后要能运行、能验证、能回退。
- 用户友好：默认体验简单，复杂功能放入设置或后续版本。
