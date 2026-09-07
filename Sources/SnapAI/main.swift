import SnapAILogic
import AppKit

let arguments = ProcessInfo.processInfo.arguments
let environment = ProcessInfo.processInfo.environment
let launchSmoke: (settings: AppSettings, directory: URL, token: String)?
if arguments.contains("--release-smoke") || environment["SNAPAI_LAUNCH_SMOKE_DIRECTORY"] != nil {
    guard let path = environment["SNAPAI_LAUNCH_SMOKE_DIRECTORY"], path.hasPrefix("/"),
          let token = environment["SNAPAI_LAUNCH_SMOKE_TOKEN"], UUID(uuidString: token) != nil,
          let flagIndex = arguments.firstIndex(of: "--release-smoke"),
          arguments.indices.contains(flagIndex + 1), arguments[flagIndex + 1] == token else {
        fputs("error: invalid isolated launch smoke configuration\n", stderr)
        exit(1)
    }
    setenv("SNAPAI_LOGIC_TESTS", "1", 1)
    let directory = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
    let pid = ProcessInfo.processInfo.processIdentifier
    let suiteName = "com.snapai.release-smoke.\(token)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        fputs("error: cannot create isolated launch smoke defaults\n", stderr)
        exit(1)
    }
    do {
        try Data("\(pid)\n".utf8).write(to: directory.appendingPathComponent("pid"), options: .atomic)
        let supportDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .resolvingSymlinksInPath()
            .appendingPathComponent("SnapAI-LogicTests-\(pid)", isDirectory: true)
        try Data((supportDirectory.path + "\n").utf8)
            .write(to: directory.appendingPathComponent("support-directory"), options: .atomic)
        var argumentDefaults = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        argumentDefaults[AppSettings.iCloudDeviceIDDefaultsKey] = token
        argumentDefaults["ApplePersistenceIgnoreState"] = true
        UserDefaults.standard.setVolatileDomain(argumentDefaults, forName: UserDefaults.argumentDomain)
        let settings = AppSettings()
        settings.persistenceDefaults = defaults
        settings.persistenceHistoryStore = HistoryStore(url: directory.appendingPathComponent("history.sqlite"))
        settings.providers = [AIProvider(id: "release-smoke", name: "Release Smoke",
                                         baseURL: "http://127.0.0.1:9/v1",
                                         models: [AIModelEntry(name: "smoke-model")])]
        settings.activeProviderID = "release-smoke"
        settings.activeModel = "smoke-model"
        settings.iCloudDeviceID = token
        settings.iCloudSyncEnabled = false
        settings.iCloudHasLocalChanges = false
        settings.onboardingDone = true
        settings.showDockIcon = false
        guard settings.loadHistoryFromLocalStoreOrMigrate(), settings.save() else {
            fputs("error: isolated launch smoke persistence is unavailable\n", stderr)
            exit(1)
        }
        launchSmoke = (settings, directory, token)
    } catch {
        fputs("error: cannot prepare isolated launch smoke files\n", stderr)
        exit(1)
    }
} else {
    launchSmoke = nil
}

let app = NSApplication.shared
let delegate: NSApplicationDelegate
if let launchSmoke {
    delegate = MainActor.assumeIsolated {
        AppDelegate(settings: launchSmoke.settings,
                    launchSmokeDirectory: launchSmoke.directory,
                    launchSmokeToken: launchSmoke.token)
    }
} else {
#if DEBUG
    if arguments.contains("--preview") || Bundle.main.bundleIdentifier == "com.snapai.preview" {
        setenv("SNAPAI_LOGIC_TESTS", "1", 1)
        var previewDefaults = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        previewDefaults[AppSettings.iCloudDeviceIDDefaultsKey] = UUID().uuidString
        UserDefaults.standard.setVolatileDomain(previewDefaults, forName: UserDefaults.argumentDomain)
        delegate = AppPreviewDelegate()
    } else {
        delegate = MainActor.assumeIsolated { AppDelegate() }
    }
#else
    delegate = MainActor.assumeIsolated { AppDelegate() }
#endif
}
app.delegate = delegate
// 激活策略由 AppDelegate 按用户设置(是否显示 Dock 图标)决定
app.run()
