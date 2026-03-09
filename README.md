<p align="center">
  <img src="docs/logo.svg" width="80" height="80" alt="Aavaz logo">
</p>

<h1 align="center">Aavaz</h1>
<p align="center"><strong>Voice to text, entirely on your Mac.</strong></p>
<p align="center">Push-to-talk transcription that lives in your menubar. Fully local. No cloud. No latency.</p>

<p align="center">
  <a href="https://github.com/shyamkhakharia/aavaz/releases/latest"><img src="https://img.shields.io/github/v/release/shyamkhakharia/aavaz?style=flat-square&color=6E6AE8" alt="Release"></a>
  <a href="https://github.com/shyamkhakharia/aavaz/blob/main/LICENSE"><img src="https://img.shields.io/github/license/shyamkhakharia/aavaz?style=flat-square" alt="License"></a>
  <img src="https://img.shields.io/badge/platform-macOS%2015%2B-000?style=flat-square" alt="Platform">
  <img src="https://img.shields.io/badge/chip-Apple%20Silicon-000?style=flat-square" alt="Apple Silicon">
</p>

---

## Download

Grab the latest `.dmg` from [**Releases**](https://github.com/shyamkhakharia/aavaz/releases/latest) — no build tools required.

## How It Works

1. **Download & install** — drop Aavaz into Applications
2. **Walk through setup** — the onboarding wizard helps you pick a trigger key, choose a transcription profile, and grant permissions
3. **Start talking** — double-tap your trigger key to record, tap again to stop. Transcribed text appears at the cursor

## Profiles

| Profile | Model | Size | Latency | Best for |
|---------|-------|------|---------|----------|
| **Fast** | whisper tiny.en | ~75 MB | < 1s | Quick notes |
| **Balanced** | whisper base.en | ~142 MB | ~1-2s | Daily use |
| **Quality** | whisper medium.en | ~1.5 GB | ~3-5s | Long-form dictation |

Models are downloaded on-demand during setup. You can add or remove models from the menubar at any time.

## Features

- **Fully local** — audio never leaves your Mac. No cloud, no accounts, no data collection
- **Metal accelerated** — hardware-accelerated inference via Apple's GPU framework
- **Configurable hotkey** — double-tap Right Option by default, customisable to any key
- **Cursor injection** — transcribed text is pasted at your cursor in any app. Clipboard preserved
- **Menubar native** — lives in the menubar with no dock icon. Visual + audio feedback for recording state

## Build from Source

### Requirements

- macOS 15+
- Apple Silicon (arm64)
- Xcode or Command Line Tools
- CMake (`brew install cmake`)

### Steps

```bash
git clone --recursive https://github.com/shyamkhakharia/aavaz.git
cd aavaz

# Build whisper.cpp static library
./scripts/build-whisper.sh

# Build the .app bundle
./scripts/bundle-app.sh

# Launch
open build/Aavaz.app
```

## License

MIT
