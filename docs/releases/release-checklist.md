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
