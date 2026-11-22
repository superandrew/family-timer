+++
id = "001"
title = "Config file parser"
edit = ["Sources/FamilyTimerCore/Config.swift", "Tests/FamilyTimerCoreTests/ConfigTests.swift"]
read = ["Package.swift", "Sources/FamilyTimerCore/Version.swift", "Tests/FamilyTimerCoreTests/VersionTests.swift"]
checks = ["test -s Sources/FamilyTimerCore/Config.swift && test -s Tests/FamilyTimerCoreTests/ConfigTests.swift", "swift build", "swift test --filter ConfigTests", "swift test", "git add -N -- Sources/FamilyTimerCore/Config.swift Tests/FamilyTimerCoreTests/ConfigTests.swift && git --no-pager diff --check HEAD"]
commit = "feat(core): parse the KEY=VALUE config file"
edit_format = "whole"
+++

# 001 - Config file parser

Both files are new. Write them whole.

## Sources/FamilyTimerCore/Config.swift

    import Foundation

    public enum ConfigError: Error, Equatable {
        case missing(String)
        case invalidNumber(key: String, value: String)
    }

    public struct Config: Equatable {
        public var childUser: String
        public var weekdayLimit: Int
        public var weekendLimit: Int
        public var extensionTime: Int
        public var idleThreshold: Int
        public var graceTime: Int
        public var approvalTimeout: Int
        public var telegramBotToken: String
        public var telegramChatID: String
        public var parentUserIDs: [Int64]
        public var healthcheckURL: String
        public var healthcheckInterval: Int

        public static func parse(_ text: String) throws -> Config
    }

Give `Config` a `public init` with every property as a parameter, in the order above, each
with the default of the table (no default for `childUser`).

| Property | Key | Default |
|---|---|---|
| childUser | CHILD_USER | required |
| weekdayLimit | TIME_LIMIT | 3600 |
| weekendLimit | WEEKEND_TIME_LIMIT | 3600 |
| extensionTime | EXTENSION_TIME | 1800 |
| idleThreshold | IDLE_THRESHOLD | 120 |
| graceTime | GRACE_TIME | 300 |
| approvalTimeout | APPROVAL_TIMEOUT | 600 |
| telegramBotToken | TELEGRAM_BOT_TOKEN | "" |
| telegramChatID | TELEGRAM_CHAT_ID | "" |
| parentUserIDs | PARENT_USER_IDS | [] |
| healthcheckURL | HEALTHCHECK_URL | "" |
| healthcheckInterval | HEALTHCHECK_INTERVAL | 300 |

`parse` rules, line by line (split `text` on newlines):

1. Trim spaces and tabs. Skip empty lines and lines that start with `#`.
2. Skip lines without `=`. Otherwise split on the **first** `=`: key = left part trimmed,
   value = right part trimmed.
3. If the value is at least 2 characters long and starts and ends with `"`, or starts and
   ends with `'`, remove those two characters.
4. Unknown keys are ignored (old minecraft-timer files have keys such as
   `DISPLAY_5_MIN_WARNING`).
5. The 7 integer keys (`TIME_LIMIT`, `WEEKEND_TIME_LIMIT`, `EXTENSION_TIME`,
   `IDLE_THRESHOLD`, `GRACE_TIME`, `APPROVAL_TIMEOUT`, `HEALTHCHECK_INTERVAL`) must be
   `Int(value)` with a result greater than 0, otherwise
   `throw ConfigError.invalidNumber(key: key, value: value)` (the value after step 3).
6. `PARENT_USER_IDS`: empty value gives `[]`. Otherwise split on `,`, trim each part, and
   each part must be `Int64(part)`, otherwise
   `throw ConfigError.invalidNumber(key: "PARENT_USER_IDS", value: part)`.
7. A key given twice: the last line wins.
8. After all lines: if `CHILD_USER` was never given or is empty,
   `throw ConfigError.missing("CHILD_USER")`.

## Tests/FamilyTimerCoreTests/ConfigTests.swift

`final class ConfigTests: XCTestCase`, like `VersionTests.swift`. One test method per case:

1. `"CHILD_USER=arthur"` gives
   `Config(childUser: "arthur")` (all defaults).
2. This text gives the values listed after it:

        # FamilyTimer
        CHILD_USER="arthur"
        TIME_LIMIT=3600
        WEEKEND_TIME_LIMIT = 7200
        EXTENSION_TIME='1800'
        TELEGRAM_BOT_TOKEN="123:abc=def"
        TELEGRAM_CHAT_ID="-100200"
        PARENT_USER_IDS="11, 22"
        DISPLAY_5_MIN_WARNING=true
        HEALTHCHECK_URL=https://hc-ping.com/xyz

   childUser `"arthur"`, weekdayLimit `3600`, weekendLimit `2 * 3600`,
   extensionTime `30 * 60`, telegramBotToken `"123:abc=def"`, telegramChatID `"-100200"`,
   parentUserIDs `[11, 22]`, healthcheckURL `"https://hc-ping.com/xyz"`, the others default.
3. `""` throws `ConfigError.missing("CHILD_USER")`.
4. `"CHILD_USER="` throws `ConfigError.missing("CHILD_USER")`.
5. `"CHILD_USER=a\nTIME_LIMIT=abc"` throws
   `ConfigError.invalidNumber(key: "TIME_LIMIT", value: "abc")`.
6. `"CHILD_USER=a\nGRACE_TIME=0"` throws
   `ConfigError.invalidNumber(key: "GRACE_TIME", value: "0")`.
7. `"CHILD_USER=a\nPARENT_USER_IDS=11,x"` throws
   `ConfigError.invalidNumber(key: "PARENT_USER_IDS", value: "x")`.
8. `"CHILD_USER=a\nTIME_LIMIT=60\nTIME_LIMIT=120"` gives weekdayLimit `120`.
9. `"CHILD_USER=a\nthis line has no equal sign"` gives `Config(childUser: "a")`.

Check thrown errors with:

    XCTAssertThrowsError(try Config.parse(text)) { error in
        XCTAssertEqual(error as? ConfigError, .missing("CHILD_USER"))
    }

Build multi-line inputs with `"\n"` or Swift multi-line string literals (`"""`).
