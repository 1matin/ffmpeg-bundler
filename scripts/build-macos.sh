#!/usr/bin/env bash
set -euo pipefail
ARCH="${1:?usage: build-macos.sh x86_64|arm64}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/common.sh"
TARGET="macos-$([[ "$ARCH" == x86_64 ]] && echo x64 || echo arm64)"
PREFIX="$WORK/prefix-$TARGET"
OUT="$DIST/$TARGET"
SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
MIN_MACOS="${MACOSX_DEPLOYMENT_TARGET:-12.0}"
export MACOSX_DEPLOYMENT_TARGET="$MIN_MACOS"
export CC="clang -arch $ARCH -isysroot $SDKROOT -mmacosx-version-min=$MIN_MACOS"
export CXX="clang++ -arch $ARCH -isysroot $SDKROOT -mmacosx-version-min=$MIN_MACOS"
export CFLAGS="-O2 -arch $ARCH -isysroot $SDKROOT -mmacosx-version-min=$MIN_MACOS"
export CXXFLAGS="$CFLAGS"
export LDFLAGS="-arch $ARCH -isysroot $SDKROOT -mmacosx-version-min=$MIN_MACOS"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"

rm -rf "$PREFIX" "$OUT"; mkdir -p "$PREFIX" "$OUT"

clone_checkout https://code.videolan.org/videolan/x264.git "$X264_COMMIT" "$WORK/x264-$TARGET"
pushd "$WORK/x264-$TARGET"
./configure --prefix="$PREFIX" --host="$ARCH-apple-darwin" --enable-static --disable-shared --disable-cli
make -j"$(sysctl -n hw.ncpu)" && make install
popd

clone_checkout https://code.videolan.org/videolan/dav1d.git "$DAV1D_VERSION" "$WORK/dav1d-$TARGET"
pushd "$WORK/dav1d-$TARGET"
meson setup build --wipe --prefix="$PREFIX" --default-library=static -Denable_tools=false -Denable_tests=false
ninja -C build -j"$(sysctl -n hw.ncpu)" && ninja -C build install
popd

clone_checkout https://git.ffmpeg.org/ffmpeg.git "$FFMPEG_TAG" "$WORK/ffmpeg-$TARGET"
pushd "$WORK/ffmpeg-$TARGET"
./configure --prefix="$PREFIX/ffmpeg" --cc="$CC" --extra-cflags="$CFLAGS -I$PREFIX/include" --extra-ldflags="$LDFLAGS -L$PREFIX/lib" --pkg-config-flags=--static --enable-gpl --enable-libx264 --enable-libdav1d --disable-ffplay --disable-debug
make -j"$(sysctl -n hw.ncpu)" && make install
popd

cp "$PREFIX/ffmpeg/bin/ffmpeg" "$PREFIX/ffmpeg/bin/ffprobe" "$OUT/"
write_manifest "$OUT" "$TARGET"
collect_licenses "$OUT" "FFmpeg-GPL:$WORK/ffmpeg-$TARGET/COPYING.GPLv3" "x264-COPYING:$WORK/x264-$TARGET/COPYING" "dav1d-COPYING:$WORK/dav1d-$TARGET/COPYING"
"$ROOT/scripts/verify.sh" "$OUT/ffmpeg" "$TARGET" "$OUT/build-info.txt"
otool -L "$OUT/ffmpeg" >> "$OUT/build-info.txt"
file "$OUT/ffmpeg" >> "$OUT/build-info.txt"
(cd "$OUT" && shasum -a 256 ffmpeg ffprobe > SHA256SUMS)
