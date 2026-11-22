import XCTest
@testable import FamilyTimerCore

final class ConfigTests: XCTestCase {
    func testChildUserOnly() {
        let config = try? Config.parse("CHILD_USER=arthur")
        XCTAssertEqual(config, Config(childUser: "arthur"))
    }

    func testFullConfig() {
        let text = """
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
        """
        let config = try? Config.parse(text)
        let expected = Config(
            childUser: "arthur",
            weekdayLimit: 3600,
            weekendLimit: 2 * 3600,
            extensionTime: 30 * 60,
            idleThreshold: 120,
            graceTime: 300,
            approvalTimeout: 600,
            telegramBotToken: "123:abc=def",
            telegramChatID: "-100200",
            parentUserIDs: [11, 22],
            healthcheckURL: "https://hc-ping.com/xyz",
            healthcheckInterval: 300
        )
        XCTAssertEqual(config, expected)
    }

    func testEmptyTextThrowsMissingChildUser() {
        XCTAssertThrowsError(try Config.parse("")) { error in
            XCTAssertEqual(error as? ConfigError, .missing("CHILD_USER"))
        }
    }

    func testEmptyChildUserThrowsMissing() {
        XCTAssertThrowsError(try Config.parse("CHILD_USER=")) { error in
            XCTAssertEqual(error as? ConfigError, .missing("CHILD_USER"))
        }
    }

    func testInvalidTimeLimitThrows() {
        XCTAssertThrowsError(try Config.parse("CHILD_USER=a\nTIME_LIMIT=abc")) { error in
            XCTAssertEqual(error as? ConfigError, .invalidNumber(key: "TIME_LIMIT", value: "abc"))
        }
    }

    func testZeroGraceTimeThrows() {
        XCTAssertThrowsError(try Config.parse("CHILD_USER=a\nGRACE_TIME=0")) { error in
            XCTAssertEqual(error as? ConfigError, .invalidNumber(key: "GRACE_TIME", value: "0"))
        }
    }

    func testInvalidParentUserIDThrows() {
        XCTAssertThrowsError(try Config.parse("CHILD_USER=a\nPARENT_USER_IDS=11,x")) { error in
            XCTAssertEqual(error as? ConfigError, .invalidNumber(key: "PARENT_USER_IDS", value: "x"))
        }
    }

    func testDuplicateKeyLastWins() {
        let config = try? Config.parse("CHILD_USER=a\nTIME_LIMIT=60\nTIME_LIMIT=120")
        XCTAssertEqual(config?.weekdayLimit, 120)
    }

    func testLineWithoutEqualSignIsIgnored() {
        let config = try? Config.parse("CHILD_USER=a\nthis line has no equal sign")
        XCTAssertEqual(config, Config(childUser: "a"))
    }

    func testLanguage() {
        XCTAssertEqual(try? Config.parse("CHILD_USER=a\nLANGUAGE=it").language, .it)
        XCTAssertEqual(try? Config.parse("CHILD_USER=a\nLANGUAGE=EN").language, .en)
        XCTAssertEqual(try? Config.parse("CHILD_USER=a").language, .en)
        XCTAssertThrowsError(try Config.parse("CHILD_USER=a\nLANGUAGE=fr")) { error in
            XCTAssertEqual(error as? ConfigError, .invalidValue(key: "LANGUAGE", value: "fr"))
        }
    }

    func testChildNames() {
        let config = try? Config.parse("CHILD_USER=arthur2\nCHILD_NAMES= Arthur , art ,")
        XCTAssertEqual(config?.childNames, ["Arthur", "art"])
        XCTAssertEqual(config?.displayName, "Arthur")
        XCTAssertEqual(config?.isAddressed(by: nil), true)
        XCTAssertEqual(config?.isAddressed(by: "ART"), true)
        XCTAssertEqual(config?.isAddressed(by: "arthur2"), true)
        XCTAssertEqual(config?.isAddressed(by: "bea"), false)
        XCTAssertEqual(Config(childUser: "bob").displayName, "bob")
    }
}
