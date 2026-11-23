+++
id = "015"
title = "Usage category: coding"
edit = ["Sources/FamilyTimerCore/Usage.swift", "Sources/FamilyTimerCore/Replies.swift", "Tests/FamilyTimerCoreTests/RepliesTests.swift"]
read = ["Tests/FamilyTimerCoreTests/UsageTests.swift"]
checks = ["swift build", "swift test --filter RepliesTests", "swift test", "git --no-pager diff --check HEAD"]
commit = "feat(core): usage category coding"
edit_format = "diff"
+++

# 015 - Coding category

The parents want a fifth category for programming apps and sites (editors, terminals,
OpenCode, GitHub). Small change in three files, nothing else.

## Sources/FamilyTimerCore/Usage.swift

Add `case coding` to `UsageCategory`, between `video` and `other`. The order matters: the
Telegram buttons follow `allCases`. Raw value stays the default (`"coding"`).

## Sources/FamilyTimerCore/Replies.swift

- `categoryEmoji`: `.coding` returns `"💻"`.
- `categoryLabel`: `.coding` returns `t(l, "💻 coding", "💻 coding")`.

Keep every other case as it is.

## Tests/FamilyTimerCoreTests/RepliesTests.swift

Add one test method `testCodingCategory`:

- `Replies.categoryEmoji(.coding) == "💻"`
- `Replies.categoryLabel(.coding, .it) == "💻 coding"`
- `UsageCategory.allCases.map(\.rawValue) == ["games", "study", "video", "coding", "other"]`
- `UsageCategory(rawValue: "coding") == .coding`

Do not change the existing tests.
