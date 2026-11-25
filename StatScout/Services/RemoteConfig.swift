import Foundation

/// What RevenueCat can change without a release, read from the current
/// offering's metadata (a running Experiment's variant included). Every
/// variant ships in the binary; a missing or unknown value is the control,
/// which is exactly what 1.0.1 shipped. Keys a switch reads must be set the
/// same on every offering, or an Experiment arm would flip them as a side
/// effect.
///
/// DEBUG builds can pin any key for captures: `-basketball.rc.<key> <value>`.
enum RemoteConfig {
    /// The value for `key`, or `fallback` when it is missing, not a string, or
    /// not one of the shipped variants.
    static func value<T: RawRepresentable>(_ key: String, in metadata: [String: Any]?, default fallback: T) -> T
    where T.RawValue == String {
        #if DEBUG
        if let pinned = launchOverride(key).flatMap(T.init(rawValue:)) { return pinned }
        #endif
        guard let raw = metadata?[key] as? String else { return fallback }
        return T(rawValue: raw) ?? fallback
    }

    /// On unless the metadata says "off".
    static func isOn(_ remoteSwitch: RemoteSwitch, in metadata: [String: Any]?) -> Bool {
        #if DEBUG
        if let pinned = launchOverride(remoteSwitch.rawValue) { return pinned != "off" }
        #endif
        return (metadata?[remoteSwitch.rawValue] as? String) != "off"
    }

    #if DEBUG
    private static func launchOverride(_ key: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-basketball.rc.\(key)"), index + 1 < args.count else { return nil }
        return args[index + 1]
    }
    #endif
}

/// The wording on a button that starts the free trial, for a wording test run
/// from offering metadata `trial_cta`.
///
/// Only the trial branch is tested. An Apple Account that already used its
/// trial keeps the plain price or "Subscribe" wording on every arm, because a
/// button may not promise a trial the App Store will not grant (3.1.2).
enum TrialCTA: String, CaseIterable, Sendable {
    static let metadataKey = "trial_cta"

    /// Control: the 1.0.1 copy, "Start 7-day free trial" on the one-tap
    /// buttons and "Start Free Trial" in the plan picker.
    case sevenDay = "seven_day"
    case my
    case your

    static func from(metadata: [String: Any]?) -> TrialCTA {
        RemoteConfig.value(metadataKey, in: metadata, default: .sevenDay)
    }

    /// The one-tap buttons (onboarding, the trial pitch sheet, the upsell
    /// cards), in sentence case. `trial` is the offer's own label, "7-day
    /// free trial", which the control names verbatim.
    func oneTapTitle(trial: String) -> String {
        switch self {
        case .sevenDay: return "Start \(trial)"
        case .my: return "Start my free trial"
        case .your: return "Start your free trial"
        }
    }

    /// The plan picker's button, in title case.
    var planPickerTitle: String {
        switch self {
        case .sevenDay: return "Start Free Trial"
        case .my: return "Start My Free Trial"
        case .your: return "Start Your Free Trial"
        }
    }
}

/// Remote off switches, for what is worth pausing without a release.
enum RemoteSwitch: String, CaseIterable, Sendable {
    /// Apple's rating prompt after a positive moment. "off" pauses it.
    case ratingPrompt = "rating_prompt"
}
