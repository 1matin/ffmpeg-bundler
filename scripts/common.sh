#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/versions.sh"
WORK="${WORK:-$ROOT/.work}"
DIST="${DIST:-$ROOT/dist}"
mkdir -p "$WORK" "$DIST"

clone_checkout() {
  local url="$1" ref="$2" dir="$3"
  if [[ ! -d "$dir/.git" ]]; then git clone --filter=blob:none "$url" "$dir"; fi
  git -C "$dir" fetch --tags --force origin
  git -C "$dir" checkout --force "$ref"
  git -C "$dir" clean -xfd
}

write_manifest() {
  local out="$1" target="$2"
  mkdir -p "$out"
  {
    echo "target=$target"
    echo "ffmpeg=$FFMPEG_TAG"
    echo "x264=$X264_COMMIT"
    echo "dav1d=$DAV1D_VERSION"
    echo "nv-codec-headers=$NV_CODEC_HEADERS_VERSION"
    echo "oneVPL=$LIBVPL_VERSION"
    echo "AMF=$AMF_VERSION"
    echo "llvm-mingw=$LLVM_MINGW_VERSION"
    echo "date_utc=$(date -u +%FT%TZ)"
    echo
    cc --version 2>/dev/null || true
    clang --version 2>/dev/null || true
  } > "$out/build-info.txt"
}

collect_licenses() {
  local out="$1"; shift
  mkdir -p "$out/LICENSES"
  for spec in "$@"; do
    local name="${spec%%:*}" path="${spec#*:}"
    [[ -f "$path" ]] && cp "$path" "$out/LICENSES/$name" || true
  done
}
