import AppKit
import Foundation
import SnapAILogic

@main
struct ProviderIconProbe {
    @MainActor
    static func main() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let base = URL(string: CommandLine.arguments[1])!
        let directory = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        let output = URL(fileURLWithPath: CommandLine.arguments[3])
        let library = ProviderIconLibrary(directory: directory)
        var checks: [[String: Any]] = []

        func record(_ name: String, _ passed: Bool, _ start: Date) {
            checks.append(["name": name, "passed": passed,
                           "duration_ms": Int(Date().timeIntervalSince(start) * 1000)])
        }

        var start = Date()
        let relative = await library.websiteImage(base.appendingPathComponent("relative/"))
        record("quoted_relative_link", relative?.isValid == true, start)

        start = Date()
        let redirect = await library.websiteImage(base.appendingPathComponent("redirect/"))
        record("homepage_and_icon_redirects", redirect?.isValid == true, start)

        start = Date()
        let fallback = await library.websiteImage(base.appendingPathComponent("fallback/"))
        record("favicon_after_seven_invalid_links", fallback?.isValid == true, start)

        start = Date()
        let missingURL = base.appendingPathComponent("missing/")
        let missing = await library.websiteImage(missingURL)
        let missingAgain = await library.websiteImage(missingURL)
        record("failed_site_returns_nil_twice", missing == nil && missingAgain == nil, start)

        start = Date()
        let concurrentURL = base.appendingPathComponent("concurrent/")
        async let first = library.websiteImage(concurrentURL)
        async let second = library.websiteImage(concurrentURL)
        async let third = library.websiteImage(concurrentURL)
        async let fourth = library.websiteImage(concurrentURL)
        let concurrent = await [first, second, third, fourth]
        record("concurrent_fetches_share_one_image", concurrent.first! != nil && concurrent.allSatisfy { $0 === concurrent.first! }, start)

        start = Date()
        let cached = await library.websiteImage(concurrentURL)
        let cachedWithoutNetwork = await library.websiteImage(concurrentURL, allowsNetwork: false)
        record("positive_cache_available_without_network", cached != nil && cached === cachedWithoutNetwork, start)

        start = Date()
        let suppressed = await library.websiteImage(base.appendingPathComponent("suppressed/"), allowsNetwork: false)
        record("privacy_mode_suppresses_new_network", suppressed == nil, start)

        var publicSites: [[String: Any]] = []
        for raw in ["https://www.apple.com/", "https://github.com/"] {
            start = Date()
            let image = await library.websiteImage(URL(string: raw)!)
            publicSites.append(["url": raw, "fetched": image?.isValid == true,
                                "duration_ms": Int(Date().timeIntervalSince(start) * 1000)])
            if image?.isValid == true { break }
        }
        checks.append(["name": "at_least_one_public_website", "passed": publicSites.contains { $0["fetched"] as? Bool == true }])
        let payload: [String: Any] = [
            "checks": checks,
            "public_websites": publicSites,
            "snapai_logic_tests_environment": ProcessInfo.processInfo.environment["SNAPAI_LOGIC_TESTS"] ?? "unset",
            "windows_shown": NSApplication.shared.windows.count,
            "activation_policy": "prohibited",
            "failures": checks.filter { $0["passed"] as? Bool != true }.map { $0["name"] as! String }
        ]
        try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]).write(to: output)
    }
}
