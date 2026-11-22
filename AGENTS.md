# Rules for the local coding model (Aider, OpenCode, Qwen Code)

These rules are for the local model that writes the code of a task. The supervisor reads
`docs/SPEC.md` and the llm-dev `SUPERVISOR.md` instead.

FamilyTimer is a Swift package that limits a child's daily time on a Mac
(see `docs/SPEC.md` only if the task tells you to).

1. Work on exactly one task from `docs/tasks/`. Read it fully before editing.
   Edit only the files the task lists under `edit`.
2. Swift 5.9 or later, Foundation only. No other imports in `Sources/FamilyTimerCore`
   (no AppKit, no IOKit, no Combine). No third-party packages. Do not edit `Package.swift`
   unless the task lists it.
3. `FamilyTimerCore` is pure: no clock, no file system, no network, no processes.
   Time is always a `Date` parameter, the calendar is always a `Calendar` parameter.
4. Tests use XCTest: `import XCTest` and `@testable import FamilyTimerCore`, one
   `final class <Name>Tests: XCTestCase` per file, test methods named `test...`.
   Tests never sleep and never use `Date()` or `Calendar.current`.
5. Never invent behaviour the task does not ask for. If something is unclear, write the
   question in `docs/tasks/QUESTIONS.md` and stop.
6. Small diffs: no reformatting, no renaming, no unrelated clean-up. 4-space indentation.
   No line may end with spaces.
7. Done means every command in the task's `checks` passes. The tests you write are yours to
   fix: when one fails, recompute its expected value by hand before changing the code.
   Never loop on the same failure: after two attempts, stop and write the question in
   `docs/tasks/QUESTIONS.md`.
8. Do not commit. Andrew commits after review with the task's `commit` message.
