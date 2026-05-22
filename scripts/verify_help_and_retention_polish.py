#!/usr/bin/env python3
from pathlib import Path


root = Path(__file__).resolve().parents[1]
help_view = root / "Sources/ClipEase/Features/Help/HelpView.swift"
settings_view = root / "Sources/ClipEase/Features/Settings/SettingsView.swift"

help_text = help_view.read_text(encoding="utf-8")
settings_text = settings_view.read_text(encoding="utf-8")

failures: list[str] = []

required_help = [
    'title: "打开和关闭"',
    'title: "卡片操作"',
    'title: "搜索和分组"',
    'title: "预览和文件"',
    'title: "设置和权限"',
    'Text("常用操作")',
]

for snippet in required_help:
    if snippet not in help_text:
        failures.append(f"Help copy missing: {snippet}")

if help_text.count("helpSection(\n                        title:") != 5:
    failures.append("Help should stay concise with exactly 5 sections")

forbidden_help = [
    "快速了解常用操作和权限说明",
    "卡片标题栏颜色取来源 App 图标中心点颜色并加深",
    "历史文件读取失败时会自动备份损坏文件",
    "设置窗口可导出历史记录为 JSON 文件",
    "筛选可查看全部、文字、链接、图片和置顶内容",
]

for snippet in forbidden_help:
    if snippet in help_text:
        failures.append(f"Help copy still contains over-detailed text: {snippet}")

required_retention = [
    "private func retentionPolicyButton(_ policy: HistoryRetentionPolicy) -> some View",
    "let isSelected = store.retentionPolicy == policy",
    ".foregroundStyle(isSelected ? Color.white : Color.primary)",
    ".background(isSelected ? Color.accentColor : Color.white.opacity(0.72))",
    ".stroke(isSelected ? Color.accentColor",
    ".buttonStyle(.plain)",
]

for snippet in required_retention:
    if snippet not in settings_text:
        failures.append(f"Retention selected style missing: {snippet}")

forbidden_retention = [
    ".pickerStyle(.segmented)",
    "Picker(\"\", selection:",
]

for snippet in forbidden_retention:
    if snippet in settings_text:
        failures.append(f"Retention style should not use segmented picker: {snippet}")

if failures:
    print("Help and retention polish guard failed:")
    print("\n".join(failures))
    raise SystemExit(1)

print("OK help copy is concise and retention selected state is blue")
