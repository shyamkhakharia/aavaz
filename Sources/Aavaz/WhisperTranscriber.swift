import Foundation
import CWhisper

final class WhisperTranscriber: @unchecked Sendable {
    struct TranscriptionConfig: Sendable {
        var modelPath: String
        var useVAD: Bool = false
        var initialPrompt: String? = nil
        var useCoreML: Bool = false
        var language: String = "en"
    }

    private var context: OpaquePointer?
    private var loadedModelPath: String?

    deinit {
        if let context {
            whisper_free(context)
        }
    }

    func loadModel(path: String) throws {
        if loadedModelPath == path, context != nil { return }

        if let context {
            whisper_free(context)
            self.context = nil
        }

        var cparams = whisper_context_default_params()
        cparams.use_gpu = true
        cparams.flash_attn = true

        guard let ctx = whisper_init_from_file_with_params(path, cparams) else {
            throw TranscriptionError.modelLoadFailed(path)
        }

        self.context = ctx
        self.loadedModelPath = path
    }

    func transcribe(audioBuffer: [Float], config: TranscriptionConfig) throws -> String {
        if loadedModelPath != config.modelPath || context == nil {
            try loadModel(path: config.modelPath)
        }

        guard let ctx = context else {
            throw TranscriptionError.noContext
        }

        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.n_threads = Int32(max(1, ProcessInfo.processInfo.activeProcessorCount - 2))
        params.print_progress = false
        params.print_special = false
        params.print_realtime = false
        params.print_timestamps = false
        params.translate = false
        params.single_segment = false
        params.no_timestamps = true
        params.suppress_blank = true
        params.suppress_nst = true

        let promptCString = config.initialPrompt.flatMap { $0.isEmpty ? nil : strdup($0) }
        params.initial_prompt = UnsafePointer(promptCString)

        let langCString = strdup(config.language)
        params.language = UnsafePointer(langCString)

        let result = audioBuffer.withUnsafeBufferPointer { bufferPtr in
            whisper_full(ctx, params, bufferPtr.baseAddress, Int32(bufferPtr.count))
        }

        free(promptCString)
        free(langCString)

        guard result == 0 else {
            throw TranscriptionError.transcriptionFailed(code: Int(result))
        }

        let nSegments = whisper_full_n_segments(ctx)
        var text = ""
        for i in 0..<nSegments {
            if let segmentText = whisper_full_get_segment_text(ctx, i) {
                text += String(cString: segmentText)
            }
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    enum TranscriptionError: Error, LocalizedError {
        case modelLoadFailed(String)
        case noContext
        case transcriptionFailed(code: Int)

        var errorDescription: String? {
            switch self {
            case .modelLoadFailed(let path): "Failed to load model at \(path)"
            case .noContext: "No whisper context available"
            case .transcriptionFailed(let code): "Transcription failed with code \(code)"
            }
        }
    }
}
