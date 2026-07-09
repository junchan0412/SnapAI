import Foundation

public enum ScreenCaptureTemporaryFile {
    public static func makeURL(temporaryDirectory: URL = FileManager.default.temporaryDirectory,
                               uuid: UUID = UUID()) -> URL {
        temporaryDirectory
            .appendingPathComponent("snapai-screen-\(uuid.uuidString)",
                                    isDirectory: false)
            .appendingPathExtension("png")
    }
}
