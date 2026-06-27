import Foundation
import Darwin

func log(_ message: String, to logURL: URL) {
    let stamp = ISO8601DateFormatter().string(from: Date())
    let line = "\(stamp) \(message)\n"
    if let data = line.data(using: .utf8) {
        if FileManager.default.fileExists(atPath: logURL.path),
           let handle = try? FileHandle(forWritingTo: logURL) {
            _ = try? handle.seekToEnd()
            _ = try? handle.write(contentsOf: data)
            _ = try? handle.close()
        } else {
            try? data.write(to: logURL)
        }
    }
}

@discardableResult
func run(_ executable: String, _ arguments: [String], logURL: URL) -> Bool {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: executable)
    proc.arguments = arguments
    let pipe = Pipe()
    proc.standardOutput = pipe
    proc.standardError = pipe
    do {
        try proc.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        if !data.isEmpty, let text = String(data: data, encoding: .utf8) {
            log(text.trimmingCharacters(in: .whitespacesAndNewlines), to: logURL)
        }
        return proc.terminationStatus == 0
    } catch {
        log("failed to run \(executable): \(error.localizedDescription)", to: logURL)
        return false
    }
}

func relaunch(appPath: String, logURL: URL) -> Bool {
    for attempt in 1...5 {
        log("relaunch attempt \(attempt): \(appPath)", to: logURL)
        if run("/usr/bin/open", ["-n", "-F", appPath], logURL: logURL) {
            sleep(1)
            if run("/usr/bin/pgrep", ["-x", "SnapAI"], logURL: logURL) {
                log("relaunch succeeded", to: logURL)
                return true
            }
        }
        sleep(1)
    }
    log("relaunch failed after retries", to: logURL)
    return false
}

let args = CommandLine.arguments
guard args.count == 6,
      let oldPID = pid_t(args[5]) else {
    FileHandle.standardError.write(Data("usage: SnapAIUpdater <app> <new-app> <backup> <log> <old-pid>\n".utf8))
    exit(2)
}

let appPath = args[1]
let newAppPath = args[2]
let backupPath = args[3]
let logURL = URL(fileURLWithPath: args[4])
let fileManager = FileManager.default

log("helper updater started", to: logURL)
var waited = 0
while kill(oldPID, 0) == 0 {
    usleep(200_000)
    waited += 1
    if waited >= 300 {
        log("old process \(oldPID) did not exit within 60s", to: logURL)
        exit(1)
    }
}
usleep(400_000)
log("old process exited", to: logURL)

do {
    try? fileManager.removeItem(atPath: backupPath)
    log("moving current app to backup", to: logURL)
    try fileManager.moveItem(atPath: appPath, toPath: backupPath)
} catch {
    log("failed to move current app to backup: \(error.localizedDescription)", to: logURL)
    _ = relaunch(appPath: appPath, logURL: logURL)
    exit(1)
}

log("copying new app into place", to: logURL)
if !run("/usr/bin/ditto", [newAppPath, appPath], logURL: logURL) {
    log("failed to copy new app; restoring backup", to: logURL)
    try? fileManager.removeItem(atPath: appPath)
    try? fileManager.moveItem(atPath: backupPath, toPath: appPath)
    _ = relaunch(appPath: appPath, logURL: logURL)
    exit(1)
}

log("clearing extended attributes", to: logURL)
_ = run("/usr/bin/xattr", ["-cr", appPath], logURL: logURL)
try? fileManager.removeItem(atPath: backupPath)
log("installation complete", to: logURL)
_ = relaunch(appPath: appPath, logURL: logURL)
exit(0)
