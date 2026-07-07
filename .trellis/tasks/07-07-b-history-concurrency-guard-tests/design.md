# Design

## Boundaries

- Prefer tests against existing coordinator APIs.
- Only change production code when tests reveal missing cancellation or generation checks.
- Keep all user-facing search, preview, and paste behavior unchanged.

## Compatibility

- No storage changes.
- No UI changes.
- No new user settings.
