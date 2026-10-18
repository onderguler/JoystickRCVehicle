#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
build="$(mktemp -d)"
trap 'rm -rf "$build"' EXIT
args=()
if [[ $# -gt 0 ]]; then
  [[ $# -eq 2 && "$1" == --firmware ]] || { echo "Usage: $0 [--firmware /absolute/sketch.ino]" >&2; exit 2; }
  args+=("-DFIRMWARE_PATH=\"$2\"")
fi
"${CXX:-g++}" -std=c++17 -Wall -Wextra -Werror -pedantic \
  -fsanitize=address,undefined -fno-omit-frame-pointer -g \
  -I"$here" "${args[@]}" "$here/test_firmware.cpp" -o "$build/test_firmware"
# LeakSanitizer cannot enumerate processes in some sandboxed CI environments.
# AddressSanitizer and UndefinedBehaviorSanitizer remain enabled.
ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=0}" "$build/test_firmware"
