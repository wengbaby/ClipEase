# ClipEase 发布检查清单

## 发布命令

只准备本地产物：

```bash
scripts/release.sh --bump patch
```

准备产物并发布到 GitHub Releases：

```bash
scripts/release.sh --bump patch --publish
```

如果已经单独跑过完整测试，可以跳过脚本内测试：

```bash
scripts/release.sh --bump none --skip-tests
```

## 发布前必须一致

- `Resources/Info.plist` 版本。
- `.build/ClipEase.app/Contents/Info.plist` 版本。
- DMG 内部 `ClipEase.app` 版本。
- DMG 文件名：`ClipEase-<version>-<build>.dmg`。
- Git tag：`v<version>-<build>`。
- Release 标题：`ClipEase <version> (<build>)`。

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
