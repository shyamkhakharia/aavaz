#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
WHISPER_DIR="$PROJECT_ROOT/vendor/whisper.cpp"
BUILD_DIR="$PROJECT_ROOT/vendor/whisper-build"
INSTALL_DIR="$PROJECT_ROOT/vendor/whisper-install"

# Parse arguments
BUILD_TYPE="${1:-Release}"

# Detect SDK and deployment target
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
MIN_DEPLOY_TARGET="15.0"

echo "Building whisper.cpp ($BUILD_TYPE)..."
echo "  SDK: $SDK_PATH (version $SDK_VERSION)"
echo "  Deployment target: $MIN_DEPLOY_TARGET"

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

cmake "$WHISPER_DIR" \
  -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
  -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR" \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$MIN_DEPLOY_TARGET" \
  -DCMAKE_OSX_SYSROOT="$SDK_PATH" \
  -DWHISPER_BUILD_EXAMPLES=OFF \
  -DWHISPER_BUILD_TESTS=OFF \
  -DWHISPER_BUILD_SERVER=OFF \
  -DGGML_METAL=ON \
  -DGGML_ACCELERATE=ON \
  -DGGML_COREML=OFF \
  -DBUILD_SHARED_LIBS=OFF

cmake --build . --config "$BUILD_TYPE" -j$(sysctl -n hw.ncpu)
cmake --install . --config "$BUILD_TYPE"

echo ""
echo "Whisper.cpp built successfully!"
echo "  Libraries: $INSTALL_DIR/lib/"
echo "  Headers:   $INSTALL_DIR/include/"
