# Zephyr Repository Agent Guide

The Zephyr source tree and verified build or runtime behavior are the source of truth.
`zephyr-workbench/` is a navigation and collaboration aid, not a replacement for source verification.

## Read Order

1. Start from the user's request and its explicit scope.
2. If a matching task exists, read only that file under `zephyr-workbench/tasks/`.
3. Use `zephyr-workbench/map.md` only when repository routing is unclear.
4. Read a relevant `zephyr-workbench/topics/<topic>.md` when it exists.
5. Verify conclusions against source code, configuration, tests, or runtime behavior.

Do not scan the whole workbench by default. Do not treat an old note as current fact without checking its
`last_verified` metadata and relevant source revision.

## Working Rules

- Keep facts, assumptions, and unverified questions distinct.
- Keep changes within the task boundary and identify a minimal verification path.
- Current execution state belongs in `zephyr-workbench/tasks/`.
- Stable subsystem knowledge belongs in `zephyr-workbench/topics/`.
- Cross-cutting decisions and their rationale belong in `zephyr-workbench/decisions.md`.
- Update durable knowledge only when a task produces reusable information.
- Do not create placeholder directories, dashboards, registries, or duplicate human/AI versions of a note.
