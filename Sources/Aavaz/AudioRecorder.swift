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

/// Collects audio samples from the tap callback on the audio thread.
/// NOT MainActor-isolated so the tap closure doesn't trigger runtime executor checks.
final class AudioBufferCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Float] = []

    func append(_ newSamples: [Float]) {
        lock.lock()
        samples.append(contentsOf: newSamples)
        lock.unlock()
    }

    func drain() -> [Float] {
        lock.lock()
        let result = samples
        samples.removeAll()
        lock.unlock()
        return result
    }

    func clear() {
        lock.lock()
        samples.removeAll(keepingCapacity: true)
        lock.unlock()
    }
}

/// Installs the audio tap outside of any actor context so Swift 6 doesn't
/// insert a MainActor executor check in the tap callback.
private enum AudioTapInstaller {
    nonisolated static func installTap(
        on inputNode: AVAudioInputNode,
        hwFormat: AVAudioFormat,
        desiredFormat: AVAudioFormat,
        collector: AudioBufferCollector
    ) {
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hwFormat) { buffer, _ in
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

            collector.append(samples)
        }
    }
}

@MainActor
final class AudioRecorder {
    private var audioEngine: AVAudioEngine?
    private let collector = AudioBufferCollector()
    private(set) var isRecording = false

    nonisolated static let sampleRate: Double = 16000
    nonisolated static let channelCount: UInt32 = 1

    func startRecording() throws {
        guard !isRecording else { return }

        // Check microphone permission first
        let authStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        guard authStatus == .authorized else {
            throw AudioRecorderError.noMicrophonePermission
        }

        collector.clear()

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

        AudioTapInstaller.installTap(
            on: inputNode,
            hwFormat: hwFormat,
            desiredFormat: desiredFormat,
            collector: collector
        )

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

        return collector.drain()
    }

    static func requestMicrophoneAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}
