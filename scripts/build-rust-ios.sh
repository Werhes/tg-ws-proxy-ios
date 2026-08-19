#!/usr/bin/env bash
set -eu

# Builds libtgwsproxy.a from src-wrapper for the active iOS SDK/architecture.
# Called from an Xcode "Run Script" build phase, so it has access to
# PLATFORM_NAME / ARCHS / SDKROOT / BUILT_PRODUCTS_DIR environment variables.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST_PATH="$ROOT_DIR/src-wrapper/Cargo.toml"
TARGET_DIR="${DERIVED_FILE_DIR:-$ROOT_DIR/.build}/rust-target"
# Fixed output location referenced by LIBRARY_SEARCH_PATHS in the Xcode project.
OUTPUT_DIR="$ROOT_DIR/TGWSProxy/libs"

export PATH="$HOME/.cargo/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

find_tool() {
  TOOL_NAME="$1"
  if command -v "$TOOL_NAME" >/dev/null 2>&1; then
    command -v "$TOOL_NAME"
    return
  fi

  for CANDIDATE in \
    "$HOME/.cargo/bin/$TOOL_NAME" \
    "/opt/homebrew/bin/$TOOL_NAME" \
    "/usr/local/bin/$TOOL_NAME"
  do
    if [ -x "$CANDIDATE" ]; then
      printf '%s\n' "$CANDIDATE"
      return
    fi
  done

  echo "$TOOL_NAME was not found. Install Rust with rustup.rs." >&2
  exit 1
}

RUSTUP_BIN="$(find_tool rustup)"

# Ensure the iOS Rust targets are installed (idempotent).
"$RUSTUP_BIN" target list --installed | grep -qx "aarch64-apple-ios" || \
  "$RUSTUP_BIN" target add aarch64-apple-ios >/dev/null
"$RUSTUP_BIN" target list --installed | grep -qx "aarch64-apple-ios-sim" || \
  "$RUSTUP_BIN" target add aarch64-apple-ios-sim >/dev/null
"$RUSTUP_BIN" target list --installed | grep -qx "x86_64-apple-ios" || \
  "$RUSTUP_BIN" target add x86_64-apple-ios >/dev/null

RUSTC_BIN="$("$RUSTUP_BIN" which --toolchain stable rustc)"
CARGO_BIN="$("$RUSTUP_BIN" which --toolchain stable cargo)"

if [ -n "${SDKROOT:-}" ] && [ ! -d "$SDKROOT" ]; then
  echo "SDKROOT does not exist: $SDKROOT" >&2
  echo "Select a full Xcode installation in Xcode Settings > Locations." >&2
  exit 1
fi

export IPHONEOS_DEPLOYMENT_TARGET="${IPHONEOS_DEPLOYMENT_TARGET:-17.0}"

# Generate Cargo.lock on first build if it is missing.
if [ ! -f "$ROOT_DIR/src-wrapper/Cargo.lock" ]; then
  echo "Cargo.lock missing; generating..."
  (cd "$ROOT_DIR/src-wrapper" && "$CARGO_BIN" generate-lockfile)
fi

mkdir -p "$OUTPUT_DIR"

requested_architectures() {
  if [ -n "${ARCHS:-}" ]; then
    printf '%s\n' "$ARCHS"
  elif [ -n "${CURRENT_ARCH:-}" ] && [ "$CURRENT_ARCH" != "undefined_arch" ]; then
    printf '%s\n' "$CURRENT_ARCH"
  else
    printf '%s\n' "arm64"
  fi
}

rust_target_for_architecture() {
  ARCHITECTURE="$1"
  case "${PLATFORM_NAME:-iphonesimulator}:$ARCHITECTURE" in
    iphoneos:arm64|iphoneos:arm64e) printf '%s\n' "aarch64-apple-ios" ;;
    iphonesimulator:arm64) printf '%s\n' "aarch64-apple-ios-sim" ;;
    iphonesimulator:x86_64) printf '%s\n' "x86_64-apple-ios" ;;
    *)
      echo "Unsupported platform/architecture: ${PLATFORM_NAME:-unknown}/$ARCHITECTURE" >&2
      exit 1
      ;;
  esac
}

# Deduplicate by Rust target so "arm64 arm64e" builds only once.
BUILT_TARGETS=""
set -- "$@"
for ARCHITECTURE in $(requested_architectures); do
  RUST_TARGET="$(rust_target_for_architecture "$ARCHITECTURE")"
  case " $BUILT_TARGETS " in
    *" $RUST_TARGET "*) continue ;;
  esac
  BUILT_TARGETS="$BUILT_TARGETS $RUST_TARGET"
  CARGO_TARGET_DIR="$TARGET_DIR" "$CARGO_BIN" rustc \
    --manifest-path "$MANIFEST_PATH" \
    --target "$RUST_TARGET" \
    --release \
    --locked \
    --lib \
    -- \
    --crate-type=staticlib

  LIBRARY_PATH="$TARGET_DIR/$RUST_TARGET/release/libtgwsproxy.a"
  if [ ! -f "$LIBRARY_PATH" ]; then
    LIBRARY_PATH="$TARGET_DIR/$RUST_TARGET/release/deps/libtgwsproxy.a"
  fi

  if [ ! -f "$LIBRARY_PATH" ]; then
    echo "Cargo completed but libtgwsproxy.a was not found for $RUST_TARGET." >&2
    exit 1
  fi

  set -- "$@" "$LIBRARY_PATH"
done

if [ "$#" -eq 1 ]; then
  cp "$1" "$OUTPUT_DIR/libtgwsproxy.a"
else
  xcrun lipo -create "$@" -output "$OUTPUT_DIR/libtgwsproxy.a"
fi

echo "Rust core: ${PLATFORM_NAME:-unknown} [$(requested_architectures)] -> $OUTPUT_DIR/libtgwsproxy.a"