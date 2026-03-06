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

Double-tap the Right Option key to start recording. Release to transcribe and paste at cursor.

## Profiles

- **Fast** — tiny.en model, lowest latency
- **Balanced** — base.en model, good accuracy
- **Quality** — medium.en model, best accuracy with CoreML

## License

MIT
