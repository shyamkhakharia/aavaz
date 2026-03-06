import Foundation

final class ModelManager: Sendable {
    enum ModelName: String, CaseIterable, Sendable {
        case tinyEN = "tiny.en"
        case baseEN = "base.en"
        case mediumEN = "medium.en"
    }

    private static let modelHashes: [ModelName: String] = [
        .tinyEN:   "921e4cf8b3368e495d5ed803dabe6e91e0ec4e82e775e4eb9e4ba8b597517b55",
        .baseEN:   "a03779c86df3323075f5e796cb2ce5029f00ec8869eee3fdfb897afe36ce1f1e",
        .mediumEN: "0848698aa8f80e43e0e5e87c4c53d tried 4f9b3e41e91f155b8eb3af3e6362d",
    ]

    private static let baseURL = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main"

    static let modelsDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("aavaz/models", isDirectory: true)
    }()

    func modelPath(for model: ModelName) -> URL {
        Self.modelsDirectory.appendingPathComponent("ggml-\(model.rawValue).bin")
    }

    func isModelDownloaded(_ model: ModelName) -> Bool {
        FileManager.default.fileExists(atPath: modelPath(for: model).path)
    }

    func downloadModel(_ model: ModelName, progress: @Sendable @escaping (Double) -> Void) async throws {
        let destination = modelPath(for: model)

        try FileManager.default.createDirectory(
            at: Self.modelsDirectory,
            withIntermediateDirectories: true
        )

        let urlString = "\(Self.baseURL)/ggml-\(model.rawValue).bin"
        guard let url = URL(string: urlString) else {
            throw ModelError.invalidURL(urlString)
        }

        let delegate = DownloadDelegate(progress: progress)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

        let (tempURL, response) = try await session.download(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ModelError.downloadFailed
        }

        // Move to final destination
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: tempURL, to: destination)

        // Verify SHA256
        if let expectedHash = Self.modelHashes[model] {
            let actualHash = try sha256(of: destination)
            if actualHash != expectedHash {
                try? FileManager.default.removeItem(at: destination)
                throw ModelError.hashMismatch(expected: expectedHash, actual: actualHash)
            }
        }
    }

    private func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { handle.closeFile() }

        var hasher = SHA256Hasher()
        while autoreleasepool(invoking: {
            let data = handle.readData(ofLength: 1024 * 1024)
            if data.isEmpty { return false }
            hasher.update(data: data)
            return true
        }) {}

        return hasher.finalize()
    }

    enum ModelError: Error, LocalizedError {
        case invalidURL(String)
        case downloadFailed
        case hashMismatch(expected: String, actual: String)

        var errorDescription: String? {
            switch self {
            case .invalidURL(let url): "Invalid download URL: \(url)"
            case .downloadFailed: "Model download failed"
            case .hashMismatch(let expected, let actual): "Hash mismatch: expected \(expected), got \(actual)"
            }
        }
    }
}

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, Sendable {
    let progress: @Sendable (Double) -> Void

    init(progress: @Sendable @escaping (Double) -> Void) {
        self.progress = progress
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // Handled in the async download call
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let pct = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        progress(pct)
    }
}

// Minimal SHA256 using CommonCrypto
import CommonCrypto

private struct SHA256Hasher {
    private var context = CC_SHA256_CTX()

    init() {
        CC_SHA256_Init(&context)
    }

    mutating func update(data: Data) {
        data.withUnsafeBytes { bytes in
            _ = CC_SHA256_Update(&context, bytes.baseAddress, CC_LONG(data.count))
        }
    }

    mutating func finalize() -> String {
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        CC_SHA256_Final(&digest, &context)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
