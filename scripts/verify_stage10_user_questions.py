#!/usr/bin/env python3
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PRODUCT_PLAN = ROOT / "docs/V2_PRODUCT_PLAN.md"
RUNBOOK = ROOT / "docs/V2_AGENT_RUNBOOK.md"


def fail(message: str) -> None:
    print(f"FAIL: {message}")
    sys.exit(1)


def require(condition: bool, message: str) -> None:
    if not condition:
        fail(message)


def main() -> None:
    text = PRODUCT_PLAN.read_text(encoding="utf-8") + "\n" + RUNBOOK.read_text(encoding="utf-8")
    required_question_topics = [
        "是否接受 Stage 10 只产出预研结论",
        "元数据 / 文本类数据",
        "文件卡片路径跨设备",
        "删除历史",
        "是否需要同步设置",
        "端到端加密",
        "附件",
    ]
    for topic in required_question_topics:
        require(topic in text, f"Stage 10 user confirmation questions missing topic: {topic}")

    require("用户已确认 Stage 10 关键问题" in text, "Stage 10 confirmation record must be present")
    print("OK Stage 10 user question checks passed")


if __name__ == "__main__":
    main()
