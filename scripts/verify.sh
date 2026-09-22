#!/usr/bin/env bash
set -euo pipefail
BIN="$1"; TARGET="$2"
OUT="${3:-$(dirname "$BIN")/build-info.txt}"
"$BIN" -version >> "$OUT"
"$BIN" -buildconf >> "$OUT"
"$BIN" -hide_banner -encoders > /tmp/encoders.txt
"$BIN" -hide_banner -decoders > /tmp/decoders.txt
"$BIN" -hide_banner -hwaccels >> "$OUT" || true

need_encoder() { grep -Eq "[[:space:]]$1([[:space:]]|$)" /tmp/encoders.txt || { echo "Missing encoder: $1"; exit 1; }; }
need_decoder() { grep -Eq "[[:space:]]$1([[:space:]]|$)" /tmp/decoders.txt || { echo "Missing decoder: $1"; exit 1; }; }
forbid_encoder() { ! grep -Eq "[[:space:]]$1([[:space:]]|$)" /tmp/encoders.txt || { echo "Forbidden encoder present: $1"; exit 1; }; }

need_encoder libx264
need_decoder libdav1d

case "$TARGET" in
  windows-x64)
    need_encoder h264_mf
    need_encoder h264_nvenc
    need_encoder h264_qsv
    need_encoder h264_amf
    ;;
  windows-arm64)
    need_encoder h264_mf
    forbid_encoder h264_nvenc
    forbid_encoder h264_qsv
    forbid_encoder h264_amf
    ;;
  macos-x64|macos-arm64|macos-universal2)
    need_encoder h264_videotoolbox
    ;;
  *) echo "Unknown target: $TARGET"; exit 2 ;;
esac

TMP="$(mktemp -d)"
"$BIN" -hide_banner -loglevel error -f lavfi -i testsrc2=size=320x180:rate=30 -t 1 -c:v libx264 -pix_fmt yuv420p -y "$TMP/x264.mp4"
rm -rf "$TMP"
echo "Verified $TARGET"
