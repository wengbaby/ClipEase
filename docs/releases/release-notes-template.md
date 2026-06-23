## 本次优化

- 在“关于”中新增版本更新检查，可以手动检查 GitHub 最新正式 Release。
- 支持每天静默检查一次新版本，并可在“关于”中关闭自动检查。
- 发现新版本时可直接下载 DMG，或打开 GitHub Release 页面查看更新内容。
- 检查失败时会显示“检查失败，稍后重试”，并保留打开 GitHub 自行下载的入口。
- 更新检查只使用 GitHub 最新正式 Release，不包含 draft 或 prerelease。

## 验证

- {{TEST_LINE}}
- 已构建 `.build/ClipEase.app`，版本为 `{{VERSION}} ({{BUILD}})`。
- 已生成并验证 `{{DMG_NAME}}`。
- 已挂载 DMG 检查内部 `ClipEase.app` 版本为 `{{VERSION}} ({{BUILD}})`。
- DMG SHA-256：`{{SHA256}}`。
