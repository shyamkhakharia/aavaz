# Aavaz

A macOS menubar push-to-talk voice-to-text app. Fully local transcription via whisper.cpp, configurable hotkey trigger, clean prose output injected at cursor.

## Requirements

- macOS 14+
- Apple Silicon (arm64)
- Xcode or Command Line Tools
- CMake (`brew install cmake`)

## Build

```bash
# Build whisper.cpp static library
./scripts/build-whisper.sh

# Build the app
swift build
```

## Usage

Double-tap Right Shift to start recording. Tap again to stop, transcribe, and paste at cursor. Configurable in Settings → Trigger Key.

## Profiles

- **Fast** — tiny.en model, lowest latency
- **Balanced** — base.en model, good accuracy
- **Quality** — medium.en model, best accuracy with CoreML

## License

MIT
