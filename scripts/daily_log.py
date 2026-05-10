#!/usr/bin/env python3

from datetime import date
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
LOG_DIR = ROOT / "dev-logs"


TEMPLATE = """# {today} 开发日志

## 今日目标

- 

## 已完成

- 

## 验证结果

- 

## 遇到的问题

- 

## 明日待办

- 

## 决策记录

- 
"""


def main() -> None:
    LOG_DIR.mkdir(exist_ok=True)
    today = date.today().isoformat()
    log_path = LOG_DIR / f"{today}.md"

    if log_path.exists():
        content = log_path.read_text(encoding="utf-8")
        required_sections = [
            "## 今日目标",
            "## 已完成",
            "## 验证结果",
            "## 遇到的问题",
            "## 明日待办",
            "## 决策记录",
        ]
        missing = [section for section in required_sections if section not in content]
        if missing:
            with log_path.open("a", encoding="utf-8") as file:
                file.write("\n")
                for section in missing:
                    file.write(f"\n{section}\n\n- \n")
        return

    log_path.write_text(TEMPLATE.format(today=today), encoding="utf-8")


if __name__ == "__main__":
    main()

