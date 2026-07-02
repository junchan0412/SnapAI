import AppKit

enum ServicePasteboardText {
    static let supportedPlainTextTypes: [NSPasteboard.PasteboardType] = [
        .string,
        NSPasteboard.PasteboardType("public.utf8-plain-text"),
        NSPasteboard.PasteboardType("public.utf16-plain-text"),
        NSPasteboard.PasteboardType("public.utf16-external-plain-text"),
        NSPasteboard.PasteboardType("public.plain-text"),
        NSPasteboard.PasteboardType("public.text"),
        NSPasteboard.PasteboardType("NSStringPboardType"),
        NSPasteboard.PasteboardType("NeXT plain ascii pasteboard type"),
        NSPasteboard.PasteboardType("com.apple.traditional-mac-plain-text")
    ]

    private static let supportedAttributedTextTypes: [(NSPasteboard.PasteboardType, NSAttributedString.DocumentType)] = [
        (NSPasteboard.PasteboardType("public.rtf"), .rtf),
        (NSPasteboard.PasteboardType("NSRTFPboardType"), .rtf),
        (NSPasteboard.PasteboardType("public.html"), .html),
        (NSPasteboard.PasteboardType("NSHTMLPboardType"), .html),
        (NSPasteboard.PasteboardType("Apple HTML pasteboard type"), .html)
    ]
    private static let supportedPlainTextTypeNames = Set(supportedPlainTextTypes.map(\.rawValue))
    private static let legacyPlainTextTypeNames: Set<String> = [
        "NSStringPboardType",
        "NeXT plain ascii pasteboard type",
        "com.apple.traditional-mac-plain-text"
    ]
    private static let legacyAttributedTextTypeNames: Set<String> = [
        "NSRTFPboardType",
        "NSHTMLPboardType",
        "Apple HTML pasteboard type"
    ]
    private static let legacyPasteboardTypeNames = legacyPlainTextTypeNames.union(legacyAttributedTextTypeNames)

    static func text(from pasteboard: NSPasteboard) -> String? {
        for text in attributedTextCandidates(from: pasteboard) {
            if TextCapture.usableCapturedText(text) != nil {
                return text
            }
        }

        for text in plainTextCandidates(from: pasteboard) {
            if TextCapture.usableCapturedText(text) != nil {
                return text
            }
        }

        if let objects = pasteboard.readObjects(forClasses: [NSString.self, NSAttributedString.self], options: nil) {
            for object in objects {
                let text: String?
                if let string = object as? String {
                    text = string
                } else if let attributed = object as? NSAttributedString {
                    text = attributed.string
                } else {
                    text = nil
                }
                if let text,
                   TextCapture.usableCapturedText(text) != nil {
                    return text
                }
            }
        }

        return nil
    }

    private static func plainTextCandidates(from pasteboard: NSPasteboard) -> [String] {
        var candidates: [String] = []
        for type in orderedPlainTextTypes(availableTypes: pasteboard.types) {
            if let text = stringValue(from: pasteboard, forType: type) {
                candidates.append(text)
            } else if canReadData(for: type),
                      let data = dataValue(from: pasteboard, forType: type),
                      let text = decodedPlainText(data, type: type) {
                candidates.append(text)
            }
        }
        for item in pasteboard.pasteboardItems ?? [] {
            for type in orderedPlainTextTypes(availableTypes: item.types) {
                if let text = stringValue(from: item, forType: type) {
                    candidates.append(text)
                } else if canReadData(for: type),
                          let data = dataValue(from: item, forType: type),
                          let text = decodedPlainText(data, type: type) {
                    candidates.append(text)
                }
            }
        }
        return candidates
    }

    private static func stringValue(from pasteboard: NSPasteboard,
                                    forType type: NSPasteboard.PasteboardType) -> String? {
        if legacyPlainTextTypeNames.contains(type.rawValue) {
            if let text = pasteboard.propertyList(forType: type) as? String {
                return text
            }
        }
        return pasteboard.string(forType: type)
    }

    private static func stringValue(from item: NSPasteboardItem,
                                    forType type: NSPasteboard.PasteboardType) -> String? {
        if legacyPlainTextTypeNames.contains(type.rawValue) {
            if let text = item.propertyList(forType: type) as? String {
                return text
            }
        }
        return item.string(forType: type)
    }

    private static func orderedPlainTextTypes(availableTypes: [NSPasteboard.PasteboardType]?) -> [NSPasteboard.PasteboardType] {
        var result: [NSPasteboard.PasteboardType] = []
        var seen = Set<String>()

        func append(_ type: NSPasteboard.PasteboardType) {
            guard supportedPlainTextTypeNames.contains(type.rawValue),
                  seen.insert(type.rawValue).inserted else { return }
            result.append(type)
        }

        for type in availableTypes ?? [] {
            append(type)
        }
        for type in supportedPlainTextTypes {
            guard !legacyPasteboardTypeNames.contains(type.rawValue) else { continue }
            append(type)
        }
        return result
    }

    private static func attributedTextCandidates(from pasteboard: NSPasteboard) -> [String] {
        var candidates: [String] = []
        for (type, documentType) in supportedAttributedTextTypes {
            guard shouldRead(type, availableTypes: pasteboard.types) else { continue }
            if let text = attributedText(from: dataValue(from: pasteboard, forType: type),
                                         documentType: documentType) {
                candidates.append(text)
            }
        }
        for item in pasteboard.pasteboardItems ?? [] {
            for (type, documentType) in supportedAttributedTextTypes {
                guard shouldRead(type, availableTypes: item.types) else { continue }
                if let text = attributedText(from: dataValue(from: item, forType: type),
                                             documentType: documentType) {
                    candidates.append(text)
                }
            }
        }
        return candidates
    }

    private static func shouldRead(_ type: NSPasteboard.PasteboardType,
                                   availableTypes: [NSPasteboard.PasteboardType]?) -> Bool {
        guard let availableTypes else { return true }
        return availableTypes.contains { $0.rawValue == type.rawValue }
    }

    private static func dataValue(from pasteboard: NSPasteboard,
                                  forType type: NSPasteboard.PasteboardType) -> Data? {
        if legacyPasteboardTypeNames.contains(type.rawValue) {
            return legacyData(from: pasteboard.propertyList(forType: type))
        }
        return pasteboard.data(forType: type)
    }

    private static func dataValue(from item: NSPasteboardItem,
                                  forType type: NSPasteboard.PasteboardType) -> Data? {
        if legacyPasteboardTypeNames.contains(type.rawValue) {
            return legacyData(from: item.propertyList(forType: type))
        }
        return item.data(forType: type)
    }

    private static func legacyData(from propertyList: Any?) -> Data? {
        if let data = propertyList as? Data {
            return data
        }
        if let string = propertyList as? String {
            return Data(string.utf8)
        }
        return nil
    }

    private static func decodedPlainText(_ data: Data,
                                         type: NSPasteboard.PasteboardType) -> String? {
        let raw = type.rawValue.lowercased()
        let encodings: [String.Encoding]
        if raw.contains("utf16") {
            encodings = [.utf16LittleEndian, .utf16BigEndian, .utf16, .utf8]
        } else {
            encodings = [.utf8, .ascii]
        }
        for encoding in encodings {
            if let text = String(data: data, encoding: encoding) {
                return text
            }
        }
        return nil
    }

    private static func canReadData(for type: NSPasteboard.PasteboardType) -> Bool {
        let raw = type.rawValue.lowercased()
        return raw.hasPrefix("public.") || legacyPasteboardTypeNames.contains(type.rawValue)
    }

    private static func attributedText(from data: Data?,
                                       documentType: NSAttributedString.DocumentType) -> String? {
        guard let data else { return nil }
        var options: [NSAttributedString.DocumentReadingOptionKey: Any] = [.documentType: documentType]
        if documentType == .html {
            options[.characterEncoding] = String.Encoding.utf8.rawValue
        }
        return try? NSAttributedString(
            data: data,
            options: options,
            documentAttributes: nil
        ).string
    }
}
