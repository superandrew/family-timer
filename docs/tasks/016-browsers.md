+++
id = "016"
title = "Browsers are containers: no category question, 🌐 in usage replies"
edit = ["Sources/FamilyTimerCore/Usage.swift", "Sources/FamilyTimerCore/Replies.swift", "Tests/FamilyTimerCoreTests/UsageTests.swift", "Tests/FamilyTimerCoreTests/RepliesTests.swift"]
read = []
checks = ["swift build", "swift test --filter UsageTests", "swift test --filter RepliesTests", "swift test", "git --no-pager diff --check HEAD"]
commit = "feat(core): browsers are containers, shown with 🌐 and never classified"
edit_format = "diff"
+++

# 016 - Browsers

A browser has no category of its own: the time inside it is counted per site, and the sites
get the categories. So the parents are never asked about a browser, and usage replies show
it with 🌐 instead of a category emoji.

## Sources/FamilyTimerCore/Usage.swift

Inside `UsageLog`, next to `isSite`, add:

    /// Bundle ids of the browsers whose page the agent reads.
    public static let browsers: Set<String> = [
        "com.apple.Safari", "com.apple.SafariTechnologyPreview", "com.google.Chrome",
        "org.mozilla.firefox", "com.microsoft.edgemac", "com.brave.Browser",
        "company.thebrowser.Browser", "com.operasoftware.Opera", "com.vivaldi.Vivaldi",
    ]

    /// True for the app key of a browser ("app:com.google.Chrome").
    public static func isBrowser(_ key: String) -> Bool

    /// True when the parents should be asked to classify `key`: not a browser, not classified yet.
    public func needsCategory(_ key: String) -> Bool

`isBrowser`: `key` starts with `"app:"` and the rest is in `browsers`.
`needsCategory`: `!UsageLog.isBrowser(key) && categories[key] == nil`.

## Sources/FamilyTimerCore/Replies.swift

In `usage(...)`, the line of an app uses `"🌐"` instead of `categoryEmoji(...)` when
`UsageLog.isBrowser(e.key)`, whatever its category. Sites do not change.

## Tests

`UsageTests.swift`, new method `testBrowsers`:
- `UsageLog.isBrowser("app:com.google.Chrome")` and `UsageLog.isBrowser("app:com.apple.Safari")` are true;
- `UsageLog.isBrowser("app:com.mojang.minecraft")`, `UsageLog.isBrowser("site:google.com")`, `UsageLog.isBrowser("com.google.Chrome")` are false;
- a `UsageLog` with `categories["app:com.mojang.minecraft"] = .games`: `needsCategory` is
  false for `"app:com.mojang.minecraft"` and `"app:com.google.Chrome"`, true for
  `"app:com.apple.Terminal"` and `"site:github.com"`.

Build the `UsageLog` the same way the existing tests do.

`RepliesTests.swift`, in `testUsage`: the entries already contain Safari. Change only the
expected `❓ Safari 1h 15m` into `🌐 Safari 1h 15m` in the first assertion. Nothing else.
