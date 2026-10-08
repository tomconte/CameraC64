import Foundation
import Testing

@testable import CameraC64

/// Settings' acknowledgements, and the privacy manifest (plan, section 11).
@MainActor
struct SettingsTests {
    /// The acknowledgements show the table in the bundled
    /// THIRD_PARTY_NOTICES.md, and the app's licence.
    @Test func acknowledgementsListWhatTheAppIncludes() {
        let notices = AcknowledgementsView.bundledText("THIRD_PARTY_NOTICES", "md")
        let included = Acknowledgement.included(inNotices: notices)
        #expect(included.contains { $0.name.contains("character ROM") })
        #expect(included.contains { $0.name.contains("Colodore") })
        #expect(included.allSatisfy { !$0.licence.isEmpty && !$0.use.isEmpty })
        #expect(AcknowledgementsView.bundledText("LICENSE", nil).hasPrefix("MIT License"))
    }

    @Test func acknowledgementsSkipTheTableHeader() {
        let notices = """
            # Notices

            Some text, with a | in it.

            | Material | Licence | Use |
            |---|---|---|
            | [A](https://example.com) | MIT | In `A.swift` |
            | B | Public domain | Ideas |
            """
        #expect(
            Acknowledgement.included(inNotices: notices) == [
                Acknowledgement(name: "[A](https://example.com)", licence: "MIT", use: "In `A.swift`"),
                Acknowledgement(name: "B", licence: "Public domain", use: "Ideas"),
            ])
    }

    /// Settings links to the support page and the privacy policy, which App
    /// Review opens too.
    @Test func settingsLinkToTheWebsite() {
        for url in [Website.support, Website.privacyPolicy] {
            #expect(url.scheme == "https" && url.host() == "camerac64.com", "\(url)")
        }
        #expect(Website.support != Website.privacyPolicy)
    }

    /// The privacy manifest says the app tracks no one and collects nothing,
    /// and why it reads the user defaults: its own settings.
    @Test func privacyManifestDeclaresTheUserDefaults() throws {
        let url = try #require(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
        let manifest = try #require(
            try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any])
        #expect(manifest["NSPrivacyTracking"] as? Bool == false)
        #expect((manifest["NSPrivacyTrackingDomains"] as? [String])?.isEmpty == true)
        #expect((manifest["NSPrivacyCollectedDataTypes"] as? [Any])?.isEmpty == true)
        let accessed = try #require(manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        #expect(accessed.count == 1)
        let userDefaults = try #require(
            accessed.first { $0["NSPrivacyAccessedAPIType"] as? String == "NSPrivacyAccessedAPICategoryUserDefaults" })
        #expect(userDefaults["NSPrivacyAccessedAPITypeReasons"] as? [String] == ["CA92.1"])
    }
}
