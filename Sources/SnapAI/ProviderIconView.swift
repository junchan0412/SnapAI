import AppKit
import SnapAILogic
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class ProviderIconLibrary: ObservableObject {
    static let shared = ProviderIconLibrary()
    static let symbols = ["network", "server.rack", "desktopcomputer", "cpu", "brain", "bolt.fill", "leaf.fill", "cloud.fill"]
    @Published private(set) var files: [String] = []
    private let directory: URL
    private var images: [String: NSImage] = [:]
    private var downloads: [URL: Task<NSImage?, Never>] = [:]
    private var failedDownloads: [URL: Date] = [:]

    init(directory: URL? = nil) {
        let support = ProcessInfo.processInfo.environment["SNAPAI_LOGIC_TESTS"] == "1"
            ? FileManager.default.temporaryDirectory.appendingPathComponent("SnapAI-LogicTests-\(ProcessInfo.processInfo.processIdentifier)")
            : FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("SnapAI")
        self.directory = directory ?? support.appendingPathComponent("ProviderIcons", isDirectory: true)
        reload()
    }

    private func reload() {
        files = ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
            .filter { $0.hasSuffix(".png") }.sorted()
    }

    func localImage(_ name: String) -> NSImage? {
        guard files.contains(name), name == URL(fileURLWithPath: name).lastPathComponent else { return nil }
        if let image = images[name] { return image }
        let image = NSImage(contentsOf: directory.appendingPathComponent(name))
        images[name] = image
        return image
    }

    func add(_ url: URL) throws -> String {
        guard let source = NSImage(contentsOf: url), source.size.width > 0, source.size.height > 0 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let size = NSSize(width: 256, height: 256)
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 256, pixelsHigh: 256,
                                             bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                             isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { throw CocoaError(.fileReadCorruptFile) }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.clear(NSRect(origin: .zero, size: size))
        context.imageInterpolation = .high
        let scale = min(size.width / source.size.width, size.height / source.size.height)
        let fit = NSSize(width: source.size.width * scale, height: source.size.height * scale)
        source.draw(in: NSRect(x: (256 - fit.width) / 2, y: (256 - fit.height) / 2, width: fit.width, height: fit.height))
        NSGraphicsContext.restoreGraphicsState()
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileReadCorruptFile) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = UUID().uuidString + ".png"
        try data.write(to: directory.appendingPathComponent(name), options: .atomic)
        reload()
        return name
    }

    func remove(_ name: String) throws {
        guard files.contains(name) else { return }
        try FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        images[name] = nil
        reload()
    }

    func websiteImage(_ website: URL, allowsNetwork: Bool = true) async -> NSImage? {
        let key = website.absoluteString
        if let cached = images[key] { return cached }
        guard allowsNetwork, ProcessInfo.processInfo.environment["SNAPAI_LOGIC_TESTS"] != "1" else { return nil }
        if let task = downloads[website] { return await task.value }
        if let failed = failedDownloads[website], Date().timeIntervalSince(failed) < 60 { return nil }
        let task = Task<NSImage?, Never> {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 5
            configuration.timeoutIntervalForResource = 10
            configuration.httpCookieStorage = nil
            configuration.httpShouldSetCookies = false
            configuration.urlCredentialStorage = nil
            let session = URLSession(configuration: configuration)
            defer { session.invalidateAndCancel() }
            var candidates: [URL] = []
            if let (data, response) = try? await session.data(from: website),
               let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
               data.count <= 1_000_000, let html = String(data: data, encoding: .utf8),
               let regex = try? NSRegularExpression(pattern: "<link\\b[^>]*>", options: .caseInsensitive) {
                for match in regex.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
                    guard let range = Range(match.range, in: html) else { continue }
                    let tag = String(html[range])
                    guard tag.range(of: "rel\\s*=\\s*[\"'][^\"']*\\b(icon|apple-touch-icon)\\b", options: [.regularExpression, .caseInsensitive]) != nil,
                          let href = tag.range(of: "href\\s*=\\s*[\"']([^\"']+)[\"']", options: [.regularExpression, .caseInsensitive]) else { continue }
                    let attribute = String(tag[href])
                    guard let first = attribute.firstIndex(where: { $0 == "\"" || $0 == "'" }) else { continue }
                    let value = String(attribute[attribute.index(after: first)..<attribute.index(before: attribute.endIndex)])
                        .replacingOccurrences(of: "&amp;", with: "&")
                    if let url = URL(string: value, relativeTo: response.url ?? website)?.absoluteURL,
                       ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                       website.scheme?.lowercased() != "https" || url.scheme?.lowercased() == "https",
                       url.user == nil, url.password == nil, !candidates.contains(url) { candidates.append(url) }
                }
            }
            let fallback = website.appendingPathComponent("favicon.ico")
            candidates = Array(candidates.filter { $0 != fallback }.prefix(7)) + [fallback]
            for url in candidates {
                if let (data, response) = try? await session.data(from: url),
                   let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                   data.count <= 2_000_000, let image = NSImage(data: data), image.isValid { return image }
            }
            return nil
        }
        downloads[website] = task
        let image = await task.value
        downloads[website] = nil
        images[key] = image
        failedDownloads[website] = image == nil ? Date() : nil
        return image
    }
}

struct ProviderIconView: View {
    let provider: AIProvider
    var size: CGFloat = 28
    var allowsWebsiteRequest = true
    @ObservedObject private var library = ProviderIconLibrary.shared
    @State private var downloaded: NSImage?

    var body: some View {
        Group {
            if let customSymbol {
                Image(systemName: customSymbol).resizable().scaledToFit().padding(4)
            } else if let custom = provider.customIcon, let image = library.localImage(custom) {
                Image(nsImage: image).resizable().scaledToFit()
            } else if let downloaded {
                Image(nsImage: downloaded).resizable().scaledToFit()
            } else {
                Image(systemName: provider.isLocalEndpoint ? "desktopcomputer" : "network")
                    .resizable().scaledToFit().padding(4).foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
        .accessibilityLabel("\(provider.name) 图标")
        .task(id: "\(provider.iconWebsite?.absoluteString ?? "")|\(provider.customIcon ?? "")|\(allowsWebsiteRequest)") {
            downloaded = nil
            if let custom = provider.customIcon,
               customSymbol != nil || library.localImage(custom) != nil { return }
            if let website = provider.iconWebsite {
                let image = await library.websiteImage(website, allowsNetwork: allowsWebsiteRequest)
                guard !Task.isCancelled else { return }
                downloaded = image
            }
        }
    }

    private var customSymbol: String? {
        guard let custom = provider.customIcon, custom.hasPrefix("symbol:") else { return nil }
        let symbol = String(custom.dropFirst(7))
        return NSImage(systemSymbolName: symbol, accessibilityDescription: nil) == nil ? nil : symbol
    }
}

struct ProviderIconPicker: View {
    let provider: AIProvider?
    @ObservedObject var settings: AppSettings
    let commit: () -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var library = ProviderIconLibrary.shared
    @State private var error: String?
    @State private var pendingDelete: String?
    @State private var website = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("图标库").font(.title2.weight(.semibold))
                    Text(provider.map { "为 \($0.name) 选择图标" } ?? "管理本机图标，可供所有供应商复用")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("完成") { if saveWebsite() { dismiss() } }.keyboardShortcut(.defaultAction)
            }
            if provider != nil {
                HStack {
                    TextField("网站地址（留空则根据 API 端点获取）", text: $website)
                        .onSubmit { _ = saveWebsite() }
                    Button("使用网站图标") { choose(nil) }
                }
                Text(settings.prefersLocalModelRoutes
                     ? "隐私模式下暂停网站请求，网站设置仍会保存；可继续使用缓存、本地图片或内置符号。"
                     : "自动读取网站声明的 favicon，失败时显示通用图标。请求不携带 API Key；本地图标只保存在这台 Mac。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 14) {
                    ForEach(ProviderIconLibrary.symbols, id: \.self) { symbol in
                        iconButton("symbol:" + symbol) {
                            Image(systemName: symbol).font(.system(size: 24)).frame(width: 40, height: 40)
                        }
                    }
                    ForEach(library.files, id: \.self) { name in
                        if let image = library.localImage(name) {
                            iconButton(name) {
                                Image(nsImage: image).resizable().scaledToFit().frame(width: 40, height: 40)
                            }
                            .overlay(alignment: .topTrailing) {
                                Button { pendingDelete = name } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, Color.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("删除图标")
                                .accessibilityLabel("删除自定义图标")
                            }
                            .contextMenu { Button("删除图标…", role: .destructive) { pendingDelete = name } }
                        }
                    }
                }.padding(4)
            }.frame(minHeight: 150, maxHeight: 280)
            HStack {
                Button("导入图片…", systemImage: "plus") { importImage() }
                Spacer()
                Text("PNG、JPEG、HEIC、TIFF、ICO 等系统支持的图片")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }
        .padding(24).frame(width: 560)
        .onAppear { website = provider?.websiteURL ?? "" }
        .onDisappear { _ = saveWebsite() }
        .confirmationDialog("删除图标？使用它的供应商将恢复网站图标。", isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible) {
                Button("删除", role: .destructive) {
                    guard let name = pendingDelete else { return }
                    do {
                        try library.remove(name)
                        for index in settings.providers.indices where settings.providers[index].customIcon == name {
                            settings.providers[index].customIcon = nil
                        }
                        commit()
                    } catch { self.error = "删除失败：\(error.localizedDescription)" }
                    pendingDelete = nil
                }
            }
    }

    @ViewBuilder
    private func iconButton<Content: View>(_ value: String, @ViewBuilder content: () -> Content) -> some View {
        let tile = content().frame(maxWidth: .infinity).padding(8)
            .background(selectedIcon == value ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).stroke(selectedIcon == value ? Color.accentColor : .clear) }
        if provider != nil {
            Button { choose(value) } label: { tile }
                .buttonStyle(.plain)
                .accessibilityLabel(value.hasPrefix("symbol:") ? String(value.dropFirst(7)) : "自定义图标")
                .accessibilityAddTraits(selectedIcon == value ? .isSelected : [])
        } else {
            tile.accessibilityLabel(value.hasPrefix("symbol:") ? String(value.dropFirst(7)) : "自定义图标")
        }
    }

    private var selectedIcon: String? {
        settings.providers.first(where: { $0.id == provider?.id })?.customIcon
    }

    private func saveWebsite() -> Bool {
        guard let provider, let index = settings.providers.firstIndex(where: { $0.id == provider.id }) else { return true }
        let trimmed = website.trimmingCharacters(in: .whitespacesAndNewlines)
        var updated = settings.providers[index]
        updated.websiteURL = trimmed
        guard trimmed.isEmpty || updated.iconWebsite != nil else {
            error = "请输入有效的 http/https 网站地址，或留空使用 API 端点的网站。"
            return false
        }
        error = nil
        guard settings.providers[index].websiteURL != trimmed else { return true }
        settings.providers[index].websiteURL = trimmed
        commit()
        return true
    }

    private func choose(_ value: String?) {
        guard saveWebsite() else { return }
        guard let provider, let index = settings.providers.firstIndex(where: { $0.id == provider.id }) else { return }
        settings.providers[index].customIcon = value
        commit()
    }

    private func importImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let name = try library.add(url)
            error = nil
            choose(name)
        }
        catch { self.error = "无法导入图片：\(error.localizedDescription)" }
    }
}
