# C History Performance Budget Expansion

## Goal

Extend existing performance budget coverage to 10k-item history scenarios without adding user-visible features.

## Requirements

- Extend performance tests for preview generation, search filtering, render window slicing, and SQLite FTS search.
- Use the existing performance test style and keep assertions broad enough to avoid brittle CI failures.
- Validate correctness first and use timing budgets only where existing tests already use stable budget patterns.

## Acceptance Criteria

- [x] 10k preview generation test exists and passes.
- [x] 10k search filter test exists and passes.
- [x] 10k render window slicing test exists and passes.
- [x] 10k SQLite FTS search test exists and passes.
- [x] `swift test --filter HistoryPerformanceBudgetTests` passes.
