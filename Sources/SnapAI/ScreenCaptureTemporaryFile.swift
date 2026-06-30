import Foundation

enum ScreenCaptureTemporaryFile {
    static func makeURL(temporaryDirectory: URL = FileManager.default.temporaryDirectory,
                        uuid: UUID = UUID()) -> URL {
        temporaryDirectory
            .appendingPathComponent("snapai-screen-\(uuid.uuidString)",
                                    isDirectory: false)
            .appendingPathExtension("png")
    }
}
