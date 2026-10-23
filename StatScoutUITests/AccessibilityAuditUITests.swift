import XCTest

/// Accessibility audit captures: the same screens as the tour, at the largest
/// accessibility text sizes, plus a touch-target census. Fixture data only, so
/// a run is deterministic. Reduced motion has no launch switch on iOS, so it is
/// audited from source, not here.
@MainActor
final class AccessibilityAuditUITests: XCTestCase {
    private enum Size: String {
        case standard = "UICTContentSizeCategoryL"
        case ax3 = "UICTContentSizeCategoryAccessibilityL"
        case ax5 = "UICTContentSizeCategoryAccessibilityXXXL"
    }

    private var step = 0

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
    }

    func testA01OnboardingAX5() {
        let app = launch(.ax5, onboarding: true)
        shot("onboarding_ax5_p1")
        for page in 2...4 {
            tap("Continue", in: app)
            shot("onboarding_ax5_p\(page)")
        }
    }

    func testA02TabsAX3() {
        for tab in ["games", "stats", "trends", "teams", "compare"] {
            let app = launch(.ax3, tab: tab)
            Thread.sleep(forTimeInterval: 4)
            shot("\(tab)_ax3_top")
            app.swipeUp(velocity: .slow)
            shot("\(tab)_ax3_scrolled")
            app.terminate()
        }
    }

    func testA03TabsAX5() {
        for tab in ["games", "stats"] {
            let app = launch(.ax5, tab: tab)
            Thread.sleep(forTimeInterval: 4)
            shot("\(tab)_ax5_top")
            app.terminate()
        }
    }

    func testA04ProfileAX3() {
        let app = launch(.ax3, extra: ["-ScreenshotRoute", "profile"])
        Thread.sleep(forTimeInterval: 5)
        shot("profile_ax3_p1")
        for page in 2...4 {
            app.swipeUp(velocity: .slow)
            shot("profile_ax3_p\(page)")
        }
    }

    func testA05CompareRouteAX3() {
        let app = launch(.ax3, extra: ["-ScreenshotRoute", "compare"])
        Thread.sleep(forTimeInterval: 5)
        shot("compare_ax3_p1")
        app.swipeUp(velocity: .slow)
        shot("compare_ax3_p2")
    }

    func testA06PaywallAX3() {
        for mode in ["yearly", "trial"] {
            let app = XCUIApplication(bundleIdentifier: "com.jackwallner.basketball")
            app.launchArguments = ["-PaywallSnapshot", mode, "-ResetUITestState",
                                   "-UIPreferredContentSizeCategoryName", Size.ax3.rawValue]
            app.launch()
            Thread.sleep(forTimeInterval: 4)
            shot("paywall_\(mode)_ax3_p1")
            app.swipeUp(velocity: .slow)
            shot("paywall_\(mode)_ax3_p2")
            app.swipeUp(velocity: .slow)
            shot("paywall_\(mode)_ax3_p3")
            app.terminate()
        }
    }

    func testA07SettingsAX3() {
        let app = launch(.ax3, tab: "stats")
        Thread.sleep(forTimeInterval: 4)
        tap("Settings", in: app)
        Thread.sleep(forTimeInterval: 1.5)
        shot("settings_ax3_p1")
        app.swipeUp(velocity: .slow)
        shot("settings_ax3_p2")
    }

    /// Lists every on-screen button smaller than 44x44 pt (Apple HIG minimum)
    /// at default text size, per tab, as a text attachment and as failures-free
    /// log lines, so the report can name the controls.
    func testA08TouchTargetCensus() {
        var report = ""
        for tab in ["games", "stats", "trends", "teams", "compare"] {
            let app = launch(.standard, tab: tab)
            Thread.sleep(forTimeInterval: 4)
            shot("census_\(tab)")
            let screen = app.frame
            report += "== \(tab) (screen \(Int(screen.width))x\(Int(screen.height)))\n"
            for element in app.buttons.allElementsBoundByIndex {
                let f = element.frame
                guard f.width > 0, f.height > 0, screen.intersects(f), f.minX >= 0, f.maxX <= screen.width,
                      f.minY >= 0, f.maxY <= screen.height else { continue }
                if f.width < 44 || f.height < 44 {
                    report += "  \(Int(f.width))x\(Int(f.height)) at (\(Int(f.minX)),\(Int(f.minY))) label='\(element.label)'\n"
                }
            }
            app.terminate()
        }
        let attachment = XCTAttachment(string: report)
        attachment.name = "census_small_targets"
        attachment.lifetime = .keepAlways
        add(attachment)
        print(report)
    }

    /// One-handed reach: where the primary controls sit on the screen, as a
    /// fraction of height from the top, for the Stats and Games tabs.
    func testA09ReachMap() {
        var report = ""
        for tab in ["games", "stats"] {
            let app = launch(.standard, tab: tab)
            Thread.sleep(forTimeInterval: 4)
            let h = app.frame.height
            report += "== \(tab)\n"
            for element in app.buttons.allElementsBoundByIndex.prefix(60) {
                let f = element.frame
                guard f.width > 0, f.minY >= 0, f.maxY <= h else { continue }
                if f.midY / h < 0.2 {
                    report += "  top-zone y=\(Int(f.midY / h * 100))% label='\(element.label)'\n"
                }
            }
            app.terminate()
        }
        let attachment = XCTAttachment(string: report)
        attachment.name = "reach_top_zone_controls"
        attachment.lifetime = .keepAlways
        add(attachment)
        print(report)
    }

    // MARK: - Helpers

    private func launch(
        _ size: Size,
        tab: String = "stats",
        onboarding: Bool = false,
        extra: [String] = []
    ) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "com.jackwallner.basketball")
        app.launchEnvironment = ["SCREENSHOT_MODE": "1", "FORCE_PRO": "1", "STATSCOUT_FORCE_PRO": "1"]
        var arguments = [
            "-ScreenshotData",
            "-stats.board", "advanced",
            "-stats.qualifier", "All Players",
            "-ResetUITestState",
            "-profileOpenCount", "0",
            "-StartTab", tab,
            "-favoriteTeam", "NYK",
            "-UIPreferredContentSizeCategoryName", size.rawValue,
        ]
        if !onboarding { arguments += ["-hasCompletedOnboarding", "YES"] }
        app.launchArguments = arguments + extra
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30), "App should launch in the foreground")
        return app
    }

    private func shot(_ name: String) {
        Thread.sleep(forTimeInterval: 1)
        step += 1
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "\(String(format: "%02d", step))_\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func tap(_ label: String, in app: XCUIApplication) {
        let matches = app.buttons.matching(NSPredicate(format: "label ==[c] %@", label))
        let element = matches.allElementsBoundByIndex.first(where: \.isHittable) ?? matches.firstMatch
        guard element.waitForExistence(timeout: 20) else {
            XCTFail("Button \(label) not found")
            shot("missing_\(label)")
            return
        }
        element.tap()
        Thread.sleep(forTimeInterval: 0.8)
    }
}
