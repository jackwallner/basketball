import XCTest
@testable import Hardwood_StatScout

/// Offering metadata `trial_cta` and the remote off switches. The control arm
/// must be the 1.0.1 copy character for character, and an account without a
/// trial keeps its no-trial wording on every arm.
final class RemoteConfigTests: XCTestCase {
    private let trial = "7-day free trial"

    func testMissingNonStringAndUnknownValuesAreTheControl() {
        XCTAssertEqual(TrialCTA.from(metadata: nil), .sevenDay)
        XCTAssertEqual(TrialCTA.from(metadata: [:]), .sevenDay)
        XCTAssertEqual(TrialCTA.from(metadata: ["trial_cta": 1]), .sevenDay)
        XCTAssertEqual(TrialCTA.from(metadata: ["trial_cta": ["my"]]), .sevenDay)
        XCTAssertEqual(TrialCTA.from(metadata: ["trial_cta": "three_day"]), .sevenDay)
        XCTAssertEqual(TrialCTA.from(metadata: ["trial_cta": "My"]), .sevenDay)
        XCTAssertEqual(TrialCTA.from(metadata: ["other_key": "my"]), .sevenDay)
    }

    func testEachKnownValueIsItsArm() {
        XCTAssertEqual(TrialCTA.metadataKey, "trial_cta")
        XCTAssertEqual(TrialCTA.from(metadata: ["trial_cta": "seven_day"]), .sevenDay)
        XCTAssertEqual(TrialCTA.from(metadata: ["trial_cta": "my"]), .my)
        XCTAssertEqual(TrialCTA.from(metadata: ["trial_cta": "your"]), .your)
    }

    func testEachArmsTitlePerSurface() {
        XCTAssertEqual(TrialCTA.sevenDay.oneTapTitle(trial: trial), "Start 7-day free trial")
        XCTAssertEqual(TrialCTA.my.oneTapTitle(trial: trial), "Start my free trial")
        XCTAssertEqual(TrialCTA.your.oneTapTitle(trial: trial), "Start your free trial")
        XCTAssertEqual(TrialCTA.sevenDay.planPickerTitle, "Start Free Trial")
        XCTAssertEqual(TrialCTA.my.planPickerTitle, "Start My Free Trial")
        XCTAssertEqual(TrialCTA.your.planPickerTitle, "Start Your Free Trial")
    }

    /// The labels every trial button showed before this change.
    func testControlIsThePreChangeCopy() {
        XCTAssertEqual(StoreService.directCTALabel(price: "$1.99 / month", trial: trial, isWinback: false),
                       "Start 7-day free trial")
        XCTAssertEqual(StoreService.directCTALabel(price: "$1.99 / month", trial: trial, isWinback: false, cta: .sevenDay),
                       "Start 7-day free trial")
        XCTAssertEqual(StoreService.planPickerCTALabel(isLifetime: false, trialEligible: true), "Start Free Trial")
        XCTAssertEqual(StoreService.planPickerCTALabel(isLifetime: false, trialEligible: true, cta: .sevenDay),
                       "Start Free Trial")
    }

    func testArmsReachEveryTrialButton() {
        XCTAssertEqual(StoreService.directCTALabel(price: "$9.99 / year", trial: trial, isWinback: false, cta: .my),
                       "Start my free trial")
        XCTAssertEqual(StoreService.planPickerCTALabel(isLifetime: false, trialEligible: true, cta: .your),
                       "Start Your Free Trial")
    }

    /// No arm may promise a trial to an account that already used it (3.1.2).
    func testIneligibleWordingIsUnchangedOnEveryArm() {
        for arm in TrialCTA.allCases {
            XCTAssertEqual(StoreService.directCTALabel(price: "$9.99 / year", trial: nil, isWinback: false, cta: arm),
                           "Try StatScout+ for $9.99 / year")
            XCTAssertEqual(StoreService.directCTALabel(price: "$9.99 / year", trial: trial, isWinback: true, cta: arm),
                           "Restart StatScout+ for $9.99 / year")
            XCTAssertEqual(StoreService.planPickerCTALabel(isLifetime: false, trialEligible: false, cta: arm), "Subscribe")
            XCTAssertEqual(StoreService.planPickerCTALabel(isLifetime: true, trialEligible: true, cta: arm), "Unlock Lifetime")
        }
    }

    func testSwitchIsOnByDefaultAndOffOnlyForOff() {
        XCTAssertEqual(RemoteSwitch.ratingPrompt.rawValue, "rating_prompt")
        XCTAssertTrue(RemoteConfig.isOn(.ratingPrompt, in: nil))
        XCTAssertTrue(RemoteConfig.isOn(.ratingPrompt, in: [:]))
        XCTAssertTrue(RemoteConfig.isOn(.ratingPrompt, in: ["rating_prompt": "on"]))
        XCTAssertTrue(RemoteConfig.isOn(.ratingPrompt, in: ["rating_prompt": false]))
        XCTAssertTrue(RemoteConfig.isOn(.ratingPrompt, in: ["rating_prompt": "OFF"]))
        XCTAssertFalse(RemoteConfig.isOn(.ratingPrompt, in: ["rating_prompt": "off"]))
    }
}
