@preconcurrency import AVFoundation
import CoreAudio

enum AudioRecorderError: Error, LocalizedError {
    case noMicrophonePermission
    case noInputDevice
    case formatError

    var errorDescription: String? {
        switch self {
        case .noMicrophonePermission: "Microphone permission not granted"
        case .noInputDevice: "No audio input device available"
        case .formatError: "Failed to create audio format"
        }
    }
}

@MainActor
final class AudioRecorder {
    private var audioEngine: AVAudioEngine?
    private var audioBuffer: [Float] = []
    private(set) var isRecording = false

    static let sampleRate: Double = 16000
    static let channelCount: UInt32 = 1

    func startRecording() throws {
        guard !isRecording else { return }

        // Check microphone permission first
        let authStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        guard authStatus == .authorized else {
            throw AudioRecorderError.noMicrophonePermission
        }

        audioBuffer.removeAll(keepingCapacity: true)

        let engine = AVAudioEngine()

        // Accessing inputNode can crash if no input device — check first
        guard engine.inputNode.inputFormat(forBus: 0).channelCount > 0 else {
            throw AudioRecorderError.noInputDevice
        }

        let inputNode = engine.inputNode

        guard let desiredFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.sampleRate,
            channels: AVAudioChannelCount(Self.channelCount),
            interleaved: false
        ) else {
            throw AudioRecorderError.formatError
        }

        let hwFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hwFormat) { [weak self] buffer, _ in
            let pcmBuffer: AVAudioPCMBuffer
            if hwFormat.sampleRate != AudioRecorder.sampleRate || hwFormat.channelCount != AudioRecorder.channelCount {
                guard let converter = AVAudioConverter(from: hwFormat, to: desiredFormat) else { return }
                let frameCapacity = AVAudioFrameCount(
                    Double(buffer.frameLength) * AudioRecorder.sampleRate / hwFormat.sampleRate
                )
                guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: desiredFormat, frameCapacity: frameCapacity) else { return }

                var error: NSError?
                let inputBuffer = buffer
                nonisolated(unsafe) var hasData = true
                converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                    if hasData {
                        hasData = false
                        outStatus.pointee = .haveData
                        return inputBuffer
                    }
                    outStatus.pointee = .noDataNow
                    return nil
                }

                if error != nil { return }
                pcmBuffer = convertedBuffer
            } else {
                pcmBuffer = buffer
            }

            guard let channelData = pcmBuffer.floatChannelData else { return }
            let frames = Int(pcmBuffer.frameLength)
            let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frames))

            DispatchQueue.main.async {
                self?.audioBuffer.append(contentsOf: samples)
            }
        }

        engine.prepare()
        try engine.start()

        self.audioEngine = engine
        isRecording = true
    }

    func stopRecording() -> [Float] {
        guard isRecording else { return [] }

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        isRecording = false

        let result = audioBuffer
        audioBuffer.removeAll()
        return result
    }

    static func requestMicrophoneAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}
