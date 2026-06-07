# ClipEase 发布检查清单

## 发布命令

只准备本地产物：

```bash
scripts/release.sh --bump patch
```

准备产物并发布到 GitHub Releases：

```bash
scripts/release.sh --bump none --skip-tests --publish
```

如果已经单独跑过完整测试，可以跳过脚本内测试：

```bash
scripts/release.sh --bump none --skip-tests
```

发布到远端前必须先提交本次版本号和 release 文档改动；`--publish` 会要求工作区干净，并且会先检查 `origin/main` 没有本地缺失提交。

## 发布前必须一致

- `Resources/Info.plist` 版本。
- `.build/ClipEase.app/Contents/Info.plist` 版本。
- DMG 内部 `ClipEase.app` 版本。
- DMG 文件名：`ClipEase-<version>-<build>.dmg`。
- Git tag：`v<version>-<build>`。
- Release 标题：`ClipEase <version> (<build>)`。

## 发布脚本保护

- 发布模式只接受已提交版本：先本地构建、确认、提交，再用 `--bump none --publish`。
- 发布前会执行 `git fetch origin main`，如果远端 `main` 有本地没有的提交，脚本会停止。
- 脚本会先推送当前分支，再创建 tag；tag 推送或 Release 创建失败时会清理本地 tag。
- 发布模式会在真正推送前输出免费发布失败恢复步骤，包含 GitHub CLI、GitHub 网页备用、GitHub API 备用、SSH 443 备用和 hash 校验说明。

## 免费发布失败恢复

如果 `--publish` 因网络、GitHub CLI 或认证问题中断，先看脚本输出的 tag、DMG 路径、SHA-256 和 Release 正文路径，再按失败位置恢复。

- 分支推送失败：修复网络或认证后重跑脚本，或手动执行 `git push origin HEAD:<branch>`。
- tag 推送失败：确认本地 tag 存在后执行 `git push origin <tag>`。
- GitHub CLI 创建失败：确认 tag 已推送后执行 `gh release create <tag> <dmg> --title <title> --notes-file <body>`。
- GitHub 网页备用：在 GitHub Releases 页面选择同一个 tag，标题使用脚本输出的 Release title，正文使用 release md，上传同一个 DMG。
- GitHub API 备用：通过 GitHub REST API 创建 release 后，再按 upload_url 上传 DMG。
- SSH 443 备用：如果普通 SSH 推送失败，可配置 github.com 使用 `ssh.github.com:443` 后重试。
- hash 校验：无论用 CLI、网页还是 API 上传，最后都必须下载远端 DMG 并对照脚本输出的 SHA-256。

## Release 正文格式

Release 正文从 `docs/releases/release-notes-template.md` 生成，必须包含：

- `本次优化`
- `本次修复`
- `验证`
- DMG SHA-256

## 脚本输出

发布脚本会输出：

- Release title
- Release tag
- DMG 路径
- SHA-256
- Release 正文路径

本地产物固定输出到：

```text
.build/release-artifacts/
```
