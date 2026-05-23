# 文档

[English](README.md) | 简体中文

本目录用于存放 ClipEase 的公开、非敏感仓库说明。

## 仓库结构

```text
.
├── Package.swift
├── README.md
├── Resources/
├── Sources/
├── docs/
└── scripts/
```

## 目录说明

| 路径 | 说明 |
| --- | --- |
| `Package.swift` | ClipEase 可执行目标的 Swift Package 定义。 |
| `Resources/` | App bundle 资源，包括 `Info.plist`、图标资源和声音文件。 |
| `Sources/ClipEase/` | macOS App 的 Swift 源码。 |
| `Sources/ClipEase/App/` | App 生命周期、菜单栏和状态栏项目相关代码。 |
| `Sources/ClipEase/Core/` | 模型、存储、设置、服务和共享工具。 |
| `Sources/ClipEase/Features/` | 历史记录、设置、粘贴执行和帮助等面向用户的功能。 |
| `scripts/build-app.sh` | 用于构建 `.build/ClipEase.app` 的辅助脚本。 |
| `scripts/bump_version.py` | `scripts/build-app.sh` 使用的版本号辅助脚本。 |

## 构建产物

生成文件不属于公开源码目录：

- `.build/`
- `dist/`
- 本地 Xcode 和 SwiftPM 用户状态
