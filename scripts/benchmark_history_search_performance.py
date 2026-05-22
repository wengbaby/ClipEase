#!/usr/bin/env python3
from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta
from statistics import median
import time
import unicodedata


@dataclass(frozen=True)
class HistoryItem:
    item_id: int
    preview_type: str
    created_at: datetime
    source_app_name: str
    normalized_search_text: str
    search_fingerprint: int
    is_pinned: bool
    group_id: str | None
    grouped_at: datetime | None

    @property
    def source_signature(self) -> tuple[object, ...]:
        return (
            self.item_id,
            self.preview_type,
            self.created_at,
            self.source_app_name,
            self.search_fingerprint,
            self.is_pinned,
            self.group_id,
            self.grouped_at,
        )


@dataclass(frozen=True)
class SearchCriteria:
    types: frozenset[str] = frozenset()
    source_app_names: frozenset[str] = frozenset()
    groups: frozenset[str] = frozenset()


def normalize_search_text(value: str) -> str:
    decomposed = unicodedata.normalize("NFD", value)
    without_marks = "".join(
        character for character in decomposed
        if unicodedata.category(character) != "Mn"
    )
    return without_marks.casefold()


def item_matches_search_group(item: HistoryItem, group: str) -> bool:
    if group == "pinned":
        return item.is_pinned
    return item.group_id == group


def filter_items(
    items: list[HistoryItem],
    *,
    selected_group: str,
    search_text: str,
    criteria: SearchCriteria,
) -> list[HistoryItem]:
    query = search_text.strip()
    normalized_query = normalize_search_text(query)

    result: list[HistoryItem] = []
    criteria_types = criteria.types
    criteria_sources = criteria.source_app_names
    criteria_groups = criteria.groups

    for item in items:
        if selected_group == "pinned":
            if not item.is_pinned:
                continue
        elif selected_group != "all":
            if item.group_id != selected_group:
                continue

        if criteria_types and item.preview_type not in criteria_types:
            continue

        if criteria_sources and item.source_app_name not in criteria_sources:
            continue

        if criteria_groups and not any(
            item_matches_search_group(item, group)
            for group in criteria_groups
        ):
            continue

        if not normalized_query:
            result.append(item)
            continue

        if normalized_query in item.normalized_search_text:
            result.append(item)

    if selected_group not in {"all", "pinned"}:
        result.sort(key=lambda item: item.grouped_at or datetime.min, reverse=True)

    return result


def make_items(count: int) -> list[HistoryItem]:
    base_date = datetime(2026, 5, 23, 9, 30, 0)
    preview_types = ("text", "link", "image", "color", "file")
    source_apps = ("Google Chrome", "WeChat", "Finder", "Preview", "Mail", "Notes")
    groups = ("work", "personal", "review", "archive")
    chinese_terms = (
        "\u53d1\u7968",
        "\u90ae\u4ef6",
        "\u5408\u540c",
        "\u8ba2\u5355",
    )

    items: list[HistoryItem] = []
    for index in range(count):
        preview_type = preview_types[index % len(preview_types)]
        source_app_name = source_apps[index % len(source_apps)]
        group_id = groups[index % len(groups)] if index % 5 != 0 else None
        created_at = base_date - timedelta(seconds=index * 17)
        grouped_at = created_at + timedelta(seconds=index % 13) if group_id else None
        is_pinned = index % 17 == 0
        term = chinese_terms[index % len(chinese_terms)]

        parts = [
            preview_type,
            source_app_name,
            f"clip-{index:05d}",
            f"user{index % 97}@example.com",
            f"https://example.com/order/{index % 4096}",
            f"/Users/wpc/Documents/report-{index % 211}.pdf",
            f"gmail project invoice order task {index % 31}",
            term,
        ]
        normalized_search_text = normalize_search_text(" ".join(parts))

        items.append(
            HistoryItem(
                item_id=index,
                preview_type=preview_type,
                created_at=created_at,
                source_app_name=source_app_name,
                normalized_search_text=normalized_search_text,
                search_fingerprint=hash(normalized_search_text),
                is_pinned=is_pinned,
                group_id=group_id,
                grouped_at=grouped_at,
            )
        )

    return items


def measure_median_ms(function, *, warmups: int = 2, repeats: int = 9) -> tuple[float, int]:
    last_count = 0
    for _ in range(warmups):
        last_count = len(function())

    durations: list[float] = []
    for _ in range(repeats):
        start = time.perf_counter()
        last_count = len(function())
        durations.append((time.perf_counter() - start) * 1000)

    return median(durations), last_count


def benchmark() -> int:
    items_1k = make_items(1_000)
    items_10k = make_items(10_000)
    failures: list[str] = []

    scenarios = [
        (
            "1k common query",
            80.0,
            lambda: filter_items(
                items_1k,
                selected_group="all",
                search_text="gmail",
                criteria=SearchCriteria(),
            ),
        ),
        (
            "10k common query",
            250.0,
            lambda: filter_items(
                items_10k,
                selected_group="all",
                search_text="gmail",
                criteria=SearchCriteria(),
            ),
        ),
        (
            "10k chinese query",
            250.0,
            lambda: filter_items(
                items_10k,
                selected_group="all",
                search_text="\u53d1\u7968",
                criteria=SearchCriteria(),
            ),
        ),
        (
            "10k type/source filter",
            180.0,
            lambda: filter_items(
                items_10k,
                selected_group="all",
                search_text="",
                criteria=SearchCriteria(
                    types=frozenset({"image", "file"}),
                    source_app_names=frozenset({"Google Chrome", "Finder"}),
                ),
            ),
        ),
        (
            "10k group query sort",
            250.0,
            lambda: filter_items(
                items_10k,
                selected_group="work",
                search_text="order",
                criteria=SearchCriteria(),
            ),
        ),
        (
            "10k source signatures",
            120.0,
            lambda: [item.source_signature for item in items_10k],
        ),
    ]

    print("History search benchmark:")
    print("scenario                  median_ms  threshold_ms  result_count")
    for name, threshold_ms, function in scenarios:
        median_ms, result_count = measure_median_ms(function)
        print(f"{name:<25} {median_ms:>9.2f} {threshold_ms:>13.2f} {result_count:>13}")
        if result_count <= 0:
            failures.append(f"{name}: expected non-empty result")
        if median_ms > threshold_ms:
            failures.append(
                f"{name}: median {median_ms:.2f}ms exceeded {threshold_ms:.2f}ms"
            )

    if failures:
        print("History search benchmark failed:")
        print("\n".join(failures))
        return 1

    print("OK history search benchmark within thresholds")
    return 0


if __name__ == "__main__":
    raise SystemExit(benchmark())
