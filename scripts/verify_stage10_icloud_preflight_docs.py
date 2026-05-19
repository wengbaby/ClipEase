#!/usr/bin/env python3
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def fail(message: str) -> None:
    print(f"FAIL: {message}")
    sys.exit(1)


def require(condition: bool, message: str) -> None:
    if not condition:
        fail(message)


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def main() -> None:
    product = read("docs/V2_PRODUCT_PLAN.md")
    technical = read("docs/V2_TECHNICAL_PLAN.md")
    development = read("docs/V2_DEVELOPMENT_PLAN.md")
    test_plan = read("docs/V2_TEST_PLAN.md")
    runbook = read("docs/V2_AGENT_RUNBOOK.md")

    required_docs = [
        "docs/V2_S10_ICLOUD_RISK_MATRIX.md",
        "docs/V2_S10_SCHEMA_GAP.md",
        "docs/V2_S10_SYNC_DATA_DICTIONARY.md",
    ]
    for path in required_docs:
        require((ROOT / path).exists(), f"missing Stage 10 artifact {path}")

    combined = "\n".join([product, technical, development, test_plan, runbook])
    required_phrases = [
        "Stage 10 第一批只做预研",
        "不做正式 iCloud 同步功能",
        "不新增 schema 迁移",
        "不出现用户可见同步开关",
        "风险矩阵",
        "schema gap",
        "同步数据字典",
        "用户确认问题",
        "CloudKit private",
        "端到端加密",
        "附件",
        "删除同步",
    ]
    for phrase in required_phrases:
        require(phrase in combined, f"Stage 10 docs missing required phrase: {phrase}")

    for path in required_docs:
        text = read(path)
        require("Stage 10" in text, f"{path} must identify Stage 10")
        require("只做预研" in text, f"{path} must keep the docs-only boundary")

    require("继续 HOLD runtime" in runbook, "runbook must keep runtime implementation on hold")
    print("OK Stage 10 iCloud preflight docs checks passed")


if __name__ == "__main__":
    main()
