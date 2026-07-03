import AppKit

enum CaptureTargetSource: String, Equatable {
    case serviceInvocation
    case frontmost
    case lastExternal
    case none
}

enum CaptureTargetResolver {
    static func preferredDeferredSource(serviceInvocationPID: pid_t?,
                                        serviceInvocationIsTerminated: Bool,
                                        serviceInvocationBundleIdentifier: String? = nil,
                                        frontmostPID: pid_t?,
                                        frontmostIsTerminated: Bool,
                                        frontmostBundleIdentifier: String? = nil,
                                        lastExternalPID: pid_t?,
                                        lastExternalIsTerminated: Bool,
                                        lastExternalBundleIdentifier: String? = nil,
                                        currentPID: pid_t = ProcessInfo.processInfo.processIdentifier) -> CaptureTargetSource {
        if isUsableExternalApp(pid: serviceInvocationPID,
                               isTerminated: serviceInvocationIsTerminated,
                               bundleIdentifier: serviceInvocationBundleIdentifier,
                               currentPID: currentPID) {
            return .serviceInvocation
        }
        return preferredSource(frontmostPID: frontmostPID,
                               frontmostIsTerminated: frontmostIsTerminated,
                               frontmostBundleIdentifier: frontmostBundleIdentifier,
                               lastExternalPID: lastExternalPID,
                               lastExternalIsTerminated: lastExternalIsTerminated,
                               lastExternalBundleIdentifier: lastExternalBundleIdentifier,
                               currentPID: currentPID)
    }

    static func preferredSource(frontmostPID: pid_t?,
                                frontmostIsTerminated: Bool,
                                frontmostBundleIdentifier: String? = nil,
                                lastExternalPID: pid_t?,
                                lastExternalIsTerminated: Bool,
                                lastExternalBundleIdentifier: String? = nil,
                                currentPID: pid_t = ProcessInfo.processInfo.processIdentifier) -> CaptureTargetSource {
        if isUsableExternalApp(pid: frontmostPID,
                               isTerminated: frontmostIsTerminated,
                               bundleIdentifier: frontmostBundleIdentifier,
                               currentPID: currentPID) {
            return .frontmost
        }
        if isUsableExternalApp(pid: lastExternalPID,
                               isTerminated: lastExternalIsTerminated,
                               bundleIdentifier: lastExternalBundleIdentifier,
                               currentPID: currentPID) {
            return .lastExternal
        }
        return .none
    }

    static func resolve(frontmost: NSRunningApplication?,
                        lastExternal: NSRunningApplication?,
                        currentPID: pid_t = ProcessInfo.processInfo.processIdentifier) -> NSRunningApplication? {
        switch preferredSource(frontmostPID: frontmost?.processIdentifier,
                               frontmostIsTerminated: frontmost?.isTerminated ?? true,
                               frontmostBundleIdentifier: frontmost?.bundleIdentifier,
                               lastExternalPID: lastExternal?.processIdentifier,
                               lastExternalIsTerminated: lastExternal?.isTerminated ?? true,
                               lastExternalBundleIdentifier: lastExternal?.bundleIdentifier,
                               currentPID: currentPID) {
        case .serviceInvocation:
            return nil
        case .frontmost:
            return frontmost
        case .lastExternal:
            return lastExternal
        case .none:
            return nil
        }
    }

    static func resolveDeferred(serviceInvocation: NSRunningApplication?,
                                frontmost: NSRunningApplication?,
                                lastExternal: NSRunningApplication?,
                                currentPID: pid_t = ProcessInfo.processInfo.processIdentifier) -> NSRunningApplication? {
        switch preferredDeferredSource(serviceInvocationPID: serviceInvocation?.processIdentifier,
                                       serviceInvocationIsTerminated: serviceInvocation?.isTerminated ?? true,
                                       serviceInvocationBundleIdentifier: serviceInvocation?.bundleIdentifier,
                                       frontmostPID: frontmost?.processIdentifier,
                                       frontmostIsTerminated: frontmost?.isTerminated ?? true,
                                       frontmostBundleIdentifier: frontmost?.bundleIdentifier,
                                       lastExternalPID: lastExternal?.processIdentifier,
                                       lastExternalIsTerminated: lastExternal?.isTerminated ?? true,
                                       lastExternalBundleIdentifier: lastExternal?.bundleIdentifier,
                                       currentPID: currentPID) {
        case .serviceInvocation:
            return serviceInvocation
        case .frontmost:
            return frontmost
        case .lastExternal:
            return lastExternal
        case .none:
            return nil
        }
    }

    static func isUsableExternalApp(pid: pid_t?,
                                    isTerminated: Bool,
                                    bundleIdentifier: String? = nil,
                                    currentPID: pid_t = ProcessInfo.processInfo.processIdentifier) -> Bool {
        guard let pid,
              pid > 0,
              !isTerminated,
              pid != currentPID else {
            return false
        }
        if let bundleIdentifier,
           unsuitableCaptureBundleIdentifiers.contains(bundleIdentifier.lowercased()) {
            return false
        }
        return true
    }

    private static let unsuitableCaptureBundleIdentifiers: Set<String> = [
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
        "com.apple.systemuiserver"
    ]
}
