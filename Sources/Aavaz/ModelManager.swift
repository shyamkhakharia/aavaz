import Foundation
import CommonCrypto

final class ModelManager: Sendable {
    enum ModelName: String, CaseIterable, Sendable {
        case tinyEN = "tiny.en"
        case baseEN = "base.en"
        case mediumEN = "medium.en"
    }

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

        // Use bytes(for:) for reliable streaming progress
        let (bytes, response) = try await URLSession.shared.bytes(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ModelError.downloadFailed
        }

        let totalBytes = httpResponse.expectedContentLength
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        FileManager.default.createFile(atPath: tempURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: tempURL)
        defer { try? handle.close() }

        var receivedBytes: Int64 = 0
        var buffer = Data()
        let chunkSize = 256 * 1024 // 256KB write chunks

        for try await byte in bytes {
            try Task.checkCancellation()

            buffer.append(byte)

            if buffer.count >= chunkSize {
                handle.write(buffer)
                receivedBytes += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)

                if totalBytes > 0 {
                    progress(Double(receivedBytes) / Double(totalBytes))
                }
            }
        }

        // Write remaining bytes
        if !buffer.isEmpty {
            handle.write(buffer)
            receivedBytes += Int64(buffer.count)
        }

        try handle.close()
        progress(1.0)

        // Move to final destination
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: tempURL, to: destination)
    }

    enum ModelError: Error, LocalizedError {
        case invalidURL(String)
        case downloadFailed

        var errorDescription: String? {
            switch self {
            case .invalidURL(let url): "Invalid download URL: \(url)"
            case .downloadFailed: "Model download failed"
            }
        }
    }
}
