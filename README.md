# Aavaz

A macOS menubar push-to-talk voice-to-text app. Fully local transcription via whisper.cpp, configurable hotkey trigger, clean prose output injected at cursor.

## Download

Grab the latest `.dmg` from [Releases](https://github.com/shyamkhakharia/aavaz/releases) — no build required.

## Build from Source

### Requirements

- macOS 15+
- Apple Silicon (arm64)
- Xcode or Command Line Tools
- CMake (`brew install cmake`)

### Steps

```bash
# Clone with submodules (important!)
git clone --recursive https://github.com/shyamkhakharia/aavaz.git
cd aavaz

# If you already cloned without --recursive:
git submodule update --init --recursive

# Build whisper.cpp static library
./scripts/build-whisper.sh

# Build the .app bundle
./scripts/bundle-app.sh

# Launch
open build/Aavaz.app
```

## Usage

Double-tap Right Option to start recording. Tap again to stop, transcribe, and paste at cursor.

On first launch, the onboarding wizard will guide you through setup — choose your trigger key, transcription profile, and grant permissions.

## Profiles

- **Fast** — tiny.en model, lowest latency
- **Balanced** — base.en model, good accuracy
- **Quality** — medium.en model, best accuracy

## License

MIT
