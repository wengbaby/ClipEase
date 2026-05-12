# 轻贴 ClipEase

轻贴是一款 macOS 菜单栏剪贴板历史工具，副标题为“简洁好用的 macOS 粘贴板历史助手”。

当前项目处于第一版 RC 稳定性收尾阶段。实施前请先阅读 [docs/PROJECT_GUIDE.md](./docs/PROJECT_GUIDE.md)，并按文档中的开发顺序推进。

## 当前功能

- 菜单栏常驻和底部横向历史窗口
- 文字、图片、链接、颜色记录
- 搜索、筛选、置顶、删除、预览
- 双击、回车、`Command + 1-9` 粘贴
- 新建富文本、暂停记录、忽略 App
- 设置页、快捷键、保存期限、开机启动
- 历史导入导出、备份包、数据健康检查和清理

第一版发布前按 [第一版回归测试清单](./docs/FIRST_VERSION_TEST_CHECKLIST.md) 逐项验收。

发布资料：

- [第一版发布说明](./docs/RELEASE_NOTES.md)
- [发布候选流程](./docs/RELEASE_CANDIDATE_PROCESS.md)
- [发布候选报告](./docs/RELEASE_CANDIDATE_REPORT.md)
- [已知限制](./docs/KNOWN_ISSUES.md)

本地打包并启动：

```bash
scripts/build-app.sh --run
```

发布前基础检查：

```bash
scripts/smoke_check.py
```
